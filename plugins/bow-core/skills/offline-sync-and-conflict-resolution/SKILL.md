---
name: offline-sync-and-conflict-resolution
description: Triggers when clients work offline and must reconcile divergent state — sync protocols, CRDTs/operational-transform, last-writer-wins vs merge policies, tombstones, vector clocks, and convergence guarantees.
---

# Offline Sync and Conflict Resolution

Two devices edited the same row while disconnected. There is no "correct" order — there is only the policy you chose in advance. Offline sync is the discipline of making that policy explicit, deterministic, and convergent, so every device that has seen the same set of changes ends up byte-identical regardless of arrival order.

The cardinal rule: **convergence is a property you design, not one you hope for.** If you cannot state why two replicas with the same operations reach the same state, you do not have sync — you have an intermittent data-loss bug.

## 1. Pin down the requirement before choosing a mechanism

Answer these out loud first; they eliminate most of the design space.

- **What's the conflict unit?** A whole row, a single field, or a position inside a list/text? Field-level conflicts are cheap to merge; intra-string edits are not.
- **Is silent overwrite acceptable?** For a "last viewed at" timestamp, yes. For a shared note body or an inventory count, a lost write is a bug report.
- **Who resolves — machine or human?** Decide whether a conflict is auto-merged, auto-resolved by policy, or surfaced to the user. Never invent a fourth option mid-implementation.
- **How long can a client stay offline?** A 30-second flaky tunnel and a two-week field deployment need different tombstone-retention and clock assumptions.

Red flag: "we'll just take the latest one." Latest by *whose* clock? That sentence is last-writer-wins smuggled in without its failure modes.

## 2. Never trust wall-clock time for ordering

Device clocks lie — skew, drift, manual resets, timezone bugs. Ordering causally-related events by `DateTime.now()` will silently drop the "earlier" write that actually happened later.

- **Last-writer-wins (LWW)** is acceptable *only* with a tiebreaker that is total and deterministic: pair a (coarse) timestamp with a stable node id, e.g. `(hlc_ts, device_uuid)`. Compare the tuple, not the bare time.
- Prefer a **Hybrid Logical Clock (HLC)**: physical time bumped to stay monotonic and to dominate any incoming timestamp. It reads like a wall clock for humans but never goes backwards across the merge.
- When you need true causality (did A *see* B?), use a **vector clock** — one counter per replica. `A < B` iff every component of A ≤ B and at least one is strictly less; otherwise A and B are concurrent and you have a real conflict to resolve.

```dart
// Dart — HLC tick on every local mutation; merge dominates any seen remote stamp
class Hlc {
  int wall; int counter; final String node;
  Hlc(this.wall, this.counter, this.node);

  Hlc tick(int nowMs) => (nowMs > wall)
      ? Hlc(nowMs, 0, node)
      : Hlc(wall, counter + 1, node);

  // total order: time, then counter, then node id as final tiebreaker
  int compareTo(Hlc o) =>
      wall != o.wall ? wall.compareTo(o.wall)
      : counter != o.counter ? counter.compareTo(o.counter)
      : node.compareTo(o.node);
}
```

## 3. Pick a conflict strategy per field, not per app

One policy for the whole entity is almost always wrong. Classify each field:

| Field shape | Strategy | Why |
|---|---|---|
| Scalar where freshness wins | LWW register (HLC-stamped) | Overwrite is the intended semantics |
| Counter (likes, stock delta) | PN-Counter / op-based increments | Two `+1`s offline must sum to `+2`, not collapse to `+1` |
| Set membership (tags, members) | OR-Set (add/remove with unique tags) | Concurrent add+remove must not silently lose the add |
| Free text / rich document | OT or a sequence CRDT (RGA/Yjs-style) | Character positions must survive concurrent insertion |
| Immutable-after-create | Reject on conflict | Divergence here is corruption, surface it |

CRDTs buy automatic convergence at the cost of metadata growth (every element carries identity). Use them where merges must be hands-off; do **not** reach for a text CRDT to sync a settings toggle.

