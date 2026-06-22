---
name: flutter-state-management
description: Triggers when choosing or structuring app state — picking Riverpod/Bloc/Provider/signals/setState, scoping providers, separating ephemeral vs app state, or fixing state that leaks, rebuilds too much, or lives in the wrong place.
---

# Flutter state management

State bugs in Flutter are almost always placement bugs: the wrong widget owns the
state, or too many widgets watch it. Fix placement first, framework second.

## Step 1 — Classify the state before choosing a tool

Two questions decide everything:

- **Who needs to read it?** One widget subtree, or screens that don't share a parent?
- **What is its lifetime?** Dies with the widget, or outlives navigation?

| State | Example | Owner |
|---|---|---|
| Ephemeral / UI | text field focus, expand/collapse, current tab, scroll offset | local `State` via `setState` |
| App / shared | auth session, cart, fetched entities, feature flags | a provider above the consumers |

Do not reach for Riverpod/Bloc to hold a checkbox's value. `setState` is correct,
not a smell, when the state is private to one widget.

```dart
class _ExpanderState extends State<Expander> {
  bool _open = false; // ephemeral: no one else cares
  @override
  Widget build(BuildContext c) => GestureDetector(
        onTap: () => setState(() => _open = !_open),
        child: _open ? widget.child : const SizedBox.shrink(),
      );
}
```

## Step 2 — Scope, don't globalize

Mount shared state at the **lowest common ancestor** of its consumers, not at the
root. Root-scoping makes everything a global singleton, defeats disposal, and turns
every screen into a candidate for a rebuild.

A per-feature scope disposes cleanly when the feature leaves the tree:

```dart
// Riverpod: scope a provider to one route's subtree
final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);

GoRoute(
  path: '/checkout',
  builder: (_, __) => ProviderScope(
    overrides: [cartProvider], // fresh instance, auto-disposed on pop
    child: const CheckoutScreen(),
  ),
);
```

Use `autoDispose` for state that should reset when no widget is listening (a search
query, a form draft). Keep it alive across a brief navigation with `ref.keepAlive()`
inside a guard, not by removing `autoDispose`.

## Step 3 — Watch narrowly so you rebuild narrowly

Most "rebuilds too much" reports are over-broad subscriptions. Subscribe to the
smallest slice, and only inside the widget that renders it.

```dart
// BAD: rebuilds the whole screen when any user field changes
final u = ref.watch(userProvider);
return Text(u.name);

// GOOD: rebuild only when name changes
final name = ref.watch(userProvider.select((u) => u.name));
return Text(name);
```

Provider equivalents: `context.select<User, String>((u) => u.name)` rather than
`Provider.of<User>(context)`. Bloc: `BlocSelector<C, S, T>` or
`buildWhen:` on `BlocBuilder` so identical slices skip rebuild.

Push the consumer down the tree. A `Consumer`/`BlocBuilder` wrapping a 200-line
`build` rebuilds all of it; wrap just the `Text` that changes and let the static
chrome stay `const`.

## Step 4 — Separate state from side effects

Reads (build the UI) and effects (navigate, snackbar, dialog) are different. Never
trigger navigation from inside `build` — it runs every frame.

- **Bloc/Cubit:** emit data states in `state`; route one-shot events through
  `BlocListener` (or `listenWhen`), not `BlocBuilder`.
- **Riverpod:** use `ref.listen(provider, (prev, next) => ...)` for effects;
  reserve `ref.watch` for rebuilds.

```dart
ref.listen(authProvider, (prev, next) {
  if (next is AuthFailure) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
  }
});
```

## Step 5 — Model async state as data, not flags

Three booleans (`isLoading`, `hasError`, `data != null`) drift into impossible
combinations. Use one sealed/union type and switch on it exhaustively.

```dart
// Riverpod gives you AsyncValue for free
final feedProvider = FutureProvider.autoDispose<List<Post>>((ref) async {
  final repo = ref.watch(repoProvider);
  return repo.fetchFeed();
});

ref.watch(feedProvider).when(
  data: (posts) => FeedList(posts),
  loading: () => const CircularProgressIndicator(),
  error: (e, st) => ErrorView(e),
);
```

Roll your own with Dart sealed classes when not on Riverpod:

```dart
sealed class Result<T> {}
class Loading<T> extends Result<T> {}
class Data<T> extends Result<T> { Data(this.value); final T value; }
class Failure<T> extends Result<T> { Failure(this.error); final Object error; }
// switch (state) { case Data(:final value): ... } — compiler enforces all cases
```

## Step 6 — Plug leaks

State that outlives its widget is the classic Flutter leak. Audit:

- Every `AnimationController`, `TextEditingController`, `ScrollController`,
  `StreamSubscription`, and `Timer` created in a `State` is cancelled/disposed in
  `dispose()`.
- A controller you didn't create, you don't dispose (the owner does).
- No `setState`/`ref.read` after `mounted` is false; guard async callbacks with
  `if (!mounted) return;`.
- Provider streams use `ref.onDispose(sub.cancel)` so they close with the provider.

```dart
@override
void dispose() {
  _controller.dispose();
  _sub?.cancel();
  super.dispose();
}
```

## Step 7 — Choose the framework last

Once placement, scoping, and async modeling are right, the tool is a small choice:

- **setState / ValueNotifier:** ephemeral and single-widget state. Always available.
- **Provider:** simple DI + `ChangeNotifier`; fine for small/medium apps.
- **Riverpod:** compile-safe, testable without `BuildContext`, great `AsyncValue`
  and auto-dispose ergonomics. Default for new shared state.
- **Bloc/Cubit:** explicit event→state transitions, strong for complex flows and
  audit trails; more boilerplate.
- **Signals:** fine-grained reactivity with minimal ceremony; newer ecosystem.

Do not mix two app-state libraries for the same concern. One source of truth per
piece of state.

## Guardrails

- Keep business logic out of widgets — put it in notifiers/blocs/repositories so it
  is unit-testable. See [[test-driven-development]].
- Don't store derived data; compute it (`select`, getters) to avoid sync bugs.
- For network/disk-backed state, fold in retries and timeouts via
  [[resilience-and-fault-tolerance]]; cross-check structural choices with
  [[system-architecture-design]].
- When committing, follow [[commit-pipeline]].

## Quick triage

- Rebuilds too much → narrow the subscription (`select`/`buildWhen`), push the
  consumer down, mark static subtrees `const`.
- State resets unexpectedly → it's ephemeral but should be shared; lift it to a
  scoped provider above both consumers.
- State persists when it shouldn't → add `autoDispose` or scope it to a route.
- Memory grows over navigation → unclosed controllers/streams; audit `dispose`.
