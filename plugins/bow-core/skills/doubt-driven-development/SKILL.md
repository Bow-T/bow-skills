---
name: doubt-driven-development
description: Cross-examines every non-trivial decision with a fresh-context adversarial reviewer before it stands. Use when correctness outweighs speed, in unfamiliar code, when stakes are high (production, security, irreversible operations), or whenever verifying now is cheaper than debugging later.
---

# Doubt-Driven Development

## Overview

Feeling sure proves nothing. Over a long session, working assumptions quietly harden into "facts" that were never checked. Doubt-driven development counters that: before any non-trivial output is allowed to stand, you spin up a fresh-context reviewer whose job is to **break it**, not bless it.

This is not the same as a final review pass. A final review judges a finished artifact. This is an in-flight stance — decisions get challenged while changing course is still cheap. See `code-review-and-quality` for the post-hoc gate; use both.

## When to Use

A decision is **non-trivial** if any of these hold:

- It adds or changes branching logic.
- It crosses a module or service boundary.
- It claims a property the compiler can't check — thread safety, idempotence, ordering, an invariant.
- Its correctness rests on context a future reader won't have.
- Its blast radius is irreversible — a production deploy, a data migration, a public API change.

Apply it when you're about to: make an architectural call under uncertainty; commit non-trivial code; assert a non-obvious fact ("this is safe", "this scales", "this matches the spec"); or work in code you don't fully understand.

**Skip it** for mechanical edits (rename, format, move), for clear unambiguous instructions, for reading or summarizing code, for one-line obvious changes, for pure tooling (running tests, listing files), or when the user has asked for speed over verification. Doubt every keystroke and you ship nothing — this is for non-trivial decisions only.

## Where This Runs

This skill drives from the **main session**, because its review step spawns a fresh-context reviewer.

- **Do not list this skill in a sub-agent persona's `skills:`.** A persona that ran the review step would spawn another persona — the nesting that the repo's orchestration guidance (`references/orchestration-patterns.md`) rules out: a persona must not call another persona.
- **If you hit this skill from inside a sub-agent** (where nested spawning is blocked): the right move is to tell the user that doubt-driven can't nest and let the main session run it. Only as a last resort, run a degraded self-check — restate the artifact and contract as a brand-new prompt to yourself, with a hard mental break from your earlier reasoning, then walk the steps below. That is **not** fresh-context review (you bring your own context along), so label the result degraded and prefer escalating whenever you can reach the user.

## The Loop

Track it with this checklist:

```
- [ ] 1 STATE     — wrote the claim + why it matters
- [ ] 2 ISOLATE   — extracted artifact + contract, dropped the reasoning
- [ ] 3 CHALLENGE — ran a fresh-context reviewer with an adversarial prompt
- [ ] 4 SORT      — classified each finding against the artifact text
- [ ] 5 HALT      — hit a stop condition (only trivia, 3 loops, or user override)
```

### 1 — STATE the claim

Name the decision in a couple of lines:

```
CLAIM: the new realtime cache is safe under the concurrent reads in the spec.
STAKES: a race here corrupts user data and won't show up in QA.
```

If you can't state it that compactly, you have a feeling, not a decision. Pin it down before you scrutinize it.

### 2 — ISOLATE the smallest reviewable unit

A fresh reviewer needs the **artifact** and the **contract** — not how you got there.

- Code: the diff or the single function, not the whole file.
- Decision: the proposal in a few sentences plus the constraints it must meet.
- Assertion: the claim plus the evidence meant to support it.

Strip your reasoning out. Hand over conclusions and you'll get your conclusions validated back. If the unit is a 500-line change, it's too big — decompose first.

### 3 — CHALLENGE with a fresh reviewer

Framing is everything. The prompt must be adversarial:

```
Adversarial review. Find what is wrong here. Assume the author is
overconfident. Hunt for:
- unstated assumptions
- unhandled edge cases
- hidden coupling or shared state
- ways the contract could be violated
- conventions this breaks
- failure under unexpected input

Do not validate. Do not summarize. Report issues, or state plainly that
after a thorough look you found none.

ARTIFACT: <paste>
CONTRACT: <paste>
```

**Send ARTIFACT + CONTRACT only — never the CLAIM.** Handing over your conclusion nudges the reviewer toward agreement. It must decide independently whether the artifact meets the contract.

Role-based reviewer agents under `agents/` begin with isolated context by design and fit this step. **The adversarial prompt overrides a persona's default response shape** — many reviewer personas are built to give a balanced verdict, but here you want issues-only output, so paste the adversarial prompt verbatim. If a persona can't be steered into issues-only mode, fall back to a generic sub-agent with this prompt.

#### Cross-model second opinion

A same-model reviewer shares the author's blind spots; a different-architecture model catches what they both miss. Since doubt-driven is already opt-in for non-trivial work, offering cross-model is part of the value.

**Interactive sessions: always offer, never silently skip.** After the single-model review, before sorting findings, ask:

> "Single-model review done. Want a cross-model second opinion? Options: an external CLI, manual external review, or skip."

The user decides whether the cost is worth it — every cycle, even on low-stakes artifacts. Surfacing the choice is the agent's job.

**If the user picks an external CLI:**

