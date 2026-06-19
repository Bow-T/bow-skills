# Orchestration Patterns

How agents, sub-agents, and personas should be composed in this repo — the arrangements we endorse and the ones we refuse. Read this before writing a slash command that coordinates several personas, or before adding a persona that delegates to other personas.

## The one rule everything else follows

**Orchestration lives with the human or the slash command they run. A persona produces one perspective and stops; it never reaches for another persona.** Skills, by contrast, are required steps inside a persona's own workflow — those are expected.

Keep that distinction in mind throughout: composing *skills* into a persona is good; composing *personas* into a persona is the thing we're guarding against.

---

## Patterns we endorse

### Pattern A — Call one persona directly

The simplest and cheapest arrangement. One persona, one artifact, one report back.

```
user → persona → report
```

Reach for it when the request is a single perspective on a single thing and fits in one sentence:

- "Review this PR" → the reviewer persona
- "Audit `auth.ts` for vulnerabilities" → the security persona
- "What's untested in checkout?" → the test persona

Cost is one round trip — the yardstick every fancier pattern has to beat.

### Pattern B — Wrap one persona in a slash command

A slash command that pins one persona to the project's standard skills, so nobody has to restate the setup each time.

```
/review → reviewer persona (+ its skills) → report
```

Use it when the same single-persona call keeps recurring with the same configuration. The command is just a saved prompt, so it costs the same as Pattern A.

Warning sign: if the command's body is mostly logic for *choosing* a persona, it shouldn't exist — let the human pick directly.

### Pattern C — Fan out in parallel, then merge

Several personas work the same input at once, each returning its own report. The main agent (not a sub-agent) merges those into a single decision.

```
              ┌─ reviewer  ─┐
/ship ───────┼─ security  ─┼──→ merge → verdict + rollback note
              └─ tester    ─┘
```

Before adopting it, all of these should be true:

- [ ] The sub-tasks are truly independent — no shared mutable state, no required ordering
- [ ] Each persona surfaces a *different kind* of finding, not the same point from another angle
- [ ] The merge is small enough to finish inside the main agent's remaining context
- [ ] The wait is long enough that parallelism is actually felt

If any are false, drop back to Pattern A or B. The trade is more sub-agent contexts in exchange for shorter wall-clock time and sharper reports (each persona stays narrow).

### Pattern D — A human-run sequence of slash commands

The person runs commands in a deliberate order, carrying context (or just the commit history) between them. There is no orchestrating agent — the human is the orchestrator.

```
/spec → /plan → /build → /test → /review → /ship
```

Right when steps depend on each other and human judgment between them is valuable — which describes the whole DEFINE → PLAN → BUILD → VERIFY → REVIEW → SHIP lifecycle. Each step is one sub-agent context; the orchestration layer is free because no agent runs it.

Don't try to automate this with a "lifecycle agent." It would have to summarize for each hand-off (losing nuance), would erase the human checkpoints that catch wrong-direction work early, and would roughly double token cost with paraphrase turns.

### Pattern E — Isolate research so it doesn't flood the main context

When a task needs to read a lot of material that shouldn't crowd the main conversation, hand it to a research sub-agent that returns only a condensed answer.

```
main agent → research sub-agent (reads many files) → digest → main agent resumes
```

Good when the answer is far smaller than the input, and when the main session needs room to keep thinking afterward — e.g. "find every caller of this deprecated API" or "summarize what these design docs decided about caching."

On Claude Code, use the built-in `Explore` sub-agent for this instead of authoring a custom researcher. It's read-only, runs on a cheaper model, and is built for exactly this job. Only write your own when `Explore` genuinely doesn't fit (say, you need a domain-specific system prompt).

---

## Running these on Claude Code

The patterns above are harness-agnostic, but most of us run them on Claude Code, which also enforces some of our rules for free.

### Where personas live

Plugin sub-agents are auto-discovered from `agents/` at the plugin root. Because this repo ships as a plugin, the persona files under `agents/` load automatically when the plugin is enabled — no path setup.

### Two parallelism primitives

