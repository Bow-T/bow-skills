---
name: memory-and-resource-leak-diagnosis
description: Triggers when a process grows unbounded or exhausts resources — heap/leak profiling, GC tuning, file-descriptor and connection-pool exhaustion, and OOM-kill investigation.
---

# Memory and resource leak diagnosis

A leak is a slope, not a spike. Before you profile anything, confirm you are
chasing a leak and not normal saturation, a one-time load, or a cache that is
working as designed.

## 0. Classify the symptom first

| Symptom | Likely class | First instrument |
|---|---|---|
| RSS climbs steadily, never plateaus, then OOM-kill | Memory leak | Heap snapshots over time |
| Memory plateaus high but stable, throughput drops | GC pressure / churn | GC/allocation logs |
| "Too many open files" / `EMFILE` | FD or socket leak | `lsof` count over time |
| "Connection pool timeout" / "remaining connection slots" | Pool/connection leak | Pool gauge + DB session count |
| Fast spike then crash | Not a leak — a single oversized allocation | Single-request memory diff |

Decision: if the resource curve **returns to baseline** after load stops, it is
not a leak — it is capacity. Hand off to [[scalability-and-capacity-planning]].

## 1. Establish the slope with evidence

Never trust "it feels like it's leaking." Plot it.

- Sample one number on a fixed interval and confirm a monotonic trend across
  several GC cycles. A leak survives garbage collection; churn does not.
- Hold load roughly constant while sampling, or you cannot separate leak from traffic.

```bash
# Node/TS service: RSS + heap every 10s, timestamped
while sleep 10; do
  node -e 'const m=process.memoryUsage();console.log(Date.now(),m.rss,m.heapUsed)'
done
# Or for any PID:
while sleep 10; do ps -o rss= -p "$PID"; done
```

For a Supabase edge function (Deno), log `Deno.memoryUsage().rss` per invocation
and watch whether warm-instance RSS drifts up across requests.

Red flag: heapUsed flat but RSS climbing → leak is **outside** the JS heap
(native buffers, FDs, off-heap allocations), not in objects you can snapshot.

## 2. Memory leaks: diff, don't stare

A single snapshot tells you what is big, not what is leaking. Take **two or
three** under steady load and diff retained size.

**Node / TypeScript**

```bash
node --inspect server.js        # then attach DevTools → Memory
# or programmatic, comparable across runs:
node --heapsnapshot-signal=SIGUSR2 server.js
kill -USR2 $PID                 # snapshot 1, drive load, repeat
```

In the diff, sort by **retained size delta** and follow the **retainer path** to
the root. The object growing is rarely the bug; the collection still pointing at
it is. Usual roots: a module-level `Map`/array that only ever `.push`/`.set`, an
event emitter never `.off()`d, a closure captured in a long-lived callback,
unbounded in-memory cache, or timers that re-arm.

```ts
// Classic: listener added per request, never removed → emitter retains every closure
client.on('message', handler);   // leak
// Fix: scope + teardown
client.on('message', handler);
req.signal.addEventListener('abort', () => client.off('message', handler));
```

**Dart / Flutter** — the dominant leak is undisposed objects.

```dart
// Every long-lived holder of resources MUST be released in dispose().
@override
void dispose() {
  _controller.dispose();           // TextEditingController, AnimationController
  _subscription.cancel();          // StreamSubscription
  _timer?.cancel();
  _focusNode.dispose();
  super.dispose();
}
```

Use DevTools → Memory: take a snapshot, navigate away from the screen, force GC,
snapshot again. Any widget/State/controller from the closed screen still present
is leaked. The leak tracker (`flutter run --track-widget-creation` + DevTools)
flags un-disposed `Disposable`s directly. In MVVM, an undisposed view-model or a
`Stream` listened to without cancellation is the repeat offender — see
[[flutter-mvvm]] for the lifecycle hooks that own this.

Red flags: growing `static`/global collections, `addListener` without
`removeListener`, `StreamController` never `close()`d, image/byte caches with no
eviction bound, `GlobalKey`s retained past their widget.

## 3. GC pressure (high but stable) is a different bug

If memory plateaus but the process is slow and CPU spikes in GC, you are
allocating too fast, not leaking.

