---
name: rate-limiting-and-quota-design
description: Trigger when designing or fixing request throttling, API quotas, abuse prevention, or protecting a downstream service from overload.
---

# Rate Limiting and Quota Design

A throttle that protects nothing is just latency. Before writing a limiter, name the resource you are protecting and the failure you are preventing. Everything below flows from that one answer.

## 1. Frame the problem in one sentence

Fill this in before touching code:

> "I am protecting **\<resource\>** from **\<who\>** doing **\<action\>** more than **\<budget\>** per **\<window\>**, and when they exceed it I will **\<response\>**."

If you cannot fill every blank, you are not ready. Common confusions to resolve here:

- **Rate limit** (smooth flow: requests/second) vs **quota** (total budget: requests/month). You usually need both, with different storage.
- **Fairness limit** (stop one tenant starving others) vs **abuse limit** (stop a malicious flood) vs **capacity limit** (stop your DB from melting). Different identities, different numbers.

## 2. Pick the limit dimension (the key)

The key decides everything. Choose the narrowest stable identity you can attribute the cost to.

| Dimension | Use when | Watch out for |
|-----------|----------|---------------|
| User / tenant ID | Authenticated APIs, fairness | Free before login |
| API key | Machine-to-machine | Key sharing |
| IP / subnet | Unauthenticated endpoints, abuse | NAT, shared proxies, IPv6 /64 |
| Composite (`tenant:route`) | Per-endpoint budgets | Key explosion in storage |

Red flag: limiting by IP on a mobile app — carrier NAT puts thousands of users behind one address. Limit by device/session token instead, and keep a looser IP backstop only for abuse.

## 3. Choose the algorithm — default to token bucket

- **Token bucket** — default choice. Allows bursts up to bucket size, refills at a steady rate. Maps cleanly to "N per second, burst up to M."
- **Sliding window counter** — best for quotas and accuracy ("100/min" that does not double-fire at window edges).
- **Fixed window** — simplest, but a client can send `2 x limit` across the boundary. Acceptable only for coarse daily quotas.
- **Concurrency limiter** — when the cost is *in-flight work* (open DB connections, LLM streams), not request count. Limit simultaneous, not per-second.

Decision: bursty user traffic -> token bucket. Billing/quota -> sliding window. Expensive long-lived calls -> concurrency.

## 4. Decide where state lives

- **Single instance** -> in-memory map. Fine for one process; resets on restart.
- **Multiple instances** -> shared store (Redis, or a Postgres table for low-rate quotas). In-memory per-instance silently multiplies the real limit by your instance count — a classic production surprise.
- **Edge / per-region** -> accept approximate global limits; do not pay a cross-region round trip on every request.

Make the limiter check atomic. A read-then-write race lets concurrent requests both pass. Use an atomic Redis script or a DB `UPDATE ... RETURNING`.

## 5. Reference implementations

**Token bucket via atomic Redis (TypeScript / edge function):**

```ts
// Refill + consume in one atomic Lua script — no read/modify/write race.
const SCRIPT = `
local key, rate, burst, now, cost = KEYS[1], tonumber(ARGV[1]), tonumber(ARGV[2]), tonumber(ARGV[3]), tonumber(ARGV[4])
local b = redis.call('HMGET', key, 'tokens', 'ts')
local tokens = tonumber(b[1]) or burst
local ts = tonumber(b[2]) or now
tokens = math.min(burst, tokens + (now - ts) * rate)
if tokens < cost then
  redis.call('HSET', key, 'tokens', tokens, 'ts', now)
  redis.call('EXPIRE', key, math.ceil(burst / rate) + 1)
  return {0, tokens}
end
tokens = tokens - cost
redis.call('HSET', key, 'tokens', tokens, 'ts', now)
redis.call('EXPIRE', key, math.ceil(burst / rate) + 1)
return {1, tokens}`;

export async function allow(redis, key: string, rate = 10, burst = 20, cost = 1) {
  const [ok, remaining] = await redis.eval(SCRIPT, [key], [rate, burst, Date.now() / 1000, cost]);
  return { allowed: ok === 1, remaining: Math.floor(remaining) };
}
```

**Monthly quota in Postgres / Supabase (atomic, no race):**

```sql
create table usage_quota (
  tenant_id uuid not null,
  period text not null,           -- e.g. '2026-06'
  used int not null default 0,
  limit_max int not null,
  primary key (tenant_id, period)
);

-- Returns the row only if the increment stayed under budget.
update usage_quota
set used = used + 1
where tenant_id = $1 and period = $2 and used < limit_max
returning used, limit_max;
-- zero rows returned == quota exceeded
```

**Client side (Dart / Flutter) — respect the server, do not fight it:**

```dart
Future<Response> call() async {
  final res = await _send();
  if (res.statusCode == 429) {
    final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
    final wait = retryAfter != null
        ? Duration(seconds: retryAfter)
        : _backoff(); // exponential + jitter
    await Future.delayed(wait);
    return call();
  }
  return res;
}
```

## 6. Respond correctly when over limit

- Return **HTTP 429**, not 403/500. 503 is acceptable for capacity shedding.
- Always send headers: `RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`, and `Retry-After` on a 429.
- Make `Retry-After` truthful — a wrong value trains clients to hammer or to give up.
- Fail **open or closed deliberately**: if the limiter store is down, decide whether to allow traffic (protect availability) or block it (protect the resource). Capacity limiters fail closed; fairness limiters usually fail open. Log either way.

## 7. Stop the retry storm

A limiter without client discipline creates a feedback loop: 429 -> immediate retry -> more 429.

- Require **exponential backoff with full jitter** on every client/SDK. Synchronized retries are a self-inflicted DDoS.
- Add a **circuit breaker** so clients stop calling a failing downstream entirely for a cooldown, rather than draining their quota against errors.
- For your own outbound calls to a rate-limited third party, throttle *before* you send, sized to their published limit, not after you get rejected.

## 8. Test and observe before shipping

- Load test at `limit - 1`, `limit`, and `limit + burst`. Confirm the boundary behaves and counters do not leak.
- Verify the multi-instance case: run two app instances and confirm the *combined* throughput is capped, not doubled.
- Emit metrics: allowed vs throttled count per key dimension, and remaining-budget distribution. A spike in 429s for legitimate users means the limit is wrong, not the users.
- Alert on "approaching quota" (e.g. 80%) so tenants can act before they hit a wall.

## Red flags checklist

- In-memory limiter behind a load balancer with N replicas.
- Limiting authenticated traffic by IP.
- Read-then-write limiter logic (non-atomic) — race lets bursts through.
- 429 with no `Retry-After`, or a fabricated one.
- Clients retrying immediately with no jitter.
- One global number for fairness, abuse, and capacity at once.
- No metric distinguishing throttled-legit from throttled-abuse.

## Related

- See your edge-function conventions for running the limiter at the edge.
- See [[observability-and-instrumentation]] for the throttle metrics and alerts above.
- Commits for limiter changes follow [[commit-pipeline]].
