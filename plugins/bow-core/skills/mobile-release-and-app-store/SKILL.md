---
name: mobile-release-and-app-store
description: Trigger when shipping a mobile app — store submission, phased rollout, forced/optional update gates, crash monitoring, and recovering from an un-recallable release.
---

# Mobile Release & App Store

A mobile binary is **immutable once downloaded**. You cannot patch a device you already shipped to. Treat every release as a one-way door and design the escape hatches *before* you press submit.

## Core mental model

- A store build can take hours to days to review; a rollout takes days to reach everyone; an uninstall takes never. Plan timelines around the slowest leg.
- Two kill switches must exist server-side, controlled without a new binary:
  1. **Force-update gate** — refuse to run versions below a floor.
  2. **Remote feature flags** — disable a broken feature without a release.
- If you cannot turn a feature off from the server, it is not ready to ship.

## Step 1 — Pre-flight gate (block release until all true)

- [ ] `version` and `build number` bumped; build number strictly increases (stores reject equal/lower).
- [ ] Release notes written for each store locale.
- [ ] Crash-free baseline known from the previous version (e.g. 99.7%).
- [ ] Every new surface sits behind a remote flag, defaulted **off** for the rollout.
- [ ] Backend changes are deployed and **backward compatible** with the *currently live* app — see [[backend-api-contracts]].
- [ ] Force-update floor decided (see Step 4).
- [ ] Rollback story for any DB migration confirmed (see [[octopus-model]]).

Red flag: a migration that drops/renames a column the live app still reads. The old binary keeps running for weeks — never break its contract.

## Step 2 — Version source of truth

Keep one canonical version. In Flutter, derive everything from `pubspec.yaml`:

```yaml
# pubspec.yaml — format is <semver>+<build>
version: 2.7.0+184
```

```bash
flutter build appbundle --release   # Android
flutter build ipa --release         # iOS
```

Never hand-edit `Info.plist` / `build.gradle` version fields; let the tool propagate. Tag the release commit per [[commit-pipeline]] (Conventional Commits + gitmoji).

## Step 3 — Phased rollout, not big bang

Release to a slice of users and widen only while health holds.

| Day | Audience | Gate to advance |
| --- | --- | --- |
| 0 | Internal testers | 0 new crash signatures |
| 1 | 5% | crash-free ≥ baseline − 0.2% |
| 2 | 20% | no severity-1 reports |
| 4 | 50% | metrics stable |
| 6 | 100% | — |

- Android: staged rollout percentage on the production track. iOS: phased release (7-day automatic ramp) — you can **pause** but not rewind it.
- Halt the moment a metric regresses. Halting is cheap; a bad 100% is not.

Decision point: regression detected?
- **Server-fixable** (bad config, flag, endpoint) → flip the flag / fix backend, keep rollout paused.
- **Client-fixable** (crash in the binary) → halt rollout, ship a patch build, force-update past the broken floor.

## Step 4 — Forced vs optional updates

Drive the decision from the server so old clients learn their fate on launch.

```typescript
// Supabase: app_version_policy table
// platform | min_supported | latest | message
//  ios     | 2.5.0         | 2.7.0  | "..."

export type UpdatePolicy = { action: 'none' | 'optional' | 'forced'; latest: string; message: string };

export async function resolveUpdate(platform: string, current: string): Promise<UpdatePolicy> {
  const { data } = await supabase
    .from('app_version_policy').select('*').eq('platform', platform).single();
  if (!data) return { action: 'none', latest: current, message: '' };
  if (semverLt(current, data.min_supported)) return { action: 'forced', latest: data.latest, message: data.message };
  if (semverLt(current, data.latest))        return { action: 'optional', latest: data.latest, message: data.message };
  return { action: 'none', latest: data.latest, message: '' };
}
```

Force only for: data-corruption bugs, security holes, broken backend contracts. Everything else is optional — forced updates burn user trust and spike support load.

Client side, check on resume and render a non-dismissible gate when forced:

```dart
final policy = await versionService.resolve(Platform.operatingSystem, appVersion);
if (policy.action == UpdateAction.forced) {
  await showForcedUpdateDialog(context, policy); // no dismiss, deep-links to store
}
```

Red flag: a force-update floor set *above* the version still under review. You strand users with no installable target. Only raise the floor after the new build is live at 100%.

## Step 5 — Crash & health monitoring

Wire this before rollout, not after the fire.

- Capture native + Dart errors and route them to your sink:

```dart
FlutterError.onError = (d) => crashReporter.record(d.exception, d.stack, fatal: true);
PlatformDispatcher.instance.onError = (e, s) { crashReporter.record(e, s); return true; };
```

- Stamp every event with `app_version`, `build_number`, and `flag_set` so you can diff a regression to one release and one flag.
- Watch in the first 24h: crash-free sessions, ANR/hang rate, error rate per new endpoint, and adoption curve.
- Set an alert that pages when crash-free drops below baseline on the new version — see [[observability-and-logging]] if present.

## Step 6 — When it's already out (un-recallable release)

You found a severity-1 bug after users have it. In priority order:

1. **Flip the flag.** Disable the broken feature server-side. Fastest, zero review.
2. **Fix the backend.** If the bug is a contract mismatch, adapt the server to tolerate the shipped client.
3. **Halt the rollout** so you stop adding victims while you work.
4. **Ship a patch** with a bumped build number; once live, raise `min_supported` to force users off the broken build.
5. **Never** rely on store removal — it stops new installs but does nothing for installed devices.

Post-incident: write down which kill switch *would have* prevented it, and add it.

## Anti-patterns

- Shipping a feature with no server-side off switch.
- Big-bang 100% release with no phased ramp.
- Backend deployed *after* the app, breaking old clients.
- Force-updating for cosmetic changes.
- Reusing or lowering a build number.
- Raising the version floor before the fixed build is fully live.

## Done when

- Rollout reached 100% with crash-free at or above baseline.
- Force-update floor reflects the minimum genuinely-safe version.
- All rollout flags resolved to their intended steady state (on or removed).
- Release tagged and notes archived per [[commit-pipeline]].
