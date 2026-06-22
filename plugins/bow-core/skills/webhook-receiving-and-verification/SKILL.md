---
name: webhook-receiving-and-verification
description: Triggers when consuming inbound webhooks from third parties — signature verification, replay protection, ordering, retries, idempotent handling, and fast-ack-then-process patterns.
---

# Webhook Receiving and Verification

> Scope: the **consumer / receiving** side. For the **provider / sending** side, see [[webhook-design-and-delivery]].

You are accepting events you did not generate, from a sender you do not control, over a
channel anyone can POST to. Treat every request as hostile until proven otherwise, ack
fast, and process exactly once. This skill is for the **receiving** side; designing your
own outbound webhooks is a different problem.

## The non-negotiable order of operations

Do these in sequence inside the handler. Skipping or reordering causes the classic bugs.

1. Read the **raw request body** as bytes/string — before any JSON parsing.
2. **Verify the signature** against that raw body. Reject early if it fails.
3. **Check freshness** (timestamp window) to block replays.
4. **Dedupe** by event ID; if seen, return 200 and stop.
5. **Persist** the event (raw + parsed) and return 200 immediately.
6. **Process asynchronously** off the request path.

If you parse before verifying, your framework may re-serialize the body and your HMAC
will never match. Capture the raw bytes first, always.

## Step 1–2: Verify on the raw body

Most providers sign `timestamp + "." + rawBody` (or just the body) with HMAC-SHA256 and a
shared secret, sending it in a header. Recompute and compare in **constant time**.

```ts
// Supabase edge function (Deno) — verify before trusting anything
import { timingSafeEqual } from "https://deno.land/std/crypto/timing_safe_equal.ts";

async function verify(raw: string, header: string, secret: string, ts: string) {
  const signed = `${ts}.${raw}`;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signed));
  const expected = [...new Uint8Array(mac)].map(b => b.toString(16).padStart(2, "0")).join("");
  const a = new TextEncoder().encode(expected);
  const b = new TextEncoder().encode(header);
  return a.length === b.length && timingSafeEqual(a, b);
}
```

Red flags:
- `==` or `.equals()` on signatures — leaks length/timing. Use a constant-time compare.
- Trusting an `?signature=` query param instead of a header.
- Verifying a parsed-then-restringified body. Sign the bytes you received.
- A "verification" that only checks the source IP. IPs spoof and rotate; require the HMAC.

If the provider signs with asymmetric keys (Ed25519/RSA), verify against their **published
public key**, and cache it with a sane TTL — don't refetch on every request.

## Step 3: Replay protection

A valid signature is replayable forever unless you bound it. Reject events whose timestamp
is outside a tolerance (commonly five minutes), accounting for clock skew both directions.

```ts
const skewMs = 5 * 60 * 1000;
if (Math.abs(Date.now() - Number(ts) * 1000) > skewMs) return reject(400);
```

The timestamp alone is not enough — an attacker can replay within the window. Combine with
idempotency (step 4): the first delivery of an event ID wins, repeats are no-ops.

## Step 4: Idempotency is mandatory, not optional

At-least-once delivery is the norm. The same event **will** arrive twice — from provider
retries, network retries, or your own slow ack. Key on the provider's event ID and let the
database enforce uniqueness; never rely on "we probably won't get a dupe."

```sql
create table webhook_events (
  id            text primary key,          -- provider event id
  source        text not null,
  payload       jsonb not null,
  received_at   timestamptz not null default now(),
  processed_at  timestamptz,
  status        text not null default 'pending'  -- pending|done|failed
);
```

```sql
-- Insert-or-skip: the unique PK makes the second delivery a no-op.
insert into webhook_events (id, source, payload)
values ($1, $2, $3)
on conflict (id) do nothing
returning id;
```

If `returning` yields no row, you've seen this event — return 200 and stop. If the provider
sends no usable ID, derive one deterministically (e.g. hash of source + payload + timestamp),
but prefer a provider ID when offered.

## Step 5–6: Fast-ack, then process

The handler's only job is to verify, persist, and return 200 quickly. Senders time out in
seconds and a slow handler triggers a retry storm that amplifies load and duplicates.

Do **not** run business logic, call other APIs, or send email inside the request. Enqueue
and return.

```ts
// Edge function: ack in milliseconds, hand off the work.
const row = await insertOrSkip(eventId, source, payload);
if (!row) return new Response("ok", { status: 200 });   // duplicate
await enqueue(eventId);                                   // queue / pgmq / job row
return new Response("ok", { status: 200 });
```

A separate worker picks up `pending` rows, processes them, and flips `status` to `done`.
On failure it leaves the row for retry with backoff and a max-attempt cap; exhausted events
go to a dead-letter status for human review. See [[background-jobs-and-queues]] and
[[resilience-and-fault-tolerance]] for the worker side.

## Ordering: assume none

Webhooks arrive out of order. A `subscription.updated` can land before the
`subscription.created` it depends on. Defend against it:

- **Carry a version/sequence** (or the event's own `created` timestamp) and ignore an update
  older than the state you already hold. Last-writer-by-source-timestamp, not by arrival.
- **Make handlers commutative** where possible — set the resulting state, don't apply a delta.
- If an event references something you haven't seen, **don't drop it** — park it and retry,
  or fetch the current state from the provider's API as the source of truth.

```ts
// Reject stale updates instead of clobbering newer state.
if (incoming.updatedAt <= current.updatedAt) return;  // older or equal — ignore
```

## Return codes the sender understands

- **200/2xx** — accepted; the provider stops retrying. Return this once persisted.
- **400/401** — bad signature or malformed. The provider should not retry; don't make it.
- **5xx** — you failed transiently. The provider **will** retry — use this on purpose when
  you couldn't even persist, and never for a duplicate you handled fine.

Never return 5xx for a duplicate or an unparseable-but-authentic event you've already stored.

## Secrets, rotation, and multiple sources

- Pull the signing secret from config, never hardcode it. See [[secrets-and-config-management]].
- Support **two active secrets** during rotation: accept if either verifies, then retire the
  old one. Rotating with a single secret guarantees dropped events mid-cutover.
- Keep a per-source secret and a `source` column when you receive from several providers; a
  shared endpoint with one secret is a foot-gun.

## Dart/Flutter note

If a Flutter app receives provider callbacks (deep links, redirect with params), it is the
**untrusted** side — never trust client-delivered status. Confirm the real event server-side
via the verified webhook or a backend API call before granting anything (entitlements,
unlocks, balances). The client tells you "they came back"; the webhook tells you "it happened."

## Definition of done

- [ ] Raw body captured and signature verified in constant time before parsing.
- [ ] Timestamp freshness window enforced.
- [ ] Event ID persisted under a unique constraint; duplicates are 200 no-ops.
- [ ] Handler returns 200 within the sender's timeout; work runs async.
- [ ] Failed processing retries with backoff and dead-letters after a cap.
- [ ] Out-of-order deliveries can't overwrite newer state.
- [ ] Signing secret comes from config and supports rotation.
- [ ] Tests cover: bad signature, expired timestamp, replayed event, duplicate ID, out-of-order pair.

Commit via the [[commit-pipeline]] skill.
