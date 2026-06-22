---
name: event-sourcing-and-cqrs
description: Triggers when persisting state as an immutable event log with separate read/write models — designing event stores, aggregates, snapshots, projections, replay/rebuild, and schema-versioning of historical events.
---

# Event Sourcing & CQRS

A process for storing the truth as an append-only log of facts and deriving every read shape from it — without losing replay determinism, leaking write concerns into read models, or trapping yourself with un-versionable historical events.

## 0. First decide: do you actually need this?

Event sourcing is a tax you pay forever. Reach for it only when at least one is true:

- The **audit trail is the product** — finance ledgers, access logs, anything where "how did we get here" is a real requirement, not a nice-to-have.
- You need **temporal queries**: "what was the balance on this date," "replay the account as of last Tuesday."
- The same facts feed **many divergent read shapes** that would otherwise fight over one mutable table.
- Concurrent edits to a rich domain object need **per-aggregate optimistic concurrency** that row-level locking handles badly.

**Red flags that mean stop:** "we might want an audit log someday," or a CRUD form with one read shape. A `created_at`/`updated_at` table plus an `audit_log` insert trigger covers 80% of "we want history" without the rebuild machinery. Default to that; cross-link [[data-modeling-and-schema-design]] and walk away.

CQRS (separate read/write models) is **independent** of event sourcing. You can split reads from writes over a plain relational store. Don't conflate the two — adopt each only for its own reason.

## 1. Define aggregates and their boundaries

An **aggregate** is the unit of consistency: the smallest thing that must be valid as a whole after every command. It is also your **concurrency boundary** and your **stream**.

- One aggregate instance = one event stream, keyed by `aggregate_id`.
- A command targets exactly one aggregate. Cross-aggregate work happens via events + a process manager, never one command spanning two streams.
- Keep aggregates **small**. A giant `Account` holding every transaction forever means rehydrating thousands of events per command. If a collection grows unboundedly, it's probably its own aggregate.

Sketch each aggregate as: current in-memory state, the commands it accepts, the invariants it guards, and the events each command emits.

## 2. Design events as immutable, self-contained facts

- **Past tense, business language:** `FundsWithdrawn`, `InviteAccepted` — not `UpdateBalance`.
- Store the **intent and the outcome**, not a diff against current code. An event read in three years must mean exactly what it meant when written.
- Include a `schema_version` from day one. You will need it (§7).
- No derived or environment-dependent values that can't be recomputed. Store the deposit amount, not "the new balance" if balance is a projection — unless the balance was the *decision input* (then freeze it).

A TypeScript event envelope:

```ts
interface EventEnvelope<T = unknown> {
  event_id: string;        // uuid, idempotency key for consumers
  aggregate_id: string;
  aggregate_type: string;  // 'account'
  version: number;         // per-stream sequence, 1,2,3...
  type: string;            // 'FundsWithdrawn'
  schema_version: number;  // payload shape version
  payload: T;
  occurred_at: string;     // domain time
  recorded_at: string;     // wall-clock insert time
  causation_id?: string;   // the command/event that caused this
  correlation_id?: string; // the originating request
}
```

`causation_id`/`correlation_id` are not optional luxuries — without them you cannot debug a replay or trace a fact back to its trigger.

## 3. Build the event store as an append-only table

On Supabase/Postgres, the store is one table plus one rule: **insert-only, never update, never delete.**

```sql
create table event_log (
  global_seq   bigint generated always as identity primary key,
  aggregate_id uuid not null,
  aggregate_type text not null,
  version      int not null,
  type         text not null,
  schema_version int not null default 1,
  payload      jsonb not null,
  occurred_at  timestamptz not null,
  recorded_at  timestamptz not null default now(),
  causation_id uuid,
  correlation_id uuid,
  unique (aggregate_id, version)   -- optimistic concurrency lives here
);
```

The `unique (aggregate_id, version)` constraint **is** your concurrency control. A writer reads the stream at version N, decides, and inserts version N+1. Two concurrent writers both try N+1; one wins, the loser gets a unique-violation and retries from the fresh state. No `SELECT FOR UPDATE`, no lost updates.

Lock the table down: enable RLS, grant the app role `INSERT` and `SELECT` only — explicitly **no** `UPDATE`/`DELETE`. An event store you can edit is just a worse mutable table. See [[supabase-security-review]].

## 4. The write path (command → events)

For each command:

