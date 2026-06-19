---
name: spec-driven-development
description: Write an agreed specification, linked to a tracker ticket, before any implementation. Trigger when kicking off a new feature, a multi-file change, or an architectural decision and no spec exists yet — especially when the ask is vague ("make it faster", "add reporting"). Convert fuzzy wants into testable acceptance criteria with concrete code-path evidence. Hands off to [[planning-and-task-breakdown]].
---

# Spec-Driven Development

## Why this exists

A spec is the contract you and the requester agree on *before* code is typed. It pins down the target so the work can be verified instead of vibe-checked. Skip it and you are building from your own guesses — the most expensive kind of misunderstanding, because nobody notices until the feature is wrong.

## Reach for this when

- A feature or epic is starting and there is no written agreement on scope
- The request is open-ended, hand-wavy, or one line long
- The change spans multiple modules, packages, or a Supabase migration
- An architectural call is on the table (state management, data shape, auth model)
- The work is clearly more than a quick edit

Skip it for typos, copy tweaks, one-line fixes, and anything where "done" is self-evident.

## Gate the work into phases

Each phase ends with the requester signing off. Do not roll into the next phase on your own authority.

```
DEFINE → DESIGN → SLICE → BUILD
  (sign-off)  (sign-off)  (sign-off)  (sign-off)
```

`SLICE` and `BUILD` are owned by [[planning-and-task-breakdown]] and [[incremental-implementation]]. This skill owns DEFINE and DESIGN.

## Phase 1 — Define

### State your assumptions out loud first

Before drafting anything, dump every assumption you are about to bake in and ask for a correction. Example for this stack:

```
ASSUMPTIONS (correct me before I continue):
- Client is Flutter (mobile + web), not a separate native build
- Backend is Supabase; auth is Supabase Auth with RLS, not a custom server
- New tables get row-level security from day one
- Reads go through the existing repository layer, not raw queries in widgets
```

Never quietly resolve an ambiguity. Surfacing assumptions is the entire point — a wrong assumption caught here costs a sentence, caught in code review it costs a day.

### Turn vague asks into measurable criteria

Rewrite the request as conditions a test or a person can check.

```
ASK:    "Loading the dashboard feels slow"

CRITERIA (confirm these are the right numbers):
- First meaningful frame renders in under 400ms on a mid-tier Android device
- The summary query returns in under 200ms p95 against production-sized data
- No spinner flashes for cached data (stale-while-revalidate)
```

Now you have something to build toward and loop against, instead of chasing a feeling.

### Capture acceptance criteria WITH evidence

Each criterion names the code path that proves it, not a checkbox someone ticks by hand.

```
- [ ] User can archive a task
      Evidence: TaskRepository.archive() flips status; widget test
      task_card_test.dart asserts archived tasks move to the Archived tab
- [ ] Archived tasks are excluded from the active count
      Evidence: SQL view active_task_count filters status <> 'archived'
```

### Spec skeleton

```markdown
# Spec: <feature> (<TICKET-ID>)

## Goal
Who is this for, what do they get, and how do we recognise success?

## Stack & dependencies
Languages, frameworks, packages/versions, Supabase tables touched.

## Acceptance criteria (with evidence)
- [ ] <criterion> — Evidence: <code path / test that proves it>

## Out of scope
Things people will assume are included but are not.

## Boundaries
- Always: <e.g. RLS on new tables, validate input at the edge>
- Ask first: <schema migrations, new dependency, auth changes>
- Never: <commit secrets, delete failing tests, skip RLS>

## Open questions
Anything still unresolved that needs a human answer.
```

## Phase 2 — Design

With the spec approved, write a short technical approach the requester can react to:

- The components involved and how data flows between them
- The build order driven by dependencies (what must exist first)
- Risks and how you will de-risk them
- Verification checkpoints between chunks of work

The design is good when someone can read it and reply "yes" or "change X" without reading any code.

## Keep the spec alive

The spec is a living document tied to its ticket:

- Decision changes? Edit the spec first, then the code follows.
- Scope grows or shrinks? Reflect it in the spec before building.
- Keep the spec in version control next to the code.
- When you open a PR, point at the spec section it satisfies.

Committing the spec follows the team convention — see [[commit-pipeline]]. Do not invent a different message format.

## Excuses and rebuttals

| Excuse | Reality |
|---|---|
| "Too small for a spec" | Small means a *short* spec, not no acceptance criteria. Two lines is fine. |
| "I'll document it after" | After-the-fact notes describe what you built; a spec forces clarity before you build. |
| "A spec slows us down" | Fifteen minutes of spec beats a day of rework on the wrong thing. |
| "Requirements will shift" | Exactly why it is a living doc. A stale spec still beats no spec. |
| "The requester already knows what they want" | They know the want; the spec exposes the hidden assumptions inside it. |

## Red flags

- Writing code with no written agreement on what "done" means
- Asking "should I just start?" before defining the target
- Shipping behaviour that appears in no criterion
- Making an architecture decision and recording it nowhere
- Skipping the spec because "it's obvious"

## Before you leave this phase

- [ ] Assumptions were stated and confirmed
- [ ] Every acceptance criterion is testable and names its evidence
- [ ] Out-of-scope and boundaries are written down
- [ ] The requester approved the spec
- [ ] The spec is committed and linked to its ticket
