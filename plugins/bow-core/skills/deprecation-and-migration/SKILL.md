---
name: deprecation-and-migration
description: Retires old code and moves users onto its replacement safely. Trigger when sunsetting a system, API, or feature; when migrating consumers from one implementation to another; or when deciding whether to keep maintaining something or kill it.
---

# Deprecation and Migration

## Overview

Code is a cost center, not a trophy. Every line carries a recurring bill — bugs, dependency bumps, security patches, and the time it takes each new person to understand it. Deprecation is the discipline of deleting code that no longer pays that bill; migration is the work of moving its users somewhere better without breaking them. Teams are usually good at building and bad at removing. This skill is about removing.

## When to Use

- Swapping an old system, API, or library for a newer one
- Killing a feature nobody needs anymore
- Folding two duplicate implementations into one
- Clearing out dead code that has no owner but live dependents
- Designing a new system (plan its eventual removal at design time)
- Choosing between maintaining a legacy path and investing in migration

## Principles

**Less code is the goal.** The value is the behavior delivered, not the lines that deliver it. When the same behavior fits in less code, fewer dependencies, or a cleaner interface, the old version should go.

**Everything observable becomes load-bearing.** Once enough consumers exist, someone depends on every quirk you expose — including bugs, timing, and undocumented side effects. That is why deprecation demands active migration rather than a notice; people cannot "just switch" off behaviors the replacement does not reproduce.

**Plan removal while you build.** When creating a system, ask how you would delete it in three years. Clean interfaces, flag points, and a small surface area make that future cheap; leaked internals make it impossible.

## The Deprecation Decision

Answer before you deprecate anything:

```
1. Does it still deliver unique value?      yes -> keep it; no -> continue
2. How many consumers depend on it?         quantify the migration scope
3. Does a real replacement exist?           no -> build it first, never deprecate without one
4. What's the per-consumer migration cost?  trivially scriptable -> just do it; high manual -> weigh vs. upkeep
5. What's the cost of NOT removing it?       security exposure, engineer time, complexity drag
```

## Advisory vs. Mandatory

| Mode | Use when | How it works |
|---|---|---|
| Advisory | The old path is stable and migration is optional | Warnings, docs, nudges. Consumers move on their own schedule. |
| Mandatory | The old path is insecure, blocks progress, or is too costly to keep | A firm removal date — plus migration tooling, docs, and support. |

Default to advisory. Reserve mandatory for cases where risk or upkeep justifies forcing the move — and remember that a deadline without tooling and support is an abdication, not a plan.

## Migration Process

### 1. Build and prove the replacement

Never deprecate without a working alternative that covers the critical use cases, has a migration guide, and is proven in production — not merely "better in theory".

### 2. Announce and document

```markdown
## Deprecation: LegacyTaskClient

Status:      Deprecated 2025-03-01
Replaces it: TaskClient (migration guide below)
Removal:     Advisory — no hard date yet
Why:         LegacyTaskClient needs manual scaling and emits no telemetry;
             TaskClient handles both.

### Migrate
1. Swap the import: `legacy_task_client` -> `task_client`
2. Update config (examples below)
3. Run the checker: `dart run tool/migrate_check.dart`
```

### 3. Move consumers one at a time

Per consumer: find every touchpoint, switch it to the replacement, verify behavior matches with tests, delete the old references, confirm no regression. Incremental beats big-bang every time.

**You own the migration.** If you own the thing being deprecated, you own moving its users — or you ship backward-compatible changes that need no migration. Announcing a sunset and leaving consumers to fend for themselves is not allowed.

### 4. Remove the old system

Only once usage is genuinely zero (confirmed by metrics, logs, and dependency analysis): delete the code, then its tests, docs, and config, then the deprecation notices themselves. Deleting code is a win, not a loss.

## Migration Patterns

### Strangler

Run old and new side by side and shift traffic across in steps until the old path serves nothing, then delete it.

```
0%  -> 10% (canary) -> 50% -> 100% on new
then remove the old system (now idle)
```

### Adapter

Wrap the new implementation behind the old interface so existing callers keep working while you replace the internals.

```dart
// Old interface, new engine behind it
class LegacyTaskService implements OldTaskApi {
  LegacyTaskService(this._next);
  final TaskService _next;

  @override
  OldTask getTask(int id) => _toOldShape(_next.findById(id.toString()));
}
```

### Flag-gated cutover

Switch consumers across one cohort at a time with a flag, so you can advance or retreat instantly.

```dart
TaskService resolveTaskService(String userId) =>
    featureFlags.enabled('task-service-v2', userId)
        ? TaskService()
        : LegacyTaskService(TaskService());
```

When the migration is a database change, coordinate the schema steps with `shipping-and-launch`: expand the schema first, backfill, switch reads, then contract — never a destructive change while both versions are live.

## Orphaned Code

Code with live dependents but no owner is the worst category: unmaintained, accruing vulnerabilities, yet load-bearing. Tells:

- No commits in 6+ months but active consumers
- No assigned team or maintainer
- Failing tests nobody fixes
- Known-vulnerable dependencies nobody updates
- Docs referencing systems that no longer exist

It cannot stay in limbo: either assign an owner and maintain it properly, or deprecate it with a concrete migration plan. Invest or remove.

## Common Rationalizations

| Excuse | Reality |
|---|---|
| "It still works, why touch it?" | Working but unmaintained code silently accrues security debt and complexity. |
| "Someone might need it someday" | If so, rebuild it then. Hoarding unused code costs more than rebuilding. |
| "Migration is too expensive" | Compare it to two or three years of upkeep — migration usually wins long-term. |
| "We'll plan removal after the new system ships" | By then new priorities will own you. Plan removal at design time. |
| "Users will migrate themselves" | They won't. Provide tooling and docs, or do it yourself. |
| "We can run both forever" | Two systems for one job means double the tests, docs, and onboarding, indefinitely. |

## Red Flags

- A deprecation with no replacement
- A sunset notice with no tooling or docs
- "Soft" deprecation that has been advisory for years with no movement
- Orphaned code with active consumers
- New features added onto a deprecated system
- Deprecating without first measuring current usage
- Deleting code without confirming zero consumers

## Verification

- [ ] Replacement is production-proven and covers the critical use cases
- [ ] Migration guide exists with concrete, runnable steps
- [ ] All active consumers migrated (confirmed by metrics/logs)
- [ ] Old code, tests, docs, and config fully removed
- [ ] No references to the deprecated system remain
- [ ] Deprecation notices removed once their job is done

Removals and cutover commits follow the `commit-pipeline` skill.
