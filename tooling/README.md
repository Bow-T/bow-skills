# tooling — enforce the conventions, don't just hope

The skills in `bow-core` describe how to work; the files here make the *machine-checkable*
parts actually block. Two layers, on purpose:

- **Hard rules → tooling** (this folder): commit format, no-AI-trailer, secret files. A bad
  commit is rejected at commit time, regardless of which assistant (or human) wrote it.
- **Judgment rules → skills** (`plugins/bow-core/skills/`): the deeper workflows a linter
  can't check — TDD, debugging, Flutter MVVM, RLS review, the commit pipeline itself.

## Files

| File | Role |
|---|---|
| `commitlint.config.cjs` | Conventional-Commits + custom rules: `jira-key-present` (warn), `no-ai-coauthor` (block). Standalone — only needs `@commitlint/*`. |
| `lefthook.yml` | Git hooks: run commitlint on `commit-msg`, block secret-like files on `pre-commit`. |
| `conventions.example.json` | Per-repo config template. Copy to repo root as `.conventions.json`. |
| `conventions.base.md` | Source of truth for the multi-assistant rules digest. |
| `render-rules.mjs` | Renders `conventions.base.md` + a skill index into each assistant's rule file. |

## Install in a target repo

```bash
npm i -D lefthook @commitlint/cli @commitlint/config-conventional
cp tooling/commitlint.config.cjs   ./commitlint.config.cjs
cp tooling/lefthook.yml            ./lefthook.yml
cp tooling/conventions.example.json ./.conventions.json   # then edit the values
npx lefthook install
```

Test it:

```bash
echo "chore: bad" | npx commitlint        # fails: subject too short, no Jira key (warn)
```

## Multi-assistant rules

Claude Code loads the full skills by context. Other assistants (Codex/AGENTS.md, Cursor,
Copilot) read a static rule file instead. One command renders all of them from a single source:

```bash
node tooling/render-rules.mjs
```

It writes a digest of `conventions.base.md` plus an auto-generated skill index into:

| Target | Assistant |
|---|---|
| `CLAUDE.md` | Claude Code / Claude |
| `AGENTS.md` | Codex and other AGENTS.md-aware tools |
| `.github/copilot-instructions.md` | GitHub Copilot |
| `.cursor/rules/bow-skills.mdc` | Cursor |

Each file keeps a `BOW:BEGIN … BOW:END` managed block; content you write outside it is preserved,
and re-running is idempotent. Edit the conventions in `conventions.base.md` (never the generated
files), then re-run. The skill index is rebuilt from every `SKILL.md` frontmatter automatically.

## Per-repo config (`.conventions.json`)

One file removes every hardcoded placeholder. Both the skills and `commitlint.config.cjs`
read it:

| Key | Used by | Example |
|---|---|---|
| `jiraKey` / `jiraKeys` | commit footer, branch name, commitlint | `"ABC"` or `["ABC","XYZ"]` |
| `baseBranch` | "never commit directly to …" guard | `"dev"` |
| `appDir` | where the Flutter app lives | `"apps/mobile"` |
| `appPackage` | Dart import root (`package:<appPackage>/…`) | `"app"` |
| `commitScript` / `securityScript` | the repo's local gate scripts, if any | `"scripts/commit.sh"` |

`JIRA_KEYS` as an env var overrides the file for commitlint (handy in CI).
