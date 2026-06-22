---
name: state-management-and-data-flow
description: Triggers when structuring client-side or app state — choosing local vs global state, normalizing stores, optimistic updates, cache sync, and avoiding prop-drilling or stale-state bugs.
---

# State Management and Data Flow

State bugs are rarely about the library. They come from putting state in the wrong
place, keeping two copies of the same fact, or guessing what the server holds. Decide
ownership first, then wire the flow.

## Step 1 — Classify every piece of state before storing it

Sort each value into one bucket. The bucket dictates where it lives.

| Kind | Examples | Owner |
|---|---|---|
| **Server cache** | rows from Supabase, API responses | a query/cache layer, keyed by query |
| **Shared UI state** | logged-in user, theme, selected workspace | one app-wide store |
| **Local UI state** | form text, toggles, scroll position, modal open | the widget/component itself |
| **Derived** | filtered list, totals, "is form valid" | computed on read, never stored |
| **Ephemeral transport** | in-flight request, optimistic patch | the mutation layer |

Red flag: you stored a value you could have **derived**. Two facts that must agree are
a bug waiting to happen. Compute it.

## Step 2 — Default to local; promote only on proven need

Start state as local. Lift it only when a second consumer genuinely needs the same value.

Promote when:
- two sibling subtrees must read or write the same value, or
- the value must survive navigation away and back, or
- a background event (realtime, push) must update it.

Do **not** promote because passing it down "feels tedious." Prop-drilling 2 levels is
fine; drilling 5 means the component tree is wrong or the value should be in context.

```dart
// Flutter: local stays in the widget's own state/ChangeNotifier.
class _SearchBarState extends State<SearchBar> {
  String _query = ''; // ephemeral; never goes global
}
```

## Step 3 — Treat server data as a cache, not as state you own

The source of truth lives in the database. The client holds a **stale copy**. Never
hand-roll `List<Item> _items` populated once in `initState` — it rots the moment
anything mutates server-side.

Use a query layer (Flutter: a `FutureProvider`/`AsyncNotifier`; TS: a query client)
that gives you `data | loading | error` and a refetch handle.

```dart
final tasksProvider = FutureProvider.family<List<Task>, String>((ref, projectId) async {
  final rows = await supabase.from('tasks').select().eq('project_id', projectId);
  return rows.map(Task.fromJson).toList(); // typed model — see [[flutter-data-model]]
});
```

Red flags:
- the same row cached under two different query keys (they will drift),
- manual `setState` to "keep the list in sync" after a write — invalidate the query instead.

## Step 4 — Normalize when the same entity appears in many places

If one `User` shows in a header, a list row, and a detail page, do not store three
copies. Keep entities in a map keyed by id; lists hold ids.

```ts
type Store = {
  users: Record<string, User>;        // single copy per entity
  feedOrder: string[];                // list = array of ids
};
// Update once → every view reads the fresh entity.
```

Skip normalization for flat, read-only screens — it is overhead with no payoff there.
Normalize when entities are shared and mutable.

## Step 5 — Optimistic updates with a real rollback path

For snappy UX, write to the cache before the server confirms — but only if you can
undo it cleanly.

1. Snapshot the current cached value.
2. Apply the optimistic change to the cache.
3. Fire the mutation.
4. On error: restore the snapshot and surface the failure.
5. On success: reconcile against the server's returned row (it may differ — server
   timestamps, computed columns, trigger side effects).

```dart
Future<void> toggleDone(Task task) async {
  final previous = ref.read(tasksProvider(task.projectId)).valueOrNull;
  _patchCache(task.copyWith(done: !task.done));         // optimistic
  try {
    final row = await supabase.from('tasks')
        .update({'done': !task.done}).eq('id', task.id).select().single();
    _patchCache(Task.fromJson(row));                    // reconcile, don't assume
  } catch (e) {
    if (previous != null) _restore(previous);           // rollback
    rethrow;
  }
}
```

Red flag: optimistic update with no snapshot. On failure the UI lies permanently.
Reserve optimism for low-risk, reversible actions (likes, toggles), not for money or
irreversible operations.

## Step 6 — Keep cache fresh without polling everything

Pick the cheapest invalidation that meets the need:

- **After a mutation** → invalidate exactly the affected query keys.
- **Realtime push** (Supabase channel) → patch or invalidate on the event; do not also poll.
- **Staleness window** → refetch on focus/reconnect for data that drifts slowly.

```dart
supabase.channel('tasks:$projectId')
  .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'tasks',
    callback: (_) => ref.invalidate(tasksProvider(projectId)))
  .subscribe();
```

Always handle reconnection: after the socket drops, the cache is stale. Refetch on
resubscribe — see [[resilience-and-fault-tolerance]].

## Step 7 — Make data flow one-directional and traceable

State flows **down**, events flow **up**. A child never reaches sideways into a
sibling's state; it emits an event, the shared owner updates, the new value flows down.

Each mutation should answer: who owns this fact, who reads it, what invalidates it.
If you cannot name the owner, the state is misplaced.

## Decision shortcuts

- **Local vs global** → "Does anyone outside this subtree need it?" No → local.
- **Store it vs derive it** → can you compute it from existing state? Then derive.
- **Optimistic vs pessimistic** → is it cheap to reverse and low-stakes? Yes → optimistic.
- **Normalize vs nest** → is the entity shared and mutable? Yes → normalize.

## Red flags to stop on

- A `setState`/store write inside a `build`/render — infinite loop or stale closure.
- Two sources for one fact (e.g. count stored *and* derivable from a list).
- `initState` fetch with no refetch path — guaranteed staleness.
- Optimistic write without rollback.
- Global store holding a transient form field.
- A `useEffect`/listener that syncs state A into state B — usually means B should be derived.

## Verify before done

- Mutate on one screen; confirm every other view reflects it without a manual reload.
- Force the mutation to fail; confirm the UI rolls back and shows the error.
- Drop the network, reconnect; confirm caches refresh and no duplicate/stale rows linger.

Commit via [[commit-pipeline]]. Related: [[caching-strategy]], [[data-modeling-and-schema-design]],
[[flutter-mvvm]], [[concurrency-and-async-correctness]].
