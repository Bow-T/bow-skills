---
name: flutter-error-handling-and-crash-reporting
description: Triggers when hardening reliability — wiring FlutterError.onError and PlatformDispatcher.onError, runZonedGuarded, error-boundary widgets, user-facing error UI, and crash reporting (Sentry/Crashlytics) with symbolication and breadcrumbs.
---

# Flutter error handling and crash reporting

Goal: every crash, async failure, and rejected future surfaces somewhere — a report with a
symbolicated stack, or a screen the user can recover from. Nothing dies silently.

## The four channels you must catch

Flutter has distinct error pathways. Wiring one and assuming you are covered is the classic gap.

1. `FlutterError.onError` — synchronous errors inside the framework (build, layout, paint, gestures).
2. `PlatformDispatcher.instance.onError` — uncaught async errors from the engine (since Flutter 3.3+).
3. `runZonedGuarded` — uncaught errors in zones you create (timers, microtasks, streams without
   `onError`). Still needed for code that runs outside the platform dispatcher's reach.
4. Native crashes — Kotlin/Swift/NDK. Only a native SDK (Crashlytics/Sentry native) catches these.

## Bootstrap: one entry point that wires all channels

Order matters. `WidgetsFlutterBinding.ensureInitialized()` must run inside the same zone as
`runApp`, or you get a zone-mismatch assertion.

```dart
Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Framework (synchronous) errors.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details); // keeps the red box in debug
      if (kReleaseMode) {
        Reporter.recordFlutterError(details);
      }
    };

    // Engine-level async errors. Return true = handled.
    PlatformDispatcher.instance.onError = (error, stack) {
      // fatal should reflect whether the app actually terminated; most
      // async/zone errors are non-fatal (the app keeps running).
      Reporter.recordError(error, stack, fatal: false);
      return true;
    };

    await Reporter.init(); // Sentry/Crashlytics init

    runApp(const App());
  }, (error, stack) {
    // Zone fallback: timers, unawaited futures, stream errors.
    Reporter.recordError(error, stack, fatal: false);
  });
}
```

Do not also call `runApp` inside `Sentry.init(appRunner: ...)` if you already manage the zone —
pick one strategy. With Sentry, the idiomatic path is `SentryFlutter.init(..., appRunner: () => runApp(...))`,
which installs the integrations and zone for you; only hand-roll `runZonedGuarded` when you need
custom zone behavior.

## Classify errors before you report them

Reporting expected failures as crashes destroys your crash-free-sessions metric. Separate
*operational* errors (network down, 404, validation) from *programmer* errors (null deref, bad cast).

```dart
sealed class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
}

class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'No connection']);
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure([super.message = 'Not found']);
}
```

Operational failures bubble up as typed `AppFailure`s and drive UI. Only *unexpected* errors reach
the global handlers. In a repository, translate raw exceptions at the boundary:

```dart
Future<User> fetchUser(String id) async {
  try {
    final res = await _dio.get('/users/$id');
    return User.fromJson(res.data);
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) throw const NotFoundFailure();
    throw const NetworkFailure();
  }
  // FormatException / TypeError are NOT caught here — they're bugs, let them crash & report.
}
```

## Error-boundary widget: contain a bad subtree

A throwing `build()` paints the gray error screen across the whole app. Override
`ErrorWidget.builder` for a non-alarming fallback in release, and wrap risky subtrees.

```dart
void setupErrorWidget() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kReleaseMode) {
      // Provide Directionality: the error may occur above MaterialApp,
      // and Text asserts without an ambient text direction.
      return const Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: Center(child: Text('Something went wrong')),
        ),
      );
    }
    return ErrorWidget(details.exception); // verbose in debug
  };
}
```

Flutter has no React-style boundary, but you can scope failures by catching at the data layer and
rendering states explicitly rather than letting widgets throw:

```dart
switch (state) {
  AsyncData(:final value) => ContentView(value),
  AsyncError(:final error) => RetryView(
      message: error is AppFailure ? error.message : 'Unexpected error',
      onRetry: controller.reload,
    ),
  _ => const Center(child: CircularProgressIndicator()),
}
```

## User-facing error UI: actionable, not a stack trace

- Never show raw exception text or stack traces to users.
- Map failure type to a recovery affordance: retry, sign in again, go offline, contact support.
- Surface transient failures as a `SnackBar`/banner; surface page-load failures as a full retry view.
- Include a correlation id (the report event id) so support can find the crash.

```dart
void showFailure(BuildContext context, AppFailure failure) {
  final id = Reporter.lastEventId; // tie UI to the report
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(failure.message),
    action: SnackBarAction(label: 'Retry', onPressed: () {/* re-run */}),
  ));
}
```

## Breadcrumbs and context — the difference between a usable report and noise

A stack trace alone rarely reproduces a bug. Attach a trail of what happened before.

- Log navigation as breadcrumbs (a `NavigatorObserver` that records route pushes/pops).
- Log network calls (a Dio/http interceptor: method, path, status — never bodies with secrets).
- Tag the user/session with a non-PII id, app version, and feature flags.
- Add custom keys for screen state right before a risky operation.

```dart
class BreadcrumbNavObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    Reporter.addBreadcrumb('nav', 'push ${route.settings.name}');
  }
}
```

Scrub PII before it leaves the device — strip auth headers, emails, tokens in a `beforeSend` hook.
Reporting personal data without consent is a compliance issue; see [[data-privacy-and-compliance]].

## Symbolication — without it, release stacks are useless

Release builds are obfuscated/stripped. A stack of `#0 0x000... ` means nothing until symbolicated.

- Build with `flutter build apk --obfuscate --split-debug-info=build/symbols` (same for `appbundle`/`ipa`).
- Upload the Dart debug symbols to your crash service for every release (Sentry: `sentry-cli debug-files upload`;
  Crashlytics: upload Flutter symbols + native dSYM/mapping files).
- Automate the upload in your release pipeline so no build ships without symbols — see [[ci-cd-and-automation]].
- Keep the `build/symbols` artifact archived per version; you cannot resymbolicate later without it.

## Verify it actually works

Do not trust that handlers are wired — prove each channel reports.

```dart
// Sync framework error:
Builder(builder: (_) => throw StateError('test-sync'));
// Async / zone error:
Future<void>(() => throw StateError('test-async'));
// Platform dispatcher:
Timer.run(() => throw StateError('test-timer'));
```

Trigger each in a release/profile build, confirm a symbolicated report lands with breadcrumbs and
the right `fatal` flag. Test that operational `AppFailure`s render UI and do NOT create reports.
Apply the discipline in [[debugging-and-error-recovery]] to chase any channel that stays silent.

## Checklist

- [ ] All four channels wired in one `main` entry point, single zone.
- [ ] Typed `AppFailure` hierarchy; operational vs programmer errors separated.
- [ ] `ErrorWidget.builder` overridden for release.
- [ ] User UI is actionable and PII-free; carries an event id.
- [ ] Breadcrumbs (nav + network) and non-PII context attached; `beforeSend` scrubs secrets.
- [ ] Obfuscated builds + symbol upload automated per release.
- [ ] Each channel verified to report in a release build.

Commit the wiring per [[commit-pipeline]].
