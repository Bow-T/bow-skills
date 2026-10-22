# Store review readiness — report template

Copy this, fill it in, and lead with the verdict. One line per finding; never merge two findings.

```markdown
# <App> <version> (<build>) — store review readiness, <YYYY-MM-DD>

**Verdict:** READY / NOT READY — <the blockers in one sentence, if any>.

Scope: iOS <yes/no>, Android <yes/no>. Built from `<commit>` on `<branch>`.
Last approved build: <build> (<date>). Past rejections: <guidelines, or none>.

## Rejection items (only when answering a rejection)

| # | Guideline (as cited) | Status | Evidence | Owner |
|---|---|---|---|---|
| 1 | 2.1(b) IAP not submitted | ❌ | — | console |
| 2 | 4 — name asked after Sign in with Apple | ✅ | `abc123`, test `apple_sign_in_test` | code |

## Findings

| Severity | Area | Finding | Evidence | Fix | Owner | Status |
|---|---|---|---|---|---|---|
| Blocker | Apple 3.1.1 | Referral code lowers the price on iOS | `revenuecat_service.dart:160` | Attribution only on iOS; offer codes | decision → code | ✅ `def456` |
| High | Apple 2.1(a) | Quit button dimmed and inert on the ready screen | `session_page.dart:150` | Always enabled | code | ⚠ fixed, not tested on device |

Status: ✅ evidence attached · ⚠ fixed but unverified (say why) · ❌ open.

## Console checklist

- [ ] <App Store Connect / Play Console action> — owner: <name>

## Review notes (draft)

- Demo account: <email / password>, with <paid plan> active.
- How to reach <feature>: <steps>.
- <Anything that looks unusual but is intended: partner accounts, referral codes that only credit, hardware needs.>

## QA handoff

- Build: <version (build)>, from `<branch/commit>`; how to tell it has the fixes: <visible change>.
- Test on: <devices incl. an iPad>, fresh install, permissions denied, sandbox account <with/without trial>.
- Re-test: <one line per item>.

## Verification run

- Gates: `<analyze/test commands>` → <result>.
- Sweep: `store-sweep.sh` → <n> leads, <n> confirmed.
- Not verified: <what, and why>.
```
