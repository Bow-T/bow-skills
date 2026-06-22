---
name: flutter-flavors-and-environments
description: Triggers when separating environments — build flavors/schemes, --dart-define / dart-define-from-file config, per-environment app IDs/icons/endpoints, and keeping secrets out of the bundle.
---

# Flutter Flavors and Environments

Ship dev, staging, and prod from one codebase without hand-editing config or leaking
secrets into the bundle. A flavor is a build-time identity: its own app ID, name, icon,
and signing, plus the compile-time values your Dart code reads.

## Decide what varies, and where it lives

Sort every difference into one of three buckets — they have different mechanisms:

- **Native identity** (app ID suffix, display name, icon, signing) → Android product
  flavors + iOS schemes/xcconfig. Set once per flavor.
- **Compile-time Dart values** (API base URL, feature toggles, log level) → `--dart-define`
  or `--dart-define-from-file`. Read with `String.fromEnvironment`.
- **Secrets** (API keys, signing passwords, service tokens) → never in source, never in a
  committed define file. See "Keep secrets out of the bundle" below.

Resist a runtime `if (env == 'prod')` switch baked into the binary. It ships every
environment's config to every user and makes staging URLs grep-able in the APK.

## Type-safe config from dart-define

`String.fromEnvironment` and friends are `const` — they fold at compile time, so an
unset value is the declared default, not a crash. Centralize them:

```dart
// lib/config/app_config.dart
enum Flavor { dev, staging, prod }

class AppConfig {
  const AppConfig._();

  static const String _flavorName =
      String.fromEnvironment('FLAVOR', defaultValue: 'dev');

  static Flavor get flavor => Flavor.values.byName(_flavorName);

  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static const bool enableAnalytics =
      bool.fromEnvironment('ENABLE_ANALYTICS', defaultValue: false);

  static const int requestTimeoutMs =
      int.fromEnvironment('REQUEST_TIMEOUT_MS', defaultValue: 15000);

  static bool get isProd => flavor == Flavor.prod;
}
```

Guard against a misbuilt binary at startup rather than silently hitting an empty host:

```dart
void main() {
  assert(
    AppConfig.apiBaseUrl.isNotEmpty,
    'API_BASE_URL is unset — pass --dart-define-from-file=config/dev.json',
  );
  runApp(const MyApp());
}
```

Only `int`, `bool`, `String`, and (recent SDKs) `double` have `fromEnvironment`. For a
list or map, pass JSON in one string and `jsonDecode` it once at boot.

## dart-define-from-file: one file per flavor

Long `--dart-define` chains rot. Put each flavor's values in a JSON (or `.env`) file and
pass the whole file:

```json
// config/staging.json
{
  "FLAVOR": "staging",
  "API_BASE_URL": "https://api.staging.example.com",
  "ENABLE_ANALYTICS": true,
  "REQUEST_TIMEOUT_MS": 20000
}
```

```bash
flutter run --flavor staging \
  --dart-define-from-file=config/staging.json
flutter build apk --flavor prod \
  --dart-define-from-file=config/prod.json
```

`--flavor` selects the native build variant; `--dart-define-from-file` feeds the Dart
side. They are independent — pass both, every time. Commit the non-secret files
(`config/dev.json`, `config/staging.json`) and gitignore anything holding keys.

## Native: Android product flavors

```gradle
// android/app/build.gradle
android {
    flavorDimensions += "env"
    productFlavors {
        dev {
            dimension "env"
            applicationIdSuffix ".dev"
            resValue "string", "app_name", "App Dev"
        }
        staging {
            dimension "env"
            applicationIdSuffix ".staging"
            resValue "string", "app_name", "App Staging"
        }
        prod {
            dimension "env"
            resValue "string", "app_name", "App"
        }
    }
}
```

Distinct `applicationIdSuffix` lets dev, staging, and prod sit side by side on one device
without overwriting each other. Reference `@string/app_name` in `AndroidManifest.xml`.

## Native: iOS schemes and xcconfig

In Xcode, duplicate the build configurations (e.g. `Debug-dev`, `Release-prod`) and make
a scheme per flavor. Drive the changing values from per-flavor `.xcconfig`:

```
// ios/Flutter/dev.xcconfig
#include "Generated.xcconfig"
BUNDLE_ID_SUFFIX = .dev
DISPLAY_NAME = App Dev
```

Set `PRODUCT_BUNDLE_IDENTIFIER = com.example.app$(BUNDLE_ID_SUFFIX)` and the `Info.plist`
`CFBundleDisplayName` to `$(DISPLAY_NAME)`. The scheme name must match the `--flavor` value
you pass to Flutter, or the build fails to resolve the variant.

## Per-flavor icons and assets

Don't fork your asset code. Generate launcher icons per flavor with `flutter_launcher_icons`:

```yaml
# flutter_launcher_icons-dev.yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon/icon_dev.png"
```

```bash
dart run flutter_launcher_icons -f flutter_launcher_icons-dev.yaml
```

A tinted icon and `Dev`/`Staging` suffix make it impossible to demo the wrong build.

## Keep secrets out of the bundle

A `--dart-define` value is compiled into the binary as a plain string — trivially
extracted from a release APK/IPA with `strings`. Treat this as the core rule:

- **No real secrets in `--dart-define`.** API base URLs and feature flags are fine; signing
  keys, server-side tokens, and private credentials are not. Put those behind your backend.
- **Keep the key on the server.** A mobile app calling a third-party API should proxy through
  your own endpoint that holds the secret, not ship it to the device.
- **In CI, inject from the secret store**, not the repo. Write the config file at build time
  from CI secrets and never commit it:

```yaml
# CI step (pseudo)
- run: |
    echo '{ "FLAVOR": "prod",
            "API_BASE_URL": "${{ secrets.PROD_API_URL }}" }' > config/prod.json
    flutter build appbundle --flavor prod \
      --dart-define-from-file=config/prod.json
```

- **Gitignore the generated files**: `config/prod.json`, `*.keystore`, `ios/**/*.p8`. See
  [[secrets-and-config-management]] for rotation and storage.

## Verify before you trust the build

- Print the resolved flavor and base URL once at startup (debug builds only) and confirm
  it matches the `--flavor` you passed.
- Install two flavors side by side; confirm distinct icons, names, and that they don't
  collide on app ID.
- `strings` the release artifact for any string that should be a secret — there should be
  zero hits.
- Add a smoke test asserting `AppConfig.apiBaseUrl` is non-empty and well-formed.

## Cross-links

- [[secrets-and-config-management]] — storing, injecting, and rotating the real secrets.
- [[ci-cd-and-automation]] — wiring per-flavor builds and signing into the pipeline.
- [[threat-modeling]] — what an attacker extracts from a shipped binary.
- Commit any new config/native changes via [[commit-pipeline]].