| | Sub-agents | Agent Teams |
|---|---|---|
| Coordination | main agent fans out; each only reports back | teammates message each other, share a task list |
| Context | one window per sub-agent | one window per teammate |
| Best for | independent tasks producing reports | collaborative work that needs back-and-forth |
| Maturity | stable | experimental (needs a feature flag) |
| Cost | lower | higher — every teammate is a separate instance |

Pattern C maps onto **sub-agents**. When you need teammates that actually talk, use **Agent Teams**. The same persona definition works in both modes; only the spawning context differs.

One gotcha: a persona's `skills` and `mcpServers` frontmatter are honored when it runs as a sub-agent but ignored when it runs as a teammate (teammates inherit skills/MCP from session settings). If a persona depends on a particular skill or MCP server, configure it at the session level so both modes get it.

### Rules the platform enforces for you

- **A sub-agent can't spawn another sub-agent.** This makes the persona-calls-persona and deep-tree anti-patterns below impossible to build by accident — they simply won't load.
- **Teams can't nest.** A teammate can't start its own team, blocking the same anti-patterns at the team level.

### Built-ins to prefer over custom personas

| Built-in | Role |
|---|---|
| `Explore` | read-only codebase search — use it for Pattern E |
| `Plan` | read-only research during planning |
| `general-purpose` | multi-step work that both explores and edits |

Layer specialist personas on top of these rather than redefining them.

### Frontmatter that does and doesn't apply to plugin agents

Plugin sub-agents **ignore** `hooks`, `mcpServers`, and `permissionMode`. To use any of those, the persona has to be copied into `.claude/agents/` or `~/.claude/agents/`. The fields that do work include `name`, `description`, `tools`, `disallowedTools`, `model`, `maxTurns`, `skills`, `memory`, `background`, `effort`, `isolation`, `color`, and `initialPrompt`. Set `model` per persona to tune cost (a lighter model for coverage scans, a heavier one for security work).

### Firing sub-agents in parallel

True fan-out (Pattern C) needs **several Agent tool calls in one assistant turn**. Issuing them across separate turns serializes them. Any new orchestrator command should spawn its personas together in a single turn.

---

## Worked example: competing-hypothesis debugging with Agent Teams

Here's a case where Agent Teams beats Pattern C's sub-agent fan-out, even though both spawn the same three personas. The value comes from a different place.

### The bug

> Checkout occasionally stalls ~30s before finishing — roughly 1 in 50 sessions, no errors logged, began after last week's release.

Several mutually exclusive theories all fit:

1. A race in the new payment-confirmation path
2. An auth check that sometimes falls into a slow synchronous network call
3. A missing index on a query that scales with cart size
4. A flaky third-party SDK retrying silently before it times out

A lone agent latches onto the first plausible theory and stops. A sub-agent fan-out would have each persona report on its own — but the reports never meet, so nothing rules the wrong theories *out*. The point of a team here is that investigators actively try to **disprove each other**; the theory left standing is far more likely to be the real cause.

### Why this isn't a `/ship` job

| | Sub-agent fan-out | Agent Teams |
|---|---|---|
| What each sees | the same diff through a different lens | a shared task list and each other's messages |
| Output | three separate reports, merged once | an adversarial debate that converges |
| Right when | you want a verdict on a known artifact | you want to *find* the artifact among hypotheses |

`/ship` delivers a verdict; a team runs an investigation.

### Enabling it (once per environment)

Agent Teams is experimental. Turn it on in `~/.claude/settings.json`:

```json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```

The repo's personas are picked up automatically — no team-config files to write.

### Kicking it off

Describe the problem to the lead session in plain language and ask it to assemble a team, naming the existing persona types and what each should chase:

```
Checkout intermittently stalls ~30s after last week's release; no errors logged.

Start an agent team to debug this with competing hypotheses. Spawn three
teammates from the existing agent types:
  - reviewer  — race conditions and blocking calls in the checkout path
  - security  — recently added auth checks, session handling, synchronous calls
  - tester    — tests that would distinguish the hypotheses, plus coverage gaps

Have them message each other to challenge theories directly. Only converge
when two of them agree they can disprove the rest.
```

The lead spawns the teammates; each persona body is appended to that teammate's instructions on top of the team-coordination prompt.

### How it plays out

