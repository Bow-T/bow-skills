---
name: load-and-stress-testing
description: Trigger when establishing a performance baseline, finding a breaking point, verifying autoscaling, running soak/spike/stress tests, or proving a capacity assumption with measurement instead of a guess.
---

# Load and Stress Testing

Load testing answers a question. If you cannot write the question as a falsifiable sentence, you are not ready to generate traffic.

## 0. Write the question first

Pick exactly one shape. Each has a different traffic profile and a different pass/fail line.

- **Baseline** — "At 200 RPS on the checkout path, p95 stays under 400 ms with <0.1% errors." Steady load, known SLO.
- **Stress** — "Where does it break, and how?" Ramp until something fails; capture the failure mode.
- **Spike** — "A 10x burst in 5s recovers within 30s." Instant load, measure recovery.
- **Soak** — "8 hours at 70% peak shows no memory growth or connection leak." Modest load, long duration.

Red flag: a test with no number to compare against. That is a demo, not a test.

## 1. Define the SLO and the test environment honestly

Decide before running, because deciding after is just rationalizing the result.

- **Metrics**: p50/p95/p99 latency, error rate, throughput (RPS), and saturation (CPU, DB connections, queue depth). Latency without throughput is meaningless — both move together.
- **Environment**: never load-test production blind. Use a Supabase preview branch or a sized staging clone. State the difference from prod explicitly (e.g. "staging DB is 1 vCPU vs prod 4 — divide throughput by ~4").
- **Data**: seed realistic row counts. A query over 100 rows and the same query over 10M rows are different programs. Empty tables hide every index problem.

## 2. Model real traffic, not a flat wall

Real users do not all hit one endpoint at the same rate. Build a weighted scenario.

```javascript
// k6 scenario: weighted journey + a ramping arrival rate
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';

const checkout = new Trend('checkout_latency', true);

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate', // open model: fixed RPS, not fixed VUs
      startRate: 50, timeUnit: '1s',
      preAllocatedVUs: 200, maxVUs: 2000,
      stages: [
        { target: 200, duration: '2m' },  // warm up
        { target: 200, duration: '5m' },  // steady baseline
        { target: 800, duration: '3m' },  // push toward the knee
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.001'],
    checkout_latency: ['p(95)<400'],
  },
};

export default function () {
  const r = Math.random();
  if (r < 0.7)      http.get(`${__ENV.BASE}/feed`);       // 70% browse
  else if (r < 0.95) http.get(`${__ENV.BASE}/product/42`); // 25% detail
  else {
    const res = http.post(`${__ENV.BASE}/checkout`, payload);
    check(res, { '200': (x) => x.status === 200 });
    checkout.add(res.timings.duration);
  }
  sleep(Math.random() * 2); // think time — real users pause
}
```

Use an **open model** (arrival rate) for capacity questions: it injects N requests/sec regardless of how slow responses get, so a slowing system shows backpressure instead of self-throttling. Use a closed model (fixed VUs) only when you genuinely model a fixed pool of clients.

Red flag: zero think time and one endpoint. You measured a microbenchmark, not your system.

## 3. Generate load from where it hurts

- **Network APIs / Supabase / TS edge functions**: `k6`, `vegeta`, or `oha`. Run from a machine with more bandwidth than the target, in the same region, or you measure the internet.
- **Flutter / Dart clients**: do not drive 1000 emulators. Capture the HTTP/Realtime traffic a real session produces, then replay it at scale against the backend. For client-side render budgets, profile the widget tree separately — that is a different test (see [[performance-optimization]] if present), not a load test.
- **Database directly**: `pgbench` against a Postgres clone to isolate whether the bottleneck is the app or the DB. Always test the DB layer separately at least once; otherwise you cannot attribute the bottleneck.

## 4. Find the knee, then characterize the failure

Ramp until throughput stops rising while latency climbs — that inflection is the **knee** (max sustainable capacity). Past it, response time goes vertical.

When it breaks, record *how*:

- **Graceful**: requests queue, latency rises, errors stay near zero. Acceptable.
- **Brownout**: rising 5xx/timeouts but the service survives and recovers. Tolerable with a circuit breaker.
- **Collapse**: cascading failure, OOM kill, connection-pool exhaustion that does not recover after load stops. Unacceptable — fix before launch.

The most common Supabase/Postgres collapse: pooler connections exhausted. Each serverless instance opening its own connection multiplies fast. Check pool mode (transaction vs session) and `max_connections` before blaming the query.

## 5. Verify autoscaling explicitly

Autoscaling is not "set and forget"; it has a reaction time you must measure.

1. Apply a spike that exceeds current capacity.
2. Measure **time-to-scale**: from threshold breach to new capacity serving traffic.
3. Watch the gap — the window before new instances are ready is where users see errors. If cold start + scale lag > spike duration, autoscaling did nothing useful.
4. Test **scale-down** too: does it shed instances without dropping in-flight requests?

Red flag: a scaling policy never tested under real spike timing. It will trigger too late in the incident that matters.

## 6. Read the result like an engineer

- Compare against the SLO sentence from step 0. Pass or fail, no narrative.
- Distrust averages. A great mean with a p99 of 8s means a slice of users is suffering — report percentiles.
- Correlate client metrics with server saturation. A latency spike at a CPU plateau is a compute bound; a latency spike at a flat CPU is lock contention, GC, or an exhausted pool.
- One variable per run. Change the query plan, the pool size, or the instance count — never two — or you cannot attribute the delta.

## 7. Make it repeatable and cheap to re-run

- Commit the test scripts and the SLO thresholds next to the code; a load test that lives on one laptop dies there. Follow [[commit-pipeline]] for the commit.
- Wire a scaled-down smoke version into CI (e.g. 60s at low RPS) to catch a 5x regression on a PR. Save the full ramp for pre-release.
- Store each run's summary (date, commit, environment, p95, knee RPS) so "is it slower than last release?" is a lookup, not a redo.

## Pitfalls that invalidate a whole run

- Testing against a warmed cache that real users will not hit — clear caches or model the realistic hit rate.
- Coordinated omission: the load tool stops sending while waiting for slow responses, hiding the worst latency. Open-model executors and tools that record intended send time avoid this.
- The load generator itself saturating (its own CPU/network) — confirm the bottleneck is the target, not your client.
- Calling it done after one green run. Run it twice; flaky capacity is still a failure.
