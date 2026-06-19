---
name: large-scale-refactoring
description: Restructures code across many files without breaking it — touching dozens of call sites, splitting/merging modules, introducing a cross-cutting abstraction, or a repo-wide rename/move.
---

# Large-Scale Refactoring

Big refactors fail not because the new design is wrong, but because the *transition* is unsafe. The job is to change shape across many files while keeping the tree green at every step. Optimize for reversibility and reviewability, not for finishing fast.

## 0. Decide if you should even start

Stop and reconsider if:
- There is no test coverage on the code you're about to move. Add characterization tests first.
- The desired end state isn't clear. You cannot mechanically transform toward a target you can't name.
- A feature freeze is impossible and the blast radius spans hot files. Coordinate a window or use the expand/contract path below.

Green light: clear target shape, tests (or a fast feedback loop) exist, and you can land it in reviewable slices.

## 1. Map the blast radius before touching anything

Quantify scope first — it drives the strategy.

```bash
# How many call sites? Dart + TS in one pass.
grep -rn "OldServiceName" --include="*.dart" --include="*.ts" lib/ src/ | wc -l
# Where do they cluster? Module-level heatmap.
grep -rl "OldServiceName" lib/ src/ | xargs -n1 dirname | sort | uniq -c | sort -rn
```

Decision point on the count:
- **< ~15 sites, one layer** → do it in a single atomic change.
- **Dozens of sites, or crosses layers** → use expand/contract (Section 3).
- **Public API others depend on** → expand/contract is mandatory; you don't control the callers.

## 2. Prefer mechanical over manual

A refactor that a tool can do is a refactor you can trust and repeat.

- Pure renames/moves: use the IDE's rename-symbol or `dart fix` / TS language-server refactors — they update imports and references atomically. Never hand-edit a rename across 40 files.
- Repeatable structural edits the IDE can't do: write a codemod (`ts-morph` for TypeScript, `jscodeshift`, or a `dart` analyzer script) instead of sed. AST tools won't corrupt strings, comments, or partial matches the way regex does.
- One-off, irregular edits: do them by hand, but in the smallest batch you can verify.

Red flag: reaching for `sed -i 's/foo/bar/g'` across the repo. It will rewrite substrings inside unrelated identifiers and string literals.

## 3. Expand / contract (the parallel-change pattern)

The only safe way to change a widely-used contract without a flag-day. Three landable steps:

**Expand** — introduce the new shape alongside the old. Nothing breaks; both work.

```dart
// New API lives next to the old. Old delegates to new.
@Deprecated('Use fetchProfile. Removed after v2.4.')
Future<User> getUser(String id) => fetchProfile(id);

Future<Profile> fetchProfile(String id) { /* new impl */ }
```

**Migrate** — move call sites to the new shape, in batches by module. Each batch is independently reviewable and revertible. Tree stays green throughout.

**Contract** — once `grep` shows zero remaining callers, delete the old shape.

```bash
grep -rn "getUser(" --include="*.dart" lib/ | grep -v "@Deprecated"  # must be empty before deleting
```

For Supabase schema changes, the same pattern is non-negotiable because the database and the deployed app version differently:
1. Migration adds the new column/table (additive, nullable, backfilled). Old code ignores it.
2. Regenerate types and ship code that writes both old and new.
3. Backfill, then ship code that reads new.
4. Later migration drops the old column.

Never rename a live column in one migration while old app builds are still in users' hands — that's a flag-day outage.

## 4. Land in slices, keep the tree green

- One logical transformation per change set. "Introduce the abstraction" and "migrate module A to it" are separate changes.
- Run the full check after each slice: `flutter analyze && flutter test`, `tsc --noEmit && <test runner>`, `supabase db reset` against fresh migrations.
- A pure move/rename change should contain **zero** behavioral edits. If you spot a bug mid-move, note it and fix it in a follow-up — mixing the two makes review impossible and blame useless.
- Commit per slice using [[commit-pipeline]]. Refactor slices are `refactor:`; the deletion step is also `refactor:`.

## 5. Verify behavior is unchanged

Refactoring means external behavior is identical by definition. Prove it:
- Tests pass without modification. If you had to change a test's *assertions* (not just imports/names), you changed behavior — that's not a refactor anymore.
- Diff the public surface where possible: compare generated TS types (`generate_typescript_types`) before/after a data-layer move; they should match.
- For risky moves, run the app against the real path — see [[verify]].

## 6. Make the diff reviewable

A 4,000-line refactor PR gets rubber-stamped, which defeats the safety net.

- Separate mechanical churn (rename/move) from hand edits into different commits so a reviewer can skim the boring one and focus on the real one.
- In the PR body, state: the target shape, the strategy (atomic vs expand/contract), how you verified behavior held, and what the final cleanup commit removes.
- Keep formatting-only changes out. A drive-by reformat buried in a rename hides the real change — run the formatter as its own commit if needed.

## Red flags

- Editing imports by hand across many files → you skipped the tool.
- A "refactor" commit that also changes test assertions or adds a feature → it's not a refactor; split it.
- Renaming a live DB column in a single migration → flag-day outage.
- The old code path can't be grep'd to zero before deletion → you don't actually know all callers; finish migrating.
- One giant commit "because it's all related" → unreviewable and unrevertible; slice it.
- Branch lives for weeks and drifts from main → rebase often or land expand/contract slices to trunk continuously.

## See also

- [[commit-pipeline]] — slicing the work into Conventional Commits.
- [[octopus-model]] — when the refactor reshapes the Supabase data layer.
- [[verify]] — confirming behavior held on risky moves.
