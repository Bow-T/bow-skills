---
name: documentation-and-adrs
description: Captures the reasoning behind technical work so future readers can rebuild context. Trigger when making an architectural decision, weighing competing approaches, changing a public API, shipping user-facing behavior, or recording context the next engineer or agent will need.
---

# Documentation and ADRs

## Overview

The documentation worth writing captures *why*, not *what*. The code already shows what got built. What it cannot show is the constraint you were under, the option you rejected, or the trade-off you accepted — and that is exactly the context the next person (or agent) needs to avoid relitigating a settled decision or breaking an invariant they never knew existed. Document decisions and intent; let the code speak for the mechanics.

## When to Use

- Making a significant architectural call
- Picking one approach over plausible alternatives
- Adding or changing a public API
- Shipping a change to user-facing behavior
- Bringing a new teammate or agent up to speed
- Catching yourself explaining the same thing for the third time

**Skip it when:** the code is self-evident, a comment would only echo the line below it, or it's a throwaway prototype.

## Architecture Decision Records

An ADR is a short, durable record of one significant decision and the reasoning around it. Per minute spent, it is the highest-value documentation you can produce.

### Worth an ADR

- Adopting a framework, library, or major dependency
- Shaping a data model or schema
- Choosing an auth strategy
- Picking an API style (REST vs. GraphQL vs. RPC)
- Selecting build tooling, hosting, or infrastructure
- Anything expensive to undo later

### Template

Keep ADRs in `docs/decisions/`, numbered in sequence:

```markdown
# ADR-007: Postgres via Supabase as the primary datastore

## Status
Accepted   (later: Superseded by ADR-NN / Deprecated)

## Date
2026-02-10

## Context
The app needs a primary store. Requirements:
- Relational shape (users, tasks, teams with real relationships)
- ACID transactions for task state transitions
- Full-text search over task content
- Managed hosting (small team, little ops capacity)
- Row-level authorization close to the data

## Decision
Use Postgres on Supabase, with row-level security policies enforcing access.

## Alternatives considered
- Document store: flexible, but our data is relational; we'd hand-roll joins
  or duplicate data. Rejected.
- Embedded SQL file DB: zero-config and fast for reads, but weak concurrent
  writes and no managed prod hosting. Rejected for a multi-user service.
- Another managed SQL: mature, but weaker JSON and search ergonomics for us.
  Rejected on fit.

## Consequences
- RLS lets us push authorization into the database instead of app code.
- Built-in full-text search avoids standing up a separate search service.
- The team needs working Postgres + RLS knowledge (low risk, standard skill).
- We're coupled to Supabase platform conventions; revisit if that constrains us.
```

### Lifecycle

```
Proposed -> Accepted -> (Superseded | Deprecated)
```

Never delete an old ADR — it is the historical record. When a decision changes, write a new ADR that references and supersedes the old one.

## Inline Comments

Comment intent, not mechanics:

```dart
// Weak: restates the statement
// add one to the retry count
retries += 1;

// Strong: explains the non-obvious choice
// Sliding window resets at the window boundary rather than on a fixed
// timer, so a burst straddling two windows can't sneak past the limit.
if (now - windowStart > windowSizeMs) {
  count = 0;
  windowStart = now;
}
```

Do not comment self-explanatory code, do not leave a TODO for something you could just do now, and do not keep commented-out code — version control already remembers it.

Do flag genuine traps:

```dart
/// IMPORTANT: call before the first frame. Calling it after the theme
/// provider mounts causes a flash of unstyled content during startup.
/// Rationale in ADR-009.
void initializeTheme(Theme theme) { /* ... */ }
```

## API Documentation

For anything other code calls, document the contract.

Inline doc comments (preferred for typed code):

```dart
/// Creates a task.
///
/// [input] requires a non-empty `title` (<= 200 chars); `description`
/// is optional. Returns the stored task with its server-assigned id and
/// timestamps. Throws [ValidationError] on a bad title and
/// [AuthError] when the caller is unauthenticated.
Future<Task> createTask(CreateTaskInput input) { /* ... */ }
```

For HTTP surfaces, keep a schema spec (OpenAPI) describing each request body, response, and error status so consumers and tools can rely on it.

## README

Every project's README should cover, briefly: a one-paragraph statement of what it is; a quick start (clone, install, copy env, run); a command table (dev, test, build, lint); an architecture sketch that links out to ADRs for the detail; and how to contribute. Enough for a newcomer to run it and find the deeper docs — no more.

## Changelog

For shipped work, keep a human-readable changelog grouped by Added / Changed / Fixed, each entry tied to its tracking reference:

```markdown
## [1.4.0] - 2026-03-01
### Added
- Task sharing across team members (PROJ-321)
### Fixed
- Duplicate task on rapid create taps (PROJ-330)
### Changed
- Task list page size raised to 50 (PROJ-334)
```

## Docs Aimed at Agents

Agents read docs too, so a few artifacts pay off directly: rules files (e.g. CLAUDE.md) that encode project conventions an agent should follow; current spec files so the agent builds the intended thing; ADRs so it understands prior decisions instead of re-making them; and inline gotcha notes that keep it out of known traps.

## Common Rationalizations

| Excuse | Reality |
|---|---|
| "The code is self-documenting" | Code shows what, never why, the rejected options, or the constraints. |
| "We'll document once the API settles" | Documenting it is what settles it — the doc is the design's first test. |
| "Nobody reads docs" | Agents do, the next engineer does, and so does you-in-three-months. |
| "ADRs are overhead" | A ten-minute ADR prevents the same two-hour debate six months on. |
| "Comments rot" | Why-comments are stable; what-comments rot — which is exactly why you only write the former. |

## Red Flags

- Architectural choices with no written rationale
- Public APIs with no docs or types
- A README that can't get someone running the project
- Commented-out code left in place of deletion
- TODOs aging for weeks
- A project with real architecture and zero ADRs
- Docs that restate the code instead of its intent

## Verification

- [ ] An ADR exists for every significant architectural decision
- [ ] README covers quick start, commands, and an architecture overview
- [ ] Public functions document parameters, returns, and errors
- [ ] Real gotchas are flagged inline where they bite
- [ ] No commented-out code remains
- [ ] Rules files (CLAUDE.md, etc.) are current

When and how to commit these docs follows the `commit-pipeline` skill.
