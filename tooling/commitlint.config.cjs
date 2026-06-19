/**
 * Shared commit-message convention — standalone, brand-neutral.
 * Adapted from the company's internal convention toolkit; rebuilt on the standard
 * `@commitlint/config-conventional` base so it works in any repo with no private deps.
 *
 * Install in a target repo:
 *   npm i -D @commitlint/cli @commitlint/config-conventional
 *   cp tooling/commitlint.config.cjs <repo>/commitlint.config.cjs
 * Wire it to the commit-msg hook with lefthook — see tooling/lefthook.yml.
 *
 * Jira keys: read from env `JIRA_KEYS="ABC,XYZ"`, else from `.conventions.json`
 * (`jiraKey` / `jiraKeys`). When none is set, any UPPERCASE-123 pattern counts.
 * Missing key is WARN-only (nudge, never blocks) — flip `jira-key-present` to 2 to gate.
 */
const fs = require('fs');
const path = require('path');

function readJiraKeys() {
  if (process.env.JIRA_KEYS) {
    return process.env.JIRA_KEYS.split(',').map((s) => s.trim()).filter(Boolean);
  }
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(process.cwd(), '.conventions.json'), 'utf8'));
    const k = cfg.jiraKey || cfg.jiraKeys;
    return Array.isArray(k) ? k : k ? [k] : [];
  } catch {
    return [];
  }
}

const KEYS = readJiraKeys();
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const KEY_GROUP = KEYS.length ? `(?:${KEYS.map(escapeRe).join('|')})` : '[A-Z][A-Z0-9]+';
const JIRA_RE = new RegExp(`\\b${KEY_GROUP}-\\d+\\b`);

// AI-authorship trailers to keep OUT of commits. Needs an AI product/email marker
// (e.g. "Claude Code", "noreply@anthropic.com") — won't false-match a human named Claude.
const AI_TRAILER_RE =
  /(co-authored-by:\s*.*(copilot|cursor|gemini|chatgpt|gpt-[0-9]|openai|claude\s+(code|opus|sonnet|haiku)|noreply@anthropic\.com)|generated with\s+\[?(claude|copilot|cursor)|🤖\s*generated with)/i;

/** Custom plugin rules. */
const conventionPlugin = {
  rules: {
    'jira-key-present': ({ raw }) => [
      JIRA_RE.test(raw || ''),
      `add a Jira key (e.g. ${KEYS[0] || 'PROJ'}-123) in the subject or footer — e.g. "Jira: ${KEYS[0] || 'PROJ'}-123"`,
    ],
    'no-ai-coauthor': ({ raw }) => [
      !AI_TRAILER_RE.test(raw || ''),
      'remove the AI-authorship trailer (no Co-Authored-By: Claude/Copilot/… or "Generated with") — commit as the human author',
    ],
  },
};

module.exports = {
  extends: ['@commitlint/config-conventional'],
  plugins: [conventionPlugin],
  rules: {
    // Conventional Commits types. `style` kept but discouraged.
    'type-enum': [
      2,
      'always',
      ['feat', 'fix', 'refactor', 'perf', 'test', 'docs', 'chore', 'style', 'ci', 'build', 'revert'],
    ],
    'type-case': [2, 'always', 'lower-case'],
    'type-empty': [2, 'never'],
    'scope-case': [2, 'always', 'kebab-case'],
    // Subject 10..72 incl. header; config-conventional defaults to 100 — tighten to 72.
    'header-max-length': [2, 'always', 72],
    'subject-empty': [2, 'never'],
    'subject-min-length': [2, 'always', 10],
    'subject-full-stop': [2, 'never', '.'],
    // Subject is an imperative, capitalized ("Add", "Fix") — disable the case lock.
    'subject-case': [0],
    // Body should explain WHY — nudge a blank line + non-trivial body.
    'body-leading-blank': [1, 'always'],
    'body-min-length': [1, 'always', 1],
    // Jira key — WARN by default (nudge). Flip to 2 for a hard gate.
    'jira-key-present': [1, 'always'],
    // AI-authorship trailers — BLOCK (commit as the human author).
    'no-ai-coauthor': [2, 'always'],
  },
};
