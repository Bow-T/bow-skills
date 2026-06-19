---
name: code-review-and-quality
description: Reviews a change across correctness, readability, architecture, security, and performance before it merges. Use before merging any change, after finishing a feature, when evaluating code produced by yourself, another agent, or a human, and after any bug fix.
---

# Code Review and Quality

## Overview

Every change is reviewed before it merges — no exceptions — and the review looks at five things, not just whether tests pass: correctness, readability, architecture, security, and performance.

**The bar for approval:** approve once the change clearly improves the health of the codebase, even if it isn't flawless. Perfect code is a myth; the aim is steady improvement. Don't block a change just because it differs from how you'd have written it. If it makes the codebase better and respects the project's conventions, approve it.

## When to Use

- Before merging any change
- After a feature is implemented
- When code from another agent or model needs evaluating
- While refactoring
- After a bug fix — review the fix *and* its regression test

## The Five Axes

### 1. Correctness

Does it do what it claims?

- Matches the spec or task?
- Edge cases handled — null, empty, boundaries?
- Failure paths handled, not just the happy path?
- Tests pass, and do they test the right behavior?
- Any off-by-one, race condition, or inconsistent state?

### 2. Readability and simplicity

Can another engineer follow it without the author narrating?

- Names are descriptive and match conventions — no bare `temp`, `data`, `result`.
- Control flow is flat — no nested ternaries or deep callback chains.
- Related code is grouped; boundaries are clear.
- No "clever" trick that a plain version would beat.
- **Could it be shorter?** A thousand lines where a hundred suffice is a failure.
- **Is each abstraction paying its way?** Don't generalize before a third caller exists — see `code-simplification`.
- Comments explain non-obvious intent, and don't restate obvious code.
- No dead leftovers: no-op vars, compat shims, `// removed` comments.

### 3. Architecture

Does it fit the system?

- Follows an existing pattern, or introduces a new one — and if new, is it justified?
- Keeps module boundaries clean.
- No duplication that should be shared.
- Dependencies point the right way — no cycles.
- Abstraction level is right: not over-built, not over-coupled.

### 4. Security

For the deep checklist see `references/security-checklist.md`; for broader guidance see `security-and-hardening`. Database-layer review (RLS, policies) goes through `supabase-security-review`. Ask:

- User input validated and sanitized at the edge?
- Secrets kept out of code, logs, and version control?
- Auth and authorization enforced where required?
- Queries parameterized — no string-built SQL?
- Output encoded against XSS?
- Dependencies trusted and free of known CVEs?
- External data (APIs, user content, config) treated as untrusted and validated at boundaries before it drives logic or rendering?

### 5. Performance

For profiling depth see `references/performance-checklist.md` and `performance-optimization`. Ask:

- Any N+1 query pattern?
- Any unbounded loop or unconstrained fetch?
- Any sync work that should be async?
- Any needless widget rebuilds / re-renders?
- Any list endpoint missing pagination?
- Any large allocation on a hot path?

## Keep Changes Small

Small, focused changes review faster, merge sooner, and deploy more safely.

```
~100 lines   good — reviewable in one sitting
~300 lines   acceptable for a single logical change
~1000 lines  too big — split it
```

A "single change" addresses one thing, carries its tests, and leaves the system working after it lands — one slice of a feature, not the whole feature.

**Splitting when it's too big:**

| Strategy | How | Use when |
|---|---|---|
| Stack | land a small change, build the next on it | sequential dependencies |
| By file group | separate changes for groups needing different reviewers | cross-cutting work |
| Horizontal | shared code/stubs first, consumers after | layered architecture |
| Vertical | smaller full-stack slices | feature work |

Large changes are acceptable for whole-file deletions and mechanical refactors where the reviewer verifies intent, not every line. **Keep refactoring separate from new behavior** — that's two changes; submit them apart. Trivial cleanups (a rename) can ride along at the reviewer's discretion.

## Change Descriptions

A change's description must stand on its own in history.

- **First line:** short, imperative, self-contained — "Remove the legacy booking RPC", not "removing it". Someone searching history should grasp it without the diff.
- **Body:** what's changing and why — context, decisions, and reasoning that the code doesn't show. Link the ticket, benchmark, or design note. Name the approach's weaknesses where they exist.
- **Avoid:** "fix bug", "fix build", "wip", "phase 1", "move code".

Defer commit message format, Conventional Commits, the Jira footer, and branching to `commit-pipeline`.

## How to Review

1. **Get the intent first.** What is this change for? What spec does it serve? What behavior should change?
2. **Read the tests before the code.** Do they exist? Do they test behavior, not implementation? Edge cases covered? Descriptive names? Would they catch a regression?
3. **Walk the implementation** through all five axes, file by file.
4. **Label every comment with severity** so the author knows what's required versus optional:

   | Prefix | Meaning | Author does |
   |---|---|---|
   | *(none)* | required | must fix before merge |
   | **Blocker:** | stops the merge | security hole, data loss, broken behavior |
   | **Nit:** | minor, optional | may ignore — style |
   | **Consider:** | suggestion | weigh it, not required |
   | **FYI:** | informational | nothing — context only |

   Without labels, authors treat every comment as mandatory and burn time on optional ones.
