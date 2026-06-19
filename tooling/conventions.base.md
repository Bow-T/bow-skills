# Engineering Conventions

> Single source of truth for AI coding assistants. Edit this file, then run
> `node tooling/render-rules.mjs` to regenerate every assistant's rule file.
> In Claude Code the full skills load automatically; other assistants get this digest
> plus the skill index below.

## Core operating agreement

These hold on every change, regardless of which skill is active:

- **State assumptions before acting.** On anything non-trivial, list what you're assuming about
  requirements, scope, and design, and invite correction before you proceed.
- **Stop when confused.** Conflicting requirements or unclear specs mean halt and ask — never
  paper over ambiguity with a guess.
- **Push back when warranted.** Name a concrete downside and propose an alternative instead of
  agreeing to a flawed approach. Honest disagreement beats sycophancy.
- **Prefer the boring solution.** Resist over-engineering; fewer moving parts, no abstraction
  before a third caller needs it.
- **Stay in scope.** Touch only what the task needs. Log unrelated issues instead of fixing them.
- **Verify, don't assume.** "Looks right" is not done — show evidence (passing tests, build
  output, runtime behavior). A test that passed on its first run proves nothing.

## Commit convention

- Conventional Commits, **lowercase** type: `feat|fix|refactor|perf|test|docs|chore|style|ci|build|revert`.
- One gitmoji **right after the colon**, chosen by the change's intent — e.g. `fix(auth): 🔒️ …`.
- Imperative, capitalized subject ≤ 72 chars (including the emoji); no trailing period.
- Body explains **why**. Add a tracker footer (e.g. `Jira: ABC-123`) when a ticket exists.
- **Never** add an AI-authorship trailer (`Co-Authored-By: Claude/Copilot/…`, "Generated with …").
  Commit as the human author.
- Never commit secrets. Don't `git add -A` blindly or use `--no-verify`.