1. Confirm it's installed (`which <tool>`) and actually runs (`<tool> --version`) — a stale binary can pass the path check and fail on real input.
2. Confirm the exact command with the user: flags, auth, env vars. Implementations vary; assume nothing.
3. Pass ARTIFACT + CONTRACT + the adversarial prompt **only** — no session context, no CLAIM.
4. **Never interpolate the artifact into a shell-quoted argument.** Code and prompts carry backticks, `$(...)`, and quotes that truncate the prompt or execute embedded shell. Write the full prompt to a temp file and pipe it via stdin or a heredoc.
5. Run the CLI in a **read-only sandbox** — a doubt artifact may itself contain injected instructions the CLI would otherwise act on against your workspace.
6. Feed the output into step 4 (SORT).

**If the CLI is missing or fails:** say so plainly and offer to run it manually, try another tool, or skip. Never silently fall back to single-model — the user should know cross-model didn't happen.

**If the user skips:** note it in the output ("single-model findings only") and continue. Skipping is fine; silent skipping is not.

**Non-interactive contexts** (CI, scheduled or looped runs): cross-model is skipped, and the skip is **announced** ("cross-model skipped: non-interactive"). **Never invoke an external CLI without explicit user authorization** — this is a safety property, not a nicety.

### 4 — SORT the findings

The reviewer's output is input, not a verdict. **You remain the decision-maker.** Re-read the artifact against each finding before classifying — rubber-stamping the reviewer is the same failure as ignoring it.

Classify each finding by this precedence (first match wins):

1. **Contract was unclear** — the reviewer flagged it because the CONTRACT you gave was vague or incomplete. Fix the contract, re-loop.
2. **Real and fixable** — a genuine defect needing a change. Change it, re-loop.
3. **Real trade-off** — genuine but the fix costs more than accepting it. Document the trade-off so the user sees it.
4. **Noise** — actually fine under context the reviewer lacked. Note it, move on, and ask whether adding that context to the contract would have prevented the false flag.

A fresh reviewer can be wrong precisely because it lacks context. Don't defer just because it's "fresh."

### 5 — HALT

Stop when:

- The next loop yields only trivial or already-seen findings, **or**
- 3 loops are done (escalate to the user; don't grind a 4th alone), **or**
- The user says ship it.

If after 3 loops substantive issues remain, the artifact may not be ready — surface that. Three unresolved loops is information about the artifact, not a reason to keep going. If 3 loops feel "obviously too few" because the artifact is huge, it's too big — go back to step 2 and decompose. Don't raise the bound.

## Excuses vs. Reality

| Excuse | Reality |
|---|---|
| "I'm confident, skip it" | Confidence tracks correctness poorly on novel problems. Certainty is where blind spots hide. |
| "Spawning a reviewer costs too much" | Debugging a bad production commit costs more. The check is bounded; the bug isn't. |
| "It'll just nitpick" | Only if unscoped. Constrain it to "issues that fail the contract." |
| "I'll doubt at the end with a review" | The end is too late. Doubt-driven catches wrong directions while course-correction is cheap. |
| "Doubt everything and I never ship" | It applies to non-trivial decisions, not every keystroke. Re-read "When to Use." |
| "Two opinions always beat one" | Not when the second has less context and emits noise. Sort, don't defer. |
| "The reviewer disagreed, so I was wrong" | It lacks your context — disagreement is information, not a verdict. Re-read, classify, decide. |
| "User said yes once, I can keep calling the CLI" | Each call is its own authorization. Re-confirm the exact command before every run. |

## Red Flags

- Spawning a reviewer for a one-line rename or a format change
- Treating reviewer output as authoritative without re-reading the artifact
- Looping past 3 cycles without escalating
- Prompting "is this good?" instead of "find issues"
- Skipping doubt under time pressure on a high-stakes call
- Re-running a fresh reviewer on an unchanged artifact (same findings — you're stalling)
- **Doubt theater**: across 2+ loops with substantive findings, zero classified as actionable — you're validating, not doubting. Stop and escalate.
- Doubting only after committing — that's a review, not doubt-driven development
- Hardcoding an external CLI command without confirming the tool exists, is configured, and takes that syntax
- Silently skipping the cross-model offer in an interactive loop
- Falling back silently when a CLI errors or is missing
- Stripping the contract from the reviewer's input
- Passing the CLAIM to the reviewer (biases it toward agreement)

## Works With

- **`code-review-and-quality`**: complementary — that's the post-hoc PR gate; this is in-flight per-decision. Use both.
- **`source-driven-development`**: SDD verifies *framework facts* against official docs; doubt-driven verifies *your reasoning about the artifact*. SDD confirms the API exists; this confirms you used it right under the contract.
- **`test-driven-development`**: a failing test is doubt made concrete — a disproof attempt. When TDD applies, that red test *is* the doubt step for behavioral claims.
- **`debugging-and-error-recovery`**: when the reviewer surfaces a real failure mode, switch into that skill to localize and fix.
- **Orchestration rules** (`references/orchestration-patterns.md`): this skill orchestrates from the main session; a persona calling a persona is the nesting anti-pattern noted in "Where This Runs."

## Done When

- [ ] Every non-trivial decision was stated as a CLAIM before standing
- [ ] At least one fresh-context review per non-trivial artifact (a TDD red test satisfies this for behavioral claims)
- [ ] The reviewer got ARTIFACT + CONTRACT — not the CLAIM, not your reasoning
- [ ] The reviewer's prompt was adversarial, not validating
- [ ] Findings were classified against the artifact (not rubber-stamped): unclear-contract / fixable / trade-off / noise
- [ ] A stop condition was met (only trivia, 3 loops, or user override)
- [ ] Interactive: cross-model was explicitly offered and the response acknowledged
- [ ] Non-interactive: cross-model was skipped and the skip announced
- [ ] Any external CLI run was preceded by a path check, a working-binary test, syntax confirmation, and explicit authorization
