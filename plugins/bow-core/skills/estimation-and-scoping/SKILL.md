---
name: estimation-and-scoping
description: Trigger when asked how long something will take, sizing a task or epic, or breaking unknowns into estimable pieces with explicit uncertainty.
---

# Estimation and Scoping

Estimates are forecasts, not promises. Your job is to produce a number people can plan around AND surface the unknowns that could blow it up. Never give a single bare figure for non-trivial work.

## Step 1 — Refuse to estimate the fog

If you cannot describe the change in 2-3 concrete sentences, you cannot estimate it. Convert the request into a thin slice first.

Ask until you can answer:
- What is the smallest user-visible outcome that proves this works?
- What touches the data layer (new tables, RLS, migrations) vs. pure UI?
- What is already built that I can reuse vs. genuinely new?
- What system do I NOT control (third-party API, another team, design sign-off)?

Red flag: the ask is a noun ("the dashboard", "search"), not a verb. Push back: "Search across what, returning what, filtered how?"

## Step 2 — Decompose into estimable atoms

Break until each leaf is something you've done before or can spike in under a day. Stop splitting when a piece is < ~1 day; keep splitting anything fuzzy or > ~3 days.

Tag every leaf with a **confidence class**, not just hours:

| Class | Meaning | Multiplier on raw guess |
|-------|---------|-------------------------|
| KNOWN | Done it, clear path | x1.0 |
| FAMILIAR | New combo of known parts | x1.5 |
| UNKNOWN | Real research/design needed | x2-3 + spike first |

UNKNOWN items don't get an estimate — they get a **timeboxed spike** (see Step 4).

Example breakdown for "Add saved filters to the project list":

```
KNOWN     migration: saved_filters table + RLS policy        0.5d
KNOWN     TS types regen + Supabase query layer              0.5d
FAMILIAR  Flutter: filter chip UI + persistence wiring       1.5d
FAMILIAR  apply saved filter -> existing list query          1.0d
UNKNOWN   share a filter via deep link  -> SPIKE             0.5d box
```

## Step 3 — Estimate ranges, not points

For each leaf give three numbers and combine them. Use a PERT-style weighted mean so the likely case dominates but the tail is respected:

```
expected = (optimistic + 4*likely + pessimistic) / 6
spread   = (pessimistic - optimistic) / 6   // ~1 std dev
```

```typescript
type Leaf = { name: string; o: number; m: number; p: number };

function roll(leaves: Leaf[]) {
  const expected = leaves.reduce((s, l) => s + (l.o + 4 * l.m + l.p) / 6, 0);
  // variances add; std devs do not -> combine in quadrature
  const variance = leaves.reduce((s, l) => s + ((l.p - l.o) / 6) ** 2, 0);
  const sd = Math.sqrt(variance);
  return { expected, low: expected - sd, high: expected + sd };
}
```

Report it as a range with a confidence: "**~6 days, likely 5-8**" beats "6 days". The spread shrinks as you do spikes — that is the point.

## Step 4 — Timebox the unknowns

A spike answers ONE question and produces a decision, not production code.

- State the question: "Can we deep-link a filter without a server round-trip?"
- Set a hard box (2h, half a day). When it rings, stop.
- Output: a one-paragraph finding + a revised estimate for the dependent leaves.

If the spike doesn't resolve the question, that IS the finding — escalate it as a risk, don't silently absorb it into padding.

## Step 5 — Add the overhead nobody counts

Raw coding time is not delivery time. Apply a multiplier for the work around the work:

- Code review + revision rounds
- Tests (unit + the integration test you'll be told to add anyway)
- Migrations applied to staging, RLS verified, types regenerated
- Edge cases, error states, empty states, loading states
- PR + CI flake + merge

A reasonable default: **delivery = sum(expected) x 1.3-1.6**. State the multiplier explicitly so it's negotiable, not hidden.

## Step 6 — Communicate the estimate

Deliver three things together:
1. **Range + confidence**: "5-8 dev-days, medium confidence."
2. **Drivers**: the 1-2 leaves that dominate the spread.
3. **Assumptions & cut lines**: what you assumed, and what you'd drop to hit a deadline.

```
Estimate: 5-8 dev-days (medium confidence)
Biggest unknown: deep-link sharing (spike pending) — could add 2d
Assumes: design exists; reuses current list query; no new auth scope
If pressed: ship without share-via-link, lands at ~4d high confidence
```

## Re-estimate on a trigger, not a schedule

Re-estimate when: a spike resolves, scope changes, or an assumption breaks. When you do, say what moved and why. An estimate that never changes was never honest.

## Red flags

- A single number with no range — you're guessing and hiding it.
- "It's basically done" for anything with a TODO, no tests, or unverified RLS.
- Estimating around a deadline (working backward to the number someone wants).
- No line item for review, tests, or migrations.
- Padding instead of spiking — inflated numbers hide ignorance you could have removed in two hours.
- Estimating someone else's blocker (a third-party API, a pending design) as if it's in your control. Surface it as a dependency.
- Reusing a past estimate for a "similar" task without checking what's actually different.

## Cross-links

- Slicing work and writing the ticket: [[task-breakdown]]
- Sizing data-layer leaves (tables, RLS, migrations): [[octopus-model]]
- Spinning up reproducible spikes: [[spike-and-prototype]]
- Committing the result follows [[commit-pipeline]] (Conventional Commits + gitmoji).
