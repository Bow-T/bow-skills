---
name: using-agent-skills
description: Picks the right skill for the task at hand. Use at the start of a session, or any time you're unsure which skill applies. This is the index skill that routes you to every other skill in this marketplace.
---

# Using Agent Skills

## What this is

This marketplace bundles two kinds of skills:

- **Lifecycle skills** — one per stage of building software, each encoding a process a careful engineer follows.
- **Stack/team skills** — conventions specific to this codebase (Flutter/Dart, Supabase, TypeScript, and the commit workflow). When a task touches their area, they are authoritative and override the generic advice.

Your first move on any non-trivial task: find the skill that fits, then follow its steps. This index helps you find it.

## Routing: pick by what you're doing

Walk down to the first row that matches your situation.

```
What are you doing right now?

  Still figuring out what the user actually wants ........ interview-me
  Have a rough idea, want to explore/sharpen it ......... idea-refine
  Ready to define a feature or change .................. spec-driven-development
  Have a spec, need to break it into tasks ............. planning-and-task-breakdown
  Loading the right context for the work ............... context-engineering

  Writing implementation code .......................... incremental-implementation
    └ and it's user-facing UI .......................... frontend-ui-engineering
    └ and it's an API or interface ..................... api-and-interface-design
    └ and you need doc-verified facts .................. source-driven-development
    └ and the stakes/uncertainty are high .............. doubt-driven-development

  Writing or running tests ............................. test-driven-development
    └ and it needs a real browser ...................... use the Chrome DevTools MCP
  Something broke ...................................... debugging-and-error-recovery

  Reviewing code ....................................... code-review-and-quality
    └ it's too complex ................................. code-simplification
    └ security is a concern ............................ security-and-hardening
    └ performance is a concern ......................... performance-optimization

  Adding logs / metrics / traces / alerts ............. observability-and-instrumentation
  Committing or pushing ................................ commit-pipeline
  Working on CI/CD ..................................... ci-cd-and-automation
  Removing or migrating an old system ................. deprecation-and-migration
  Writing docs or an ADR .............................. documentation-and-adrs
  Deploying or launching .............................. shipping-and-launch
```

## Behaviors that apply everywhere

These hold regardless of which skill you're in. They are not optional.

**Say your assumptions out loud.** Before any non-trivial work, list what you're assuming about requirements, architecture, and scope, and invite correction. The most common way work goes wrong is filling an ambiguous gap silently and running with it.

**Stop when you're confused.** If the spec contradicts the code, or two requirements conflict, do not pick one and hope. Name the specific conflict, present the trade-off or ask the question, and wait. "The spec says X but the code does Y — which wins?" beats a silent guess.

**Disagree when you should.** You are not a rubber stamp. If an approach has a real downside, state it plainly, quantify it where you can ("this adds ~200 ms per request," not "this might be slow"), offer an alternative, and accept the human's call once they've heard it. Cheerful agreement with a bad plan helps no one.

**Default to simple.** The natural pull is to overbuild — resist it. Before finishing, ask whether it could be fewer lines, whether each abstraction earns its keep, and whether a senior engineer would say "why not just…". The boring, obvious solution usually wins.

**Stay in scope.** Touch only what the task needs. Don't delete code you don't understand, refactor adjacent systems as a side effect, strip comments, or add unrequested features. Be a surgeon, not a renovator.

**Verify with evidence.** Nothing is done on "looks right." Show the passing tests, the build output, the runtime behavior. Every skill ends in a verification step — honor it.

## Failure modes to watch for

Each of these feels like progress and isn't:

- Guessing at ambiguous requirements instead of asking.
- Pressing on while confused.
- Noticing an inconsistency and staying quiet.
- Skipping the trade-off on a non-obvious decision.
- Agreeing with a plan that has clear problems.
- Overbuilding the code or the API.
- Editing things unrelated to the task.
- Removing code you don't fully understand.
- Building with no spec because "it's obvious."
- Declaring done without verifying.

## Rules of use

