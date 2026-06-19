---
name: dependency-and-supply-chain
description: Use when adding or upgrading a library, auditing for CVEs or license conflicts, pinning and locking versions, deciding whether to adopt a dependency, or responding to a supply-chain advisory.
---

# Dependency and Supply Chain

Every dependency is code you ship but did not write and cannot fully see. Treat each one as a long-term liability with a maintenance cost, an attack surface, and a license obligation — not a free win. The cheapest dependency is the one you never add.

## Step 1: Decide whether to adopt at all

Run the adopt/reject gate before touching a manifest. Reject if any answer is bad.

- **Can I do it in <50 lines myself?** A left-pad, a debounce, a slugify — copy a vetted snippet instead of taking a transitive tree.
- **How big is the tree?** Inspect the real cost, not the top-level name.
  ```bash
  npm view <pkg> dependencies          # direct deps
  npx howfat <pkg>                      # install size + transitive count
  dart pub deps --style=tree            # Dart/Flutter transitive graph
  ```
- **Is it alive?** Last release date, open-vs-closed issue ratio, single-maintainer risk, commit cadence in the last 12 months.
- **Does it fit the platform?** A Flutter package must support every target you ship (iOS, Android, web, desktop). Check the platform matrix, not just the pub score.
- **License compatible?** See Step 4 before adoption, not after.

Red flags that should stop adoption: zero releases in 18+ months, one maintainer with no successor, a postinstall script, an unexplained native binary, or a download count that does not match the marketing.

## Step 2: Pin and lock deterministically

Two different concerns: the **range** you declare (intent) and the **lockfile** you commit (the exact resolved graph).

- Commit the lockfile always: `package-lock.json` / `pnpm-lock.yaml` for TypeScript, `pubspec.lock` for Flutter **apps** (libraries stay loose so consumers can resolve).
- Declare conservative ranges. Caret is fine for libraries you trust; pin exact for anything security-sensitive or that has burned you.
  ```yaml
  # pubspec.yaml — caret allows 1.x but not 2.0
  dependencies:
    dio: ^5.4.0
    some_risky_pkg: 2.1.3   # exact pin: no surprise minors
  ```
- In CI, install from the lockfile, never re-resolve:
  ```bash
  npm ci                  # fails if package.json and lockfile disagree
  dart pub get --enforce-lockfile
  ```
- Enable integrity verification. npm lockfiles carry `integrity` hashes; do not strip them. Reject PRs that regenerate the whole lockfile for a one-line change.

## Step 3: Audit for known vulnerabilities

Scan on every install and on a schedule (advisories land after you ship, not before).

```bash
npm audit --audit-level=high          # gate CI on high+ severity
pnpm audit --prod                     # ignore dev-only noise where appropriate
dart pub outdated                     # surfaces upgradable + discontinued
osv-scanner --lockfile=pubspec.lock   # cross-ecosystem CVE scan, incl. Dart
```

Wire this into [[ci-cd-and-automation]] as a blocking job. Triage by reachability, not raw severity:

1. **Is the vulnerable code path reachable?** A prototype-pollution CVE in a build-only tool that never runs at runtime is lower priority than a parsing CVE in your request path.
2. **Is a fix released?** If yes, upgrade (Step 5). If no, evaluate an override/resolution or a temporary patch.
3. **No fix, reachable, severe?** Pin a forked/patched version, isolate the call behind your own boundary, or rip it out.

Suppress a finding only with a written, time-boxed reason — never a blanket ignore.

## Step 4: Check licenses before they bind you

License problems are discovered at the worst time (a deal, an audit). Enforce a policy automatically.

```bash
npx license-checker --summary --excludePackages "your-own-pkg"
dart pub global run license_checker    # or a CI license-scan action
```

- **Permissive (MIT, BSD, Apache-2.0):** generally fine. Apache-2.0 adds a patent grant — usually a plus.
- **Weak copyleft (MPL-2.0, LGPL):** file-level obligations; usually fine for dynamic linking, risky if statically bundled into a mobile app.
- **Strong copyleft (GPL, AGPL):** AGPL in a network service can force you to release your own source. Default to reject for proprietary work.
- **No license / "UNLICENSED" / custom:** treat as all-rights-reserved. Do not ship it.

Maintain an allowlist in CI so a disallowed license fails the build instead of a human noticing later.

## Step 5: Upgrade safely

Upgrade often in small steps — stale dependencies are harder and riskier to move than fresh ones.

- **Patch/minor:** batch them, run the full test suite, read the changelog for anything labeled "breaking" despite the version.
- **Major:** one dependency per change. Read the migration guide first. Land it isolated so a regression bisects cleanly.
- **Automate the boring part:** a bot that opens grouped patch PRs is good; auto-merging majors is not. Require green CI plus the audit gate on every bump.
- Diff the lockfile, not just the manifest — a one-line manifest bump can pull a dozen new transitive packages.

```bash
npm outdated                          # what's behind
dart pub upgrade --major-versions     # apply major bumps deliberately
```

Defer the commit itself to [[commit-pipeline]].

## Step 6: Respond to a supply-chain advisory

When a package you depend on is reported as compromised (typosquat, hijacked maintainer, malicious version), move fast and assume breach.

1. **Scope it.** Which versions are bad, and do any of your lockfiles resolve to them? `grep` the lockfile for the exact version string.
2. **Contain.** Pin away from the bad version immediately; if the whole package is compromised, remove it and clear caches (`rm -rf node_modules ~/.pub-cache/...`) before reinstalling.
3. **Assess exposure.** Did a malicious postinstall run on a dev machine or CI? If so, rotate every credential that machine could read — defer to [[secrets-and-config-management]] for rotation.
4. **Rebuild from clean state** and re-scan (Step 3) to confirm the bad version is gone from the resolved graph.
5. **Record it.** Note the incident and the new constraint so it cannot creep back.

## Hardening the supply chain

- Pin CI actions/images to a digest, not a moving tag, so a re-tag cannot swap code under you.
- Restrict install scripts where the ecosystem allows (e.g. `npm config set ignore-scripts true`, allowlisting only the few that need them).
- Generate an SBOM (`syft`, `cyclonedx`) per release so you can answer "are we affected?" in minutes, not days.
- Prefer first-party Supabase/official SDKs over community wrappers for anything touching auth or data access.

## Red flags

- A lockfile change far larger than the manifest change in a PR.
- A dependency added "to save 20 lines" that drags in 40 transitive packages.
- `npm audit` ignored because "they're all dev deps" without checking reachability.
- Pinning to a fork with no upstream tracking and no plan to return.
- A new package with high downloads but a name one character off a popular one (typosquat).
- License field empty, or changed between two minor versions.
