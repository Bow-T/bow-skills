# BOW Skills

**Production-grade engineering skills for Claude Code, packaged as a plugin marketplace.**

Install once, and every engineer shares the same working agreement with Claude: how we spec,
plan, test, review, harden, ship, and commit. Skills are *workflows the agent activates by
context* — not documents you read. Each skill declares a trigger; when your task matches, Claude
applies that process automatically.

The machine-checkable parts (commit format, secret hygiene) are enforced by git hooks, so the
rules hold regardless of which assistant — or human — is at the keyboard.

---

## Why skills

A skill encodes what a senior engineer does on autopilot and a model otherwise forgets under
pressure: write the failing test first, find the root cause instead of the symptom, reuse before
you build, verify at runtime instead of trusting a green compile. Bundling them into one
marketplace means the whole team inherits the same judgment, and it improves in one place.

Two layers, on purpose:

- **Judgment rules → skills** (`plugins/bow-core/skills/`) — deep, contextual procedure a linter
  can't encode.
- **Hard rules → tooling** (`tooling/`) — commit format, no-AI-trailer, secret files. Enforced at
  commit time, not left to goodwill.

---

## Install

> This repository is private — each member needs read access to the marketplace repo.

```bash
/plugin marketplace add <your-org>/bow-skills
/plugin install bow-core@bow-skills
```

Skills appear automatically; Claude selects them by context. To run one explicitly, use the
slash commands below.

---

## Skill catalog (26)

### Discover & define
| Skill | Use when |
| :-- | :-- |
| `interview-me` | Surface what the user actually wants before any plan or code (one question at a time). |
| `idea-refine` | Turn a vague idea into a sharp, actionable concept. |
| `spec-driven-development` | Write a tracker-linked spec before coding. |
| `planning-and-task-breakdown` | Decompose a spec into ordered, verifiable tasks — one branch per unit. |

### Build
| Skill | Use when |
| :-- | :-- |
| `context-engineering` | Load the right context into the session/agent. |
| `source-driven-development` | Ground implementation in official, cited documentation. |
| `incremental-implementation` | Deliver in thin vertical slices, verifying each before expanding. |
| `api-and-interface-design` | Design stable APIs/interfaces with clear contracts. |
| `frontend-ui-engineering` | Build production-quality web UI with accessibility. |
| `flutter-data-model` | Write Flutter models the generated way (`@JsonSerializable` + build_runner) — never hand-write `fromJson`. |
| `flutter-mvvm` | Build Flutter screens with the BaseViewModel + MixinBasePage MVVM pattern. |

### Verify & review
| Skill | Use when |
| :-- | :-- |
| `test-driven-development` | Failing test first, then make it pass (`*_test.dart`, `*.spec.ts`, …). |
| `doubt-driven-development` | Subject high-stakes decisions to adversarial, fresh-context review. |
| `debugging-and-error-recovery` | Reproduce → localize → fix → guard. Verify at runtime, not just a green build. |
| `code-review-and-quality` | Multi-axis review before merge. |
| `code-simplification` | Reduce complexity while preserving behavior. |

### Harden
| Skill | Use when |
| :-- | :-- |
| `security-and-hardening` | App-layer hardening (input, auth, storage, integrations). |
| `supabase-security-review` | Audit Supabase RLS / views / triggers / edge functions before commit. |
| `performance-optimization` | Optimize against measured budgets / Core Web Vitals. |

### Ship & operate
| Skill | Use when |
| :-- | :-- |
| `ci-cd-and-automation` | Set up or modify build/deploy pipelines and quality gates. |
| `shipping-and-launch` | Pre-launch checklist, monitoring, rollback plan. |
| `observability-and-instrumentation` | Add logs, metrics, traces, and symptom-based alerts. |
| `commit-pipeline` | Commit & push — Conventional Commits, tracker footer, **no AI-authorship trailer**. |
| `deprecation-and-migration` | Retire old systems and migrate users safely. |
| `documentation-and-adrs` | Record architectural decisions and the *why*. |

### Meta
| Skill | Use when |
| :-- | :-- |
| `using-agent-skills` | Discover which skill applies to the current task. |

### Slash commands
Invoke a skill directly instead of waiting for the router:

| Command | Skill |
| :-- | :-- |
| `/spec <feature>` | spec-driven-development |
| `/plan <spec>` | planning-and-task-breakdown |
| `/tdd <behavior>` | test-driven-development |
| `/debug <symptom>` | debugging-and-error-recovery |
| `/tidy <area>` | code-simplification |
| `/harden <surface>` | security-and-hardening |

---

## Subagents (4)

Specialized agents in `plugins/bow-core/agents/`, for delegated deep passes:

| Agent | Role |
| :-- | :-- |
| `code-reviewer` | Multi-axis review of a diff. |
| `security-auditor` | Adversarial security audit. |
| `test-engineer` | Test design and coverage analysis. |
| `web-performance-auditor` | Web performance audit (Core Web Vitals, traces). |

Reference checklists live in `plugins/bow-core/references/` (accessibility, observability,
orchestration, performance, security, testing) and are linked from the skills.

---

## Enforcement (`tooling/`)

Skills describe *how* to work; `tooling/` turns the machine-checkable parts into **hard rules**
that block at commit time:

| File | Role |
| :-- | :-- |
| `tooling/commitlint.config.cjs` | Conventional Commits + `jira-key-present` (warn) + `no-ai-coauthor` (blocks AI-authorship trailers). |
| `tooling/lefthook.yml` | Hooks: lint the commit message, block secret-like files at pre-commit. |
| `tooling/conventions.example.json` | Template for per-repo `.conventions.json`. |

Install steps are in [`tooling/README.md`](tooling/README.md). The skill-vs-tooling strategy is
in [`docs/conventions-strategy.md`](docs/conventions-strategy.md).

### Per-repo config (`.conventions.json`)

One file removes every hardcoded placeholder — both the skills and `commitlint.config.cjs` read
it:

| Key | Used for |
| :-- | :-- |
| `jiraKey` / `jiraKeys` | Commit footer, branch prefix, commitlint. |
| `baseBranch` | The branch you must not commit to directly. |
| `appDir` | Where the app lives (scoping for staging / analysis). |
| `appPackage` | Import root (`package:<appPackage>/…`). |
| `commitScript` / `securityScript` | The repo's local gate scripts, if any. |

---

## Repository structure

```
.claude-plugin/
  marketplace.json            # marketplace definition + plugin list
plugins/
  bow-core/
    .claude-plugin/plugin.json
    commands/<command>.md       # slash commands
    skills/<skill>/SKILL.md     # the skills
    agents/<agent>.md           # subagents
    references/<checklist>.md    # checklists the skills cite
tooling/                       # commitlint + lefthook + .conventions.json template
docs/
  conventions-strategy.md      # skills vs enforced tooling
```

---

## Contributing

- Every skill lives in `plugins/bow-core/skills/`. Keep names and content neutral and reusable —
  no project- or vendor-specific branding in the skill body; read per-repo values from
  `.conventions.json` instead.
- A skill is one folder with `SKILL.md` carrying frontmatter `name` + `description`.
- The `description` must state **when** the skill triggers, so Claude routes to it correctly.
- Do not embed sensitive internal information in a skill.

## License

MIT — see [`LICENSE`](LICENSE). All skills, subagents, and reference checklists are original works.