1. Load the stream for `aggregate_id` (or the snapshot + tail, §6).
2. Fold events into current state — the aggregate's `apply(state, event)` reducer.
3. Validate the command against state. Reject if an invariant would break. **No event is written for a rejected command** — a refusal is not a fact about the domain, it's a fact about a request (log it elsewhere if you must).
4. Emit one or more events.
5. Append at `expected_version + 1`. On unique violation, go to step 1 and retry (bounded).

Keep the `apply` reducer **pure and total** — same events always fold to same state, and it never throws. All rejection logic lives in the command handler (the `decide` function), never in `apply`. This split is what makes replay safe: rebuilding never re-runs validation.

```ts
// pure, total — used by both live writes and replay
function apply(state: Account, e: EventEnvelope): Account { ... }

// impure decision — only on the live write path
function decide(state: Account, cmd: Withdraw): EventEnvelope[] {
  if (cmd.amount > state.balance) throw new DomainError('insufficient_funds');
  return [event('FundsWithdrawn', { amount: cmd.amount })];
}
```

## 5. The read path (projections)

Read models are **disposable, rebuildable caches** derived from the log. Never let the write path read from a projection to make a decision — that couples them and breaks the guarantee that the log is the sole truth.

- Each projection is a consumer that folds events into a query-optimized table (`account_balances`, `monthly_statements`).
- Track a **checkpoint**: the last `global_seq` each projection has processed. Resume from it on restart.
- Projections are **eventually consistent** by design. Surface this in the UI (optimistic update locally, reconcile when the projection catches up) rather than pretending reads are synchronous. In Flutter, drive the view-model off the projection's Realtime stream — see [[flutter-mvvm]].
- Make every projection handler **idempotent** keyed on `event_id`, because at-least-once delivery means you will see duplicates. See [[idempotency-and-exactly-once]].

## 6. Snapshots — only when you measure a need

A snapshot is a cached fold of a stream up to version N, so writes load `snapshot + events-since-N` instead of the whole history.

- Do **not** add snapshots preemptively. Add them when a hot aggregate's rehydration shows up in latency profiling.
- A snapshot is also disposable — it must be reconstructable purely from the log. Store its `schema_version`; on a version mismatch, ignore the snapshot and fold from scratch.
- Snapshot every K events or above a length threshold. Keep the last one or two, not all.

## 7. Schema-versioning historical events (the hard part)

Events are immutable, but your code evolves. You can never rewrite the old rows, so you must read them. Strategy, in order of preference:

1. **Upcasting:** on read, transform an old `schema_version` payload into the current shape before `apply` sees it. Keep a chain of upcasters (v1→v2→v3). This is the workhorse — old events stay byte-for-byte intact on disk; only the in-memory shape is migrated.
2. **Additive-only changes** need no upcaster: a new optional field with a default. Prefer designing events so most changes are additive.
3. **Never** repurpose an existing field's meaning or reuse a `type` name for new semantics. That silently corrupts replay of old data.

```ts
const upcasters: Record<string, (p: any) => any> = {
  'FundsWithdrawn:1': (p) => ({ ...p, currency: 'USD' }), // v1 had no currency
};
```

If a genuinely breaking rewrite is unavoidable, do a **copy-transform migration**: stream the old log into a new event type, write a new store, cut over readers, and retire the old stream. Treat it like any risky migration — see [[deprecation-and-migration]] and [[zero-downtime-database-migrations]].

## 8. Replay and rebuild

Rebuilding a projection from zero is a routine operation, not an emergency — design for it:

- Build the new projection table **alongside** the live one, replay the full log into it, then atomically swap. Don't truncate-in-place; a failed rebuild leaves you with no read model.
- Replay must be **deterministic**: pure `apply`, no calls to `now()`, no external lookups, no random ids. Any non-determinism means two rebuilds disagree — a silent data-integrity bug.
- For large logs, replay in `global_seq` batches and checkpoint frequently so an interrupted rebuild resumes.
- A projection bug is fixed by changing the handler and replaying — **never** by hand-editing the projection table, which the next rebuild silently reverts.

## 9. Verify before trusting it

- **Round-trip test:** apply a sequence of commands, then rebuild state purely from the persisted log and assert it equals the live state.
- **Upcaster test:** keep a fixture of real old-version event JSON; assert each upcaster chain produces a valid current event. This is your regression net against breaking old data.
- **Concurrency test:** fire two conflicting commands at the same aggregate version; assert exactly one wins and the loser retries cleanly.
- **Idempotency test:** deliver the same event twice to a projection; assert the read model is unchanged.

Follow [[test-driven-development]] for these — the determinism guarantees are exactly what tests must pin. When committing, use [[commit-pipeline]].
