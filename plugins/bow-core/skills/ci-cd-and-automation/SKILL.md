---
name: ci-cd-and-automation
description: Sets up and maintains automated build, test, and deploy pipelines. Trigger when creating or changing CI workflows, enforcing quality gates in CI, configuring test runners or deploy stages, or debugging a failing pipeline.
---

# CI/CD and Automation

## Overview

CI/CD is where every other engineering rule gets enforced automatically, on every change, without anyone remembering to. It is the machine that says "no" consistently — to broken builds, failing tests, type errors, and risky merges.

Two principles drive the design:

- **Push failures left.** The earlier a problem is caught, the cheaper it is. A lint error caught in seconds is free; the same defect found in production costs hours. Order the pipeline so cheap, broad checks run before slow, narrow ones.
- **Small and frequent beats big and rare.** A deploy of three changes is trivial to diagnose; a deploy of thirty is an investigation. Frequent releases shrink the blast radius and build trust in the release process itself.

## When to Use

- Bootstrapping CI on a new project
- Adding or changing automated checks
- Configuring deploy stages
- Wanting a change to trigger automatic verification
- Diagnosing why CI is failing

## The Quality Gate Sequence

Each change clears these, cheapest first, before it can merge:

```
PR opened
   -> format + lint        (fast, catches most noise)
   -> type check
   -> unit tests
   -> build
   -> integration tests    (DB / API)
   -> e2e                   (optional, heavier)
   -> dependency audit
   -> bundle-size budget
   => ready for review
```

A failing gate is fixed, never bypassed. Lint fails? Fix the code, don't disable the rule. Test fails? Fix the cause, don't skip the test.

## A Baseline Pipeline (GitHub Actions)

```yaml
# .github/workflows/ci.yml
name: ci
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npx tsc --noEmit
      - run: npm test -- --coverage
      - run: npm run build
      - run: npm audit --audit-level=high
```

### Flutter variant

```yaml
  flutter-checks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable, cache: true }
      - run: flutter pub get
      - run: dart format --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test --coverage
```

### Integration tests against a real Postgres

```yaml
  integration:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_DB: testdb
          POSTGRES_USER: ci
          POSTGRES_PASSWORD: ${{ secrets.CI_DB_PASSWORD }}
        ports: ['5432:5432']
        options: >-
          --health-cmd pg_isready --health-interval 10s
          --health-timeout 5s --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '22', cache: npm }
      - run: npm ci
      - run: npx supabase db push    # apply local migrations to the test DB
        env:
          DATABASE_URL: postgresql://ci:${{ secrets.CI_DB_PASSWORD }}@localhost:5432/testdb
      - run: npm run test:integration
        env:
          DATABASE_URL: postgresql://ci:${{ secrets.CI_DB_PASSWORD }}@localhost:5432/testdb
```

Even a throwaway CI database gets its password from a secret, never a literal. It keeps the habit clean and stops test credentials leaking into other contexts.

## Closing the Loop with an Agent

The real leverage of CI plus an agent is the tight feedback cycle. When the pipeline goes red:

```
CI red -> grab the exact failing output -> hand it to the agent verbatim:
  "CI failed with:
   <paste the precise error>
   Fix it and confirm locally before pushing again."
-> agent fixes -> pushes -> CI reruns
```

Routing by failure type:

```
lint    -> run the auto-fixer, then commit the result
types   -> jump to the error location, correct the type
test    -> hand off to debugging-and-error-recovery
build   -> inspect config and dependency versions
```

## Deploy Strategies

**Preview per PR.** Spin up an ephemeral deployment for each pull request so reviewers test the real thing, not a description of it.

**Feature flags** decouple deploy from release: merge code dark, switch it on when ready, disable to roll back without a redeploy, and ramp gradually for canaries or experiments. Give every flag a creation note and a removal date — a flag that outlives its purpose is debt. Rollout sequencing and ramp thresholds live in `shipping-and-launch`.

**Staged promotion:**

```
merge to main
  -> auto-deploy to staging
  -> manual verification
  -> promote to production (manual gate or auto-after-staging)
  -> watch errors ~15 min
       red  -> roll back
       clean -> done
```

**Rollback workflow** — every deploy must be reversible:

```yaml
name: rollback
on:
  workflow_dispatch:
    inputs:
      version: { description: 'version to roll back to', required: true }
jobs:
  rollback:
    runs-on: ubuntu-latest
    steps:
      - run: ./scripts/deploy.sh --rollback "${{ inputs.version }}"
```

## Secrets and Environments

```
.env.example     committed   template, no real values
.env             ignored     local dev
.env.test        committed   test config, no real secrets
CI secrets       vault       GitHub Secrets / secret manager
prod secrets     vault       deployment platform / secret manager
```

CI must never hold production secrets — give it its own scoped set.

## Automation Beyond the Pipeline

**Dependency bots** (Dependabot / Renovate) open scheduled update PRs that ride through the same gates:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule: { interval: weekly }
    open-pull-requests-limit: 5
```

**Keep-green ownership.** Make one person responsible at any time for restoring a broken main — fix or revert. Without a clear owner, a red build lingers while everyone assumes someone else has it.

**Branch protection.** Require at least one approval, require all status checks, forbid force-push to main, and allow auto-merge once checks pass and the review lands. Branch and commit conventions are owned by `commit-pipeline`.

## When CI Gets Slow

Past ~10 minutes, apply in order of payoff:

```
1. cache dependencies          (setup-node/flutter cache, restore node_modules)
2. parallelize jobs            (lint / typecheck / test / build as separate jobs)
3. run only what changed       (path filters: skip e2e on docs-only PRs)
4. shard tests across runners  (matrix split of the test suite)
5. move slow tests off the critical path (run them on a schedule)
6. use bigger runners          (last resort, for CPU-bound builds)
```

## Common Rationalizations

| Excuse | Reality |
|---|---|
| "CI is too slow" | Optimize it (see above); don't skip it. Minutes in CI save hours debugging. |
| "This change is trivial" | Trivial changes break builds, and CI is fast on trivial changes anyway. |
| "The test is flaky, just rerun" | Flakiness hides real bugs and burns everyone's time. Fix the flake. |
| "We'll add CI later" | Projects without CI rot into broken states. Set it up on day one. |
| "Manual testing covers it" | Manual testing isn't repeatable and doesn't scale. Automate what you can. |

## Red Flags

- No pipeline at all
- Red CI ignored or muted
- Tests disabled to make the pipeline pass
- Production deploys with no staging step
- No rollback path
- Secrets in code or workflow files instead of a vault
- A long pipeline nobody has tried to speed up

## Verification

- [ ] All gates present: format, lint, types, tests, build, audit
- [ ] Runs on every PR and on push to main
- [ ] Failing checks block merge (branch protection on)
- [ ] CI output feeds back into the dev loop
- [ ] Secrets come from a vault, not source
- [ ] A rollback mechanism exists
- [ ] Test pipeline finishes under ~10 minutes
