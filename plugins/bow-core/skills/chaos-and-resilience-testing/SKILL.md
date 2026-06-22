---
name: chaos-and-resilience-testing
description: Trigger when proactively validating failure handling — injecting faults, killing dependencies, simulating latency or partitions, or running a game day.
---

# Chaos & Resilience Testing

Resilience is not proven by uptime; it is proven by surviving a fault you caused on purpose. The job here is to turn vague "it should be fine" claims into evidence.

## 0. Gate before you break anything

Refuse to inject faults unless ALL of these hold:
- A **hypothesis** is written: "When X fails, the system stays Y." No hypothesis means you are just vandalising.
- You have a **steady-state metric** and its normal range (p95 latency, error rate, queue depth) — not "feels healthy".
- A **blast-radius limit** is set: one tenant, one region, 5% of traffic, or staging only.
- An **abort condition + rollback** is one command away.

If you cannot observe the system, do not perturb it. Fix observability first.

## 1. Pick the weakest seam, not the easiest one

Map dependencies and rank by `(blast radius) × (uncertainty about its failure mode)`. Favourites that hide bugs:

| Seam | Fault to inject | Failure you expect to find |
|------|-----------------|----------------------------|
| Database / Supabase | Connection refused, slow query, RLS denial | Unbounded retries, missing timeout, leaked spinner |
| Auth / token refresh | 401 mid-session, expired JWT | Infinite refresh loop, logout instead of retry |
| Third-party API | 500s, 429 rate limit, 30s hang | No circuit breaker, thread/isolate starvation |
| Realtime / websocket | Drop + reconnect | Stale UI, duplicate event handling |
| Network | Added latency, packet loss, partition | Cascading timeouts, thundering-herd reconnect |

## 2. Write the experiment as code, never as clicks

A chaos experiment must be repeatable and reviewable. Encode the four parts explicitly.

```typescript
// experiment: supabase read times out under load
const exp = {
  hypothesis: "If profile fetch exceeds 3s, UI shows cached data, no crash",
  steadyState: async () => (await errorRatePct()) < 1,   // probe BEFORE and AFTER
  inject: () => proxy.delay({ route: "/rest/v1/profiles", ms: 8000 }),
  rollback: () => proxy.reset(),
  blastRadius: { env: "staging", tenants: ["canary"] },
};
```

Run steady-state → inject → re-check steady-state → rollback → re-check. A passing experiment is one where steady-state holds *during* injection, or degrades gracefully and recovers fully after.

## 3. Inject faults at the right layer

**Client (Dart/Flutter)** — wrap the HTTP client so faults are deterministic and unit-testable:

```dart
class ChaosInterceptor extends Interceptor {
  final double dropRate;
  final Duration extraLatency;
  ChaosInterceptor({this.dropRate = 0, this.extraLatency = Duration.zero});

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    if (extraLatency > Duration.zero) await Future.delayed(extraLatency);
    if (_rng.nextDouble() < dropRate) {
      return h.reject(DioException(requestOptions: o, type: DioExceptionType.connectionError));
    }
    h.next(o);
  }
}
```

Assert the *user-visible* contract, not the exception:

```dart
test('cached profile shown when network drops', () async {
  final repo = ProfileRepo(dio: dioWith(ChaosInterceptor(dropRate: 1.0)), cache: warmCache);
  final p = await repo.getProfile('u1');
  expect(p.source, ProfileSource.cache);   // graceful degradation, not a thrown error
});
```

**Edge / TypeScript** — fail the dependency, then assert the timeout and fallback:

```typescript
it("returns 503 fast, not a 30s hang, when DB is unreachable", async () => {
  withDbUnreachable(() => {
    const t0 = Date.now();
    const res = await handler(req);
    expect(res.status).toBe(503);
    expect(Date.now() - t0).toBeLessThan(2500);   // a timeout EXISTS
  });
});
```

**Infra** — use a fault-injection proxy or `tc`/`iptables` in a throwaway namespace. Never run network faults against shared prod hosts.

## 4. The four faults that catch the most bugs

1. **Latency** (slow, not dead) — exposes missing timeouts. The dead-dependency case is usually handled; the *slow* one starves pools and hangs UIs.
2. **Partial failure** — 1 of N calls fails. Reveals all-or-nothing code that should be partially-available.
3. **Reconnect storm** — kill realtime, watch reconnect. Look for synchronized retries; require jitter.
4. **Dependency lies** — returns 200 with garbage/empty body. Validation gaps surface here.

## 5. Game day procedure

1. Announce window, scope, and the abort word. Page nobody by accident.
2. Assign roles: one drives faults, one watches dashboards, one scribes timeline.
3. Inject **one** fault. Observe. Do not stack faults until the first is understood.
4. Record: time-to-detect, time-to-recover, and every surprise.
5. Rollback. Confirm full recovery to steady state before the next round.
6. Convert each surprise into a regression test (Section 3) so it can never surprise twice.

## 6. Red flags

- "We'll test resilience in prod later." Later never comes; the incident does.
- Retries with no cap, no backoff, or no jitter — you built a self-DDoS.
- A timeout longer than the user's patience (>10s) or absent entirely.
- Catch-all `catch (_) {}` that swallows the fault you are trying to observe.
- Circuit breaker that never closes again — no half-open probe.
- Experiment has no rollback, or rollback was never rehearsed.
- "It recovered" with no metric showing return to steady state.

## 7. Wire it in

- Add the cheap, deterministic faults (interceptor, DB-unreachable) to the regular test suite so resilience does not rot.
- Keep destructive/network experiments behind an explicit flag and run on a schedule, never on every push.
- After fixing a discovered failure, add a test and commit it per [[commit-pipeline]].
- For deciding which user-facing degradation is acceptable, defer to [[error-handling-and-observability]] if present.

## Definition of done

Every ranked seam has a written hypothesis, a coded experiment, and either a passing graceful-degradation test or a tracked fix. Steady state returns after every injected fault.