1. Each teammate explores in its own context from its own angle.
2. Teammates message findings to each other directly — the lead doesn't relay.
3. The shared task list shows who's on what (visible with `Ctrl+T`, or in a tmux pane).
4. When the reviewer spots a `Promise.all` that should be sequential, it pings the security teammate to confirm the auth call isn't part of the race; security checks and either confirms or produces counter-evidence.
5. The tester proposes a focused integration test for whichever theory is leading, and the team verifies before declaring consensus.
6. The lead synthesizes the converged answer for you.

Redirect any teammate that's wandering by cycling to it (`Shift+Down`) and typing.

### Wrapping up

When the root cause is found, tell the lead `Clean up the team` — always through the lead, never a teammate (teammates lack the full team context to tear it down).

### Cost note

Three model-backed teammates investigating for 10–15 minutes costs noticeably more than the same three spawned as sub-agents by `/ship`. The justification is **confidence in the conclusion** — worth it for production debugging where a wrong fix is expensive, not worth it for a routine review.

### The trap to avoid here

Don't rebuild this as a `/debug` command that fans out sub-agents. Sub-agents can't message each other, so you'd lose the debate that makes it work. If this keeps coming up, save the trigger prompt above as a snippet — don't wrap it in a command that misuses sub-agents.

### When *not* to reach for a team

- A verdict on a known diff → `/ship` sub-agents
- One perspective on one artifact → direct persona call (Pattern A)
- A dependent, step-by-step lifecycle → human-run commands (Pattern D)
- Read-heavy research with a small digest → the `Explore` sub-agent (Pattern E)

Use a team only when the teammates genuinely *need* to argue to land on the right answer.

---

## Anti-patterns we refuse

### Anti-pattern 1 — The router persona

A persona whose only job is deciding which other persona to invoke.

```
/work → router → "needs a review" → reviewer → router (re-summarizes) → user
```

It's a pure dispatch layer with no domain value, it adds paraphrase hops (lost context, roughly double the tokens), and the human already knew what they wanted — they could have run `/review`. It also duplicates what slash commands and intent mapping already do. **Instead:** add or sharpen slash commands and document intent → command mapping.

### Anti-pattern 2 — A persona that calls another persona

For example, a reviewer that fires off the security persona whenever it sees auth code. Personas are built to give one perspective; chaining them defeats that, the hand-off summary drops context the second persona needs, the failure modes multiply (whose output format and rules win?), and the cost is hidden from the human. **Instead:** have the first persona *recommend* a follow-up in its report, and let the human or a command run the second pass.

### Anti-pattern 3 — An agent that paraphrases its way through the lifecycle

An agent that runs `/spec`, then `/plan`, then `/build` on the human's behalf. It strips out the checkpoints that catch wrong-direction work, accumulates drift through repeated summarization, and roughly doubles token cost (an orchestrator turn plus a sub-agent turn per step) — all while removing human judgment exactly where it matters most. **Instead:** keep the human as orchestrator; document the recommended sequence and let them drive it.

### Anti-pattern 4 — Deep persona trees

`/ship` → a "pre-ship coordinator" → a "quality coordinator" → the reviewer. Every extra layer adds latency and tokens with no added decision value, makes debugging a multi-level dig, and starves the leaf persona of context through repeated summarization. **Instead:** keep orchestration depth at one (command → personas), with the merge in the main agent.

---

## Choosing a pattern

```
One perspective on one artifact?
├─ Yes → Pattern A (direct call). Done.
└─ No  → Will the same composition recur?
        ├─ No  → Pattern A, ad hoc. Done.
        └─ Yes → Are the sub-tasks independent?
                ├─ No  → Pattern D (human-run command sequence).
                └─ Yes → Pattern C (parallel fan-out + merge).
                        Check it against Pattern C's list;
                        if anything fails, fall back to Pattern B.
```

---

## Adding a pattern to this catalog

Only add a new entry once you can say yes to all of these:

1. You've actually used it on real work at least twice.
2. You can point to a concrete artifact in this repo that demonstrates it.
3. You can explain why no existing pattern would have done the job.
4. You can name its anti-pattern shadow — what people will build by mistake instead.

Entries added before that becomes aspirational documentation nobody follows.
