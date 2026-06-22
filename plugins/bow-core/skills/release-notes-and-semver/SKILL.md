---
name: release-notes-and-semver
description: Use when cutting a release — picking a semver bump, writing a changelog or release notes, or deciding whether a change is breaking.
---

# Release Notes & SemVer

A release is a contract. The version number tells consumers what they're allowed to assume; the notes tell humans what changed. Get the bump wrong and you silently break downstream apps. Get the notes wrong and nobody upgrades.

## 0. Know what you're versioning

Pick the surface BEFORE choosing a bump. The "public API" differs per artifact:

- **Dart/Flutter package** — exported symbols (anything not `src/`-private), generics, named-param defaults, min Dart/Flutter SDK.
- **TypeScript package** — the `.d.ts` shape: exported types, function signatures, `package.json` `exports` map, min Node/TS version.
- **App (mobile/web, not a library)** — user-facing behavior + any persisted contract (deep-link routes, push payloads, stored prefs).
- **Backend / Supabase** — the wire contract: REST/RPC shapes, edge-function request+response, realtime channel names, and the DB schema other services read.

If a change touches only `src/`, internal helpers, tests, or comments, it is **not** a public change.

## 1. Decide the bump

Walk top to bottom; first match wins.

```
Did you REMOVE or RENAME anything public,
 change a type/signature incompatibly,
 tighten an input, or loosen an output guarantee?   -> MAJOR
Did you ADD new public API, or change behavior in a
 backward-compatible way (new optional param, new field)? -> MINOR
Only fixes, perf, docs, internal refactor, dep bumps
 that don't change your surface?                     -> PATCH
```

Pre-1.0 caveat: `0.y.z` gives no MAJOR guarantees. Convention: bump **minor** for breaking, **patch** for everything else — but say so in the notes, because consumers can't infer it.

### Breaking-change litmus test

Ask: *"Can a correct consumer on the previous version, doing nothing wrong, break after this?"* If yes → MAJOR.

Sneaky breakers people misfile as minor/patch:

- Narrowing a return type or making a field nullable -> `null` where callers expected a value.
- Adding a **required** field to a request body or a required named param.
- Changing a default value (`pageSize: 20 -> 50`) — behavior shifts under callers.
- Tightening validation (now rejecting input previously accepted).
- Throwing a new exception type from an existing path.
- Renaming a JSON key, even if the Dart/TS field name is unchanged.
- Raising the min SDK/runtime — drops platforms silently.

```dart
// MAJOR: removed positional param, callers won't compile
- Future<User> fetchUser(String id, {bool cache = true});
+ Future<User> fetchUser(String id);

// MINOR: new optional named param, old calls still valid
- Future<User> fetchUser(String id);
+ Future<User> fetchUser(String id, {Duration? ttl});
```

```ts
// MAJOR: response field went optional — every consumer must now null-check
type Order = { id: string; total: number; coupon?: string };
//                                            ^ was required

// MINOR: additive field, existing consumers ignore it
type Order = { id: string; total: number; currency: string /* new */ };
```

For Supabase, a migration that drops/renames a column or changes a type that another service or edge function reads is a MAJOR to *that contract* even if your app code adapts. Additive nullable columns are MINOR. See [[octopus-model]] for the data-layer conventions that define what "the schema contract" is.

## 2. Build the changelog from the merge history

Don't write notes from memory. Derive them from commits since the last tag — this is exactly why commits follow Conventional Commits + gitmoji per [[commit-pipeline]].

```bash
# range since last tag; %s gives the conventional subject
git log "$(git describe --tags --abbrev=0)"..HEAD --pretty=format:'%s'
```

Map commit type -> changelog section -> minimum bump:

| Commit type        | Section          | Floor bump |
|--------------------|------------------|------------|
| `feat`             | Added / Changed  | MINOR      |
| `fix`              | Fixed            | PATCH      |
| `perf`             | Performance      | PATCH      |
| `refactor`/`chore` | (usually omit)   | PATCH      |
| any `!` or `BREAKING CHANGE:` footer | **Breaking** | MAJOR |

The final bump = the highest floor across all commits in the range. One `feat!` forces MAJOR regardless of how many patches sit beside it.

## 3. Write notes humans actually read

Group by audience impact, not by commit. Lead with what forces action.

```markdown
## 1.4.0 — 2026-06-19

### Breaking
- `fetchUser` no longer caches by default. Pass `ttl:` to opt in.
  **Migrate:** add `ttl: Duration(minutes: 5)` to existing calls.

### Added
- Offline queue for write operations; flushes on reconnect.

### Fixed
- Crash when opening a deep link before auth completed.

### Internal
- Upgraded Supabase client to 2.x (no API change).
```

Rules for each entry:
- Write from the **consumer's** point of view, not the implementer's.
- Every Breaking entry MUST include a **Migrate:** line with the concrete change.
- One line per change; link to a PR/issue for detail, don't inline the saga.
- No internal names, ticket-only references, or "various fixes". If it's not worth a sentence, put it under Internal or drop it.

Keep an `Unreleased` section at the top of the changelog during development; rename it to the version on release so nothing is reconstructed last-minute.

## 4. Cut the release

1. Set the version: `pubspec.yaml` (Dart) or `package.json` (TS). Keep them in lockstep in a monorepo only if you intend lockstep releases.
2. Move `Unreleased` -> the version heading with today's date.
3. Commit the version bump + changelog per [[commit-pipeline]] (e.g. `chore(release): 🔖 v1.4.0`).
4. Tag: `git tag -a v1.4.0 -m 'v1.4.0'` and push tags.
5. Publish only from a clean tagged commit — never from a dirty tree.

```bash
# Dart: verify nothing surprising before publishing
dart pub publish --dry-run

# TS: confirm the tarball contains exactly the intended files
npm pack --dry-run
```

For Supabase, releasing the schema/edge layer is its own version line: ship and verify the migration in a preview branch, then merge — don't bundle a DB MAJOR into an app PATCH.

## Red flags — stop and reconsider

- "It's just a small breaking change, ship it as a patch." There is no small breaking change. MAJOR or revert it.
- Changelog assembled by hand at tag time -> you forgot something. Derive from `git log`.
- A `feat!` and a `fix` in the same range tagged as a minor -> you missed the MAJOR.
- Renamed JSON keys or tightened validation filed under "Fixed" -> these are breaking.
- Two unrelated breaking changes crammed into one release -> consumers face one wall of migration. Stage them if you can.
- Version bumped but the tag never pushed -> consumers can't pin it; CI may republish stale code.
- "No notes, see the commits" -> commits are for maintainers; release notes are for everyone else.

## One-line heuristic

If a careful consumer can break by doing nothing, it's MAJOR. If they gain something without changing code, it's MINOR. Otherwise it's PATCH — and write the migration line before you write anything else.
