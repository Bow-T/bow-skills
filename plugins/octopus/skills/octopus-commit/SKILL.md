---
name: octopus-commit
description: Commit and push changes following the DUOCT "Octopus Mode" pipeline — staged safety scan (RLS/CORS/secrets), Flutter static analysis, strict Conventional-Commit message with Jira ref, then push. Use when the user says "octopus commit", "commit + push", "push + commit", "đẩy code chuẩn octopus", or asks to commit/push on this repo.
---

# Octopus Mode — Commit & Push

Automates the project's commit pipeline. Run the steps **in order** and STOP on
any failure (fix, then resume). Do not skip the safety scan or the analyzer.

## 0. Pre-flight
- `git status` and `git rev-parse --abbrev-ref HEAD` to see changes + branch.
- Never commit on `develop`/`main` directly. If on a default branch, create a
  branch first: `<type>/DUOCT-<num>-<slug>` (type ∈ feat|fix|refactor|perf|test|docs|chore|style).
- Parse the Jira ticket from the branch name (e.g. `fix/DUOCT-800-…` → `DUOCT-800`).
  If the branch has no ticket, ask the user for one (the footer needs `Refs: DUOCT-XXX`).
- Stage intended files with `git add` (prefer scoping to the app dir, e.g.
  `git add apps/mobile`). NEVER stage local config — exclude `.claude/settings.local.json`,
  `.gemini/scratch/`, secrets, `.env*`. Confirm with the user before `git add -A`.

## 1. Safety scan (RLS / CORS / secrets) — BLOCKING
```bash
bash scripts/octopus-commit.sh
```
This runs `scripts/check-quest.sh --staged` (RLS FK-ownership, `security_invoker`
views, CORS wildcards, secrets) + branch-name check + `fvm flutter analyze` +
`scripts/quest-checklist.sh` preview.
> If it exits non-zero, STOP, extract the finding (file:line), fix the code, re-stage, re-run. Do not commit around it.

## 2. Flutter static analysis (if `apps/mobile` touched)
`scripts/octopus-commit.sh` already runs it, but if you ran a partial flow:
```bash
cd apps/mobile && fvm flutter analyze
```
> Zero errors AND zero warnings required. Fix everything before committing.

## 3. Compose the commit message (strict Conventional Commits)
```text
Type(scope): <emoji> Subject matching the Jira task title or a short clear summary

Detailed explanation of WHY these changes were made — at least 3 lines
describing the engineering decisions, structural/trigger/UI-behaviour changes,
to avoid NCV penalisation.

Refs: DUOCT-XXX
```
Rules (scoring-sensitive — get these exact):
- **Type**: capitalised (`Feat`, `Fix`, `Refactor`, `Perf`, `Test`, `Docs`, `Chore`, `Style`). Lowercase loses points.
- **Gitmoji**: one icon **right after the colon**, never before `Type` (the quest
  scorer's `^(Feat|Fix|…):` regex in `scripts/quest-checklist.sh:265` would miss it
  → lost points). Pick by the change's intent (map below). e.g.
  `Fix(notifications): 🌐 Localize push templates per recipient locale`.
- **Subject**: 10–72 chars *including the emoji*, imperative verb (`add`/`fix`/`update`, not `adding`/`fixed`).
- **Body**: ≥ 3 lines, explain WHY (not just what).
- **Footer**: `Refs: DUOCT-<num>` (from the branch). End with the Co-Authored-By trailer.

**Gitmoji map** (https://gitmoji.dev) — *intent wins over the type default*:
- Type default: `Feat` ✨ · `Fix` 🐛 · `Refactor` ♻️ · `Perf` ⚡️ · `Test` ✅ · `Docs` 📝 · `Chore` 🔧 · `Style` 🎨 · `Revert` ⏪️
- Intent override (when the change is mainly this): l10n/i18n 🌐 · security/RLS/secrets 🔒️ · DB schema / Supabase migration 🗃️ · remove dead code/files 🔥 · upgrade deps ⬆️ · CI/GitLab pipeline 👷 · config files 🔧 · critical hotfix 🚑️ · UI/cosmetic only 💄
> Type says "what kind of commit"; emoji says "what it touched". A `Fix` that localizes copy → `Fix(...): 🌐 …` (intent beats the 🐛 default).

## 4. Commit & push
Write the message to a temp file then commit (avoids shell-escaping issues):
```bash
git commit -F <tempfile>
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
```
The repo also ships `scripts/agent-commit-push.sh` which automates stage → ticket-parse
→ commit → push; prefer the explicit steps above when you need control over staging
or the message, and use the script only when the user wants the fully-automated path.

## 5. Report
Summarise: branch, commit hash + subject, files/insertions/deletions, push result,
and the GitLab MR-create URL printed by the push. Per Octopus Mode, one branch = one MR;
do NOT self-merge — assign review to a teammate (Hieu / Tuan).
