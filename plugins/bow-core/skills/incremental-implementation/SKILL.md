---
name: incremental-implementation
description: Delivers changes in small, verified steps instead of one big drop. Use when a feature or change spans multiple files, when you are about to write a large block of code at once, or when a task feels too large to finish and verify in a single pass.
---

# Incremental Implementation

## Overview

Ship work in narrow, end-to-end slices. Land one piece, prove it works, then build the next on top of it. Never write an entire feature before running anything. Every slice must leave the project buildable, tested, and reviewable. This is how a large task stays controllable instead of turning into a 600-line blob nobody can debug.

## When to Use

- Any change that spans more than one file
- Turning a task breakdown into running code
- Refactoring something that already exists
- The moment you catch yourself planning to write ~100+ lines before a single test run

**Skip it** for a genuinely tiny, single-function edit where the whole scope already fits in one verified step.

## The Slice Loop

Repeat until the task is complete:

1. **Pick the smallest piece** that adds real, observable behavior.
2. **Build it.**
3. **Prove it** — run tests (write one if none cover this), build, type-check, lint.
4. **Record it** — commit the slice with a clear message. Defer entirely to `commit-pipeline` for message format, branching, and footers.
5. **Continue** to the next slice on top of what you just landed. Don't rewind.

```
build → prove → record → next slice
  ↑__________________________|
```

## Ways to Slice

### End-to-end first (default)

Cut through every layer for one capability, then move to the next capability.

```
Slice 1: Create a booking   — migration + RPC + minimal Flutter form  → user can create one
Slice 2: List bookings      — query + repository + list widget        → user sees their bookings
Slice 3: Cancel a booking   — update + service + confirm dialog        → full path works
```

Each slice is something a user could actually exercise.

### Contract first (parallel work)

When the Supabase/edge side and the Flutter side advance at once:

```
Slice 0: Agree the contract — TypeScript types + generated Dart models
Slice 1: Backend against the contract + integration tests
Slice 2: Flutter against a stub matching the contract
Slice 3: Swap the stub for the real endpoint, test end-to-end
```

### Riskiest part first

Front-load the unknown so a dead end shows up cheaply.

```
Slice 1: Prove realtime subscription delivers row changes (the unknown)
Slice 2: Build the live UI on the proven channel
Slice 3: Add reconnection and offline handling
```

If Slice 1 can't be made to work, you learn it before paying for Slices 2 and 3.

## Working Rules

### Simplest version first

Before coding, ask what the most boring solution that satisfies the task is — then write that. After coding, re-check:

- Can this lose lines without losing behavior?
- Is each abstraction paying for itself right now?
- Am I solving the task, or an imagined future one?

```
✗ A pluggable notification dispatcher for one toast message
✓ Call the toast function directly

✗ A generic "BaseRepository<T>" to back two tables
✓ Two small repositories that share a helper
```

Repeating three obvious lines beats one clever abstraction introduced too early. Get it correct and tested first; generalize only when a third caller actually appears. See `code-simplification` for trimming once it works.

### Stay inside the task

Change only what the task needs. Do **not** tidy nearby code, reorder imports in files you're only reading, drop comments you don't understand, or bolt on "handy" extras. When you spot something worth fixing elsewhere, log it instead of doing it:

```
SPOTTED, LEAVING ALONE:
- lib/utils/date.dart has a dead import (unrelated to this task)
- the auth guard's error copy is vague (separate ticket)
→ want these filed as follow-ups?
```

### One concern per slice

A slice does a single logical thing. Don't fold a new widget, a refactor of an old one, and a build-config tweak into the same step — that's three slices.

### Never leave it broken

After every slice the project compiles and the existing suite is green. The codebase is never half-broken between steps.

### Hide unfinished work behind a flag

If you need to land partial slices but users mustn't see them yet, gate them:

```dart
// Work in progress — off until the flow is complete
const enableGroupBooking =
    bool.fromEnvironment('FEATURE_GROUP_BOOKING', defaultValue: false);

if (enableGroupBooking) {
  // new group-booking UI
}
```

Now small slices can merge without exposing an unfinished feature.

### Default to the safe behavior

New behavior is opt-in and conservative by default:

```dart
Future<Booking> createBooking(BookingInput input, {bool notify = false}) async {
  // notification only fires when the caller explicitly asks
}
```

### Keep each slice revertible

Additive changes (new files, new functions) revert cleanly. Modifications stay small and focused. Every DB migration ships with its down migration. Don't delete and replace in the same step — split them so a revert is surgical.

## Directing an Agent

Be explicit about both the scope and the non-scope of the increment:

```
Implement Slice 2 from the plan.

Only the query + repository + list widget. Leave create/cancel for later slices.
When done, run the Flutter test suite and `flutter analyze` and report results.
```

## Per-Slice Checklist

- [ ] Does exactly one thing, completely
- [ ] Existing tests pass
- [ ] Build succeeds
- [ ] Type/static analysis clean (`flutter analyze` / `tsc --noEmit`)
- [ ] Lint clean
- [ ] The new behavior works as intended
- [ ] Committed per `commit-pipeline`

Run a check after a change that could affect it. Once a check is green and nothing changed since, don't re-run it for reassurance — that adds no information.

## Excuses vs. Reality

| Excuse | Reality |
|---|---|
| "I'll test the whole thing at the end" | A bug in Slice 1 silently poisons Slices 2–5. Catch it where it's cheap. |
| "Doing it all at once is faster" | Until something breaks and the cause is hidden among hundreds of unreviewed lines. |
| "Too small to commit on its own" | Small commits cost nothing and make reverts painless. Big commits bury bugs. |
| "I'll add the flag later" | Incomplete means not user-visible. Add the flag now or don't merge. |
| "This little refactor can ride along" | Mixed refactor + feature is harder to review and bisect. Separate slices. |
| "Let me run the build once more to be safe" | Re-running an unchanged, already-green check tells you nothing new. |

## Red Flags

- 100+ lines written with no test run
- Unrelated changes bundled in one slice
- "While I'm here, let me also…" scope creep
- Skipping the prove step to go faster
- Build or tests red between slices
- A growing pile of uncommitted work
- Inventing an abstraction before a third caller needs it
- Editing files the task never asked you to touch
- Re-running the same check twice with no edit in between

## Done When

- [ ] Each slice was individually proven and committed
- [ ] The full suite passes
- [ ] The build is clean
- [ ] The feature works end-to-end per the spec
- [ ] Nothing is left uncommitted
