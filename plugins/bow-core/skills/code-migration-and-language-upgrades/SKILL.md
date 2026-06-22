---
name: code-migration-and-language-upgrades
description: Triggers when upgrading a runtime/framework/language version or porting between them — assessing breaking changes, codemods, incremental cutover, and dual-running old and new.
---

# Code Migration and Language Upgrades

A migration is a bet that the destination is worth the disruption. Most failed migrations
were not technically impossible — they were unbounded, unverifiable, and irreversible. Your
job is to make the change *bounded* (you know what breaks), *verifiable* (you can prove
parity), and *reversible* (you can stop halfway and ship).

## Step 0 — Decide if you should migrate at all

Push back before you start. A version bump for its own sake is rarely worth it.

- **Forced**: current version EOL / loses security patches, blocks a dependency you need.
- **Justified**: concrete capability you'll use (Dart 3 records, a new Flutter API, a
  TypeScript `satisfies` you keep hand-rolling).
- **Vanity**: "we're behind." Log it as debt instead — see [[technical-debt-management]].

If you proceed, write the rollback condition *first*: "If parity tests fail or p99 regresses
>10%, we revert to old." A migration without a defined abort is a one-way door.

## Step 1 — Inventory the blast radius

Measure before you touch anything. Don't trust your memory of where the old thing is used.

```bash
# Every call site of the API you're replacing (TS example: moment -> Temporal/date-fns)
rg -n "from ['\"]moment['\"]|require\(['\"]moment" --stats

# Dart: find deprecated symbol usage across the app
grep -rn "WillPopScope\|ButtonBar\b" apps/mobile/lib

# What pins you: transitive deps that constrain the version you can reach
flutter pub deps --style=compact | rg "<dep_that_blocks>"
```

Produce three lists: **direct call sites**, **behavioral dependents** (code that relies on a
quirk, not just the signature), and **blockers** (deps that won't move yet). The blockers
decide your timeline more than your own code does.

## Step 2 — Read the actual breaking-change list

Don't guess what changed. Pull the official upgrade/changelog for *each* major version you
cross, not just source→target. Crossing 2→4 means reading 2→3 and 3→4. Verify against current
docs — see [[source-driven-development]].

Classify each breaking change:

| Class | Example | Handling |
|---|---|---|
| Mechanical | renamed symbol, moved import | codemod / find-replace |
| Semantic | same name, different behavior (null handling, rounding, timezone) | test-guarded, manual |
| Structural | API removed, paradigm shift (callbacks→async) | rewrite the call site |
| Silent | no error, different result at runtime | the dangerous one — needs parity checks |

Semantic and silent changes are where migrations bleed. A `String.split` that now keeps
trailing empties, an integer division that used to truncate — these compile fine and corrupt
data quietly.

## Step 3 — Pin a working baseline and a throwaway spike

Lock the current lockfile (`pubspec.lock`, `package-lock.json`) on a tag so you can always
get back to green. Then do a **timeboxed throwaway spike**: blast the upgrade through on a
scratch branch, let it fully break, and count the errors. This tells you the order of
magnitude (10 errors vs 10,000) before you commit to a strategy. Delete the spike after.

## Step 4 — Pick a cutover strategy by scale

- **Atomic** (small, mechanical): upgrade, fix all sites, ship one change. Only when the
  spike showed a contained, mostly-mechanical blast radius.
- **Incremental in place**: introduce a compatibility shim, migrate call sites in batches
  behind it, delete the shim last. Default for medium changes.
- **Dual-run / strangler**: run old and new side by side, route a slice of traffic to new,
  compare outputs, ramp up. For high-risk semantic changes or anything user-visible at scale.

A shim lets old and new coexist so you migrate gradually instead of in one terrifying commit:

```ts
// Old call sites import from here; swap the impl once, migrate callers at leisure.
// money-fmt.ts  (migrating Intl rounding behavior)
export function formatMoney(cents: number, locale: string): string {
  // return legacyFormat(cents, locale);       // step 1: shim wraps old
  return newFormat(cents, locale);              // step 3: flip, after parity proven
}
```

## Step 5 — Codemod the mechanical changes

Hand-editing hundreds of identical call sites guarantees mistakes. Automate the boring class.

- **Dart**: `dart fix --apply` clears deprecations the SDK ships fixes for; run `dart format`
  after so the diff is reviewable.
- **TypeScript**: `tsc` with the new lib first to surface errors, then `eslint --fix`, then a
  scoped AST codemod (jscodeshift / ts-morph) for renames a regex can't do safely.
- **SQL / Supabase**: never edit applied migrations — write a *new forward* migration. For a
  type or constraint change, expand-then-contract (Step 7), each step its own migration file.

Run codemods on one module, review the diff by hand, *then* let it loose. A bad codemod across
the repo is worse than the manual edits it replaced.

## Step 6 — Prove parity, don't eyeball it

This is the step people skip and regret. Generated/transformed code that compiles is not
correct — see the verify discipline below.

- **Golden / characterization tests**: capture outputs of the old code on representative
  inputs, assert the new code matches. Especially dates, money, sorting, serialization.
- **Differential run**: in dual-run, send the same input to both and log mismatches without
  failing the request. Let it bake on real traffic before you trust it.

```ts
// shadow comparison — new path runs but old path still serves
const oldOut = legacy(input);
const newOut = migrated(input);
if (!deepEqual(oldOut, newOut)) {
  log.warn("migration.mismatch", { input, oldOut, newOut }); // collect, don't throw
}
return oldOut; // still authoritative until mismatch rate ~0
```

Regenerate Supabase types after any schema change so the TS client matches the new shape;
a stale `database.types.ts` is a silent migration bug.

## Step 7 — Database & contract migrations: expand → migrate → contract

Schema and API changes can't be atomic across deployed clients. Make every step
backward-compatible so old and new run simultaneously.

1. **Expand**: add the new column/field/endpoint as nullable/optional. Old code ignores it.
2. **Migrate**: dual-write both, backfill existing rows, switch reads to new.
3. **Contract**: once nothing reads the old, drop it — in a *later* deploy, never the same one.

Never rename in place; never make a column `NOT NULL` in the same migration that adds it to a
running system. See [[zero-downtime-database-migrations]] and [[api-versioning-and-evolution]]
for the full discipline.

## Step 8 — Land it incrementally

Ship the migration in small, independently-revertable commits, not one mega-diff — see
[[incremental-implementation]]. Keep CI green at every step; a half-migrated repo that doesn't
build blocks everyone else. For commits, follow [[commit-pipeline]].

## Red flags — stop and rethink

- You can't state the rollback condition. → You don't have a plan, you have a hope.
- "It compiles, ship it." → Mechanical correctness ≠ behavioral parity. Run Step 6.
- Editing an already-applied migration instead of writing a new one.
- Bumping across multiple majors in one commit. → Read and cross each version (Step 2).
- A single PR touches every file. → No incremental cutover; you can't review or revert it.
- Dropping the old column/field in the same deploy that stops writing it.
- Codemod run repo-wide before being verified on one module.
- Blocked dependency you're "sure" will update soon. → It dictates your timeline; plan around
  it or vendor a fork, don't assume.

## Definition of done

Old code path removed (or shim deleted), parity tests green and committed, mismatch rate at
zero in dual-run, types regenerated, lockfiles updated, and the rollback path tested at least
once — not just designed.
