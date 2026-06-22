---
name: resilience-and-fault-tolerance
description: Triggers when calling networks or external services and you need retries with backoff/jitter, timeouts, circuit breakers, bulkheads, idempotent retries, or graceful degradation.
---

# Resilience & Fault Tolerance

Every call that leaves your process can hang, fail, or lie. This is the process for making your code survive the failure of things it depends on.

## 0. Classify the dependency first

Before adding any resilience machinery, answer three questions about the call:

- **Is it idempotent?** Reads always are. Writes are only if you make them so (see step 4). Never retry a non-idempotent write blindly.
- **Is it on the critical path?** If it fails, must the whole operation fail, or can you degrade? This decides retry vs. fallback.
- **What's the user's deadline?** A 30s background sync and a tap-to-load screen need opposite tradeoffs.

Red flag: reaching for a retry library before knowing whether the operation is safe to repeat.

## 1. Timeout everything — no exceptions

An unbounded call is the most common cause of cascading failure: one slow dependency exhausts your connection pool / isolate / event loop, and now everything is slow.

- Set a timeout on **every** outbound call, even ones you "trust."
- Total budget = sum of inner budgets. If the user has 5s, don't let three sequential calls each get 5s.
- A timeout must actually cancel the work, not just stop waiting for it.

```dart
final res = await supabase
    .from('orders')
    .select()
    .eq('user_id', uid)
    .timeout(const Duration(seconds: 4)); // throws TimeoutException
```

```ts
const ctrl = new AbortController();
const t = setTimeout(() => ctrl.abort(), 4000);
try {
  const r = await fetch(url, { signal: ctrl.signal });
  return await r.json();
} finally {
  clearTimeout(t); // always release the timer
}
```

## 2. Retry only retryable failures

Retrying a `400` or a validation error just burns time and amplifies load. Build an explicit allowlist.

- **Retry:** timeouts, connection resets, `429`, `502/503/504`, DNS blips.
- **Do NOT retry:** `400`, `401`, `403`, `404`, `409`, `422`, malformed-input errors.
- Cap attempts (3–5). Unbounded retries are a self-inflicted outage.

```ts
const RETRYABLE = new Set([408, 429, 500, 502, 503, 504]);
function shouldRetry(err: unknown, status?: number): boolean {
  if (status && RETRYABLE.has(status)) return true;
  return err instanceof TypeError; // fetch network failure
}
```

## 3. Backoff with full jitter — never fixed delays

Synchronized retries from many clients create a thundering herd that keeps a recovering service down. Exponential growth bounds load; jitter de-synchronizes clients.

Use **full jitter**: `delay = random(0, min(cap, base * 2^attempt))`.

```dart
Future<T> retry<T>(Future<T> Function() op, {int max = 4}) async {
  final rnd = Random();
  for (var attempt = 0; ; attempt++) {
    try {
      return await op();
    } catch (e) {
      if (attempt >= max || !_isRetryable(e)) rethrow;
      final capMs = min(8000, 200 * (1 << attempt));
      await Future<void>.delayed(Duration(milliseconds: rnd.nextInt(capMs + 1)));
    }
  }
}
```

- Honor a `Retry-After` header when present — it overrides your computed delay.
- Don't retry inside a retry (nested layers multiply attempts exponentially). Retry at exactly one layer.

## 4. Make retried writes idempotent

A retry after a timeout is dangerous: the first request may have *succeeded*; you just never got the response. Without idempotency you double-charge, double-insert, double-send.

- Generate an **idempotency key** on the client *before* the first attempt and reuse it across retries.
- On the server, dedupe on that key (unique constraint, or upsert).

```ts
// client: one key for the whole logical operation
const key = crypto.randomUUID();
await retry(() => fetch('/api/pay', {
  method: 'POST',
  headers: { 'Idempotency-Key': key },
  body: JSON.stringify(payload),
}));
```

