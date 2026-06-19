---
name: scalability-and-capacity-planning
description: Triggers when estimating capacity, choosing horizontal vs vertical scaling, hunting bottlenecks under projected load, planning sharding/partitioning, or sizing infra to a growth forecast.
---

# Scalability and Capacity Planning

Plan for the load you will have, not the load you have. Work backwards from a forecast to concrete resource ceilings, find the first thing that breaks, and prove the headroom before the traffic arrives.

## 1. Quantify the forecast first

Do not start with architecture. Start with numbers. If you cannot write the load as figures, you are guessing.

Capture for the planning horizon (e.g. 12 months):

- **Peak RPS**, not average. Compute peak from daily/weekly shape. A common rule: peak ≈ 3-5x the average for consumer apps with a daily cycle.
- **Data growth**: rows/day and bytes/day per high-volume table.
- **Concurrency**: simultaneous active sessions, websocket/Realtime connections.
- **Read:write ratio** per critical path.

```
avg_rps      = daily_requests / 86400
peak_rps     = avg_rps * peak_factor          // measure peak_factor from real traffic, don't assume
target_rps   = peak_rps * growth_multiple      // e.g. 4x for the horizon
headroom_rps = target_rps * 1.5                // size to this, not target_rps
```

Red flag: a forecast expressed only as "10x users." Translate every business number into RPS, rows, bytes, and connections, or it is not a plan.

## 2. Establish a single-node baseline

You cannot plan capacity without knowing what one unit does today. Load-test one instance / one database to saturation.

- Drive load with a real tool (`k6`, `vegeta`, `oha`), replaying production-shaped traffic — not a single hot endpoint.
- Record the **knee**: the RPS where p95 latency starts climbing non-linearly. That, not max throughput, is your usable ceiling per node.
- Note which resource saturates at the knee: CPU, memory, DB connections, IOPS, or network.

```bash
# Saturation sweep against one node
oha -z 60s -c 200 https://staging.example.com/api/checkout
# Watch: requests/sec, p95/p99, and the saturating resource (top, db pool, iostat)
```

Red flag: reporting a throughput number without the latency at that throughput. 50k RPS at p99 = 8s is not capacity, it is a queue.

## 3. Find the binding constraint

Throughput is set by the single most contended resource. Identify it before scaling anything — scaling a non-bottleneck buys nothing.

Walk the request path and rank limits:

| Layer | Typical first limit | How to confirm |
|---|---|---|
| Edge function / app | CPU, event-loop lag | flame graph, p99 under load |
| Connection pool | exhausted pool, queueing | pool wait time metric |
| Database | IOPS, lock contention, slow queries | `pg_stat_statements`, query plans |
| Hot key / partition | one shard does all the work | per-key throughput distribution |

For Supabase/Postgres, the pool is usually the first wall before the DB itself. Front the database with a pooler (transaction mode) and size the app to the pool, not the other way around.

```sql
-- Find the queries that will break first under volume
SELECT calls, mean_exec_time, total_exec_time, query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

Red flag: adding app replicas while every replica points at one Postgres connection pool. You just moved the queue.

## 4. Decide horizontal vs vertical

Default to **vertical first, horizontal forever**. Vertical is cheaper to operate and buys time; horizontal is required for unbounded growth but adds coordination cost.

Choose **vertical** (bigger node) when:
- A single bump clears the forecast with headroom to spare.
- State is hard to distribute (a primary write DB).
- You are buying months to design the horizontal path properly.

Choose **horizontal** (more nodes) when:
- The forecast exceeds any single node's ceiling.
- The workload is stateless or partitionable.
- You need failure isolation and rolling deploys.

Make the app horizontally ready regardless: no in-process session state, no local-disk assumptions, idempotent handlers. A stateless tier scales by changing a replica count; a stateful one needs a migration.

Red flag: "we'll add a cache" used as the scaling plan. A cache hides a bottleneck until the hit rate drops; it is not capacity.

## 5. Plan partitioning and sharding before you need it

Decide the partition key while the table is small. Re-sharding live data under load is the most expensive operation you can defer.

Order of escalation for a growing table:

1. **Index and query tuning** — most "scale" problems are a missing index.
2. **Time partitioning** (`PARTITION BY RANGE`) for append-heavy, time-bounded data (events, logs, metrics). Cheap to add, lets you drop old partitions instead of `DELETE`.
3. **Sharding by tenant/entity key** only when one node cannot hold the working set or write throughput.

```sql
-- Time-partition an append-heavy table before it gets huge
CREATE TABLE events (
  id bigint, tenant_id uuid, created_at timestamptz NOT NULL, payload jsonb
) PARTITION BY RANGE (created_at);

CREATE TABLE events_2026_06 PARTITION OF events
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
```

Shard-key checklist:
- High cardinality and even distribution (avoid a key where one tenant is 90% of traffic).
- Present on every hot query so reads hit one shard, not a fan-out.
- Stable — the value must not change for a row's lifetime.

Red flag: choosing `created_at` or an auto-increment id as a shard key — guarantees a single hot shard for all new writes.

## 6. Size the infrastructure to the forecast

Translate the knee and the binding constraint into a node count and a margin.

```ts
function planNodes(targetRps: number, kneeRpsPerNode: number) {
  const utilizationCeiling = 0.6;          // never plan past 60% steady-state
  const usable = kneeRpsPerNode * utilizationCeiling;
  const required = Math.ceil(targetRps / usable);
  return { nodes: required, headroomNodes: required + Math.ceil(required * 0.3) };
}
// planNodes(8000, 1200) -> { nodes: 12, headroomNodes: 16 }
```

Rules:
- Plan steady state at ≤60% utilization so a node loss or a spike does not cascade.
- Size for **peak + failure**: N+1 minimum, N+2 if a single node is a large fraction of capacity.
- Cost the plan. Put RPS-per-dollar next to the architecture choice; vertical often wins on cost until the ceiling.

## 7. Set autoscaling and backpressure, not just a ceiling

Static sizing handles the forecast; the system still needs to survive being wrong.

- **Autoscale on the saturating signal** (CPU, queue depth, pool wait) — not request count alone.
- **Shed load** before falling over: rate-limit per client, return `429` with `Retry-After`, prioritize critical paths.
- **Queue async work** so spikes drain over time instead of toppling the DB.

```dart
// Flutter client: respect backpressure instead of hammering a degraded backend
Future<Response> withRetry(Future<Response> Function() call) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    final res = await call();
    if (res.statusCode != 429) return res;
    final wait = int.tryParse(res.headers['retry-after'] ?? '') ?? (1 << attempt);
    await Future.delayed(Duration(seconds: wait));
  }
  throw Exception('Upstream saturated');
}
```

Red flag: autoscaling a stateless tier into a fixed database. The tier scales, the connection pool does not, and the DB falls first.

## 8. Validate, then watch

A capacity plan is a hypothesis until load-tested at the target number.

- Run a **soak test at `headroom_rps`** for long enough to expose leaks, partition skew, and pool exhaustion.
- Define alerts at the planning thresholds: alert at 60% utilization (act), page at 80% (the plan is being consumed faster than forecast).
- Re-run the forecast quarterly; growth assumptions decay.

Record the model — forecast inputs, knee, node math, validated numbers — alongside the change so the next planner inherits the reasoning. See [[architecture-decision-records]] for capturing the scaling decision and its trade-offs.

When committing the plan, infra config, or migration, follow [[commit-pipeline]].
