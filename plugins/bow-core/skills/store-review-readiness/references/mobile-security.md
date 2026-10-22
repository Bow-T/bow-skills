# Mobile security checklist (OWASP MASVS v2)

Organized by the eight MASVS v2 control groups (<https://mas.owasp.org/MASVS/>). These checks are
for the **release build of the production flavor**; findings are fixed with
[[security-and-hardening]] and [[secrets-and-config-management]].

Format: **Check** — how to verify — fix.

## MASVS-STORAGE — data at rest

- **Tokens and secrets in secure storage**, not plain preferences. — Grep for `accessToken`,
  `refreshToken`, `password` written to SharedPreferences / UserDefaults / plain files. — Keychain /
  Keystore (`flutter_secure_storage`, EncryptedSharedPreferences).
- **Backups don't carry credentials.** Android `android:allowBackup` defaults to true. —
  AndroidManifest `<application>`. — `allowBackup="false"` or `dataExtractionRules` excluding the
  auth store; iOS: keychain items with `ThisDeviceOnly` accessibility.
- **No sensitive data in logs, screenshots or caches.** — Release logs (`print`, `debugPrint`,
  `NSLog`, `Log.d`, HTTP loggers with headers on); payment and health screens in the app switcher
  snapshot.

## MASVS-CRYPTO

- **Platform crypto only**, no hand-rolled ciphers, no hard-coded keys or IVs, no MD5/SHA-1 for
  security decisions.
- **Keys from the platform keystore**, not from the bundle.

## MASVS-AUTH

- **Authorization on the server** for every request; the client hiding a button is not access control.
- **Session lifecycle**: refresh tokens actually used or not stored; logout clears local tokens, push
  tokens, purchase SDK identity, caches; a 401 leads to a clean sign-out, not a half-signed-in state.
- **Account deletion** revokes sessions server-side.
- **Biometrics / local auth**, if used, unlock a keystore-bound secret, not a boolean flag.

## MASVS-NETWORK

- **TLS validation on.** — Grep `badCertificateCallback`, `onBadCertificate`, `HttpOverrides`,
  `allowBadCertificates`, `TrustAllCerts`, `NSAllowsArbitraryLoads`. — Any bypass must be
  `kDebugMode` / DEBUG-only, or gone.
- **No cleartext.** — iOS `NSAppTransportSecurity` exceptions (`NSExceptionAllowsInsecureHTTPLoads`);
  Android `usesCleartextTraffic`, `network_security_config.xml`; `http://` URLs in code and config. —
  Serve everything over HTTPS and delete the exceptions.
- **Certificate pinning** for high-risk apps (finance, health) — with a rotation plan, or it bricks
  the app on cert renewal.
- **Retries don't duplicate writes**: POST/PUT retried by an interceptor must be idempotent
  (see [[idempotency-and-exactly-once]]).

## MASVS-PLATFORM

- **Exported components and deep links** validate their input; no `exported=true` without need.
- **WebViews**: JavaScript off unless needed, no `addJavascriptInterface` / JS channels exposed to
  remote content, no file access from remote URLs; HTML from the server or an LLM sanitized before
  rendering.
- **Clipboard, screenshots, notifications** don't leak secrets (OTP, tokens, health data on the lock
  screen).
- **Permissions** minimal (see the store references).

## MASVS-CODE

- **Release build flags**: not debuggable, no debug banner, no dev menus or env switchers reachable,
  dev-only endpoints disabled.
- **Dependencies**: no known CVEs (`flutter pub outdated`, `npm audit`, Dependabot, OSV); discontinued
  packages replaced; licenses compatible with a commercial app (e.g. PDF / chart SDKs with community
  licenses that cap revenue).
- **Input validation** at the boundaries (deep links, push payloads, QR/barcode contents, API responses).
- **Force-update path** exists for security fixes (see [[mobile-release-and-app-store]]).

## MASVS-RESILIENCE

- **Obfuscation / R8** for release (`--obfuscate --split-debug-info` in Flutter, R8 on Android), with
  symbols archived. On iOS it must not hide functionality from App Review (Apple 2.5.19).
- **Root / jailbreak / tamper detection** only where the threat model needs it (payments, DRM); it is
  never a substitute for server-side checks.

## MASVS-PRIVACY

- **Data minimization**: each collected field has a feature that needs it; optional fields are optional.
- **Consent** before analytics, tracking, or sending data to third parties (including AI providers).
- **Transparency**: the privacy policy, the App Privacy label and the Data safety form describe the same
  data the binary collects.
- **User control**: export / deletion of the user's data works end to end.

## Repository and secrets (before any build leaves the building)

- [ ] No keystores (`*.jks`, `*.keystore`), `key.properties`, `.p8`/`.p12`, `google-services.json`
      for other projects, or `.env` files tracked in git. If one ever was, rotate it.
- [ ] No API keys or passwords in scripts or code; client-side keys restricted (bundle id / SHA-1).
- [ ] Release config comes from CI secrets or local untracked files.
- [ ] Crash reporting configured for the production flavor, with PII scrubbing.
