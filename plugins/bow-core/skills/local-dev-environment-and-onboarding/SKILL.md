---
name: local-dev-environment-and-onboarding
description: Triggers when setting up reproducible local development — one-command setup, seed data, service stubs, prod parity, and shrinking new-engineer time-to-first-commit.
---

# Local dev environment and onboarding

The metric is **time-to-first-commit**: from a fresh laptop to a merged change. Optimize for that, not for documentation length. Every manual step in a README is a step that rots and a question in chat. Move the README into a script.

## Decide the boundary first

Before writing setup, choose what runs locally vs. what is faked:

| Dependency | Default choice | Why |
|---|---|---|
| Postgres / Supabase | Run locally (container) | Schema and RLS must match prod; cheap to run |
| Object storage / queues | Local emulator | Behavior parity matters more than fidelity |
| Third-party APIs (payments, email, SMS) | **Stub**, never live | No real charges, no flaky network, deterministic tests |
| Internal microservices | Stub or shared dev instance | Running 12 services locally is a tax nobody pays |

Red flag: onboarding requires real credentials for a paid third party. New engineers should reach a running app with **zero secrets they had to request**.

## The one-command setup

Aim for a single entrypoint that is **idempotent** — safe to run twice, repairs a half-broken state. Make a thin `Makefile` or `justfile` the front door regardless of stack.

```makefile
# justfile
setup: check-tools env-file db-up db-reset seed gen-types
	@echo "Ready. Run 'just dev' to start the app."

check-tools:
	@command -v supabase >/dev/null || { echo "Install supabase CLI"; exit 1; }
	@flutter --version >/dev/null || { echo "Install Flutter"; exit 1; }

env-file:
	@test -f .env || cp .env.example .env

db-up:
	supabase start

db-reset:
	supabase db reset   # re-applies all migrations + seed.sql, deterministically

gen-types:
	supabase gen types typescript --local > apps/web/src/db.types.ts
	dart run build_runner build --delete-conflicting-outputs
```

Rules:
- **Pin tool versions.** Check exact versions in `check-tools` (`.tool-versions`, `flutter --version`, a CLI version gate). "Works on my machine" is almost always a version drift.
- **`.env.example` is committed and complete.** Every key the app reads has a placeholder. Missing keys fail loudly at boot, not at the first request.
- The setup must **end in a working app**, not "now manually do X."

## Seed data that mirrors reality

Seed data is a product. Bad seed data (`user1`, `test test`, one row) hides bugs that only appear with real shapes — long names, emoji, null optionals, timezones, large lists.

```sql
-- supabase/seed.sql — runs on every `db reset`, must be idempotent
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'owner@example.test'),
  ('00000000-0000-0000-0000-000000000002', 'member@example.test')
on conflict (id) do nothing;

-- Cover the awkward cases on purpose
insert into public.projects (id, owner, name, archived_at) values
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 'Tiny', null),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', 'Ünïcødé 🚀 — a deliberately long name', null),
  (gen_random_uuid(), '00000000-0000-0000-0000-000000000002', 'Archived', now());
```

Guidelines:
- **Use fixed UUIDs for anchor records** so tests and manual flows can reference them.
- Seed enough to exercise pagination, empty states, and authorization (one row each user owns, one they cannot see).
- Keep seed data **derived from one script**, not hand-edited DB snapshots that drift.
- Never seed production data dumps — PII leaks into laptops. Generate synthetic data instead. See [[data-privacy-and-compliance]].

## Stubbing third parties

Real external calls make onboarding flaky and tests non-deterministic. Stub at the boundary you own.

```typescript
// One interface, two implementations chosen by env.
export interface PaymentGateway {
  charge(cents: number, token: string): Promise<{ id: string }>;
}

export const payments: PaymentGateway =
  process.env.PAYMENTS_MODE === "live"
    ? new LivePaymentGateway(process.env.PAYMENTS_KEY!)
    : new FakePaymentGateway(); // returns deterministic ids, no network
```

In Flutter, the same pattern: an abstract class with a `FakeXClient` selected by a build flavor or env. Wire the fake by default in dev. Red flag: a stub that diverges silently from the real contract — pin it with [[contract-testing]] so the fake stays honest.

## Prod parity — and where to stop

Parity reduces "works locally, breaks in prod." Match what changes behavior; ignore what only changes scale.

**Match:** database engine and major version, schema + RLS policies, migration path, runtime language versions, feature-flag defaults, timezone handling (run local DB in UTC).

**Do not match:** replica counts, instance sizes, real CDNs, multi-region. Faking these costs more than it catches.

Run the **same migrations** locally that run in prod — never a separate "dev schema." If `supabase db reset` and the prod migration history can diverge, parity is already broken. See [[zero-downtime-database-migrations]].

## The onboarding doc is a checklist, not an essay

Keep a short `CONTRIBUTING` that links to the script, not a 40-step manual:

```
1. Install prerequisites: see `.tool-versions`
2. Run `just setup`
3. Run `just dev`, open the app, log in as owner@example.test
4. Make a trivial change, run `just check`, open a PR
```

The genuine onboarding test: **a new engineer ships a one-line change on day one** with no human unblocking them. Time it. If they got stuck, the fix is to the script, not to the wiki page.

## Verification gate

Before calling setup "done," run it on a clean machine (or a fresh container) and confirm:

- [ ] `just setup` from zero succeeds with no manual steps and no requested secrets.
- [ ] Running `just setup` twice is safe (idempotent).
- [ ] The app boots and a seeded login works.
- [ ] `just check` (lint + types + tests) passes green on a fresh checkout.
- [ ] Generated artifacts (`*.g.dart`, `db.types.ts`) regenerate, not committed-and-stale.
- [ ] No external paid API is contacted in dev mode.

Automate this in CI as a "cold start" job so the setup path can never silently break. See [[ci-cd-and-automation]].

## Common failure modes

- **Snowflake laptops.** One engineer's machine has an undocumented global install. Fix: pin in `check-tools`, verify in the cold-start CI job.
- **Stale generated code.** Someone edited a `.g.dart` by hand. Fix: regenerate in `setup`, gitignore or CI-verify cleanliness.
- **Seed rot.** Seed references a dropped column. Fix: `db reset` runs in CI on every migration.
- **Hidden ordering.** Setup only works if you run steps in a secret order. Fix: one entrypoint with explicit dependencies.
- **Secret sprawl.** `.env.example` drifts from what the code reads. Fix: fail at boot on any missing required key.

## Commit

When committing setup scripts, seed files, or onboarding docs, follow [[commit-pipeline]] — Conventional Commits with a gitmoji, no AI-authorship trailer.
