---
name: capacity-cost-tradeoff-and-rightsizing
description: Triggers when tuning resource allocation against spend — rightsizing compute/storage, autoscaling policies, spot/reserved choices, and load-vs-cost tradeoffs for a given SLO.
---

# Capacity, Cost Tradeoff, and Rightsizing

Spend is a dependent variable. You don't "cut cost" — you pick a target reliability, then buy
the cheapest capacity that holds it. Optimize against an SLO, never against the bill alone.

## Step 0 — Refuse to guess

Before changing any instance size, scaling rule, or storage tier, get three numbers:

1. **The SLO it must protect** — e.g. p99 latency < 300 ms, error rate < 0.1%. No SLO → no
   target → you're flying blind. See [[slos-and-error-budgets]].
2. **Real utilization** — CPU, memory, IOPS, connection count at p50 and p95 over 2–4 weeks.
   A single-day snapshot hides weekly batch jobs and end-of-month spikes.
3. **The cost driver** — which line item dominates? Compute, egress, storage, managed-DB tier,
   or per-invocation function billing. Optimize the top one; ignore rounding errors.

Red flag: "this box looks expensive, let's downsize it." That's a guess. Measure first.

## Step 1 — Read utilization, then size to the constraint

Rightsizing means matching the resource to whichever dimension saturates first.

- **CPU-bound**: provision to p95 CPU + headroom for the autoscaler's reaction time.
- **Memory-bound**: size to peak RSS, not average — OOM kills don't average out.
- **IO/connection-bound**: the bottleneck is often the database connection pool, not CPU.

```sql
-- Supabase/Postgres: is the instance actually working, or idle and oversized?
select
  max_conn,
  used,
  round(100.0 * used / max_conn, 1) as pct_used
from (
  select count(*) used, (select setting::int from pg_settings where name='max_connections') max_conn
  from pg_stat_activity
) s;
```

If `pct_used` peaks at 15%, you're paying for a tier you don't use. If it peaks at 95%, a pgBouncer
pool or higher tier protects the SLO — don't shrink it.

Decision: **downsize when p95 utilization sits below ~40% with stable load.** Otherwise hold.

## Step 2 — Right scaling shape: vertical, horizontal, or serverless

| Workload | Cheapest shape that holds the SLO |
|---|---|
| Steady, predictable | Reserved/committed capacity, sized to p95 |
| Spiky, bursty | Horizontal autoscale on a small base + spot for the burst |
| Idle most of the time | Serverless / scale-to-zero (e.g. Supabase Edge Functions) |
| Sustained high throughput | Vertical first (fewer cross-node hops), then shard |

Serverless wins on *idle* workloads and loses on *sustained* ones — per-invocation billing
crosses over a continuously-running container somewhere around steady moderate traffic. Estimate
the crossover before committing; don't assume serverless is always cheaper.

## Step 3 — Tune autoscaling to the SLO, not to a round number

A "scale at 80% CPU" rule is a default, not a decision. Derive the threshold:

- **Scale-out trigger** = utilization where added latency starts eating the error budget,
  minus the headroom the scaler needs to spin up a new unit. Slow cold starts → lower threshold.
- **Scale-in** must be slower than scale-out (asymmetric). Aggressive scale-in causes flapping:
  pay for churn and risk a thundering reconnect when traffic returns.
- **Floor** = enough capacity to absorb one instance failure without breaching the SLO.

```ts
// Conceptual scaling policy — encode the reasoning, not a magic number.
const policy = {
  metric: "cpu_p95",
  scaleOutAt: 0.65,     // below 80%: cold start is ~40s, need runway before SLO bites
  scaleInAt: 0.35,      // wide gap from scaleOut prevents flapping
  cooldownOutSec: 60,
  cooldownInSec: 300,   // scale in slowly and deliberately
  min: 2,               // survive one unit loss
  max: 12,              // cost ceiling — alert before hitting it
};
```

Red flag: a `max` you actually hit during normal peaks. That's not a cost ceiling, it's an
outage waiting for the next spike. Raise `max` or fix the underlying inefficiency.

## Step 4 — Spot, reserved, on-demand: match commitment to predictability

- **Reserved / committed** for the floor you'll run 24/7 for a year. Biggest discount, lowest risk.
- **Spot / preemptible** for fault-tolerant, retryable, stateless burst work (batch, async
  queue consumers, CI). Never for stateful primaries or anything without graceful drain.
- **On-demand** for the unpredictable middle and as spot's fallback.

Blend, don't pick one. A typical safe mix: reserved base + on-demand steady + spot for the spiky top.
Guard spot with a drain handler so a reclaim doesn't drop in-flight work — see
[[resilience-and-fault-tolerance]].

## Step 5 — Storage and data transfer (the silent bill)

Compute gets the attention; storage and egress quietly grow.

- **Tier by access pattern**: hot for active rows, cold/archive for audit logs and old events.
- **Egress is often the surprise** — cross-region replication, chatty client APIs, and
  un-cached assets. A CDN or response cache can beat any compute tuning; see [[caching-strategy]].
- **Retention is a cost lever**: define how long logs, backups, and soft-deleted rows live.
  Unbounded growth is a cost bug, not a feature. (Backups still protected — see
  [[backup-and-disaster-recovery]].)
- Flutter clients: oversized image payloads and unbounded query pages drive both egress and DB
  load. Page and project columns; never `select('*')` over wide tables on a list screen.

## Step 6 — Verify the change held the SLO

A cost change is not done when the bill drops — it's done when the bill drops *and the SLO holds*.

1. Apply the change to one environment / a canary slice first.
2. Run representative load — see [[load-and-stress-testing]] — at peak shape, not average.
3. Confirm p95/p99 latency and error rate stay inside budget for a full traffic cycle
   (include the weekly/monthly spike).
4. Compare projected vs actual spend after one billing cycle; re-measure utilization.

Roll back fast if the SLO breaches. A few dollars saved is never worth burning the error budget.

## Anti-patterns

- Sizing to averages — peaks cause the outages and averages hide them.
- One-time rightsizing — load drifts; schedule a quarterly re-measure.
- Optimizing a 2% line item while a 60% one sits untouched.
- Spot for stateful or non-retryable work.
- Treating the autoscaler `max` as aspirational rather than a real, alerted ceiling.
- Cutting the floor below single-instance-failure survival to save money.

## When you actually save real money

Estimate the saving before acting (see [[scalability-and-capacity-planning]]), pick the largest
driver, change one variable, verify the SLO, then commit per [[commit-pipeline]]. Log the
before/after numbers in the commit body so the next person can see the reasoning, not just the diff.