## 4. Model deletes as tombstones, never as absence

A row that is simply gone is indistinguishable from a row a peer hasn't synced yet — so a naive delete resurrects on the next pull. Delete = a flagged record, not a missing one.

- Keep `deleted_at` (HLC-stamped) and exclude soft-deleted rows from reads. A concurrent edit to a deleted row is a conflict; decide up front whether delete wins (usual) or edit revives.
- **Garbage-collect tombstones** only after every replica is guaranteed to have observed them — bound by your max-offline window, not by disk pressure. Premature GC reintroduces zombies.
- For OR-Sets, the "tombstone" is the removed element's unique tag, which must outlive any in-flight re-add.

## 5. Make the sync protocol idempotent and resumable

Sync is a partial, retried, out-of-order data stream. Design for the worst link.

- Use a **monotonic cursor** (server-assigned change sequence or HLC high-water mark), not page offsets. The client pulls "everything after cursor X" and advances only after durable local commit.
- Every change carries a **client-generated id** so a re-sent batch is deduplicated, not double-applied. See [[idempotency-and-exactly-once]] for the write-side guarantees.
- Apply remote changes in a **single local transaction** and persist the new cursor in the same transaction — a crash mid-apply must roll back to a consistent cursor, never a half-merged state.
- Push and pull are separate phases; queue local mutations in an **outbox** table, mark them in-flight, and clear them only on server ack.

```sql
-- Supabase: server-side change feed the client pages through monotonically
create table change_log (
  seq        bigint generated always as identity primary key,
  entity     text   not null,
  entity_id  uuid   not null,
  payload    jsonb  not null,   -- field values + HLC stamps
  hlc        text   not null,
  deleted    boolean default false,
  actor      uuid   not null
);
-- pull: select * from change_log where seq > :cursor order by seq limit :n
```

Enforce per-tenant/per-user access on this feed with RLS — the change log is a back door to every row if it isn't scoped. See [[authn-authz-design]].

## 6. State and test the convergence guarantee

Convergence is testable, so test it as a property, not an anecdote.

- **Commutativity**: applying the same operation set in any order yields one state. Generate random interleavings of N concurrent ops across M replicas; assert all replicas equal.
- **Idempotency**: re-delivering an already-applied change is a no-op.
- **Associativity**: how you batch merges doesn't matter.
- Replay a recorded offline session against the merge engine in CI; a passing run once proves nothing — see [[test-driven-development]] and [[concurrency-and-async-correctness]].

```ts
// TS — property test: every interleaving converges to one state
test('replicas converge under all orderings', () => {
  const ops = randomOps({ replicas: 3, count: 50 });
  const states = permutations(ops).map(seq => seq.reduce(merge, empty()));
  expect(new Set(states.map(canonical)).size).toBe(1);
});
```

## 7. Surface unresolvable conflicts honestly

When policy can't decide — concurrent edits to an immutable field, or a domain rule (stock can't go negative) — do not pick a winner silently.

- Persist **both versions** with their stamps and present a deterministic, machine-resolvable default plus a user-facing diff for the cases that need a human.
- Log every auto-resolution with the losing value retained for a recovery window; "we merged and dropped your edit with no trace" is the worst possible outcome. Instrument merge outcomes per [[observability-and-instrumentation]].
- Never resolve a conflict by re-fetching and clobbering local state — that's data loss wearing a refresh button.

## Anti-patterns

- Ordering causal events by raw device time. Skew silently drops writes.
- Hard-deleting rows in a synced table. Tombstone or resurrect.
- One LWW policy for every field. Counters and sets need merge, not overwrite.
- A text CRDT to sync a boolean. Metadata cost with no payoff.
- Trusting "it converged in my manual test." Prove it with interleaving property tests.
- GC-ing tombstones on disk pressure instead of on the max-offline bound.

When shipping any of this, commit per [[commit-pipeline]].
