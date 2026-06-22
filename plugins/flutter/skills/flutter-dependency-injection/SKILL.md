---
name: flutter-dependency-injection
description: Triggers when wiring dependencies — get_it/injectable or Riverpod-as-DI, registration scopes (singleton/factory/lazy), composition roots, and making code testable by injecting collaborators.
---

# Flutter Dependency Injection

Dependency injection means a class receives its collaborators instead of constructing
them. The goal is not a framework — it is **testable seams**: any class you can hand a
fake to is a class you can test fast and deterministically. Pick the lightest tool that
gives you those seams.

## Decision: do you even need a container?

Reach for explicit constructor injection first. A container earns its keep only when the
object graph is deep or shared across many screens.

| Situation | Use |
|---|---|
| 1–2 collaborators, local to a feature | Plain constructor parameters |
| Shared services, deep graph, many call sites | `get_it` (+ `injectable` codegen) |
| State already lives in `riverpod` | Providers as DI — no second container |

Never mix two DI containers in one app. Pick one composition strategy and hold it.

## Rule 1 — Depend on abstractions, construct at the edge

Define what a collaborator *does* as an interface; let the wiring layer decide the
concrete class. This is the single move that makes everything below testable.

```dart
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

class OrderService {
  OrderService(this._clock, this._api); // collaborators injected, never `new`ed inside
  final Clock _clock;
  final OrderApi _api;

  Future<Order> place(Cart cart) =>
      _api.submit(cart, at: _clock.now());
}
```

In a test you pass a `FakeClock` returning a frozen `DateTime` — no monkey-patching, no
global state. See [[test-driven-development]] for driving the design from the test side.

## Rule 2 — Choose the right scope, deliberately

Scope is a contract about *lifetime and sharing*. Getting it wrong leaks state between
users or rebuilds expensive objects on every screen.

```dart
final getIt = GetIt.instance;

void configureDependencies() {
  // Singleton: created NOW, one shared instance for app lifetime.
  getIt.registerSingleton<Clock>(SystemClock());

  // Lazy singleton: created on FIRST resolve, then shared. Prefer this for
  // anything heavy you may never touch (e.g. a rarely opened analytics client).
  getIt.registerLazySingleton<OrderApi>(() => HttpOrderApi(getIt<Dio>()));

  // Factory: a fresh instance EVERY resolve. Use for stateful, short-lived objects
  // like a form controller or a per-request unit of work.
  getIt.registerFactory<CheckoutController>(
    () => CheckoutController(getIt<OrderService>()),
  );
}
```

Guidance:
- **Stateless service** (clock, formatter, repository over a stateless API) → lazy singleton.
- **Stateful, must not be shared** (a per-screen controller, a draft) → factory.
- **Eagerly needed at startup** (config that everything reads) → singleton.
- Holding a `BuildContext`, `WidgetRef`, or any disposable resource → never a singleton.

## Rule 3 — One composition root, called once

Build the entire graph in a single place at startup, before `runApp`. Resolving
dependencies anywhere else turns the container into a global variable in disguise.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureDependencies();         // the ONLY place wiring happens
  runApp(const MyApp());
}
```

Widgets pull what they own at their boundary and pass it down by constructor — they do
not reach into `getIt` from deep in the tree. The service locator stays at the seam, not
sprinkled through the UI.

## Rule 4 — Let codegen wire the graph with `injectable`

Hand-written registration rots: a new constructor argument silently breaks resolution at
runtime. `injectable` generates `configureDependencies` from annotations, so the graph is
checked at build time.

```dart
@LazySingleton(as: Clock)
class SystemClock implements Clock {
  @override
  DateTime now() => DateTime.now();
}

@injectable
class OrderService {
  OrderService(this._clock, this._api);
  final Clock _clock;
  final OrderApi _api;
}

@InjectableInit()
void configureDependencies() => getIt.init();
```

Regenerate after annotation changes:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Use `@Environment('test')` / `@dev` / `@prod` to register different implementations per
environment (a `FakeOrderApi` under test, the HTTP one in prod) without `if` branches in
production code.

## Rule 5 — Scoped containers for per-session graphs

When a subtree needs its own short-lived graph — a logged-in session, a checkout flow —
push a scope and drop it when the flow ends. This disposes session objects cleanly and
prevents the next user from inheriting the last user's state.

```dart
void onLogin(User user) {
  getIt.pushNewScope(
    scopeName: 'session',
    init: (sl) {
      sl.registerSingleton<CurrentUser>(CurrentUser(user));
      sl.registerLazySingleton<Wallet>(() => Wallet(sl<CurrentUser>()));
    },
  );
}

Future<void> onLogout() => getIt.dropScope('session'); // session-scoped objects disposed
```

Register `dispose:` callbacks on scoped singletons so closing the scope releases
sockets, streams, and controllers.

## Riverpod as DI

If you already use `riverpod`, you have a container — do not add `get_it` alongside it.
Express dependencies as providers; override them in tests via `ProviderScope`.

```dart
final clockProvider = Provider<Clock>((ref) => SystemClock());

final orderServiceProvider = Provider<OrderService>((ref) {
  return OrderService(ref.watch(clockProvider), ref.watch(orderApiProvider));
});
```

`Provider` ≈ lazy singleton (cached per scope). `Provider.autoDispose` ≈ factory-ish: it
is torn down when no one listens. Override at the seam in tests:

```dart
testWidgets('places order at frozen time', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [clockProvider.overrideWithValue(FakeClock(_fixed))],
      child: const MyApp(),
    ),
  );
});
```

## Testing harness

Make resetting the container part of your test lifecycle so state never leaks between tests.

```dart
setUp(() {
  getIt.registerSingleton<Clock>(FakeClock(_fixed));
  getIt.registerSingleton<OrderApi>(FakeOrderApi());
});

tearDown(getIt.reset); // wipe all registrations between tests
```

Prefer overriding at the composition root over reaching into a singleton mid-test. If a
class can only be tested by mutating a global, that is a design smell — push the
collaborator into its constructor instead.

## Smells that mean the wiring is wrong

- `getIt<Foo>()` called from inside widget `build`, deep services, or model classes.
- A class that constructs its own HTTP client, database, or `DateTime.now()` internally —
  it has no test seam.
- Singletons holding request- or user-scoped state (the classic cross-user data bug).
- A test that needs `getIt.reset()` *and* real network — the fake never got injected.
- Two containers (`get_it` + `riverpod`) racing to own the same object.

## Related

- [[test-driven-development]] — design the seam from the failing test first.
- [[flutter-mvvm]] — where view-models receive their injected collaborators.
- [[api-and-interface-design]] — shaping the abstractions you inject behind.
- [[concurrency-and-async-correctness]] — lifetime of async/disposable singletons.
- Committing the generated `*.config.dart` and wiring → [[commit-pipeline]].
