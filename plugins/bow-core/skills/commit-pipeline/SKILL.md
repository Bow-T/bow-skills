---
name: commit-pipeline
description: Commit and push changes following the team commit convention — optional staged safety scan (RLS/CORS/secrets), static analysis, a Conventional-Commit message with a Jira footer and NO AI-authorship trailer, then push. Use when the user says "commit", "commit + push", "push + commit", or asks to commit/push on this repo.
---

# Commit Pipeline — Commit & Push

Automates the team's commit pipeline. Run the steps **in order** and STOP on any
failure (fix, then resume). The message-format rules below are also enforced by
`commitlint` if the repo installed the hook (see `tooling/`) — so treat them as hard
rules, not suggestions.

## 0. Read project config — no hardcoded values
Look for `.conventions.json` at the repo root and use it. If absent, ask the user
for the missing values (don't invent them):
- `jiraKey` → the Jira footer + branch prefix (e.g. `ABC` → `ABC-123`).
- `baseBranch` → the branch you must NOT commit to directly (default `dev`).
- `appDir` → where to scope `git add` / run analysis (e.g. `apps/mobile`).
- `commitScript` / `securityScript` → the repo's local gate scripts, **only if they exist**.

## 1. Pre-flight
- `git status` and `git rev-parse --abbrev-ref HEAD` to see changes + branch.
- Never commit on `dev`/`main`/`master` directly. If on a base branch, create one first:
  `<type>/<jiraKey>-<num>-<short-kebab>` — `type` ∈ `feat|fix|refactor|perf|test|docs|chore|ci|build|style|revert`.
- Parse the ticket from the branch name (e.g. `fix/ABC-800-…` → `ABC-800`).
  If the branch has no ticket, **ask which Jira ticket this work belongs to** before committing.
- Stage intended files with `git add` (prefer scoping to `appDir`). NEVER stage local config,
  scratch dirs, secrets, `.env*`. Don't use `git add -A` (stages unintended files) — add specific
  paths. Confirm before staging broadly.

## 2. Safety scan + static analysis (if the repo provides them) — BLOCKING
Only if `.conventions.json` points to real scripts / a Flutter app:
```bash
bash <securityScript> --staged     # e.g. scripts/check-security.sh: RLS FK-ownership,
                                   # security_invoker views, CORS wildcards, secrets
cd <appDir> && fvm flutter analyze # zero errors AND zero warnings required
```
> If anything exits non-zero, STOP, extract the finding (file:line), fix, re-stage, re-run.
> Do not commit around it. (Deep RLS/CORS review → the `supabase-security-review` skill.)

## 3. Compose the commit message (Conventional Commits)
```text
type(scope): Imperative capitalized subject — match the Jira task or a clear summary

Body explaining WHY the change was made (not just what) — the engineering decision,
the structural/behaviour change. One commit = one logical concern.

Jira: ABC-123
```
Rules (these are what `commitlint` checks — get them exact):
- **Type**: **lowercase** Conventional-Commits prefix — `feat|fix|refactor|perf|test|docs|chore|style|ci|build|revert`. Pick from the actual diff: new feature/screen/API → `feat`; runtime bug/crash → `fix`; behaviour-preserving cleanup → `refactor`. Don't relabel a chore as `feat` to look bigger. Avoid `style`.
- **Scope**: optional, `kebab-case`, in parentheses — e.g. `fix(notifications): …`.
- **Subject**: imperative and capitalized (`Add`, `Fix` — not `Added`/`Adding`), 10–72 chars including the header, no trailing period.
- **Body**: a blank line then ≥ 1 line explaining WHY. For non-trivial changes, ≥ 3 lines.
- **Footer**: `Jira: <jiraKey>-<num>` (from the branch/ticket).
- **NO AI-authorship trailer.** Do NOT append `Co-Authored-By: Claude/Copilot/Cursor/Gemini/…`, a `Generated with …` line, or any agent marker. Commit as the human author only. (`commitlint`'s `no-ai-coauthor` rule blocks these.)

## 4. Commit & push
Write the message to a temp file then commit (avoids shell-escaping issues):
```bash
git commit -F <tempfile>
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
```
- `--amend` only if the commit was **not** pushed; if pushed, make a new `fix(scope): …` commit.
- Don't use `--no-verify` (skips the hooks) or force-push unless the user explicitly asks.

## 5. Report
Summarise: branch, commit hash + subject, files/insertions/deletions, push result,
and the MR/PR-create URL printed by the push. One branch = one MR;
do NOT self-merge — assign review to a teammate.
