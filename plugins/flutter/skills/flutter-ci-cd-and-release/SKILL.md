---
name: flutter-ci-cd-and-release
description: Triggers when automating Flutter builds and releases — GitHub Actions/Codemagic/fastlane pipelines, code signing and provisioning, build/test/lint gates, versioning, and store/TestFlight/Play distribution.
---

# Flutter CI/CD and release

Automate the path from a green commit to an artifact in a tester's hands. The goal is a pipeline
that fails fast on cheap checks, signs builds with secrets that never touch the repo, and produces
a traceable version for every release. Commit and push steps defer to [[commit-pipeline]].

## Pin the toolchain first

A pipeline that floats on "latest Flutter" breaks silently when a release lands. Pin the exact SDK
and read it from one source of truth.

```yaml
# pubspec.yaml — the version solver enforces this, and CI reads it too
environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.24.0"
```

Match it in CI and cache the pub + Gradle dirs so cold builds stay under control:

```yaml
- uses: subosito/flutter-action@v2
  with:
    flutter-version: "3.24.0"   # exact, never a range, never "stable"
    channel: stable
    cache: true
- run: flutter pub get
```

## Stage the gates cheap-to-expensive

Order jobs so a formatting slip fails in seconds, not after a 12-minute build. Run analyze and
test in parallel with the platform builds gated behind them.

```yaml
analyze:
  steps:
    - run: dart format --output=none --set-exit-if-changed .
    - run: flutter analyze --fatal-infos --fatal-warnings
    - run: flutter test --coverage --reporter expanded
    - run: dart run build_runner build --delete-conflicting-outputs  # if codegen is used
```

`--fatal-infos` turns lint *infos* into failures — without it, `analysis_options.yaml` lints that
are merely informational pass CI while rotting the codebase. Treat the analyzer as the contract:

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml
analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
```

For integration coverage, keep `integration_test/` behind a separate slow job or a `[full-ci]`
label, since it boots an emulator and dominates wall-clock time.

## Version from the build number, not by hand

Hand-edited versions drift and collide. Derive the build number from the CI run and keep the
semantic version in `pubspec.yaml`. The format is `name+number` — e.g. `1.4.2+87`.

```yaml
# 1.4.2 stays human-owned in pubspec; the +build comes from CI
- run: |
    VERSION=$(grep '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*//' | cut -d'+' -f1 | tr -d '[:space:]')
    flutter build appbundle --build-name=$VERSION --build-number=${{ github.run_number }}
```

Stores reject a re-uploaded build number, so monotonic `github.run_number` (or
`$BUILD_NUMBER` on other runners) guarantees uniqueness without a manual bump. Expose it at
runtime with `package_info_plus` for crash reports and an in-app "About" screen:

```dart
final info = await PackageInfo.fromPlatform();
debugPrint('${info.version}+${info.buildNumber}'); // 1.4.2+87
```

## Inject config without committing secrets

Never bake API keys into the bundle or check them in. Pass them at build time with
`--dart-define` (or a `--dart-define-from-file` JSON for many values) and read them via
`String.fromEnvironment`, which is a compile-time constant and tree-shakes cleanly.

```dart
class Env {
  static const apiBase = String.fromEnvironment('API_BASE',
      defaultValue: 'https://staging.example');
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');
}
```

```yaml
- run: |
    flutter build appbundle \
      --dart-define=API_BASE=${{ secrets.API_BASE }} \
      --dart-define=SENTRY_DSN=${{ secrets.SENTRY_DSN }}
```

Use Flutter `--flavor`s plus entry points (`lib/main_prod.dart`) to keep dev/staging/prod app IDs
distinct so testers can install all three side by side. Broader secret handling lives in
[[secrets-and-config-management]].

## Sign with secrets restored at build time

The signing material lives in the CI secret store, gets written to disk only inside the runner,
and is read through a non-committed properties file.

**Android** — base64 the keystore into a secret, restore it, and point Gradle at a generated
`key.properties` (which must be in `.gitignore`):

Run this on the Linux/Ubuntu job that builds Android — the `base64 -d` decode flag is GNU; on a
macOS runner it would be `base64 -D`.

```yaml
- run: echo "${{ secrets.KEYSTORE_B64 }}" | base64 -d > android/app/upload.jks
- run: |
    cat > android/key.properties <<EOF
    storeFile=upload.jks
    storePassword=${{ secrets.STORE_PASSWORD }}
    keyAlias=${{ secrets.KEY_ALIAS }}
    keyPassword=${{ secrets.KEY_PASSWORD }}
    EOF
```

```kotlin
// android/app/build.gradle.kts — load only if the file exists
val keyProps = Properties().apply {
    file("../key.properties").takeIf { it.exists() }?.let { load(it.inputStream()) }
}
```

**iOS** — avoid hand-managing provisioning profiles. Use fastlane `match` to store signing
certificates in an encrypted git repo and sync them onto the runner:

```ruby
# ios/fastlane/Fastfile
lane :beta do
  match(type: "appstore", readonly: true)
  build_app(scheme: "Runner", export_method: "app-store")
  upload_to_testflight(skip_waiting_for_build_processing: true)
end
```

Pick one archive path, not both: either let fastlane `build_app` archive the Runner scheme (as
above), or drive `flutter build ipa --export-options-plist=...` yourself and have fastlane only
upload — running both double-archives and the export options can conflict. Keep `MATCH_PASSWORD`
and the App Store Connect API key (`.p8`) in secrets, never on disk after the job.

## Distribute by branch, not by hand

Wire distribution to the trigger so humans never run release commands locally. A push to a
release tag ships to the stores; a push to `develop` ships an internal build.

```yaml
on:
  push:
    tags: ["v*"]          # v1.4.2 -> store track
    branches: [develop]   # -> firebase app distribution / internal testing
```

- **Play**: `upload_to_play_store(track: "internal")` via fastlane `supply`, or the Play
  Developer API. Promote internal → production as a separate manual step.
- **TestFlight**: `upload_to_testflight` as above; processing is async, so don't block the job.
- **Ad-hoc QA**: Firebase App Distribution for fast tester loops without store review latency.

Gate the production track behind a manual approval environment so a tag push stages the build but
a human confirms the public rollout.

## Make failures debuggable

Always upload the artifact and the symbols so a release is reproducible and crashes deobfuscate.

```yaml
- run: flutter build apk --obfuscate --split-debug-info=build/symbols
- uses: actions/upload-artifact@v4
  with: { name: symbols, path: build/symbols }
```

Without `--split-debug-info`, obfuscated release stack traces are unreadable. Ship the symbol
files to your crash reporter (Crashlytics, Sentry) in the same job that built the binary.

## Checklist before calling it done

- SDK pinned identically in `pubspec.yaml` and the CI runner.
- `dart format`, `flutter analyze --fatal-infos`, and `flutter test` all gate the merge.
- Build number is CI-derived and monotonic; semantic version is human-owned.
- No keystore, `.p8`, `key.properties`, or `.env` committed — verify with `git status` before push.
- Obfuscated builds upload split debug symbols to the crash reporter.
- Store rollout requires a manual approval step, not just a tag push.

For the test layer feeding these gates see [[test-driven-development]]; for what to verify before a
public rollout see [[shipping-and-launch]].
