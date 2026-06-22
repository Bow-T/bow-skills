---
name: flutter-testing
description: Triggers when writing or fixing tests — unit, widget (pumpWidget/finders/pumpAndSettle), golden, and integration_test, plus mocktail/fakes, test setup, and choosing the right test level for a change.
---

# Flutter testing

A flaky or slow test suite is usually a leveling problem: logic verified through the
widget tree, or a real network call hiding inside a "unit" test. Pick the cheapest
level that can fail for the right reason, then make it deterministic.

## Step 1 — Choose the level by what could break

| Level | Runs on | Use for | Cost |
|---|---|---|---|
| `test` (unit) | Dart VM | pure logic, parsing, view-model state transitions, reducers | microseconds |
| `testWidgets` | flutter_test, fake clock | one widget/screen: layout, taps, conditional rendering | milliseconds |
| golden | flutter_test + `flutter_test_config.dart` | exact pixels of a stable widget | ms, brittle |
| `integration_test` | real device/emulator | end-to-end flows, plugins, platform channels | seconds |

Push logic *out* of widgets so it can be unit-tested. If you can only test a rule by
pumping a screen, the rule lives in the wrong place — see [[flutter-state-management]].
Most of the pyramid should be plain `test`; widget tests cover wiring, not arithmetic.

## Step 2 — Unit-test the logic, fake the collaborators

Use `mocktail` (no codegen, null-safe) over `mockito` for new code. Stub with `when`,
verify interactions with `verify`, and register fallbacks for non-primitive args.

```dart
class _MockRepo extends Mock implements OrderRepo {}
class _FakeOrder extends Fake implements Order {}

void main() {
  late _MockRepo repo;
  setUpAll(() => registerFallbackValue(_FakeOrder())); // for any<Order>()
  setUp(() => repo = _MockRepo());

  test('submit retries once on transient failure', () async {
    var calls = 0;
    when(() => repo.save(any())).thenAnswer((_) async {
      if (calls++ == 0) throw const SocketException('flaky');
      return 'ok';
    });

    final result = await Submitter(repo).submit(_FakeOrder());

    expect(result, 'ok');
    verify(() => repo.save(any())).called(2);
  });
}
```

Prefer a hand-written **fake** over a mock when you need real behavior (an in-memory
store, a `StreamController`). Mocks assert *how* code is called; fakes let it run.
Don't mock value objects or the class under test.

## Step 3 — Widget tests: pump, find, assert

`pumpWidget` builds the tree once and stops. `pump([duration])` advances one frame;
`pumpAndSettle` pumps until no frames are scheduled. Wrap the subject in only the
ancestors it needs — usually `MaterialApp` for `Directionality`, theme, and `Overlay`.

```dart
testWidgets('tapping submit shows a spinner then a success banner', (tester) async {
  await tester.pumpWidget(MaterialApp(home: CheckoutPage(repo: fakeRepo)));

  expect(find.text('Place order'), findsOneWidget);
  await tester.tap(find.byKey(const Key('submit')));
  await tester.pump(); // one frame: spinner is now on screen

  expect(find.byType(CircularProgressIndicator), findsOneWidget);

  await tester.pumpAndSettle(); // drain the async + animations
  expect(find.text('Order placed'), findsOneWidget);
});
```

Finder rules that prevent brittle tests:

- Prefer `find.byKey` and `find.bySemanticsLabel` over `find.text` for anything
  user-visible — text changes with copy and localization.
- Use `find.byType` for structure, `find.descendant`/`matching` to disambiguate.
- A finder matching zero or many widgets fails the test; assert with `findsNothing`,
  `findsOneWidget`, `findsNWidgets(n)` rather than indexing.

For entering text use `tester.enterText`; for scrolling use `tester.drag` or
`tester.scrollUntilVisible`. Set screen size with
`tester.view.physicalSize = const Size(1080, 1920)` and reset it in `addTearDown`.

## Step 4 — Tame async and time

`pumpAndSettle` **never returns** if something animates forever (a looping spinner,
an unbounded `Timer.periodic`). When that happens, pump explicit durations instead.

```dart
await tester.runAsync(() async {
  await precacheImage(provider, tester.element(find.byType(Image)));
}); // runAsync lets real async (I/O, image decode) complete in a widget test

await tester.pump(const Duration(seconds: 1)); // advance the fake clock by 1s
```

Wrap timer-driven code in `fakeAsync` (from `package:fake_async`) for unit tests, and
assert there are no pending timers. Never use a real `Future.delayed` to "wait" — it
hangs the suite. For streams, drive a `StreamController` you own and `await` a `pump`.

## Step 5 — Golden tests, used sparingly

Golden tests catch unintended visual change but break on font/platform differences.
Gate them so they only run where the references were generated, and load real fonts.

```dart
testWidgets('price tag golden', (tester) async {
  await tester.pumpWidget(wrap(const PriceTag(amount: 1999)));
  await expectLater(
    find.byType(PriceTag),
    matchesGoldenFile('goldens/price_tag.png'),
  );
}, skip: !Platform.isMacOS); // generate + verify on one platform only
```

Regenerate with `flutter test --update-goldens` and review the PNG diff like code.
Keep goldens to a few high-value, stable components, not every screen.

## Step 6 — Shared setup and isolation

- Put cross-cutting config (font loading, default golden tolerance) in
  `test/flutter_test_config.dart` via `testExecutable`.
- Reset global state between tests in `setUp`/`tearDown`; a leaked singleton makes
  tests pass or fail depending on order.
- `SharedPreferences.setMockInitialValues({})`, `HttpOverrides.runZoned`, and
  `tester.binding.defaultBinaryMessenger.setMockMethodCallHandler` stub platform deps
  so no test touches the network, disk, or a real plugin channel.
- A test that passes on its first run proves nothing — make it fail first (break the
  code, flip the expectation) so you trust the assertion.

## Step 7 — integration_test for the real thing

Live in `integration_test/`, driven by `IntegrationTestWidgetsFlutterBinding`. Use
them only for flows that cross plugins, channels, or screens end to end.

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('login then land on home', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'a@b.co');
    await tester.tap(find.byKey(const Key('login')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home')), findsOneWidget);
  });
}
```

Run with `flutter test integration_test`. Keep these few — they are slow and the
likeliest to flake; cover branches at the widget level instead.

## Anti-patterns

- `await tester.pump(const Duration(hours: 1))` to skip an animation you could `pumpAndSettle`.
- Asserting on private state instead of rendered output or returned values.
- One mega-test that taps through five screens — split it; a failure should name the cause.
- Mocking the class under test, or `verify`-ing every call (couples the test to implementation).
- Sharing mutable fixtures across tests without resetting in `setUp`.

When tests are green and you commit, follow [[commit-pipeline]]. For the production
performance work these tests guard, see [[flutter-performance-and-rebuild-optimization]].
