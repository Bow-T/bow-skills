# Google Play policy checklist

Sources: Play Console Help and the Developer Policy Center
(<https://play.google.com/about/developer-content-policy/>). Dated facts verified 2026-10-22;
re-check anything with a deadline before quoting it.

Format: **Check** — how to verify — fix.

## Build and technical requirements

- **Target API level.** From 2026-08-31, new apps and updates must target Android 16 (API 36)
  (Wear OS / Automotive: 35; TV / XR: 34); an extension to 2026-11-01 can be requested. Existing apps
  below API 35 stop being offered to new users on newer Android versions. (verified 2026-10-22,
  <https://support.google.com/googleplay/android-developer/answer/11926878>) — `targetSdk` /
  `targetSdkVersion` in `android/app/build.gradle(.kts)`; for Flutter `flutter.targetSdkVersion` comes
  from the Flutter SDK version. — Raise it, then retest permissions, notifications, edge-to-edge and
  foreground services, which change behavior per target.
- **16 KB memory pages.** Updates targeting Android 15+ must support 16 KB page sizes (enforced since
  2025-11-01, extension to 2026-05-31 now over). Pure Kotlin/Java is fine; native `.so` files from the
  engine or SDKs must be aligned. — Play Console → App bundle explorer warns; or
  `zipalign -c -P 16 -v 4 app.apk`; Android Studio APK Analyzer. — Update NDK/AGP and the SDKs that
  ship native code (Flutter engine, ML Kit, camera, PDF, image libs).
- **Android App Bundle** (`.aab`) for new apps, with **Play App Signing**. The upload key is
  replaceable; keep it and `key.properties` out of git.
- **Version code strictly increases** and comes from one source (`pubspec.yaml` `+N`, not hard-coded
  in Gradle).
- **Release build is not debuggable**, R8 enabled (`minifyEnabled`, `shrinkResources`) with keep rules
  for reflection-based libraries; upload native debug symbols / the R8 mapping so crashes are readable.
- **Developer verification** (2026): Google is rolling out identity verification for developers of
  apps installed on certified devices, starting 2026-09-30 in Brazil, Indonesia, Singapore and
  Thailand and expanding globally in 2027. Play developers verify through Play Console; check the
  account's status page. (verified 2026-10-22)
- **New personal developer accounts** must run a closed test with a minimum number of testers for a
  minimum number of days before applying for production access. Check the current numbers in Play
  Console → Dashboard; plan the calendar time.

## Store listing and declarations (Play Console → App content)

- [ ] **Privacy policy** URL, public and reachable, matching the app.
- [ ] **App access**: credentials for the reviewer (account with paid features, fixed OTP if SMS login).
- [ ] **Ads**: declares whether the app contains ads.
- [ ] **Content rating** (IARC questionnaire) answered honestly.
- [ ] **Target audience and content**; if children are in the target, the Families policy applies
      (certified ad SDKs only, no precise location, etc.).
- [ ] **Data safety** form matches the binary *including every SDK* — Play cross-checks declarations
      against what SDKs in the bundle access. Includes the data deletion questions.
- [ ] **Health apps declaration** for fitness, nutrition, medical or wellness features; health data
      handled per the Health Apps policy.
- [ ] **Financial features declaration** (even "none").
- [ ] **Advertising ID**: declared, or `com.google.android.gms.permission.AD_ID` removed with
      `tools:node="remove"` when nothing uses it.
- [ ] **Government apps / news / etc.** declarations if relevant.

## User Data policy

- **Account deletion, two places.** If the app lets users create an account: a discoverable in-app
  path *and* a public web resource to request deletion without reinstalling the app, linked in the Data
  safety form. Deletion means deleting the account and its data; deactivation does not count.
- **Prominent disclosure** before collecting personal or sensitive data that a user wouldn't expect
  (in-app, before the runtime permission prompt, stating what and why).
- **Data transmitted securely** (HTTPS), not logged.

## Permissions

- **Only what the app uses.** Each `uses-permission` in the *merged* manifest
  (`./gradlew :app:processReleaseManifest`, then `build/intermediates/merged_manifests/...`) maps to a
  feature. Typical leftovers: `GET_ACCOUNTS`, `READ_PHONE_STATE`, location, `RECORD_AUDIO`,
  `READ/WRITE_EXTERNAL_STORAGE` without `maxSdkVersion`.
- **Photo and video permissions.** `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` only for apps whose core
  use needs broad access, with a declaration; one-off picks must use the system photo picker.
- **All files access** (`MANAGE_EXTERNAL_STORAGE`), **background location**, **SMS / Call log**,
  **exact alarms** (`SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`), **foreground service types**, and
  **accessibility services** each need a declaration and a qualifying use case.
- **Notifications** (`POST_NOTIFICATIONS`, Android 13+) requested in context, not blocking.
- **Exported components**: only the launcher activity and intended deep-link / share targets have
  `android:exported="true"`; intent filters validate input.

## Payments policy

- **Digital goods and subscriptions through Google Play Billing** (or an approved alternative billing
  program where it applies). No links or buttons to buy digital content elsewhere.
- **Subscriptions**: price, period, trial length and what happens after, and how to cancel are clear
  before purchase; cancellation is easy (Play subscription center link).
- **Promotions**: Play promo codes and offers are the supported way to discount; in-app codes that
  change a Play price should be reviewed against current policy. Keep the code itself honest (no
  "free" when it isn't).

## Functionality and quality

- **No broken functionality**: buttons that only show "not supported" (e.g. Sign in with Apple on
  Android), dead links, crashes on launch, placeholder screens.
- **Minimum functionality**: not a thin web wrapper.
- **Deceptive behavior**: the app does what the listing says; no hidden features turned on after review.
- **Pre-launch report** (Play Console → Testing) reviewed for crashes, accessibility and security warnings.
- **Android vitals** for an update: user-perceived crash and ANR rates under the bad-behavior thresholds,
  or the app loses visibility.
