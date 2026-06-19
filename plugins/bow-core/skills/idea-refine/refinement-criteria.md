# Evaluation Rubric

Use this in Phase 2 (Narrow down) to pressure-test each direction. Not every dimension matters for every idea — judge which ones carry weight in the specific context.

## The three core dimensions

### 1. Value (does anyone really need this?)

The dimension that gates all the others. If value is unclear, nothing downstream matters.

**Painkiller vs. vitamin:**
- **Painkiller** — solves an acute, recurring problem. People seek it out, switch to it, pay for it. Tell-tale signs: they describe the problem with frustration, they've built hacky workarounds, they ask for a fix.
- **Vitamin** — a nice improvement. People nod, say "neat," and change nothing.

**Ask:**
- Can you name three real people who have this problem today?
- What are they doing instead right now? (The true competitor is always the current workaround — even if that workaround is "nothing.")
- Would they actually switch? What would it take?
- How often do they hit the problem? Daily beats monthly.
- Is this a pull (they're asking) or a push (you've decided they should want it)?

**Warning signs:**
- "Everyone could use this" — if you can't name a specific user, the value is fuzzy.
- "It's like X but better" — marginal improvements rarely move people.
- Real but rare — high pain at low frequency seldom justifies building.

### 2. Feasibility (can you actually build it?)

Technically and practically, not just in theory.

**Technical:**
- Does the core tech exist and work reliably?
- What's the hardest part — a known-hard problem or genuinely novel?
- What does it depend on that you don't control (third-party APIs, data, a payment provider)?
- How much stack does the smallest version need? If the answer is "a lot," that's a signal.

**Practical:**
- What's the minimum effort to get an MVP in front of users?
- Does it need expertise you don't have?
- Any legal, compliance, or regulatory weight? (For data-heavy ideas on Supabase, RLS and data-residency questions land here.)

**Time-to-value:**
- How fast can you put something real in front of a user — days, or months?
- What's on the critical path? What must happen first?

**Warning signs:**
- "We just need to solve [hard research problem] first."
- A chain of dependencies that all have to work at once.
- An "MVP" that still takes months — probably not minimal.

### 3. Differentiation (why this and not what exists?)

Not better — *different*.

**Ask:**
- If a user described this to a friend, would the description be compelling?
- What's the one thing it does that nothing else does? If you can't name it, that's the problem.
- Is the difference durable, or copyable in a week?
- Is it a difference users care about, or one only the builder finds interesting?

**Strength of differentiation, strongest to weakest:**
1. **New capability** — does something previously impossible.
2. **10x on a key axis** — so much better it changes behavior.
3. **New audience** — brings an existing capability to people who were shut out.
4. **New context** — works where existing tools fail.
5. **Better experience** — same capability, far simpler.
6. **Cheaper** — same thing, lower price. Weakest; competed away fastest.

**Warning signs:**
- The differentiation is purely technical, invisible to the user.
- "Faster / cheaper / prettier" with no structural reason behind it.
- The differentiating feature is not the one users care about most.

## Assumption audit

For each direction, sort assumptions into three buckets:

**Must be true (dealbreakers).** If wrong, the idea is dead. Validate before building.
Example: "Inspectors will trust local-first storage with their reports." If not, the offline product has no foundation.

**Should be true (important).** Significantly affects success but survivable — you'd change approach, not abandon.
Example: "Users prefer self-serve onboarding." If wrong, you adjust go-to-market; the core still works.

**Might be true (later).** Secondary features and optimizations. Don't validate until the core is proven.
Example: "Users will want to share results with teammates." A growth feature, not the core value.

## Choosing between directions

Place each on this grid:

|                | High feasibility    | Low feasibility   |
|----------------|---------------------|-------------------|
| **High value** | Do this first       | Worth the risk    |
| **Low value**  | Only if trivial     | Don't             |

Break ties within a quadrant using differentiation.

## Scoping the MVP

Once a direction is chosen:

1. **One job, fully.** Nail exactly one user job rather than three half-jobs.
2. **Riskiest assumption first.** The MVP's whole purpose is to test the thing most likely to be wrong.
3. **Time-box, don't feature-list.** "What can we build and test in two weeks?" beats "what features do we need?"
4. **A "Not Doing" list is mandatory.** Name what you're cutting and why — it blocks scope creep and forces real prioritization.
5. **If it isn't a little embarrassing, you over-built.** The first version should feel incomplete to you. If it doesn't, you waited too long to ship it.
