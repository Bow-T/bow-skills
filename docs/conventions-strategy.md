# Conventions strategy — skills + enforced tooling

There are two internal efforts to standardise how we (and our AI assistants) work.
They are **complementary, not competing** — different layers of the same goal.

## The two systems

### A. `bow-skills` (this repo) — Claude Code skills
Context-triggered *workflows* for Claude Code. Each `SKILL.md` carries deep, judgment-heavy
procedure (TDD, debugging, Flutter MVVM, generated data models, RLS review, the commit
pipeline) and activates only when the task matches its trigger.

- **Strength:** depth. Step-by-step procedure a linter could never encode.
- **Limit (before this change):** Claude-only; relied on goodwill — nothing *blocked* a bad commit; per-repo specifics were hardcoded placeholders.

### B. The shared-convention toolkit (separate, internal repo)
An npm monorepo on the internal registry: shared `commitlint` / `eslint` / `prettier` configs,
a scaffolder CLI, and **one** markdown source of AI rules rendered into every assistant's rule
file (Claude / Cursor / Codex / Gemini / Copilot).

- **Strength:** *enforcement* (git hooks + commitlint actually reject bad commits), multi-assistant from one source, clean per-repo scaffolding.
- **Limit:** rules are short, static text — no contextual triggering, shallow vs a full skill.

## How they fit together

| Layer | Owner | Mechanism |
|---|---|---|
| **Hard rules** — commit format, no-AI-trailer, secret files, lint/format | tooling | commitlint + lefthook + eslint (block at commit/CI) |
| **Judgment rules** — TDD, debugging, MVVM, RLS, commit pipeline | skills | Claude Code, contextual |

The right model is **both, layered**: tooling enforces the machine-checkable floor; skills
carry the depth on top. Neither replaces the other.

## What we pulled into `bow-skills` from the toolkit

1. **`tooling/`** — a standalone, brand-neutral `commitlint.config.cjs` (Conventional Commits +
   `jira-key-present` + `no-ai-coauthor`) and `lefthook.yml` (commit-msg lint + pre-commit
   secret block). Repos can now *enforce* the commit convention the `commit-pipeline` skill
   describes.
2. **`.conventions.json`** — a per-repo config (`jiraKey`, `baseBranch`, `appDir`, `appPackage`,
   scripts). The skills and commitlint read it, so there are no hardcoded placeholders.
3. **The commit convention itself** — aligned to the company standard (see below).

## Conventions reconciled (was a direct conflict)

`commit-pipeline` previously diverged from the company commit standard on three points;
all three are now aligned:

| Point | Before | Now (company standard) |
|---|---|---|
| AI-authorship trailer | added `Co-Authored-By: Claude` | **removed** — commit as the human author (commitlint blocks it) |
| Ticket footer | `Refs: PROJ-XXX` | `Jira: <key>-123` |
| Type case | `Feat` / `Fix` (capitalized) | `feat` / `fix` (lowercase); subject capitalized |

> ⚠️ Note for whoever runs the agents: Claude Code's *default* harness behaviour appends a
> `Co-Authored-By: Claude` trailer. The company standard forbids it, and the commit-msg hook
> now rejects it. Make sure agents follow this skill (no trailer), not the default.

## Recommendation

- Install **both** in product repos: the `tooling/` configs for enforcement, the `bow-core`
  plugin for the workflows.
- Keep **one** commit standard (the reconciled one above) so the hook and the skill never
  disagree.
- Coordinate with the toolkit's author so the two repos don't drift — ideally the commit
  rules live in one place that both consume.