```sql
-- server side dedupe with a unique constraint
create unique index if not exists payments_idem_key on payments (idempotency_key);
-- then upsert; a replayed request is a no-op
insert into payments (idempotency_key, user_id, amount)
values ($1, $2, $3)
on conflict (idempotency_key) do nothing;
```

Red flag: retrying a `POST` that creates a resource with no dedupe key. That's a bug waiting for a slow network.

## 5. Circuit breaker — stop hammering the dead

When a dependency is clearly down, retrying every request just wastes your own resources and slows recovery. A breaker fails fast.

States: **closed** (normal) → **open** (fail immediately) after N consecutive failures → **half-open** (let one probe through) after a cooldown.

```ts
class Breaker {
  private fails = 0;
  private openUntil = 0;
  constructor(private threshold = 5, private cooldownMs = 10_000) {}
  async run<T>(op: () => Promise<T>): Promise<T> {
    if (Date.now() < this.openUntil) throw new Error('circuit_open');
    try {
      const r = await op();
      this.fails = 0; // success closes it
      return r;
    } catch (e) {
      if (++this.fails >= this.threshold) {
        this.openUntil = Date.now() + this.cooldownMs;
      }
      throw e;
    }
  }
}
```

Keep one breaker **per dependency**, not one global breaker — a failing email API shouldn't trip your database calls.

## 6. Bulkheads — isolate the blast radius

Partition resources so a flood to one dependency can't starve others. Cap concurrency per dependency with a semaphore; excess requests fail fast rather than queueing forever.

```dart
// Flutter: limit concurrent calls to a flaky third-party API
final _sem = StreamController<void>(); // or a Pool from package:pool
final pool = Pool(6); // at most 6 in flight to this dependency
Future<T> guarded<T>(Future<T> Function() op) => pool.withResource(op);
```

Apply the same to DB connection pools: a single endpoint should never be able to grab every connection.

## 7. Graceful degradation — design the fallback path

Decide *before* failure what "degraded but working" looks like. Failing softly beats a blank error screen.

- Serve **stale cache** when the source is unreachable (stale-while-revalidate).
- Return **partial results** — load the feed, skip the recommendation strip if its service is down.
- Provide a **default** (e.g. feature flag defaults to off, not crash).
- Make the failure **visible and recoverable**: a retry button, an offline banner.

```dart
Future<List<Item>> loadFeed() async {
  try {
    final fresh = await retry(() => api.fetchFeed());
    await cache.write(fresh);
    return fresh;
  } catch (_) {
    final cached = await cache.read();
    if (cached != null) return cached; // degrade, don't die
    rethrow; // nothing to show — surface a retryable error to the UI
  }
}
```

## 8. Verify it actually works

Resilience you never tested is decoration. Prove each path:

- Inject latency/errors at the boundary (mock that throws/sleeps) and assert: timeouts fire, retries stop at the cap, the breaker opens, the fallback returns.
- Test that a duplicated request with the same idempotency key produces **one** side effect.
- Load-test with the dependency artificially slow — confirm you fail fast instead of piling up.

## Decision cheat-sheet

| Symptom | Reach for |
|---|---|
| Call can hang | Timeout (step 1) |
| Transient blips | Retry + full jitter (2, 3) |
| Retry might duplicate a write | Idempotency key (4) |
| Dependency fully down | Circuit breaker (5) |
| One dependency starving others | Bulkhead / pool limit (6) |
| Non-critical feature failed | Graceful degradation (7) |

## Red flags

- A `try/catch` that swallows the error and returns `null` silently — failures must be observable.
- Retry loop with a fixed `sleep(1s)` and no cap.
- Retrying on *any* exception, including programmer errors.
- Timeout values copy-pasted everywhere with no relation to the user's deadline.
- "It'll basically never fail" — that's exactly the call that takes you down.

## Related

- [[error-handling-and-exception-design]] for how to model and surface failures to callers.
- [[observability-and-instrumentation]] for emitting retry/breaker metrics so you can tune thresholds.
- [[commit-pipeline]] when committing these changes.