1. **Check for a matching skill before you start.** Skills exist to prevent known mistakes.
2. **Treat a skill as a workflow.** Follow its steps in order; don't drop the verification step.
3. **More than one can apply.** A feature often chains several — see the sequence below.
4. **When unsure on something non-trivial, start with a spec** (`spec-driven-development`).
5. **Stack/team skills win in their area.** If a task touches Flutter, Supabase, or committing, the matching team skill overrides generic advice.

## A typical feature, end to end

Not every task needs every step — a bug fix might be just `debugging-and-error-recovery` → `test-driven-development` → `code-review-and-quality`. But a full feature usually runs:

```
1.  interview-me                       extract the real goal
2.  idea-refine                        sharpen a vague idea
3.  spec-driven-development            write down what we're building
4.  planning-and-task-breakdown        split into verifiable tasks
5.  context-engineering                load the right context
6.  source-driven-development          verify against official docs
7.  incremental-implementation         build in thin slices
8.  observability-and-instrumentation  instrument as you go (parallel with 7–10)
9.  doubt-driven-development           cross-examine risky decisions in flight
10. test-driven-development            prove each slice works
11. code-review-and-quality            review before merge
12. code-simplification                cut complexity, keep behavior
13. commit-pipeline                    Conventional Commit + push
14. documentation-and-adrs             record the decisions
15. deprecation-and-migration          retire old systems safely (when relevant)
16. shipping-and-launch                deploy with a rollback plan
```

## Lifecycle skills at a glance

| Stage | Skill | In one line |
|---|---|---|
| Define | interview-me | Surface what the user truly wants before any plan or code |
| Define | idea-refine | Widen then narrow a fuzzy idea into a sharp brief |
| Define | spec-driven-development | Requirements and acceptance criteria before code |
| Plan | planning-and-task-breakdown | Decompose into small, checkable tasks |
| Plan | context-engineering | The right context at the right moment |
| Build | incremental-implementation | Thin vertical slices, verified one at a time |
| Build | source-driven-development | Confirm framework facts against the docs first |
| Build | doubt-driven-development | Adversarial fresh-eyes review of risky decisions |
| Build | api-and-interface-design | Stable interfaces with clear contracts |
| Build | frontend-ui-engineering | Accessible, polished, production-grade UI |
| Verify | test-driven-development | Failing test first, then make it pass |
| Verify | debugging-and-error-recovery | Reproduce, localize, fix, guard against regression |
| Review | code-review-and-quality | Structured multi-axis review with quality gates |
| Review | code-simplification | Reduce complexity while preserving behavior |
| Review | security-and-hardening | Input validation, least privilege, OWASP defenses |
| Review | performance-optimization | Measure first, then optimize what matters |
| Ship | observability-and-instrumentation | Structured logs, RED metrics, traces, useful alerts |
| Ship | ci-cd-and-automation | Automated gates on every change |
| Ship | commit-pipeline | Conventional Commit + push for this repo |
| Ship | deprecation-and-migration | Retire systems and move users safely |
| Ship | documentation-and-adrs | Capture the why, not just the what |
| Ship | shipping-and-launch | Pre-launch checklist, monitoring, rollback |

For browser-based runtime checks there is no dedicated skill — drive the running app with the **Chrome DevTools MCP** (rendering, console, network, keyboard order).

## Stack & team skills (this marketplace)

Prefer these over generic advice whenever the task lands in their area — they are authoritative.

| Area | Skill | Use when |
|---|---|---|
| Commit / push | commit-pipeline | Committing and pushing — Conventional Commits, `Jira:` footer, **no AI trailer**. Authoritative; overrides any generic git advice. |
| Flutter data | flutter-data-model | Creating or editing models — `@JsonSerializable` + build_runner; never hand-write `fromJson`. |
| Flutter UI | flutter-mvvm | Building screens — BaseViewModel + MixinBasePage MVVM. |
| Supabase / DB | supabase-security-review | Auditing RLS, views, triggers, or edge functions before commit. |