- Confirm: `node --trace-gc` (or DevTools allocation timeline). Frequent
  major/full collections = churn.
- Fix the allocation pattern, not the heap size: reuse buffers, avoid creating
  closures/objects in hot loops, stream large payloads instead of materializing
  them, paginate DB reads (defer to [[database-query-optimization]] for
  unbounded result sets).
- Only after fixing churn, consider tuning `--max-old-space-size`. Raising the
  cap on a real leak just delays the OOM and makes snapshots harder.

In Flutter, GC churn shows as jank: avoid rebuilding heavy objects in `build()`,
allocating in scroll callbacks, or decoding images without `cacheWidth`.

## 4. File-descriptor and connection leaks

These masquerade as memory problems and kill the process with `EMFILE` or pool
timeouts long before RSS does.

```bash
ls /proc/$PID/fd | wc -l      # Linux: live FD count — watch it trend up
lsof -p $PID | sort | uniq -c | sort -rn | head   # what kind: sockets? files?
ulimit -n                     # the ceiling you will hit
```

Each leaked socket holds an FD **and** off-heap memory. The cause is almost
always an early-return or thrown error between acquire and release.

```ts
// Leak: throw skips release
const conn = await pool.connect();
const rows = await conn.query(sql);   // if this throws, conn never returned
pool.release(conn);
// Fix: release in finally — always
const conn = await pool.connect();
try { return await conn.query(sql); }
finally { conn.release(); }
```

**Supabase / Postgres**: a connection leak shows as `remaining connection slots
are reserved` or pool timeouts under load that never recover.

```sql
-- Who is holding connections, and are they idle in transaction (a leak smell)?
select state, count(*) from pg_stat_activity group by state;
select pid, state, now()-state_change as idle_for, query
from pg_stat_activity where state = 'idle in transaction'
order by idle_for desc;
```

`idle in transaction` accumulating means code opens a transaction and never
commits/rolls back. In edge functions, prefer the pooled connection string and
always release per invocation — never cache a raw client in module scope across
warm invocations unless it is explicitly pool-managed.

Red flags: HTTP clients created per request instead of reused; `fetch` responses
whose body is never consumed/closed; DB clients opened in a loop; missing
`finally`; subscriptions to realtime channels never unsubscribed.

## 5. OOM-kill investigation

When the kernel kills you, exit code and dmesg tell the story.

```bash
dmesg | grep -i -E 'killed process|oom'    # confirm OOM-killer, see RSS at death
# Containers: exit code 137 = SIGKILL, usually cgroup memory limit hit
kubectl describe pod <pod> | grep -A3 'Last State'   # OOMKilled?
```

Distinguish:
- **Steady climb to limit** → real leak; go to section 2/4.
- **Single request spikes past limit** → unbounded allocation (loading a whole
  table, decoding a huge upload, building a giant string). Cap input size and
  stream.
- **Limit set below steady-state need** → not a bug, raise the limit and
  document the working-set size.

Always capture a heap snapshot or core *before* restarting — a restart erases
the only evidence. Wire `--heapsnapshot-near-heap-limit=1` (Node) so a snapshot
lands automatically just before OOM.

## 6. Verify the fix the only way that counts

A leak fix is proven by the slope, not by reading the diff. Reproduce the
original load, run **long enough to cross several GC cycles**, and show RSS/FD
count returning to a flat plateau. A short run that "looks better" proves
nothing — see the verify-don't-assume rule in the core agreement.

Add a regression guard: a soak test in CI that drives N iterations and asserts
heap/FD delta stays under a threshold. Pair instrumentation with
[[observability-and-instrumentation]] so the slope is visible in production, and
[[load-and-stress-testing]] for the sustained workload that surfaces slow leaks.

When committing the fix, follow [[commit-pipeline]].

## Triage checklist

- [ ] Confirmed a monotonic slope across GC cycles, not capacity saturation
- [ ] Identified the resource class (heap / native / FD / connection)
- [ ] Diffed two+ snapshots and followed the retainer path to the root
- [ ] Checked `dispose()` / `finally` release / listener teardown at the leak site
- [ ] Captured evidence before restarting an OOM-killed process
- [ ] Proved the fix with a sustained soak run showing a flat plateau
