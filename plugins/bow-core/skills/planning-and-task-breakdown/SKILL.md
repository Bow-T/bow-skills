---
name: planning-and-task-breakdown
description: Turn an approved spec or clear requirements into a small, ordered list of verifiable tasks before writing code. Trigger when a job feels too big to start, when scope needs estimating, when work could run in parallel, or when the build order is not obvious. Each task is sized to finish in one focused session. Follows [[spec-driven-development]]; feeds [[incremental-implementation]].
---

# Planning and Task Breakdown

## Why this exists

A plan is the bridge between "we agreed what to build" and "code is appearing." Break the work into small units that can each be built, tested, and confirmed in one sitting. The quality of this breakdown decides whether implementation goes smoothly or turns into a tangle of half-finished threads.

## Reach for this when

- A spec or clear requirement exists and needs to become concrete tasks
- A task is too large or fuzzy to begin
- Several sessions or agents could work in parallel
- You need to show scope to a person
- The order of operations is unclear

Skip it for obvious single-file changes, or when the spec already lists well-shaped tasks.

## Plan, don't type

While planning, stay in read-only mode. The deliverable is a task list, not a diff.

1. Read the spec and the relevant code
2. Note the patterns and conventions already in use
3. Trace dependencies between the pieces
4. Flag risks and unknowns

## Map dependencies, then build upward

Sketch what relies on what. For this stack a typical chain runs:

```
Supabase table + RLS policy
  └─ generated types / Dart model
       └─ repository method
            └─ view-model / service
                 └─ Flutter widget
```

Build from the bottom of the chain up — foundations before the things that lean on them.

## Cut vertical slices, not horizontal layers

Resist building every table, then every repository, then every screen. Ship one whole capability end to end at a time.

Horizontal (avoid):

```
Build all tables → build all repositories → build all screens → wire it up
```

Vertical (prefer):

```
Slice 1: user creates a task (table + RLS + model + repo + create form)
Slice 2: user sees their task list (query + repo method + list widget)
Slice 3: user archives a task (status column + repo + tab + widget test)
```

Every slice leaves a working, demoable feature behind.

## Shape of a task

```markdown
## Task N: <short title, no "and">

What it delivers: one sentence.

Acceptance:
- [ ] <testable condition>
- [ ] <testable condition>

Verify:
- [ ] Tests: `flutter test test/<area>_test.dart`
- [ ] Analyze/build: `flutter analyze`
- [ ] Manual: <what to click / observe>

Depends on: <task numbers, or None>

Files likely touched:
- lib/<path>.dart
- test/<path>_test.dart

Size: XS / S / M  (anything bigger gets split)
```

## Sizing and when to split

| Size | Files | Looks like |
|------|-------|-----------|
| XS | 1 | A validation rule, a config tweak |
| S | 1–2 | One repository method or widget |
| M | 3–5 | One vertical slice |
| L | 5–8 | Split it |
| XL | 8+ | Definitely split it |

Aim for S and M. Split a task when:

- It would take more than one focused session
- You cannot state its acceptance in three bullets or fewer
- It spans two unrelated subsystems (e.g. auth and billing)
- Its title needs the word "and"

## Order, checkpoint, de-risk

Arrange tasks so that:

1. Dependencies come first
2. Each task leaves the app working
3. Risky/unknown tasks land early (fail fast)
4. A checkpoint sits after every 2–3 tasks

```markdown
## Checkpoint after Tasks 1–3
- [ ] Tests green, `flutter analyze` clean
- [ ] Core flow works end to end
- [ ] Confirm with requester before continuing
```

## Plan document skeleton

```markdown
# Plan: <feature> (<TICKET-ID>)

## Summary
One paragraph.

## Key decisions
- <decision + why>

## Tasks
### Foundation
- [ ] Task 1 ...
### Checkpoint
### Core
- [ ] Task 2 ...
### Checkpoint
### Polish
- [ ] Task 3 ...

## Risks
| Risk | Impact | Mitigation |
|------|--------|------------|

## Open questions
- <needs a human>
```

## Parallel work

- Safe to parallelise: independent slices, tests for already-built code, docs
- Must stay sequential: migrations, shared-state edits, dependency chains
- Needs a handshake first: features sharing a contract — define the contract, then split

## Excuses and rebuttals

| Excuse | Reality |
|---|---|
| "I'll work it out as I go" | That is how threads end up half-finished. Ten minutes of planning saves hours. |
| "The tasks are obvious" | Write them anyway — the act surfaces hidden dependencies and forgotten edges. |
| "Planning is overhead" | Planning is the work. Coding without a plan is just typing. |
| "I can keep it in my head" | Context windows and memory both end. A written plan survives the session. |

## Red flags

- Starting to code with no written task list
- Tasks that say "implement the feature" with no acceptance criteria
- No verify step on any task
- Everything is L or XL
- No checkpoints
- Dependency order ignored

## Before implementation starts

- [ ] Every task has acceptance criteria and a verify step
- [ ] Dependencies identified and ordered correctly
- [ ] No task touches more than ~5 files
- [ ] Checkpoints sit between phases
- [ ] The requester approved the plan
