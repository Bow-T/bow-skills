---
name: interview-me
description: Pulls out the real goal behind a request rather than the request itself, by running a one-question-at-a-time interview until you can predict the user's answers. Use when a request lacks who/why/what-success ("build X" with no audience or motivation), when the user invokes it directly ("interview me", "grill me", "stress-test this", "are we sure?"), or when you notice yourself quietly inventing requirements before a plan, spec, or code exists.
---

# Interview Me

## Why this exists

The thing a person requests is rarely the thing they need. "Give me a report" is shorthand for a question they want answered. "Make it faster" has no target number attached. People reach for the familiar shape of an ask because that is what asks look like — not because that shape solves their problem.

The gap between the stated ask and the real goal is cheapest to close *before* anything is built. After code exists, the user starts bending the wrong solution into a tolerable one, and the mismatch quietly becomes permanent. This skill is the upfront work that prevents that: a short, deliberate interview that ends when you can anticipate what the user will say next.

It sits earlier than the other Define-phase skills. `idea-refine` takes a goal you already hold and explores variations. `spec-driven-development` writes a known goal down. `doubt-driven-development` attacks a plan you have already drafted. Interview-me runs before any of them, surfacing the goal in the first place.

## Trigger conditions

Run this when any of these hold:

- The request is missing one or more of: **who** it serves, **why** now, what **done** looks like, or which **constraint** dominates.
- The ask is generic ("build X", "improve performance") and you cannot expand the generic phrasing without guessing.
- You are about to act on an assumption you have not said out loud.
- Two sensible goals are in tension (speed vs. cost, simple vs. flexible) and the user has not said which wins.
- The user says it explicitly: "interview me", "grill me", "stress-test my thinking", "before we start, are we sure?"

Do **not** run it when:

- The request is fully specified and self-contained ("rename `userId` to `accountId`", "fix this typo").
- The user has asked for speed over scrutiny.
- It is a pure question ("how does this function work?") or a mechanical edit (format, move, rename).
- You already have ~95% confidence — re-check the stop condition below before deciding you don't.

## Environment limits

This skill requires a person who can answer in real time. **Never run it in non-interactive contexts** — CI jobs, scheduled agents, `/loop`, autonomous runs. If you are in one of those and the ask is underspecified, raise it as a blocker rather than guessing your way past it.

## Procedure

### 1. State a hypothesis with a number

Before the first question, write your current best guess of the goal in **one sentence**, and an honest confidence percentage:

```
HYPOTHESIS: You want to answer "is the migration on track?" quickly, and "status page" was just the first shape that came to mind.
CONFIDENCE: ~35% — unknown: who reads it, what "on track" means, and what would count as success
```

The number keeps you honest. If you wrote a high number but cannot predict how the user will react to your next three questions, the number is inflated — lower it. Whenever confidence is under ~70%, append a short note on the same line naming what is still open. That tells the user precisely what the interview needs to resolve.

### 2. One question at a time, each carrying your guess

Use this shape, then stop and wait:

```
Q: <a single focused question>
GUESS: <your best answer, plus the reasoning that produced it>
```

Ask the next question only after the user responds.

Single questions, not a batch, because:

- A buried hypothesis in a list gets skimmed past, not reacted to.
- Later questions often hinge on earlier answers; asking them together freezes the wrong framing.
- The user's careful-thinking budget is limited — spend it one question deep.

Attach a guess because reacting to a concrete wrong answer is faster than producing one from nothing, and stating a guess forces *your* hidden assumptions into the open where they can be corrected. The hazard is an agreeable user rubber-stamping your guess. Counter it by being plainly willing to be wrong, and now and then guessing in a direction you expect pushback on.

### 3. Catch "what they'd say" vs. "what they want"

The riskiest answers sound thoughtful but describe a stereotype of a good answer, not the user's actual desire. Watch for:

- Best-practice vocabulary with no specifics ("make it scalable", "clean architecture").
- Deference to convention ("the standard way", "how most teams do it").
- Hedges like "I guess I should…", "I think you're supposed to…".
- Buzzwords standing in for outcomes ("modern", "robust", "enterprise-grade").

When you hear one, ask:

> *"Forget what sounds right to anyone else — what would you actually want here?"*

That single question often outperforms the five before it.

### 4. Play the goal back in their words

Once confidence is high, write the goal back tightly (about 5–8 lines), reusing the user's own phrasing, structured so they can confirm or fix it line by line:

```
Here is what I now believe you want:

- Outcome:      <one line>
- Who it's for: <one line — who benefits>
- Why now:      <one line — what changed>
- Done means:   <one line — how we'll know it worked>
- Constraint:   <one line — the limit that binds>
- Not doing:    <one line — explicitly out of scope>

Confirm, correct, or refine?
```

The "Not doing" line is mandatory. A large share of misalignment is unspoken disagreement about what is *not* being built.

### 5. Get an explicit yes

The gate is a real "yes." These are not yes:

- "Whatever you think." → That is delegation, which means the user is not at 95% either. Re-ask as a choice between two concrete options.
- "Looks good." → Too vague. Ask "anything you'd change?" Silence is not agreement.
- "Sure, go ahead." → Often a polite exit. Same follow-up.
- A pause, then "fine, let's start." → The user gave up on the interview rather than reaching agreement. Stop and ask what you missed.

