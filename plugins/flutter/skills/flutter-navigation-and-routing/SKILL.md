---
name: flutter-navigation-and-routing
description: Triggers when wiring navigation — go_router/auto_route setup, declarative vs imperative routing, nested/tab routing, route guards/redirects, typed routes, deep-link and web-URL handling, or back-button/restoration behavior.
---

# Flutter Navigation and Routing

Navigation is application state, not a side effect. Model the route tree as data, drive it
declaratively, and let one source of truth decide what the user sees. The default `Navigator`
imperative stack (`push`/`pop`) breaks down the moment you add web URLs, deep links, or
auth-gated sections — reach for a router.

## Decide the approach first

- **Few screens, no web target, no deep links** → plain `Navigator 1.0` is fine. Don't add a
  router for three pages.
- **Web, deep links, tabs, or auth gates** → use a URL-driven router. `go_router` is the
  first-party choice; `auto_route` adds code-gen and nested-route ergonomics. Pick one and
  commit — mixing routers fights over the same `Router` delegate.
- **Imperative inside declarative**: even with a router you still use imperative pops for
  dialogs, bottom sheets, and "go back one step." That's expected; the router owns *page*
  state, not transient overlays.

## go_router: the spine

```dart
final _rootKey = GlobalKey<NavigatorState>();

final router = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/feed',
  refreshListenable: authState, // re-runs redirect when auth changes
  redirect: (context, state) {
    final loggedIn = authState.isLoggedIn;
    final goingToLogin = state.matchedLocation == '/login';
    if (!loggedIn && !goingToLogin) return '/login?from=${state.uri}';
    if (loggedIn && goingToLogin) return '/feed';
    return null; // no redirect
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
    GoRoute(
      path: '/feed',
      builder: (_, __) => const FeedPage(),
      routes: [
        GoRoute(
          path: 'post/:id', // relative → /feed/post/42
          builder: (context, state) =>
              PostPage(id: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);
```

Wire it with `MaterialApp.router(routerConfig: router)`. Navigate with `context.go('/feed')`
(replace the stack to a location) or `context.push('/feed/post/42')` (stack on top, returns a
result via `await`).

`go` vs `push` is the most common bug source: `go` rewrites the URL to a *destination*, `push`
adds a page and keeps the URL semantics of a stack. Use `go` for tab/section switches and
deep-link targets; use `push` for drill-down where back should return.

## Redirects are your guard layer

Centralize auth and onboarding gates in the top-level `redirect`. Keep it pure and fast — it
runs on every navigation. Return a path to divert, `null` to allow. Pass
`refreshListenable` (a `ChangeNotifier` or `GoRouterRefreshStream` wrapping a `Stream`) so the
router re-evaluates when login state flips, instead of leaving the user stranded.

```dart
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() { _sub.cancel(); super.dispose(); }
}
```

Avoid redirect loops: every diversion target must itself pass the redirect (e.g. `/login` must
not redirect away when logged out). go_router throws after too many hops — read the message,
it names the cycle.

## Typed routes — kill stringly-typed bugs

Hand-built paths rot. Use `go_router`'s typed routes so the compiler catches a missing param.

```dart
@TypedGoRoute<PostRoute>(path: '/feed/post/:id')
class PostRoute extends GoRouteData {
  const PostRoute({required this.id, this.highlight});
  final String id;
  final String? highlight; // becomes ?highlight=...
  @override
  Widget build(BuildContext context, GoRouterState state) =>
      PostPage(id: id, highlight: highlight);
}

// Navigate type-safely; run build_runner to generate $appRoutes.
const PostRoute(id: '42', highlight: 'reply').go(context);
```

For non-trivial argument objects, pass an `id` in the path and re-fetch by id at the
destination. Don't shove full domain objects through `extra` — it isn't serialized, so it's
`null` after a web reload or deep link.

## Nested and tab routing

Tabs that keep their own state and back-stack need `StatefulShellRoute`. Each branch owns a
navigator, so switching tabs preserves scroll position and inner navigation.

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, shell) => ScaffoldWithNavBar(shell: shell),
  branches: [
    StatefulShellBranch(routes: [GoRoute(path: '/feed', builder: ...)]),
    StatefulShellBranch(routes: [GoRoute(path: '/search', builder: ...)]),
    StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: ...)]),
  ],
);

// In the nav bar, switch branch without losing its stack;
// re-tapping the active tab pops that branch back to its root:
onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
```

Use `ShellRoute` (non-stateful) only for shared chrome around a single shared stack — e.g. a
persistent app bar where tabs don't need independent history.

## Deep links and web URLs

- Design paths to be linkable and meaningful: `/order/:id/track`, not `/screen?n=7`. The URL is
  a public API.
- Configure platform deep links (Android `intent-filter` / App Links, iOS Universal Links). The
  router resolves the incoming URI through the same route table — no special-casing needed.
- On web, set `usePathUrlStrategy()` (in `main`) to drop the `#` from URLs. Verify back/forward
  buttons map to `pop`/`push` and that a hard refresh on a deep path rebuilds correctly (this is
  why `extra` must not hold required data).
- Handle unknown paths with `errorBuilder` / a `errorPageBuilder` 404 page instead of a blank
  screen.

## Back button, results, and pop scope

- Return values: `final picked = await context.push<Tag>('/tags'); ... context.pop(tag);` — the
  awaited type must match.
- Guard against losing unsaved edits with `PopScope`, not the deprecated `WillPopScope`:

```dart
PopScope(
  canPop: !hasUnsavedChanges,
  onPopInvokedWithResult: (didPop, result) async {
    if (didPop) return;
    if (await confirmDiscard(context)) {
      if (context.mounted) context.pop();
    }
  },
  child: form,
);
```

- On Android predictive back, `canPop` drives the system gesture; keep it accurate.

## Verify before you call it done

- Manually exercise: cold start on a deep path, web refresh on a nested route, tab-switch then
  back, login → redirect → original destination.
- For regressions, write widget tests that pump `MaterialApp.router` and assert
  `find.byType(...)` after `router.go(...)`; assert redirect outcomes with a fake auth state.
- See [[test-driven-development]] for driving route logic from tests,
  [[flutter-push-notifications-and-deep-linking]] for platform link config, and
  your view-model / state layer when navigation is triggered from app state. Commit per
  [[commit-pipeline]].
