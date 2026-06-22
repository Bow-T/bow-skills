---
name: distributed-transactions-and-sagas
description: Triggers when a business operation spans multiple services or databases needing consistency without 2PC — saga orchestration/choreography, compensating actions, outbox pattern, and partial-failure recovery.
---

# Distributed transactions and sagas

A single ACID transaction is the right tool until your write crosses a boundary
it can't span: two services, two databases, a database plus a payment provider, a
row plus a queue. The moment that happens, you cannot get atomicity for free. This
skill is about engineering acceptable consistency across that boundary without
two-phase commit (2PC), whose blocking coordinator and lock-holding make it a poor
fit for services that scale independently and fail partially.

## First, refuse the saga when a transaction will do

Before reaching for any of this, check whether the boundary is real.

- If both writes live in the same Postgres/Supabase database, wrap them in one
  transaction (a single `rpc` calling a `plpgsql` function, or a server-side
  transaction block). No saga. No outbox. Done.
- If you "need" a saga only because the code is split across two services that
  share a database, the split is the bug — fix the boundary, not the consistency.
- If the second write is to an external API (charge a card, send an SMS), you have
  a real boundary and the rest of this skill applies.

State this assumption out loud: a saga trades atomicity for **eventual
consistency with visible intermediate states**. If the product cannot tolerate a
window where the order exists but is unpaid, a saga is the wrong model — say so.

## Pick a coordination style deliberately

**Orchestration** — one component owns the workflow and calls each step in order,
reacting to success/failure. Choose this when the flow has more than ~3 steps,
when steps have ordering constraints, or when you need one place to see "where is
order 4471 stuck." Easier to reason about; the orchestrator is a dependency.

**Choreography** — each service emits an event, the next reacts, no central brain.
Choose this for short flows (2-3 steps) with loose coupling. It decentralizes but
the workflow becomes emergent — no single place tells you the saga's state, and
adding a step means touching several services. Resist it past 3 steps; "where did
this saga die" becomes archaeology.

Default to orchestration unless the flow is genuinely tiny. Mixing both in one
saga is how you get loops you can't trace.

## Design the steps as (action, compensation) pairs

Model the saga as an ordered list where every step is two things:

1. A forward action that does work and is **idempotent** (see [[idempotency-and-exactly-once]]).
2. A compensating action that semantically undoes it — not a rollback, a new
   forward operation that reverses the effect.

Compensation is not deletion. You do not delete a payment; you issue a refund. You
do not un-send an email; you send a correction. Write each compensation as it
would appear in an audit log, because it will.

```
reserveInventory   ⇄  releaseInventory
chargeCard         ⇄  refundCharge
createShipment     ⇄  cancelShipment
```

Classify each step:

- **Compensatable** — can be undone later (inventory reservation).
- **Pivot** — the point of no return; once it commits the saga must go forward.
- **Retriable** — comes after the pivot and only ever moves forward (send receipt).

Order the saga so all compensatable steps precede the pivot, and all retriable
steps follow it. If you cannot arrange that, you have two pivots and you've
re-invented the distributed-transaction problem you were avoiding.

## Make every boundary crossing go through the outbox

The classic dual-write bug: you `UPDATE orders` and then publish an event, and the
process dies between them. Now the DB and the broker disagree forever. Never write
to a database and an external system in code as two independent steps.

Instead, write the state change and an outbox row in the **same local
transaction**, then a separate relay publishes the outbox.

```sql
-- inside ONE transaction
update orders set status = 'inventory_reserved' where id = $1;
insert into outbox (id, aggregate_id, type, payload, created_at)
values (gen_random_uuid(), $1, 'inventory.reserved', $2, now());
```

A poller (a Supabase scheduled edge function, or a worker) reads unsent outbox
rows, dispatches them, and marks them sent — at-least-once, so consumers must
dedupe on the event id. The atomic pair (state + intent) is the whole point: if
the transaction commits, the event is guaranteed to eventually fire; if it rolls
back, neither happened.