5. **Check the verification story.** What tests ran? Did the build pass? Manual check done? Screenshots for UI? Before/after where relevant?

## Multi-Model Review

Different models miss different things, so route a review through a second one:

```
Model A writes → Model B reviews for correctness + architecture → Model A
addresses feedback → human makes the final call
```

A starter prompt for a review agent:

```
Review this change for correctness, security, and our conventions.
Spec: <X>. Expected behavior: <Y>. Label findings Blocker / Required / Suggestion.
```

## Dead Code Hygiene

After a refactor or rewrite, hunt for orphans:

1. Find code now unreachable or unused.
2. List it.
3. **Ask before deleting.**

Don't leave dead code around — it misleads future readers and agents. But don't silently delete what you're unsure about.

```
DEAD CODE FOUND:
- formatLegacyDate() in lib/utils/date.dart — superseded by formatDate()
- OldBookingCard in lib/widgets/ — superseded by BookingCard
→ safe to remove these?
```

## Review Speed

A slow review blocks everyone downstream; the context-switch to review costs less than the waiting it imposes.

- Respond within one business day — that's the ceiling, not the goal.
- Reply soon after a request arrives unless you're deep in focused work; a typical change should clear several rounds in a day.
- Favor fast individual replies over a quick final approval — fast feedback eases frustration even across rounds.
- For oversized changes, ask the author to split rather than slogging through one giant diff.

## Settling Disagreements

1. Facts and data beat opinions and preference.
2. The style guide is the authority on style.
3. Design is judged on engineering principle, not taste.
4. Consistency with the codebase is fine as long as it doesn't hurt overall health.

**Don't accept "I'll clean it up later."** Deferred cleanup rarely happens. Require it before merge unless it's a genuine emergency; if surrounding issues can't be fixed in this change, require a filed, self-assigned ticket.

## Honest Review

Reviewing your own, an agent's, or a human's code:

- **No rubber-stamping.** "LGTM" with no evidence of review helps nobody.
- **Don't soften real problems.** Calling a production bug "a minor concern" is dishonest.
- **Quantify when you can.** "This N+1 adds ~50ms per list item" beats "might be slow".
- **Push back on flawed approaches.** Sycophancy is a review failure mode — say it plainly and propose an alternative.
- **Take an override gracefully.** When the author has full context and disagrees, defer. Critique the code, not the person.

## Dependency Discipline

Reviewing a change includes reviewing any dependency it adds:

1. Does the current stack already solve this? (Often, yes.)
2. How big is it? (Check the impact.)
3. Is it actively maintained?
4. Any known vulnerabilities?
5. Is the license compatible?

Prefer the standard library and existing utilities over a new package. Every dependency is a liability.

## Review Checklist

```markdown
## Review: <title>

### Context
- [ ] I understand what this does and why

### Correctness
- [ ] Matches the spec
- [ ] Edge cases handled
- [ ] Failure paths handled
- [ ] Tests cover it adequately

### Readability
- [ ] Names clear and consistent
- [ ] Flow is straightforward
- [ ] No needless complexity

### Architecture
- [ ] Follows existing patterns
- [ ] No needless coupling
- [ ] Right abstraction level

### Security
- [ ] No secrets in code
- [ ] Input validated at boundaries
- [ ] No injection
- [ ] Auth enforced
- [ ] External data treated as untrusted

### Performance
- [ ] No N+1
- [ ] No unbounded operations
- [ ] Lists paginate

### Verification
- [ ] Tests pass
- [ ] Build succeeds
- [ ] Manual check done (if applicable)

### Verdict
- [ ] Approve — ready to merge
- [ ] Request changes — must be addressed
```

## Excuses vs. Reality

| Excuse | Reality |
|---|---|
| "It works, good enough" | Working but unreadable, insecure, or ill-architected code compounds into debt. |
| "I wrote it, so it's correct" | Authors are blind to their own assumptions. Every change benefits from another set of eyes. |
| "We'll clean it later" | Later rarely comes. The review is the gate — require cleanup before merge. |
| "AI code is probably fine" | AI code needs more scrutiny, not less — confident and plausible even when wrong. |
| "Tests pass, so it's good" | Necessary, not sufficient. Tests don't catch architecture, security, or readability problems. |

## Red Flags

- Merging with no review
- "Review" that only checks the test result
- "LGTM" with no evidence of an actual review
- Security-sensitive changes without a security-focused pass
- PRs "too big to review properly" — split them
- A bug fix with no regression test
- Comments without severity labels
- Accepting "I'll fix it later"

## Done When

- [ ] All blockers resolved
- [ ] All required issues resolved or explicitly deferred with justification
- [ ] Tests pass
- [ ] Build succeeds
- [ ] The verification story is documented
