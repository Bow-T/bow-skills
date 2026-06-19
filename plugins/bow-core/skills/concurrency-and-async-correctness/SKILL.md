---
name: concurrency-and-async-correctness
description: Trigger when sharing mutable state across threads/tasks, using locks/async-await/futures/isolates, debugging race conditions or deadlocks, ordering side effects, or reasoning about atomicity and memory visibility.
---

# Concurrency and Async Correctness

A process for writing concurrent code that stays correct under arbitrary interleaving — not just the schedule you observed once on your machine.

## Step 0: Name the concurrency model first

Different runtimes give different guarantees. Misjudging this is the root of most bugs.

- **JS / TypeScript / Dart event loop**: single-threaded, cooperative. No two lines run "at the same time," but any `await` is a yield point where other tasks interleave. There is no preemption *inside* synchronous runs.
- **Dart isolates / Web Workers**: true parallelism, *no shared memory*. Communicate by message passing only.
- **OS threads (native, server runtimes, pools)**: true parallelism with shared memory — atomicity and memory visibility matter.

Write down which model applies before reasoning further. The rest of this skill branches on it.

## Step 1: Find the shared mutable state

List every piece of state touched by more than one task/thread. For each, decide:

1. Can it be made immutable or task-local? (Best fix — eliminates the problem.)
2. If shared, what is the *invariant* that must hold across reads/writes?
3. Where is that invariant temporarily broken (the critical section)?

> Red flag: you cannot state the invariant in one sentence. Then you cannot protect it.

## Step 2: Eliminate interleaving hazards in event-loop code

Single-threaded does NOT mean safe. The danger is **state observed before an `await` becoming stale after it**.

```ts
// BUG: check-then-act across an await — two callers both pass the guard.
async function joinRoom(id: string) {
  if (members.size >= MAX) return reject();   // read
  await db.insert(id);                        // <-- yield: another joinRoom runs here
  members.add(id);                            // act on stale count -> overflow
}
```

Fixes, in order of preference:
- Re-validate *after* awaits, inside the same synchronous chunk that mutates.
- Enforce the invariant where it is atomic — e.g. a DB constraint or conditional write (`insert ... where count < max`, a unique index, or a Supabase row-level check) rather than in app memory.
- Serialize the critical operation with an async mutex / single-flight queue.

```ts
const inflight = new Map<string, Promise<User>>();
function loadUser(id: string): Promise<User> {
  let p = inflight.get(id);
  if (!p) { p = fetchUser(id).finally(() => inflight.delete(id)); inflight.set(id, p); }
  return p; // dedupes concurrent callers; no thundering herd
}
```

## Step 3: Order side effects deliberately

`await` does not guarantee the order you wrote if you fire promises eagerly.

```ts
// Runs in parallel; completion order is nondeterministic.
const [a, b] = await Promise.all([stepA(), stepB()]);

// Sequential when B depends on A's effects.
const a = await stepA();
const b = await stepB(a);
```

Decision rule: parallel only when operations are **independent**. If B reads what A writes, sequence them. For N parallel tasks with a cap, bound concurrency (a pool / semaphore) — unbounded `Promise.all` over a large list exhausts connections and sockets.

## Step 4: Flutter / Dart specifics

- **No `await` between read and write of shared widget/controller state** without re-checking. After an `await`, the widget may be disposed.

```dart
Future<void> save() async {
  final value = controller.text;     // capture before await
  await repo.persist(value);
  if (!mounted) return;              // guard: State may be gone
  setState(() => _saved = true);
}
```

- Use a lock for ordered async sections that must not overlap:

```dart
final _lock = Lock(); // package:synchronized
Future<void> sync() => _lock.synchronized(() async {
  final remote = await api.fetch();
  await db.merge(remote);            // serialized; no interleaved sync()
});
```

- CPU-bound work goes to an isolate (`Isolate.run`) to avoid jank. Remember: isolates do not share memory — pass data, do not reference it.

## Step 5: Threads with shared memory (atomicity + visibility)

Two distinct problems; both must be solved:

- **Atomicity**: `count++` is read-modify-write, not one step. Use atomics or a lock.
- **Visibility**: a write on one thread may stay invisible to another without a memory barrier. Locks, atomics, and volatile-equivalents publish the write.

Rules:
- Acquire multiple locks in a **fixed global order** — the simplest deadlock cure.
- Never hold a lock across an `await`, blocking I/O, or a callback you do not control — that is how deadlocks and priority inversions are born.
- Prefer immutable snapshots and message passing over fine-grained locking when you can.

## Step 6: Cancellation, timeouts, and cleanup

Every long-running async op needs a cancel/timeout path, and cleanup must be exception-safe.

```ts
const ac = new AbortController();
const t = setTimeout(() => ac.abort(), 5000);
try { return await fetch(url, { signal: ac.signal }); }
finally { clearTimeout(t); }  // runs on success, error, AND abort
```

In Dart, propagate cancellation via stream subscriptions / `CancelableOperation` and always `cancel()` subscriptions and `close()` controllers in `dispose`.

## Step 7: Test the interleavings, not the happy path

- Drive concurrency in tests: launch the suspect operation N times with `Promise.all` / parallel futures and assert the invariant holds.
- Inject delays at yield points to force the bad schedule (`await delay(rand)` before the mutation).
- For idempotency, replay the same message/request twice and assert one effect.
- Stress in a loop; race bugs surface by frequency, not by a single run passing.

## Red flags checklist

- Check-then-act with an `await` in between.
- `setState` / UI mutation after `await` with no `mounted` guard.
- Unbounded `Promise.all` over external resources.
- A lock held across `await` or blocking I/O.
- Locks acquired in different orders on different paths.
- Shared counter / list mutated from multiple threads without atomics.
- An invariant enforced only in app memory that a DB constraint could enforce atomically.
- "It works on my machine but flakes in CI" — almost always a real race.

## Related skills

- [[error-handling-and-resilience]] for retry, timeout, and backoff policy.
- [[octopus-model]] for placing invariants in the data layer (constraints, conditional writes).
- [[testing-strategy]] for structuring the stress/interleaving tests above.
- When committing, follow [[commit-pipeline]].
