---
name: pull-request-authoring
description: Trigger when opening a pull request — scoping it reviewably, writing the description and test plan, sequencing stacked PRs, and pre-empting reviewer questions.
---

# Pull Request Authoring

A PR is a request for someone's time and trust. Optimize for the reviewer's
working memory, not your convenience. The goal: a reviewer approves quickly
*and correctly*.

## 1. Scope before you write a line of description

Decide what one PR is for. A reviewable PR does exactly one thing.

- **Target diff size:** aim under ~400 changed lines of real logic. Generated
  files, lockfiles, and snapshots don't count against the budget but should be
  in separate commits so they fold away.
- **Split signals — if you hit any, split the PR:**
  - The title needs the word "and".
  - You're touching a Supabase migration *and* the Flutter UI that consumes it.
  - A refactor (rename, move, extract) rides alongside behavior change.
  - The reviewer would have to context-switch between unrelated subsystems.
- **Separate mechanical from semantic.** Pure renames or formatting go in their
  own PR (or at least their own commit) so the behavioral diff stays readable.

Decision: *Can a reviewer hold the whole change in their head at once?* If no,
split or stack.

## 2. Sequence stacked PRs

When a change is genuinely large, stack small PRs instead of one mega-PR.

- Each PR in the stack must **compile, pass tests, and be revertible alone.**
- Order bottom-up by dependency: data layer → service → UI.

```
PR 1  feat(db): add `invoices` table + RLS policy        (Supabase migration)
PR 2  feat(api): InvoiceRepository read/write methods     (TS edge function)
PR 3  feat(ui): invoice list screen                        (Flutter)
```

- State the stack explicitly in each description: "Stacked on #PR1. Review that
  first." Link parent and children.
- Keep the stack shallow (3-4 deep max). Deeper stacks rot during review.
- Rebase the whole stack when the base merges; don't let children drift.

Red flag: a child PR's diff shows the parent's changes too → your base branch is
wrong. Repoint it at the parent branch, not the trunk.

## 3. Write the description (the part reviewers actually read)

Lead with *why*, then *what*, then *how to check*. Structure:

```markdown
## Why
Invoice totals were recomputed on every render, causing jank on large lists.
Closes #482.

## What changed
- Memoize total calc in `InvoiceController`
- Move currency formatting into `Money.format()` (was duplicated 3x)

## How to test
1. Open Invoices with 200+ rows
2. Scroll — frame timeline stays under 16ms (was spiking to 40ms+)

## Risk / blast radius
Touches the invoice render path only. No schema or API change.
```

Rules:
- **Why first.** A reviewer who understands the motivation reviews the *intent*,
  not just the syntax.
- **No restating the diff.** "Changed line 40" is noise; the diff already shows
  it. Describe what the diff doesn't: tradeoffs, alternatives rejected, why this
  approach.
- **Link the issue/ticket** and any design doc. Use `Closes #N` so merge
  auto-resolves it.
- Keep commits clean and conventional per [[commit-pipeline]]; the PR title
  follows the same convention as the squash commit.

## 4. Write a test plan that proves it

A test plan is evidence, not a promise. Reviewers should be able to reproduce.

- **Automated:** name the tests added and what they assert.
  ```
  test/invoice_controller_test.dart — total recomputed only on data change
  ```
- **Manual:** numbered, copy-pasteable steps with the *observed* result, not
  "should work". Include the before state so the delta is visible.
- **Evidence:** attach screenshots/screen recording for UI; paste the relevant
  query result or log line for backend. For Supabase RLS changes, show the
  policy denying an unauthorized role:
  ```sql
  -- as anon: returns 0 rows (was leaking all rows before)
  select * from invoices;
  ```
- State what you did **not** test and why.

Red flag: "Tested locally" with no steps. That's not a test plan.

## 5. Pre-empt reviewer questions

Answer the questions before they're asked — in the description or as inline
self-review comments on your own diff.

- **Inline-annotate the non-obvious.** Drop a PR comment on the tricky line:
  "Using a left join here because some invoices have no payments yet."
- **Flag the deliberate.** "Left the TODO — out of scope, tracked in #490."
- **Surface what you're unsure about.** "Not sure this index helps; open to
  dropping it." Honesty invites better review.
- **Pre-answer the usual suspects:**
  - Why this dependency / why a new one at all?
  - Backward compatibility — any breaking API or schema change?
  - Migration safety — is the Supabase migration reversible and zero-downtime?
  - Performance — N+1 queries, unindexed filters, rebuilds in hot widgets?
  - Error/edge handling — null, empty list, network failure, auth expiry?

## 6. Self-review pass (do this before requesting review)

Read your own diff top to bottom as if it were someone else's.

- [ ] No debug prints, commented-out code, or stray `print`/`console.log`.
- [ ] No secrets, keys, or `.env` values committed.
- [ ] Generated TS types / lockfiles match the source change and are isolated.
- [ ] The diff contains *only* files relevant to this PR's one job.
- [ ] CI is green locally before pushing — don't outsource your test run.
- [ ] Title and description match what the diff actually does now (not what you
      planned three commits ago).

If your self-review finds something, fix it before tagging a human. Every issue
you catch is reviewer time saved.

## 7. Choosing reviewers and merge strategy

- **Tag the code owner** of the most-changed area, plus one fresh set of eyes
  for risky logic. Don't tag the whole team — diffuse ownership means no review.
- Mark **draft** while CI runs or the stack base is unmerged.
- Prefer **squash merge** for feature branches so trunk history stays one
  conventional commit per PR (see [[commit-pipeline]]). Keep merge commits only
  for long-lived integration branches.
- Respond to every comment — resolve, push a fix, or explain why not. Don't
  silently force-push over a reviewer's open thread; reply first.

## Anti-patterns

- "Misc fixes" PRs — unscoped grab bags no one can review.
- Description that says "see commits" — the PR *is* the summary.
- Bundling a refactor with a behavior change to "save a PR."
- Force-pushing mid-review so the reviewer loses their place — push fixups
  instead until approval.
- Requesting review on red CI.
