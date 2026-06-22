---
name: event-driven-and-messaging
description: Triggers when introducing a broker, choosing pub/sub vs queues, handling at-least-once delivery, ordering/partitioning, dead-letters, or moving sync calls to async events.
---

# Event-Driven & Messaging

A process for replacing synchronous coupling with events, queues, and streams without inheriting silent data loss, duplicate side effects, or unbounded retries.

## 0. First decide: do you actually need async?

Reach for messaging only when at least one is true:

- The caller does not need the result to proceed (fire-and-react).
- The work is slow, bursty, or load-spiky and you want to absorb it.
- Multiple independent consumers care about the same fact.
- You need durability across a consumer being down.

**Red flag:** introducing a broker so two services can do a request/response round-trip. That is RPC with extra latency and no error channel. Keep it a synchronous call (or a Supabase RPC / edge function) until a real async need appears.

## 1. Name the thing: command vs event

Pick the wrong noun and the whole topology rots.

- **Command** — an instruction to one owner. Imperative. `ChargeCard`, `SendInvite`. Exactly one consumer is responsible. Failure is the sender's concern.
- **Event** — a fact that already happened. Past tense. `OrderPlaced`, `PaymentCaptured`. Zero-to-many consumers. The emitter does not know or care who listens.

Rule: **commands go on queues, events go on topics (pub/sub).** If you find yourself broadcasting a command to "whoever," you have an event. If you find yourself addressing an event to a specific handler, you have a command.

## 2. Choose the transport

| Need | Use |
|------|-----|
| One owner, work distribution, retries | **Queue** (SQS, a `jobs` table polled, pg-boss) |
| Many independent reactors to a fact | **Pub/sub topic** (SNS, Supabase Realtime, NOTIFY/LISTEN) |
| Replay, ordering, long retention, log of all facts | **Stream/log** (Kafka, Kinesis, Postgres logical replication) |

For a Supabase-first stack, prefer the simplest tier that works:

1. **Postgres-as-queue** (`SELECT ... FOR UPDATE SKIP LOCKED`) for moderate volume — no new infra, transactional with your data.
2. **Realtime / `pg_notify`** for fan-out to clients or edge functions.
3. A dedicated broker only when throughput, replay, or partitioned ordering forces it.

**Red flag:** adopting Kafka for 50 messages/minute. The operational tax dwarfs the benefit.

## 3. Design the message contract before any code

An event is a public API. Version it like one.

```jsonc
{
  "id": "evt_01H...",          // unique, used for idempotency
  "type": "order.placed",      // namespaced, versioned via "order.placed.v2" when breaking
  "occurredAt": "2026-06-19T10:00:00Z",
  "producer": "checkout",
  "data": { "orderId": "ord_123", "amountCents": 4200 }
}
```

Rules:
- Carry an `id` and `occurredAt` on every message — both are load-bearing later.
- Keep `data` self-describing; prefer IDs plus the few fields consumers need over the entire entity.
- **Thin events** (just IDs) force a callback fetch and a race; **fat events** (full snapshot) bloat and leak. Default thin, add fields only when a consumer demonstrably needs them.
- Evolve additively. Breaking change = new `type` version, not a mutated shape.

## 4. Assume at-least-once. Make consumers idempotent.

Almost every broker (and every retry policy) delivers a message **more than once.** Exactly-once delivery is mostly a myth; exactly-once *effect* is your job.

Patterns, in order of preference:

1. **Natural idempotency** — the operation is a no-op when repeated (`SET status='paid'`). Best case; design for it.
2. **Dedup table** — record processed `event.id`, reject repeats in the same transaction as the side effect.

```sql
create table processed_events (
  event_id text primary key,
  processed_at timestamptz default now()
);
```

```typescript
async function handle(evt: Event) {
  await db.transaction(async (tx) => {
    const dup = await tx.insertProcessedEvent(evt.id); // ON CONFLICT DO NOTHING
    if (!dup.inserted) return;                          // already handled
    await applySideEffect(tx, evt.data);                // commits atomically with the marker
  });
}
```

3. **Idempotency key on the downstream call** — when the side effect is an external API, pass `evt.id` as its idempotency key.

**Red flag:** sending an email or charging a card *before* the dedup insert commits. The marker and the effect must succeed or fail together.

## 5. Ordering and partitioning

Global ordering does not scale. Order only within a key that needs it.

- Pick a **partition key** equal to the entity whose events must stay ordered — usually the aggregate id (`orderId`, `userId`).
- Same key → same partition → ordered. Different keys → parallel, no guarantee.
- Choosing a key that is too coarse (e.g. a single tenant) serializes everything; too fine and you lose the ordering you needed.

If your transport gives no ordering, defend in the consumer: carry a monotonic `version`/`sequence` on the entity and **drop or park stale events** (`incoming.version <= stored.version`).

## 6. Failure handling: retry, then dead-letter

Define this *before* the first message flows.

- **Transient** failures (timeout, 503, lock): retry with capped exponential backoff + jitter. Set a max attempts.
- **Poison** messages (malformed, will never succeed): do not retry forever — route to a **dead-letter queue (DLQ)** after N attempts.
- The DLQ is not a graveyard. Alert on it, inspect it, and build a **replay** path to re-emit fixed/reprocessable messages.

```typescript
if (attempt >= MAX_ATTEMPTS) {
  await deadLetter.send({ ...msg, error: serialize(err), attempts: attempt });
  return ack(); // remove from main queue
}
throw err;       // let broker redeliver with backoff
```

**Red flags:** infinite redelivery of a poison message blocking the partition; a DLQ no human ever looks at; retrying a non-idempotent effect without the §4 guard.

## 7. The transactional outbox (don't dual-write)

Writing to your DB *and* publishing to a broker in two steps is a dual-write: a crash between them loses the event or fabricates one.

Instead, in **one transaction** write the business row and an `outbox` row. A relay polls the outbox and publishes, marking rows sent.

```sql
create table outbox (
  id bigserial primary key,
  type text not null,
  payload jsonb not null,
  published_at timestamptz
);
```

On Supabase this pairs cleanly with `SKIP LOCKED` polling from an edge function or a scheduled worker. The event becomes a guaranteed consequence of the commit.

## 8. Make it observable

You cannot debug what you cannot trace.

- Propagate a **correlation/trace id** from the originating request through every message (`traceId` in metadata).
- Track per-queue: **depth, age of oldest message, redelivery count, DLQ size.** Rising consumer lag is your earliest warning.
- Log on emit and on handle with `event.id` + `traceId` so a single fact is searchable end to end.

## 9. Flutter / client edge

- Treat realtime subscriptions as **at-least-once and possibly out of order.** Reconcile against authoritative state on (re)connect; never assume the stream alone is the source of truth.
- Make UI updates from events **idempotent** (upsert into local state by id), so a replayed event doesn't duplicate a list row.
- On reconnect, fetch current state, then resume the stream — bridge the gap you missed while offline.

## Definition of done

- [ ] Each message is classified command-on-queue or event-on-topic.
- [ ] Every consumer is idempotent (natural, dedup table, or downstream key).
- [ ] Ordering guarantees stated per partition key, or explicitly "none."
- [ ] Retry policy + DLQ + alert + replay path exist.
- [ ] No dual-writes; outbox used where DB-and-publish must agree.
- [ ] Correlation id flows end to end; queue depth/age/DLQ are monitored.
- [ ] Contracts versioned; changes are additive.

## Related

- [[data-modeling-and-schema-design]] for the data-layer shapes events read from and write to.

When committing any of this, follow [[commit-pipeline]] for message format.
