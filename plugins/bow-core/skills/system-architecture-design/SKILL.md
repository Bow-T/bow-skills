---
name: system-architecture-design
description: Triggers when shaping a new service or major subsystem before building components — choosing monolith vs microservices vs serverless, defining component boundaries and data flow, or weighing architectural trade-offs against requirements.
---

# System Architecture Design

Design the shape before the code. The goal of this phase is a small set of
decisions that are expensive to change later: boundaries, data ownership,
communication style, and failure behavior. Everything else is reversible.

## 0. Gate: should you even be here?

Skip heavy design when:
- The change fits inside an existing boundary (add a screen, a table, an endpoint).
- It's a prototype meant to be thrown away.

Do the work when you're starting a new service/subsystem, splitting something
that grew too big, or about to commit to a vendor or protocol. If unsure, spend
30 minutes; a wrong boundary costs months.

## 1. Pin the requirements that move architecture

Most requirements do not affect shape. Hunt for the few that do. For each, write
a number, not an adjective ("fast" is useless).

- **Load shape**: peak requests/sec, read:write ratio, burstiness.
- **Latency budget**: p95 per user action, end to end.
- **Data volume + growth**: rows/year, blob sizes.
- **Consistency need**: must a read see the last write? Per entity or globally?
- **Availability target**: what breaks if this is down 5 minutes? An hour?
- **Compliance / data residency**: anything that forces where data lives.

Red flag: you can't fill in numbers. Go ask. Designing on guesses produces
architecture that's both over-built and wrong.

## 2. Map the domain into boundaries

Draw the nouns and who owns each. A boundary is correct when one team/module
owns all writes to a set of data and others read through its interface.

Heuristics for a good seam:
- Different change rate (billing rules vs. UI copy).
- Different scaling profile (image processing vs. CRUD).
- Different consistency or compliance rules.
- Clear data ownership: exactly one writer per table cluster.

Red flag: two "services" share a database table and both write it. That's one
component pretending to be two. Either merge them or split the data.

## 3. Choose a deployment style — default to the boring one

Decision order, stop at the first that fits:

1. **Modular monolith** — one deployable, clear internal module boundaries.
   Default for new products and small teams. Cheapest to refactor.
2. **Serverless functions** — spiky/event-driven work, glue, scheduled jobs,
   webhooks. Great for unpredictable load; watch cold starts and per-invocation cost.
3. **Microservices** — only when an organizational or scaling force demands it:
   independent deploy cadence, isolated scaling, hard fault isolation, or teams
   stepping on each other.

```
load spiky + stateless?      -> serverless edge functions
one team, evolving domain?   -> modular monolith
one subsystem dwarfs the     -> extract THAT one service,
rest in scale or risk?          leave the rest a monolith
```

Red flag: choosing microservices for a 3-person team "to scale later." You'll
pay distributed-systems tax now for a problem you don't have. Start modular;
extract along the seams from step 2 when a real force appears.

## 4. Define communication & data flow

For each boundary crossing, pick synchronous or asynchronous on purpose.

- **Sync (request/response)**: caller needs the answer now (read a profile,
  validate a payment). Couples availability — if callee is down, caller degrades.
- **Async (event/queue)**: fire-and-forget, fan-out, or work that can lag
  (send email, regenerate a thumbnail, update a search index). Decouples
  availability; costs eventual consistency.

Prefer async for anything not on the user's critical path. In a Supabase-backed
stack, a write that triggers downstream work fits this shape well:

```sql
-- Source of truth writes the row; side effects ride a queue, not the request.
create trigger on_order_paid
  after update of status on orders
  for each row when (new.status = 'paid')
  execute function enqueue_fulfillment();
```

```typescript
// Edge function drains the queue; failures retry without blocking checkout.
export async function fulfill(job: FulfillmentJob): Promise<void> {
  await reserveStock(job.orderId);   // idempotent: safe to retry
  await notifyWarehouse(job.orderId);
}
```

Make every async handler **idempotent** — keyed by event id — because at-least-once
delivery means it will run twice eventually.

## 5. Decide where data lives and who owns it

- One **system of record** per entity. Caches and read models are derived and
  disposable; never let two stores both claim to be authoritative.
- Push consistency requirements down to the store: enforce invariants with
  constraints and row-level security at the database, not only in app code.
- For a Flutter client, treat the local store (e.g. an offline cache or
  signals/state layer) as a *replica*, never the source of truth. Reconcile on
  reconnect; assume the server wins unless you've explicitly designed CRDT-style merge.

Red flag: business rules duplicated in client, edge function, and DB that can
drift. Pick one enforcement point per rule.

## 6. Design for failure before success

For each external dependency and boundary crossing, answer:
- What happens when it's slow? (timeout + budget)
- What happens when it's down? (fallback, queue, or fail fast)
- What happens when it returns twice or out of order? (idempotency, ordering keys)

Add timeouts, bounded retries with backoff, and a circuit breaker on hot sync
paths. Decide the degraded mode explicitly — "checkout works but recommendations
are blank" beats "the page 500s."

## 7. Validate the design against the numbers

Walk the two or three highest-volume user actions through your boxes and arrows.
Tally hops, round trips, and storage per action; check it against step 1.

- Does p95 fit the latency budget across all sync hops?
- Does the write path survive peak load without a single bottleneck owning everything?
- Does one component's failure take down more than its blast radius should?

If a single box is on every path, that's your scaling and reliability ceiling —
isolate or replicate it.

## 8. Record the decision, then build the smallest slice

Write a short Architecture Decision Record per major choice: context, the options,
the decision, and the trade-off accepted. One screen, not a thesis. This is what
future-you reads when tempted to "fix" the architecture.

Then prove the riskiest assumption with a thin vertical slice — one real path
through every layer — before fanning out into full implementation.

## Quick red-flag checklist

- [ ] Requirements are adjectives, not numbers.
- [ ] Two components write the same data.
- [ ] Microservices chosen with no scaling/org force behind it.
- [ ] Sync call on the user's critical path to a flaky dependency, no timeout.
- [ ] Async handler that isn't idempotent.
- [ ] Two stores both claim to be the source of truth.
- [ ] No defined degraded mode for any dependency outage.
- [ ] No ADR — the decision lives only in someone's head.

## Related

- [[data-modeling-and-schema-design]] — turn the data-ownership map into concrete tables.
- [[api-and-interface-design]] — formalize the boundary interfaces from step 4.
- [[data-modeling-and-schema-design]] — data-layer conventions once boundaries are set.
- Commit the ADR and scaffolding per [[commit-pipeline]].
