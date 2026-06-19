# BOW Skills

**An open marketplace of production-grade engineering skills for Claude Code.**

Skills are *workflows the agent activates by context* — not docs you read. Each one declares a
trigger; when your task matches, Claude applies that process automatically: write the failing
test first, find the root cause instead of the symptom, reuse before you build, verify at runtime
instead of trusting a green compile.

Install once and your whole team shares the same working agreement with Claude. Copy it, fork it,
or extend it — it's MIT-licensed and built to be adopted.

---

## Two layers

- **`bow-core`** — 23 project-agnostic skills for the full spec→ship lifecycle. Works on any
  codebase, any language. This is the one everyone installs.
- **Stack plugins** (optional) — conventions for a specific stack. Ships today with
  **`flutter-supabase`**; add it only when you work on a Flutter/Supabase project.

Plus shared, opt-in **enforcement tooling** (`tooling/`) that turns the machine-checkable rules
(commit format, secret hygiene) into git hooks.

---

## Install

> Public marketplace — anyone with the repo URL can add it.

```bash
/plugin marketplace add Bow-T/bow-skills

# the project-agnostic core (recommended for everyone)
/plugin install bow-core@bow-skills

# optional: only if you work on a Flutter + Supabase app
/plugin install flutter-supabase@bow-skills
```

Skills then activate by context. To run one explicitly, use the slash commands below.

---

## `bow-core` — skill catalog (23)

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

### Verify & review
| Skill | Use when |
| :-- | :-- |
| `test-driven-development` | Failing test first, then make it pass. |
| `doubt-driven-development` | Subject high-stakes decisions to adversarial, fresh-context review. |
| `debugging-and-error-recovery` | Reproduce → localize → fix → guard. Verify at runtime, not just a green build. |
| `code-review-and-quality` | Multi-axis review before merge. |
| `code-simplification` | Reduce complexity while preserving behavior. |

### Harden
| Skill | Use when |
| :-- | :-- |
| `security-and-hardening` | App-layer hardening (input, auth, storage, integrations). |
| `performance-optimization` | Optimize against measured budgets / Core Web Vitals. |

### Ship & operate
| Skill | Use when |
| :-- | :-- |
| `ci-cd-and-automation` | Set up or modify build/deploy pipelines and quality gates. |
| `shipping-and-launch` | Pre-launch checklist, monitoring, rollback plan. |
| `observability-and-instrumentation` | Add logs, metrics, traces, and symptom-based alerts. |
| `commit-pipeline` | Commit & push — Conventional Commits + gitmoji, optional tracker footer, **no AI-authorship trailer**. |
| `deprecation-and-migration` | Retire old systems and migrate users safely. |
| `documentation-and-adrs` | Record architectural decisions and the *why*. |

### Meta
| Skill | Use when |
| :-- | :-- |
| `using-agent-skills` | Discover which skill applies to the current task. |

### Slash commands
| Command | Skill |
| :-- | :-- |
| `/spec <feature>` | spec-driven-development |
| `/plan <spec>` | planning-and-task-breakdown |
| `/tdd <behavior>` | test-driven-development |
| `/debug <symptom>` | debugging-and-error-recovery |
| `/tidy <area>` | code-simplification |
| `/harden <surface>` | security-and-hardening |

### Subagents (4)
Specialized agents in `plugins/bow-core/agents/` for delegated deep passes:
`code-reviewer`, `security-auditor`, `test-engineer`, `web-performance-auditor`. Reference
checklists live in `plugins/bow-core/references/` and are linked from the skills.

---

## `flutter-supabase` — optional stack plugin (3)

| Skill | Use when |
| :-- | :-- |
| `flutter-data-model` | Write Flutter models the generated way (`@JsonSerializable` + build_runner) — never hand-write `fromJson`. |
| `flutter-mvvm` | Build Flutter screens with the BaseViewModel + MixinBasePage MVVM pattern. |
| `supabase-security-review` | Audit Supabase RLS / views / triggers / edge functions before commit. |

These read per-repo values (app dir, package, tracker key…) from a `.conventions.json` at the
repo root, so they adapt to your project instead of hardcoding paths.

---

## Enforcement (`tooling/`)

Skills describe *how* to work; `tooling/` turns the machine-checkable parts into hard rules that
block at commit time:

| File | Role |
| :-- | :-- |
| `tooling/commitlint.config.cjs` | Conventional Commits + `jira-key-present` (warn) + `no-ai-coauthor` (blocks AI-authorship trailers). |
| `tooling/lefthook.yml` | Hooks: lint the commit message, block secret-like files at pre-commit. |
| `tooling/conventions.example.json` | Template for per-repo `.conventions.json`. |

Install steps: [`tooling/README.md`](tooling/README.md). Strategy: [`docs/conventions-strategy.md`](docs/conventions-strategy.md).

---

## Use it your way

- **Install** via the marketplace (above) — the fastest path for Claude Code users.
- **Fork** this repo and tune the skills, commands, and `.conventions.json` defaults to your team.
- **Copy** individual `SKILL.md` folders into your own `.claude/skills/` if you only want a few.

### Other assistants (Cursor, Copilot, Codex…)

Claude Code loads the full skills by context. For other assistants, render the conventions and a
skill index into their rule files from one source:

```bash
node tooling/render-rules.mjs   # writes CLAUDE.md, AGENTS.md, GEMINI.md, .github/copilot-instructions.md, .cursor/rules/
```

Each generated file ends with a per-assistant "how to load this" snippet (Copilot setting, Cursor
`alwaysApply`, plugin install, …), so any tool's setup is right there in its own rule file.

Edit [`tooling/conventions.base.md`](tooling/conventions.base.md) and re-run; each file keeps a
managed block so your own content is preserved. See [`tooling/README.md`](tooling/README.md#multi-assistant-rules).

---

## Repository structure

```
.claude-plugin/marketplace.json   # marketplace definition + plugin list
plugins/
  bow-core/                       # project-agnostic skills (everyone)
    .claude-plugin/plugin.json
    commands/  skills/  agents/  references/
  flutter-supabase/               # optional stack plugin
    .claude-plugin/plugin.json
    skills/
tooling/                          # commitlint + lefthook + .conventions.json template
docs/conventions-strategy.md      # skills vs enforced tooling
```

---

## Contributing

- Project-agnostic skills go in `plugins/bow-core/skills/`; stack-specific ones in a stack plugin.
- Keep skill content neutral and reusable — read per-repo values from `.conventions.json` rather
  than hardcoding paths, names, or tracker keys.
- A skill is one folder with `SKILL.md` carrying frontmatter `name` + `description`. The
  `description` must state **when** the skill triggers, so Claude routes to it correctly.

## License

MIT — see [`LICENSE`](LICENSE). All skills, subagents, and reference checklists are original works.
