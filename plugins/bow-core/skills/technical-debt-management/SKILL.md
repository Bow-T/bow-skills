---
name: technical-debt-management
description: Triggers when the team is slowing down, when proposing cleanup, when weighing a shortcut against its future cost, or when ranking refactors against features.
---

# Technical Debt Management

Debt is not a moral failing. It is leverage you took out against future velocity. Manage it like a ledger: know what you owe, the interest rate, and whether you can afford to keep carrying it.

## Step 1 — Name the debt before you judge it

Write one sentence with three parts: **shortcut taken**, **what it costs now**, **what triggers the bill**.

```
Auth checks duplicated across 14 widgets (shortcut)
→ every new screen re-implements the same guard, ~30min each (cost now)
→ next RBAC change touches all 14 (the bill comes due on role rework)
```

If you cannot state the trigger, you do not have debt — you have a vague discomfort. Park it.

## Step 2 — Classify by intent x awareness

| | Deliberate | Accidental |
|---|---|---|
| **Prudent** | "Ship now, refactor after launch — we logged it." | "We learned a better pattern; the old code is now debt." |
| **Reckless** | "No time for tests, just merge." | "What's a repository pattern?" |

- **Prudent-deliberate** is healthy leverage. Track it (Step 4).
- **Reckless-deliberate** is the one to stop in code review *now*.
- **Accidental** debt is normal entropy — sweep it during related work.

## Step 3 — Score interest, not size

Big-but-frozen code costs nothing. Small-but-churning code bleeds. Rank each item by **interest rate**, not effort:

```
interest = (change_frequency) x (blast_radius) x (fix_friction)
```

- `change_frequency`: how often does this file/area get touched? (`git log --since=90.days --format= -- path/ | wc -l`)
- `blast_radius`: how many call sites / how easy to break silently?
- `fix_friction`: how much does the debt slow each touch?

A duplicated `Color(0xFF...)` used in one screen: near-zero interest, ignore. A leaky Supabase RLS assumption baked into 9 Edge Functions: high interest, pay soon.

## Step 4 — Track it where it hurts, not in a graveyard backlog

A debt board nobody reads is itself debt. Track debt **at the code**, then surface it.

```dart
// DEBT(interest=high, trigger=multi-currency): hardcoded VND formatting;
// will break when we add USD. Owner: payments. Linked: PROJ-482
String formatPrice(int amountVnd) => '${amountVnd}d';
```

```typescript
// DEBT(interest=med): N+1 query — acceptable under 500 rows,
// revisit if dashboard list grows. Linked: PROJ-310
const rows = await Promise.all(ids.map((id) => fetchRow(id)));
```

Then make it visible:
- Grep `DEBT(` into a generated report in CI; never hand-maintain a parallel list.
- For anything with a real due date, open a tracker ticket and put the ID in the marker.
- See [[jira-issue-management]] for filing and linking debt tickets.

## Step 5 — Decide: pay, defer, or accept

For each high-interest item, pick **one** and write the reason:

- **Pay now** — interest is high AND you are already touching this code. Cheapest moment you will ever get.
- **Defer** — high interest but unrelated to current work. Ticket it with the trigger condition, move on.
- **Accept (forgive the debt)** — low interest or the triggering future never arrived. Delete the marker. Stop worrying about it.

Decision shortcut:

```
Am I editing this file anyway?  ── yes ──► is the fix < 2x my current change? ── yes ──► PAY
        │ no                                          │ no
        ▼                                             ▼
  High interest? ── no ──► ACCEPT                 DEFER (ticket + trigger)
        │ yes
        ▼
      DEFER
```

## Step 6 — Pay it down without stopping the line

Refactor-as-you-go beats refactor-as-a-project. Big-bang rewrites are usually new debt wearing a clean shirt.

- **Strangler approach**: route new work through the good pattern, migrate old call sites only when touched. No flag day.
- **One concern per change**: a refactor commit changes structure OR behavior, never both. Mixing them makes review impossible and hides regressions.
- **Land a characterization test first** if the messy code has no coverage — capture current behavior, *then* refactor against it.

```dart
// Before refactor: lock in what it does today, bugs and all.
test('legacy total keeps the rounding quirk', () {
  expect(legacyTotal([99, 99]), 198); // documents existing behavior
});
```

Keep refactor changes small and split from feature work — follow [[commit-pipeline]] for separating structural vs. behavioral commits.

## Step 7 — Negotiate debt with the people who own the roadmap

When refactors compete with features, do not argue "cleaner code." Argue **delivered velocity**.

- Translate interest into roadmap terms: "This guard duplication adds ~half a day to every new screen; we have 6 screens queued."
- Propose a **debt budget**: a fixed slice (e.g. 15-20% of each cycle) for paydown so it never needs re-litigating per item.
- Tie paydown to upcoming features: "The RBAC epic touches all 14 widgets anyway — consolidate first, then build on the clean base."

## Red flags — debt is past due

- Estimates inflating for work in the same area, sprint over sprint.
- "Don't touch that file, it'll break" — fear-of-code is terminal-stage debt.
- Every bug fix spawns a new bug nearby (high coupling, no tests).
- Onboarding takes weeks because the system can only be understood, not reasoned about.
- A `DEBT(` marker older than a year with no trigger fired — either it's real and ignored, or it should be deleted.

## Anti-patterns

- **Debt nihilism**: "it's all debt anyway." Then nothing is prioritized; the worst items hide among the harmless.
- **Gold-plating**: refactoring frozen, low-interest code because it offends you. That is spending, not earning.
- **The rewrite escape hatch**: declaring bankruptcy and rebuilding from scratch. You lose the embedded bug fixes and usually re-incur the same debt.
- **Silent payoff**: refactoring with no test net and no separate commit, so a regression is indistinguishable from the cleanup.
