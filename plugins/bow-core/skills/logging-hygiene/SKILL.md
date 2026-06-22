---
name: logging-hygiene
description: Trigger when adding, reviewing, or cleaning up log statements — picking levels, structuring fields, blocking PII/secret leakage, and controlling log volume and cost.
---

# Logging Hygiene

A log line is a permanent API. Once it ships to an aggregator it gets indexed, retained, billed, and possibly subpoenaed. Treat every `log.x(...)` as code that runs in production forever.

## 1. Decide if the line should exist at all

Before writing a log, answer: **who reads this, and when?**

- Operator debugging an incident at 3am → keep it, make it greppable.
- "Got here" / "entering function" → delete it, use a debugger or a span.
- Confirming the happy path on every request → demote to `debug` or drop.

Red flag: a log inside a hot loop or per-row handler. One line × 10k rows = a bill and a needle-in-haystack.

## 2. Pick the level deliberately

Map levels to **reader intent**, not to how you feel about the code.

| Level | Means | Reader action |
|-------|-------|---------------|
| `error` | A request/job failed; data may be wrong | Page or ticket |
| `warn`  | Degraded but recovered (retry, fallback) | Watch the rate |
| `info`  | A business milestone happened | Audit / trace |
| `debug` | Developer detail, off in prod | Local / opt-in |

Decision points:
- Caught an exception and rethrew? Log at the boundary that *decides*, not at every layer. Re-logging the same error 4 times triples your bill and hides the real count.
- Expected control flow (user typo, 404, validation fail)? That is `info` or `debug`, never `error`. Errors that fire on normal usage train operators to ignore the channel.

## 3. Structure the payload — message constant, data variable

Keep the message string static so it groups; put the variation in fields.

```dart
// Bad: unique string per call → no aggregation, no search
log.info('Loaded order ${order.id} for user ${user.id} in ${ms}ms');

// Good: stable message + structured fields
log.info('order.loaded', {
  'order_id': order.id,
  'user_id': user.id,
  'duration_ms': ms,
});
```

TypeScript (edge function / Node):

```ts
logger.info("checkout.completed", {
  order_id: order.id,
  amount_cents: order.totalCents,
  payment_provider: provider,
});
```

Rules:
- snake_case keys, consistent across services so dashboards join.
- Numbers as numbers, not strings. `duration_ms: 42`, not `"42ms"`.
- One event = one line. Do not emit three lines that must be stitched.

## 4. Block PII and secrets at the source

Never log raw: passwords, tokens, API keys, full auth headers, JWTs, card numbers, full emails, phone numbers, addresses, government IDs, raw request bodies, full DB rows.

Defensive patterns:

```ts
// Redact at the edge of the logger, not at every call site
const REDACT = new Set(["password", "token", "access_token", "authorization", "api_key", "secret"]);
function scrub(obj: Record<string, unknown>) {
  return Object.fromEntries(
    Object.entries(obj).map(([k, v]) =>
      REDACT.has(k.toLowerCase()) ? [k, "[redacted]"] : [k, v]
    )
  );
}
```

```dart
// Log a stable hash or last-4, never the value
log.info('user.login', {'user_id': user.id, 'email_hash': sha256(email)});
```

Supabase specifics:
- Edge function logs are queryable via the dashboard/`get_logs`; assume anything you print is visible to project members. Do not print the service-role key or the full JWT.
- Postgres function/trigger `RAISE NOTICE` lands in DB logs — never `RAISE NOTICE '%', row` on a table holding PII.
- Don't log the full row after an insert; log the id and the columns an operator actually needs.

Red flags in review: `JSON.stringify(req)`, `print(user)`, `log.d('$response')`, logging an entire Supabase row or `error.config` from an HTTP client (it carries headers).

## 5. Control volume and cost

Cost is per-byte-ingested plus retention. Treat log spend like any other budget.

- **Sample** high-frequency success events: keep 1-in-N for `info`, keep all `error`/`warn`.
- **Rate-limit** repeating errors so a flapping dependency doesn't emit 50k identical lines.

```ts
const seen = new Map<string, number>();
function logThrottled(key: string, fn: () => void, everyMs = 60_000) {
  const now = Date.now();
  if ((seen.get(key) ?? 0) + everyMs < now) { seen.set(key, now); fn(); }
}
```

- Put big blobs (payloads, stack-heavy context) behind `debug`, off by default.
- Prefer **metrics** (counters/histograms) over logs for "how often / how slow". A log per request to count requests is the classic cost trap.
- Set retention per level if the platform allows: short for `info`, longer for `error`.

## 6. Make logs correlatable

A log no one can trace is noise. Thread a request/trace id through every line of one operation.

```ts
const log = logger.child({ request_id: requestId, user_id: userId });
log.info("payment.authorized", { amount_cents });
```

In Flutter, attach a session/correlation id to the logger instance per flow so client and server lines join.

## 7. Review checklist

Before approving a diff that touches logs:

- [ ] Right level — no `error` on expected paths, no duplicate re-logs up the stack.
- [ ] Static message, variable data in fields, snake_case keys.
- [ ] No PII/secrets — scanned for emails, tokens, full bodies, raw rows.
- [ ] No log inside a hot loop without sampling/throttling.
- [ ] Counting/timing done with metrics, not log volume.
- [ ] Correlation id present for multi-step flows.
- [ ] Removed leftover `print`/`console.log`/`debugPrint` scaffolding.

## Quick reject list

- `console.log` / `print` left in shipped code → delete or convert to the real logger.
- `catch (e) { log.error(e); throw e; }` at every layer → log once at the boundary.
- Message string interpolating ids → move ids to fields.
- Logging a whole object "just in case" → name the two fields you need.

---

When committing log changes, follow [[commit-pipeline]]. For redaction tied to data-model fields, see [[octopus-model]] for which columns are sensitive.
