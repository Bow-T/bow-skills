---
name: monorepo-management
description: Trigger when structuring a multi-package repo — workspace layout, shared deps, affected-only builds/tests, codeowners, and cross-package versioning.
---

# Monorepo Management

A monorepo only pays off when the tooling makes "one change, many packages" cheap and safe. If builds aren't graph-aware and ownership is fuzzy, you've just built a slow, tangled multi-repo with extra steps. Optimize for: fast affected-only CI, explicit dependency edges, and clean release boundaries.

## Step 0 — Decide if you even need one

Pick a monorepo when packages ship together, share types/contracts, or refactor in lockstep. Stay multi-repo when teams release on independent cadences with stable public APIs.

Red flag: "we want a monorepo for code search." That's a tooling problem, not a repo-structure problem.

## Step 1 — Lay out the workspace

Group by *role*, not by team. Keep deployable units and shared libraries clearly separated.

```
repo/
  apps/            # deployable units
    mobile/        # Flutter app
    admin-web/     # TS frontend
    edge/          # Supabase edge functions (Deno/TS)
  packages/        # shared libraries (TS)
    api-contracts/ # generated DB types + zod schemas
    ui-kit/
    config/        # shared tsconfig, eslint, lint rules
  dart_packages/   # shared Dart/Flutter packages
    core_models/
    design_system/
  supabase/        # migrations, seed, config.toml
  tools/           # repo scripts
```

Hard rules:
- One language family per workspace tool. JS/TS uses a JS package manager workspace; Dart uses a Dart workspace tool. Don't force one runner to drive both — orchestrate at the CI layer instead.
- Every package gets a `name`, an explicit version, and a declared dependency list. No implicit "it's in the same repo so I'll import it" reaching across `../../`.

### TS workspace root

```jsonc
// package.json (root)
{
  "private": true,
  "workspaces": ["apps/*", "packages/*"],
  "packageManager": "pnpm@9"
}
```

### Dart workspace

```yaml
# pubspec.yaml (root)
name: _workspace
environment: { sdk: ">=3.6.0 <4.0.0" }
workspace:
  - apps/mobile
  - dart_packages/core_models
  - dart_packages/design_system
```

## Step 2 — Wire shared dependencies as graph edges

The dependency graph is the source of truth for builds, tests, and releases. Make it explicit and acyclic.

- Internal deps use workspace protocols, not version ranges, so changes are picked up locally:
  - TS: `"api-contracts": "workspace:*"`
  - Dart: `core_models: { path: ../../dart_packages/core_models }`
- Pin third-party versions **once** at the root (or a `config` package) and reference everywhere. Diverging versions of the same lib is how you get two copies in the bundle.
- Keep one lockfile per language workspace at the root. Never commit nested lockfiles.

Decision point — shared config: extract `tsconfig.base.json`, lint config, and formatter rules into a `packages/config` package that others extend. This kills config drift.

Red flag: a cycle in the package graph (`ui-kit` → `core` → `ui-kit`). The affected algorithm and release tooling both break on cycles. Add a CI check that fails on cycles.

## Step 3 — Affected-only builds and tests

Never run the whole repo on every PR. Compute the changed packages, then their reverse-dependents, and act only on that set.

Baseline algorithm:
1. Diff against the merge-base of the target branch (not `HEAD~1` — that misses squashed history).
2. Map changed files → owning packages.
3. Walk the reverse-dependency graph to include everything that imports a changed package.
4. Run `lint → typecheck → test → build` for that set, in topological order.

```bash
# affected packages since the PR branched
BASE=$(git merge-base origin/main HEAD)
CHANGED=$(git diff --name-only "$BASE"...HEAD)
# feed CHANGED into your graph tool to expand to affected packages
```

If you use a dedicated task runner, lean on its `--filter ...[origin/main]` (TS) / changed-package detection. Otherwise a ~60-line graph script is fine and worth owning.

Cache aggressively but **key the cache on inputs**: source hash + dependency-package hashes + tool versions. A cache keyed only on the package's own files will serve stale builds when a dependency changes. See [[caching-strategy]] and [[ci-cd-and-automation]].

Red flags:
- A green PR that didn't run the consumer of the file you changed → your affected graph is wrong.
- CI time grows linearly with repo size → you're not actually filtering; you're just sharding.

## Step 4 — Ownership and CODEOWNERS

Map directories to owners so reviews route automatically and "who owns this" is never a question.

```
# CODEOWNERS
/packages/api-contracts/   @data-platform
/dart_packages/            @mobile
/apps/admin-web/           @web
/supabase/migrations/      @data-platform @backend
*                          @maintainers       # fallback
```

Rules:
- Most-specific path wins; always keep a fallback owner so nothing is orphaned.
- Require owner approval for shared packages (`api-contracts`, `ui-kit`) — these are blast-radius hotspots.
- Cross-package PRs need every touched owner's approval. If that's constant friction, your package boundaries are wrong.

## Step 5 — Cross-package versioning and release

Choose a versioning model up front:

| Model | When | Trade-off |
|---|---|---|
| **Fixed/locked** (all packages share one version) | Tight-knit apps released together | Simple; noisy changelogs, version bumps for untouched packages |
| **Independent** (each package versions itself) | Reusable libraries with external consumers | Accurate semver; needs changeset tooling |

For independent versioning, require a **changeset** per PR that declares which packages changed and the bump level (patch/minor/major). Release then:
1. Aggregates pending changesets.
2. Bumps versions + updates internal dependents.
3. Generates per-package changelogs.
4. Publishes in topological order.

Internal consumers must move in the same release: bumping `api-contracts` to a major *must* bump the apps that depend on it. Validate this in CI — a published package whose internal dependents weren't rebuilt is a broken release.

Dart specifics: Flutter app version (`pubspec.yaml`) carries `build+number`; shared Dart packages get their own semver. Generate Supabase types into `packages/api-contracts` on schema change and treat a regenerated-types diff as an API change requiring a bump — coordinate with [[data-modeling-and-schema-design]].

For removing or relocating a shared package, follow [[deprecation-and-migration]]; for sweeping edits across many packages, see [[large-scale-refactoring]].

## Commits and releases

All commits (including version bumps and changesets) follow [[commit-pipeline]] — Conventional Commits with gitmoji. Scope the type to the package, e.g. `feat(ui-kit): …`, `chore(release): …`. Do not add AI-authorship trailers.

## Pre-merge checklist

- [ ] Affected set computed from merge-base, not a fixed offset.
- [ ] No new cycles in the package graph.
- [ ] Internal deps use workspace/path protocol; one lockfile per workspace.
- [ ] Third-party versions pinned once, not per-package.
- [ ] CODEOWNERS covers every touched path; shared-package changes have owner approval.
- [ ] Changeset present (independent model) and internal dependents bumped.
- [ ] Cache keys include dependency hashes, not just own-file hashes.

## Anti-patterns

- **Build-all-on-every-push** — defeats the point of a monorepo.
- **Phantom dependencies** — importing a package you didn't declare; works locally, breaks on isolated install.
- **Version skew** — two versions of the same third-party lib resolved in one app bundle.
- **God package** — a `common`/`utils` everything imports; it becomes a perpetual merge-conflict and forces the whole repo to rebuild on any change. Split by domain.
