---
name: flutter-async-and-isolates
description: Triggers when handling concurrency — Future/Stream/async-await correctness, cancellation, compute()/Isolate.run for CPU-bound work, avoiding main-isolate jank, and passing data across isolate boundaries.
---

# Flutter Async and Isolates

Dart is single-threaded per isolate with a cooperative event loop. `async` does NOT add a
thread — it yields control. CPU-bound work on the main isolate blocks frame rendering and
janks the UI. This skill keeps async code correct and moves heavy work off the UI thread.

## Mental model first

- One isolate = one event loop + one heap. Code runs to completion between events; nothing
  preempts you mid-function. So a tight `for` loop summing a million items freezes the UI
  even inside an `async` function.
- `await` only helps when the work is I/O-bound (network, file, platform channel) — it lets
  the loop pump frames while waiting. It does nothing for pure computation.
- Microtasks (resolved futures, `scheduleMicrotask`) run before the next event/frame. A
  recursive microtask chain can starve rendering. Use `Future(...)` (event queue), not
  `Future.microtask`, for yield-and-repaint work.

## Workflow

### 1. Classify the work

Before touching code, decide which bucket:

| Work | Symptom | Fix |
|---|---|---|
| I/O-bound (HTTP, DB, disk) | Spinner is fine, UI responsive | plain `async`/`await` |
| Short CPU (<8ms) | None | leave on main isolate |
| Heavy CPU (parse 5MB JSON, image filter, crypto) | Frame drops, jank | `compute` / `Isolate.run` |
| Long-lived streaming compute | Repeated heavy callbacks | long-lived isolate + ports |

8ms is the budget: at 60fps a frame is 16.6ms, and the framework needs the rest. If a sync
call can exceed it on a low-end device, offload it.

### 2. Get async-await correctness right

```dart
// WRONG: unawaited future — error vanishes, ordering is undefined.
void save() {
  repository.persist(model); // fire-and-forget, no error handling
}

// RIGHT: await, or explicitly mark intentional fire-and-forget.
Future<void> save() async {
  try {
    await repository.persist(model);
  } on PersistException catch (e, st) {
    _log.severe('persist failed', e, st);
    rethrow;
  }
}
```

- Never `await` inside a `forEach` — it does not wait. Use a `for` loop with `await`, or
  `Future.wait` for concurrent independent calls:

```dart
// Sequential when order/back-pressure matters:
for (final id in ids) {
  await fetchAndStore(id);
}
// Concurrent when they are independent (fail-fast on first error):
final results = await Future.wait(ids.map(fetch));
// Concurrent but collect all outcomes, even failures:
final settled = await Future.wait(
  ids.map((id) => fetch(id).then((v) => (id, v)).catchError(...)),
);
```

- Guard every `setState`/notify after an `await` with a mounted check — the widget may be
  gone:

```dart
final data = await load();
if (!mounted) return; // State.mounted, or context.mounted for BuildContext use
setState(() => _data = data);
```

### 3. Handle cancellation — Futures don't cancel

A `Future` cannot be cancelled. Model cancellation explicitly so stale results never win:

```dart
// Generation guard: ignore results from superseded requests.
int _searchGen = 0;
Future<void> search(String q) async {
  final gen = ++_searchGen;
  final results = await api.search(q);
  if (gen != _searchGen) return; // a newer search started; drop these
  if (!mounted) return;
  setState(() => _results = results);
}
```

For real teardown (close sockets, abort), prefer `StreamSubscription.cancel()` and a
`CancelToken` (Dio) or pass a `Completer`/`http` client you can `.close()`. Always cancel
subscriptions and timers in `dispose`:

```dart
StreamSubscription<Pos>? _sub;
@override
void initState() {
  super.initState();
  _sub = positionStream.listen(_onPos);
}
@override
void dispose() {
  _sub?.cancel();
  super.dispose();
}
```

### 4. Offload CPU with compute / Isolate.run

`Isolate.run` (Dart 2.19+) is the modern one-shot off-thread call; `compute` is the older
Flutter equivalent. Both spawn an isolate, run, return, and tear down.

```dart
// Heavy parse off the UI thread:
Future<List<Sample>> parseLarge(String raw) {
  return Isolate.run(() => _decode(raw)); // _decode is a pure top-level/static fn
}

// compute requires a top-level or static function taking one argument:
final report = await compute(_buildReport, rawCsv);
List<Row> _buildReport(String csv) { /* pure CPU */ }
```

Constraints that bite:
- The entry function must be **top-level or static** (closures capture state that can't cross
  isolates). `Isolate.run` relaxes this to any closure, but the closure still must not
  capture non-sendable objects.
- Arguments and results are **deep-copied** across the boundary (except `TransferableTypedData`
  and a few primitives). Sending a 50MB list copies 50MB twice. For large buffers use
  `TransferableTypedData.fromList(...)` to move bytes with zero-copy.
- You cannot touch the UI, `BuildContext`, plugins that need the main isolate, or platform
  channels (most) from inside. Do pure data work only.

### 5. Long-lived isolates for repeated work

For a worker you call many times (e.g. a decode pipeline), spawning per call wastes startup
cost. Use `Isolate.spawn` with bidirectional `SendPort`s, or the simpler `IsolateNameServer`
patterns from packages. Keep it boring: a request id, a response port, and a map of pending
completers.

```dart
final p = ReceivePort();
await Isolate.spawn(_worker, p.sendPort);
final SendPort toWorker = await p.first; // worker sends its port back first
```

Reach for a package before hand-rolling: `worker_manager` (pools, cancellation),
`squadron`, or `flutter_isolate` (plugin access inside isolates). Don't build a pool unless
profiling shows spawn cost matters.

### 6. Streams without leaks or double-listens

- Single-subscription streams throw on a second `listen`. Use a `StreamController.broadcast`
  for fan-out, but remember broadcast streams drop events emitted before a listener attaches.
- Debounce/throttle user-driven streams (`stream_transform`'s `debounce`, or a `Timer`) to
  cut redundant work.
- Prefer `await for` over manual `listen` when you want structured cancellation tied to the
  enclosing async function:

```dart
await for (final event in channel.events) {
  if (_done) break; // exits and cancels the subscription
  handle(event);
}
```

## Verify

- Toggle the Performance overlay / DevTools timeline and confirm no frame exceeds ~16ms
  during the heavy operation. Jank gone = offload worked. See [[performance-optimization]].
- Test cancellation: fire request A, fire B, complete A last — assert A's result is dropped.
- Run on a low-end physical device, not just the simulator; release-mode timings differ.

## Anti-patterns

- `async` on a CPU loop and expecting it to unblock the UI — it won't; offload instead.
- Sending huge collections to an isolate by value when `TransferableTypedData` would move bytes.
- Unawaited futures swallowing errors — set `lint: unawaited_futures` and use `unawaited()`
  only with intent.
- `setState` after `await` without a `mounted` check.
- Per-call `Isolate.run` inside a tight stream handler — pool or keep a long-lived isolate.

## Related

- [[flutter-mvvm]] for where async lives relative to view-models and lifecycle.
- [[concurrency-and-async-correctness]] for race/ordering reasoning beyond Dart specifics.
- [[debugging-and-error-recovery]] when an async bug's root cause is unclear.
- Commit work via [[commit-pipeline]].