Keep a `processed_events(event_id)` table on the consumer side and insert-on-
conflict-do-nothing to enforce exactly-once *effect* on top of at-least-once
*delivery*.

## Persist saga state so recovery is possible

A saga that lives only in memory cannot survive a crash. Persist a saga instance
record that captures: current step, status (`running`/`compensating`/`done`/
`failed`), the original request, and per-step outcomes. Every transition is a
durable write before the side effect, so a restarted orchestrator can answer "what
do I do next" purely from the row.

```ts
type SagaState = {
  id: string;
  step: 'reserve' | 'charge' | 'ship' | 'done';
  status: 'running' | 'compensating' | 'failed' | 'completed';
  context: Record<string, unknown>; // ids returned by each step, for compensation
};
```

Store the ids each forward step returns (the payment id, the shipment id) in
`context` — you will need them to compensate, and you will not have them otherwise.

## Drive forward and compensate on failure

The orchestrator loop:

1. Load saga state.
2. Execute the next forward step idempotently.
3. On success, persist the new step and continue.
4. On a **retriable** failure (timeout, 503), retry with backoff and jitter (see
   [[resilience-and-fault-tolerance]]). Do not compensate for transient errors.
5. On a **terminal** failure (validation rejected, business rule violated), switch
   to `compensating` and run compensations for every completed step **in reverse
   order**.

Compensations must themselves be idempotent and retriable — they run in the
unhappy path, which is exactly when systems are flaky. A compensation that fails
must not be swallowed: retry it, and if it exhausts retries, escalate to a
dead-letter / manual-intervention queue. A stuck compensation is an incident, not
a log line (see [[incident-response-and-postmortems]]).

## Handle the genuinely hard partial-failure cases

- **Timeout ambiguity.** A `chargeCard` call times out. Did it charge? Treat
  unknown as possibly-succeeded: make the call idempotent with a client-supplied
  key, then query the provider by that key before retrying or compensating. Never
  blind-retry a non-idempotent money operation.
- **Compensate-before-complete races.** Step 2's response arrives after you've
  already started compensating step 1. Your forward steps' effects must be keyed
  so a late success can still be compensated; check saga status before applying
  any callback result.
- **Compensation for a step that never pivoted.** If the pivot step itself fails,
  you only compensate the pre-pivot steps — never the pivot. Encode that boundary
  in the step list, not in the operator's head.
- **Lost outbox relay.** If the poller is down, events queue in the outbox; that's
  the design working. Alert on outbox lag (oldest unsent row age), not on outbox
  size alone.

## Test the failure paths, because they are the product

Happy-path saga tests prove almost nothing. Write tests that:

- Kill the orchestrator between each step and assert recovery resumes correctly.
- Make each step fail and assert exactly the right compensations run, in reverse.
- Deliver the same event twice and assert one effect (dedupe works).
- Fire a step's success callback after compensation began and assert no corruption.

Use [[test-driven-development]] to drive the compensation logic from these cases,
and [[chaos-and-resilience-testing]] to inject the timeouts and duplicates in a
realistic environment. A saga whose compensation path has never been exercised
under failure is unverified — "looks right" is not done.

## Observe it as one logical operation

Propagate a `saga_id` (and `correlation_id`) through every step, event, and log
line so one query reconstructs the full timeline across services. Emit metrics for
saga duration, compensation rate, and stuck-saga count. Wire these into
[[observability-and-instrumentation]]; a rising compensation rate is an early
signal that an upstream dependency is degrading.

## Before you ship

- Every step has a written, idempotent compensation, ordered pivot-aware.
- All boundary crossings go through the outbox; no dual writes remain.
- Saga state is durable and recovery is tested by killing mid-flight.
- Dead-letter path exists for compensations that cannot complete.
- Commit and push via [[commit-pipeline]].
