---
name: code-simplification
description: Make working code clearer without changing what it does. Trigger when refactoring code that runs correctly but is harder to read, maintain, or extend than it needs to be, or when a review flags accumulated complexity. Prefer deleting dead and redundant code over adding more. Behaviour-preserving only — for bug hunting use [[code-review-and-quality]].
---

# Code Simplification

## Why this exists

Simplification is reducing complexity while keeping behaviour byte-for-byte identical. The win is not fewer lines — it is code a teammate can read, change, and debug faster. The test for any edit: would someone new to this file understand the new version sooner than the old one? If not, don't make the change.

## Reach for this when

- A feature works and its tests pass, but the code feels heavier than the problem
- A review calls out tangled or unclear code
- You hit deep nesting, sprawling functions, or names that mislead
- You are cleaning up code written in a hurry
- Related logic is scattered and wants consolidating

Leave it alone when:

- The code is already clear — don't simplify for its own sake
- You don't yet understand what it does — understand first
- It is hot-path code and the "simpler" form is measurably slower
- You are about to rewrite the whole module anyway

## Ground rules

### Behaviour stays exactly the same

Change the expression, never the effect. Same outputs, same errors, same side effects, same ordering, same edge cases. Before any edit, answer:

```
- Same output for every input?
- Same error behaviour?
- Same side effects, in the same order?
- Do all tests still pass with no test changes?
```

If a "simplification" forces a test edit, you changed behaviour — stop.

### Match the codebase, not your taste

Simpler means more consistent with what is already here. Read the project conventions (CLAUDE.md), look at how nearby code solves the same shape of problem, and match its import order, naming, error-handling, and type style. Simplification that fights local convention is just churn.

### Clarity over cleverness

```dart
// Dense and slow to parse
final label = isNew ? 'New' : isUpdated ? 'Updated' : isArchived ? 'Archived' : 'Active';

// Reads top to bottom
String statusLabel(Item item) {
  if (item.isNew) return 'New';
  if (item.isUpdated) return 'Updated';
  if (item.isArchived) return 'Archived';
  return 'Active';
}
```

### Don't over-correct

Over-simplification is its own failure. Watch for:

- Inlining a helper that gave a concept a useful name
- Merging two clear functions into one murky one
- Stripping an abstraction that existed for testability or a real extension point
- Chasing line count instead of comprehension

### Stay in scope

Simplify the code you are already touching. Skip drive-by cleanups of unrelated files unless asked — they bloat the diff and risk regressions you didn't mean to cause.

## The process

### 1. Understand before you touch (Chesterton's Fence)

Don't remove a thing until you know why it is there. If a fence blocks the road and you can't say why, don't tear it down — learn the reason first, then judge whether it still holds.

```
Before simplifying, answer:
- What is this code responsible for?
- What calls it, and what does it call?
- What are its edge cases and error paths?
- Do tests define its expected behaviour?
- Was it written this way for a reason — perf, a platform quirk, history?
- What does `git blame` / the original commit say about it?
```

Can't answer these? Read more first.

### 2. Spot the opportunities

Concrete signals, not vibes:

**Structure**

| Smell | Why it hurts | Fix |
|---|---|---|
| Nesting 3+ deep | Control flow is hard to track | Guard clauses, extracted helpers |
| Functions 50+ lines | Too many jobs | Split into named functions |
| Nested ternaries | Needs a mental stack | if/else, switch, or a lookup |
| Boolean param flags | `doX(true, false)` is opaque | Options object or separate functions |
| Repeated conditionals | Same check copied around | A named predicate |

**Naming**

| Smell | Fix |
|---|---|
| `data`, `tmp`, `res`, `val` | Name the content: `userProfile`, `validationErrors` |
| `usr`, `cfg`, `btn` | Spell it out unless universal (`id`, `url`) |
| `get*` that also mutates | Rename to the truth |
| Comment restating the code | Delete it |
| Comment explaining *why* | Keep it — code can't carry intent |

**Redundancy**

| Smell | Fix |
|---|---|
| Same 5+ lines repeated | Extract a shared function |
| Dead code, unused vars, commented blocks | Remove once confirmed dead |
| Wrapper that adds nothing | Inline it |
| Pattern built for one case | Use the direct approach |

### 3. Change incrementally

One simplification at a time; run tests after each.

```
for each change:
  1. make it
  2. run the tests
  3. green → keep going
  4. red  → revert and rethink
```

Never batch many edits into one untested change — when something breaks you must know which edit did it. Keep refactoring out of feature and bug-fix diffs; a PR that refactors *and* adds a feature is two PRs.

**Scale rule:** if a refactor would span hundreds of lines, automate it (codemod, AST transform) rather than hand-editing. Manual edits at that size are error-prone and brutal to review.

### 4. Step back and judge

```
Compare before and after:
- Is it genuinely easier to follow?
- Did you introduce a pattern foreign to this codebase?
- Is the diff clean and reviewable?
- Would a teammate approve this as an improvement?
```

If the "simpler" version is harder, revert. Not every attempt lands.

## Worked examples

```typescript
// Drop a pointless async wrapper
async function getUser(id: string) { return await repo.findById(id); }
function getUser(id: string) { return repo.findById(id); }

// Collapse verbose assignment
let name; if (u.nickname) name = u.nickname; else name = u.fullName;
const name = u.nickname || u.fullName;

// Use the standard library
const active = []; for (const u of users) if (u.isActive) active.push(u);
const active = users.filter((u) => u.isActive);
```

```dart
// Redundant boolean wrapping
bool isValid(String s) { if (s.isNotEmpty && s.length < 100) return true; return false; }
bool isValid(String s) => s.isNotEmpty && s.length < 100;

// Flatten nested guards with early returns
String process(Data? d) {
  if (d == null) throw ArgumentError('data is null');
  if (!d.isValid) throw StateError('invalid data');
  if (!d.hasPermission) throw StateError('no permission');
  return doWork(d);
}
```

## Excuses and rebuttals

| Excuse | Reality |
|---|---|
| "It works, leave it" | Working-but-unreadable code is slow to fix when it breaks. Pay down now. |
| "Fewer lines is simpler" | A one-line ternary can be harder than a five-line if/else. Comprehension, not count. |
| "I'll tidy this unrelated bit too" | Out-of-scope edits create noise and risk. Stay focused. |
| "The types document it" | Types show structure, not intent. A good name explains *why*. |
| "Might need this abstraction later" | Unused abstraction is cost without value. Re-add when it's actually needed. |
| "The author surely had a reason" | Maybe — check blame. Often it's just residue of rushed iteration. |
| "I'll refactor while adding the feature" | Separate them. Mixed diffs are hard to review, revert, and trace. |

## Red flags

- A simplification that needs the tests changed (you changed behaviour)
- "Simpler" code that is longer or harder to follow
- Renaming to your preference instead of the project's convention
- Dropping error handling to "clean it up"
- Touching code you don't fully understand
- One giant hard-to-review refactor commit
- Refactoring outside the task without being asked

## Before you finish

- [ ] All tests pass with no test edits
- [ ] Build/analyze clean, no new warnings
- [ ] Linter/formatter happy
- [ ] Each change is incremental and reviewable
- [ ] Diff is clean — nothing unrelated mixed in
- [ ] Code matches project conventions
- [ ] No error handling weakened or removed
- [ ] No dead code or unused imports left behind

Commit the simplification on its own, following [[commit-pipeline]].