Fold in any correction, restate, and loop until you get a clear yes.

### The 95% stop

You are done when this is true:

> *Can I predict how the user would react to the next three questions I'd ask?*

If yes, you share their understanding — stop and produce the playback. If no, ask the next question.

This is a test, not a feeling. It also has a floor: if several rounds pass and you still cannot predict, that tells you something is fundamentally missing — don't grind. Say so: "I've asked N questions and still can't predict your answers. Something foundational is unclear. Want to step back and reframe?"

## What this produces

The deliverable is a **confirmed goal statement**: the playback from step 4 with an explicit yes from step 5. Specs, plans, and task lists come after and consume it.

If the goal needs to outlive the session (a long project, a handoff), offer to save it to `docs/intent/[topic].md`. Save only after the user agrees — the file itself implies a yes.

## Worked example

**Without the skill:**

```
User:  build a status page for the migration
Agent: <starts picking charting libraries and page layouts>
```

The agent silently decided who reads it, what "status" means, and what success is. Each silent decision is a future "that's not what I meant."

**With the skill:**

```
User: build a status page for the migration

Agent:
HYPOTHESIS: You want a fast way to answer "is the migration on track?", and "status page" was the first shape that fit.
CONFIDENCE: ~35% — unknown: who reads it, what "on track" means, what success looks like

Q:     When you ask "is it on track?", who's actually asking — you, the team in standup, or someone above you (a lead, a stakeholder)?
GUESS: it's for the team in standup, since "the migration" sounds like shared work. If it's for a stakeholder, the framing and the numbers change a lot.

User: Honestly it's for me. I keep losing track of which tables are migrated and which still have the old schema.

Agent:
Updated read: not a status page for an audience — a personal checklist of migration state. Confidence: ~60% — still open: what "migrated" means per table, and what done looks like.

Q:     Is the problem that you don't know which tables exist to migrate, or that you can't see each one's migration state in one place?
GUESS: the second — you know the table list, but their state is scattered across migration files and Supabase, and reconciling it by hand is the annoying part.

User: It's the first. I don't even have a clean list of which tables still use the old shape.

Agent: <continues>
```

Two questions in, the real ask is not "a status page." It is "an inventory of un-migrated tables." Different artifact, different scope. The status page would have been wrong.

## How it relates to other skills

- **`idea-refine`** (downstream): if the confirmed goal is "I want X but can't scope it," hand off to generate variations against the now-explicit goal.
- **`spec-driven-development`** (downstream): if the goal is concrete, hand off to write the requirements.
- **`planning-and-task-breakdown`**: two hops downstream, after the spec.
- **`doubt-driven-development`**: the mirror image in time — interview-me extracts intent before a decision; doubt-driven reviews artifacts after one.
- **`source-driven-development`**: orthogonal — interview-me clarifies the goal; SDD verifies framework facts. They don't overlap.

## Excuses that aren't valid

| Excuse | Reality |
|---|---|
| "The ask is clear enough." | If you can't state the desired outcome in one sentence right now, it isn't. Do step 1 first. |
| "Questions waste their time." | Four to six sharp questions cost minutes. Building the wrong thing costs days, and the user pays. |
| "I'll sort it out while building." | Switching costs jump roughly 10x once code exists. Discovery mid-build is just rework. |
| "They said 'whatever you think,' so I'll decide." | That's delegation, not a decision. Re-ask as a two-option choice. |
| "I'll offer them a menu of options." | Options help when the user knows what they want and is trading off. They don't yet — listing options widens the search instead of narrowing it. |
| "Attaching a guess leads them." | Leading is intentional; reacting beats generating. The real risk is sycophancy — counter it by being visibly willing to be wrong. |
| "We've talked enough." | Test it: can you predict the next three reactions? If not, you can't stop. |
| "They said yes." | If the yes followed a vague playback, it's hollow. Restate concretely and re-confirm. |

## Red flags

- Three or more questions in one message — that's a survey, not an interview.
- A question with no guess attached — surveying, not committing.
- Treating "whatever you think" as a final answer.
- Producing a spec, plan, or tasks before the user confirmed the playback.
- Asking "what's best practice?" instead of "what do you want?"
- Accepting a sophistication-signaling answer ("scalable", "clean") without probing it.
- Three rounds with no rise in confidence — wrong questions; reframe.
- A sub-70% confidence number with no reason attached.
- Saving the intent doc before the user confirmed.
- Skipping the "Not doing" line.

## Verification

- [ ] A hypothesis with a confidence number appeared in the first turn.
- [ ] Every sub-70% confidence number carried a one-line reason.
- [ ] Questions were asked one at a time, each with a guess.
- [ ] At least one "what would you actually want?" probe ran on any convention- or sophistication-signaling answer.
- [ ] A concrete playback (Outcome / Who / Why now / Done / Constraint / Not doing) was written back.
- [ ] The user gave an explicit yes (not "whatever you think", not "looks good", not silence).
- [ ] At the stop, the agent could predict the next three reactions.
- [ ] Any handoff was framed around the confirmed goal, not the original vague ask.
