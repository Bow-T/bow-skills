---
name: webhook-design-and-delivery
description: Trigger when sending or receiving webhooks — signing/verification, retries, ordering, replay protection, and giving consumers a reliable event contract.
---

# Webhook Design and Delivery

A webhook is a public API your consumers cannot poll for. Treat every event as if it will arrive twice, out of order, hours late, or never. Design for that reality up front.

## 0. Decide your role first

- **Producer** (you emit events): own the contract, signing, retries, and a replay endpoint.
- **Consumer** (you receive a third party's events): own verification, idempotency, and fast acknowledgement.
- Doing both? Apply each half independently. Never let consumer logic block producer delivery.

## Producer workflow

### 1. Define the event contract before any code

Lock these fields. Changing them later breaks every consumer silently.

```jsonc
{
  "id": "evt_01HZX...",          // unique, stable, used for idempotency
  "type": "order.fulfilled",      // dotted, versioned namespace
  "created_at": "2026-06-19T...", // RFC3339, source of truth for ordering
  "data": { "order_id": "..." },  // payload — keep it minimal
  "api_version": "2026-06-01"     // schema version, NOT the URL
}
```

Rules:
- Send IDs, not full snapshots, when the resource is mutable — consumers re-fetch the canonical state via your API. Snapshots in payloads go stale and leak data.
- `type` is an enum. Add new types freely; never repurpose an old one.
- Version the schema in the body. Pin a consumer to a version; only break behind a new `api_version`.

### 2. Sign every request

Use HMAC-SHA256 over the raw body plus a timestamp. Never sign a re-serialized body — whitespace differences break verification.

```ts
// Supabase Edge Function (producer side)
const timestamp = Math.floor(Date.now() / 1000).toString();
const signedPayload = `${timestamp}.${rawBody}`;
const sig = hmacSha256(signingSecret, signedPayload); // hex
const headers = {
  "X-Webhook-Timestamp": timestamp,
  "X-Webhook-Signature": `v1=${sig}`,
};
```

- Version the signature scheme (`v1=`) so you can rotate algorithms.
- Support two active secrets during rotation; send both and let consumers match either.
- Never put the secret in the URL or query string.

### 3. Persist, then deliver (outbox pattern)

Write the event to an outbox table in the **same transaction** as the business change. A separate worker delivers it. This guarantees you never lose an event because the HTTP call failed mid-commit.

```sql
create table webhook_outbox (
  id uuid primary key default gen_random_uuid(),
  event_id text unique not null,
  endpoint_id uuid not null,
  payload jsonb not null,
  status text not null default 'pending', -- pending|delivered|failed
  attempts int not null default 0,
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
```

### 4. Retry with capped exponential backoff + jitter

```ts
const delaySec = Math.min(3600, 2 ** attempt) + Math.random() * 5;
```

- Retry on timeouts and 5xx/429. Do **not** retry on 4xx (except 429) — the consumer rejected it deliberately.
- Cap total attempts (e.g. 8 over ~24h), then mark failed and surface it in a dashboard.
- Set a hard HTTP timeout (10s). A slow consumer must not pin your worker.

### 5. Give consumers tools to survive

- **Replay endpoint**: `POST /webhooks/{endpoint}/replay?since=...` re-sends from the outbox.
- **Delivery log**: let consumers see attempt history, status codes, and response bodies.
- Document that delivery is at-least-once and unordered, and that they must dedupe on `id`.

## Consumer workflow

### 6. Verify before you trust — constant-time

```ts
const ts = Number(req.headers["x-webhook-timestamp"]);
if (Math.abs(Date.now() / 1000 - ts) > 300) return res.status(400).end(); // replay window
const expected = `v1=${hmacSha256(secret, `${ts}.${rawBody}`)}`;
const given = req.headers["x-webhook-signature"];
if (!timingSafeEqual(expected, given)) return res.status(401).end();
```

- Use the **raw** request body. In most frameworks you must disable JSON body-parsing for this route, or capture the raw buffer first.
- Compare with a constant-time function — `===` leaks timing.
- The 5-minute window is your replay defense; without it a captured request is replayable forever.

### 7. Ack fast, process async

Return `2xx` immediately after verifying and persisting the raw event. Do the real work in a background job. If you process inline and time out, the producer retries and you do duplicate work.

```ts
await db.insert("inbox_events", { event_id, raw, status: "queued" })
  .onConflict("event_id").ignore();   // idempotent landing
res.status(200).end();                // ack now
await queue.enqueue(event_id);        // work later
```

### 8. Idempotency is mandatory, not optional

Dedupe on the producer's `event_id` with a unique constraint. At-least-once delivery means you *will* see repeats.

```dart
// Flutter/Dart client consuming via your own backend
Future<void> handle(WebhookEvent e) async {
  final inserted = await db.insertIfAbsent('processed', {'event_id': e.id});
  if (!inserted) return; // already handled — no-op
  await applyEffect(e);
}
```

### 9. Handle ordering yourself

Webhooks arrive out of order. Never assume `created` precedes `updated`.

- Store `created_at` (or a producer sequence number) per resource.
- On each event, ignore it if its timestamp is older than the last applied state for that resource (last-write-wins).
- For strict sequences, buffer and re-fetch canonical state instead of replaying deltas.

## Red flags

- Verifying a re-serialized body instead of the raw bytes → signatures randomly fail.
- No timestamp in the signed payload → replayable forever.
- Processing synchronously before acking → duplicate work and producer retry storms.
- No idempotency key → double charges, double emails, corrupted counters.
- Trusting payload snapshots of mutable data → acting on stale state.
- Secret in the URL, or a single non-rotatable secret → no safe rotation path.
- Retrying 4xx (non-429) → hammering an endpoint that already said no.
- One slow consumer blocking your delivery worker → no per-call timeout.

## Testing checklist

- Send the same event twice; assert exactly one effect.
- Tamper one byte of the body; assert `401`.
- Send a 6-minute-old timestamp; assert `400`.
- Deliver `updated` before `created`; assert correct final state.
- Force the consumer to 500; assert backoff retries then failed-state surfacing.

## Related

- Data-layer modeling for the outbox/inbox tables: see [[octopus-model]].
- Committing this work: follow [[commit-pipeline]].
