---
name: multi-tenancy-design
description: Trigger when building software that serves multiple customers/orgs — tenant isolation, data partitioning, per-tenant config/limits, and noisy-neighbor prevention.
---

# Multi-Tenancy Design

A workflow for making the irreversible early decisions correctly: how tenants are isolated, where their data lives, and how one tenant cannot starve or read another.

## Step 1 — Name the tenant and the boundary

Before any schema, answer in one sentence each:

- **What is a tenant?** A company? A workspace? A user? Pick the billing/ownership unit, not the login unit.
- **Can one user belong to many tenants?** If yes, identity and tenant are separate axes — never fold `tenant_id` into the user row.
- **What is the cross-tenant case?** Support staff, analytics, a parent org rolling up children. List them now; they break naive isolation later.

Red flag: you cannot state the tenant unit without using the word "and". Split it.

## Step 2 — Choose the isolation model

| Model | Isolation | Cost | Use when |
|---|---|---|---|
| Shared schema, `tenant_id` column | Logical (row-level) | Lowest | Many small tenants, SaaS default |
| Schema-per-tenant | Strong-ish | Medium | Tens–hundreds of tenants, per-tenant migrations |
| Database/project-per-tenant | Physical | Highest | Few large tenants, compliance/residency, hard noisy-neighbor limits |

Default to **shared schema + row-level security** and only escalate per tenant when a contract demands it. Hybrid is normal: pool the long tail, isolate the whales.

Decision points:
- Regulatory data residency or "no shared infra" clause → physical isolation for those tenants.
- Wildly uneven tenant sizes → hybrid (pooled pool + dedicated for the top few).
- Otherwise → pooled.

## Step 3 — Enforce isolation at the lowest layer possible

Application-layer `WHERE tenant_id = ?` is a single forgotten clause away from a cross-tenant leak. Push enforcement into the database.

With Supabase/Postgres, make every tenant table carry `tenant_id` and gate it with RLS keyed off the JWT — not off a value the client sends.

```sql
alter table public.invoices enable row level security;

-- tenant_id is read from the verified JWT claim, never from the request body
create policy tenant_isolation on public.invoices
  using (tenant_id = (auth.jwt() ->> 'tenant_id')::uuid)
  with check (tenant_id = (auth.jwt() ->> 'tenant_id')::uuid);
```

Rules:
- `with check` is mandatory — `using` alone blocks reads but lets a client *write* another tenant's `tenant_id`.
- Put the tenant claim into the token at sign-in (custom claim / auth hook), so it is signed and unforgeable.
- Make `tenant_id` `not null` and add `(tenant_id, ...)` as the leading column of every index.

Red flag: any query that runs as `service_role` against tenant tables. The service key bypasses RLS — treat it like root and never expose it to per-request code paths.

## Step 4 — Carry tenant context end to end

Resolve the tenant once at the edge, then make it ambient. Never re-derive it from request bodies downstream.

```typescript
// Edge function: resolve tenant from the verified token, attach to context.
type Ctx = { tenantId: string; userId: string; role: string };

function tenantContext(jwt: VerifiedJwt): Ctx {
  const tenantId = jwt.claims.tenant_id;
  if (!tenantId) throw new ForbiddenError("no tenant in token");
  return { tenantId, userId: jwt.sub, role: jwt.claims.role };
}
```

In Flutter/Dart, hold tenant context in a single provider/scope, not scattered in widgets. Every repository call takes the context or reads it from one source.

```dart
class TenantScope {
  const TenantScope(this.tenantId);
  final String tenantId;
}

// Repositories never accept a raw tenantId from the UI; they read the scope.
class InvoiceRepository {
  InvoiceRepository(this._db, this._scope);
  final SupabaseClient _db;
  final TenantScope _scope;

  Future<List<Invoice>> list() async {
    // RLS is the real guard; this filter is defense-in-depth + query planning.
    final rows = await _db.from('invoices').select().eq('tenant_id', _scope.tenantId);
    return rows.map(Invoice.fromJson).toList();
  }
}
```

## Step 5 — Per-tenant configuration and feature flags

Keep a single `tenant_settings` table; do not branch code on tenant name.

```sql
create table public.tenant_settings (
  tenant_id   uuid primary key references tenants(id),
  plan        text not null default 'free',
  features    jsonb not null default '{}'::jsonb,
  limits      jsonb not null default '{}'::jsonb  -- e.g. {"seats": 5, "rps": 20}
);
```

- Resolve config = plan defaults merged with per-tenant overrides. Compute once per request, cache by `tenant_id` with a short TTL.
- Feature flags are data, not deploys. A new tenant on a higher plan should "just work".

Red flag: `if (tenant.id == '...')` anywhere in the codebase.

## Step 6 — Prevent the noisy neighbor

One tenant must not consume the shared budget. Enforce limits *per tenant*, not globally.

- **Rate limiting:** key the limiter by `tenant_id` (or `tenant_id:endpoint`), not by IP. Use a token bucket; read the rate from `tenant_settings.limits`.
- **Concurrency / queues:** give each tenant a bounded slice of workers, or a fair-share scheduler. A single tenant's 10k-job import cannot block everyone else.
- **DB protection:** set `statement_timeout` per role; cap page sizes; require keyset pagination on tenant-scoped lists.
- **Storage/quota:** track counts per tenant and reject writes past the plan limit with a clear `402/429`, not a silent failure.

```typescript
async function allow(tenantId: string, cost = 1): Promise<boolean> {
  const { rps } = await limitsFor(tenantId);          // per-tenant, from settings
  return tokenBucket.consume(`rl:${tenantId}`, rps, cost);
}
```

## Step 7 — Test isolation as a first-class concern

- Write a cross-tenant test: authenticate as tenant A, attempt to read/write tenant B's row by id, assert it fails. Run it per table.
- Property test: every new tenant table must have RLS enabled and a `with check` policy — fail CI if a migration adds a tenant table without one.
- Seed at least two tenants in every fixture so a missing filter surfaces immediately.
- Load test with one "whale" tenant hammering an endpoint; assert other tenants' latency stays within SLO.

## Migrations and data lifecycle

- Migrations run for all pooled tenants at once; for schema/db-per-tenant, run a fan-out with per-tenant status tracking and idempotency.
- Tenant deletion: define hard-delete vs. soft-delete up front. Hard delete must purge across every table, storage bucket, and backup-retention policy — wire it as one routine, not ad hoc.
- Tenant export: support per-tenant data export early; enterprise contracts demand it.

## Red flags summary

- `tenant_id` derived from request body instead of the signed token.
- RLS policy with `using` but no `with check`.
- `service_role` used in request-handling code.
- Code branching on a specific tenant id or name.
- Global rate limits / unbounded queues shared across tenants.
- Single-tenant fixtures hiding missing filters.

## Related

- [[data-modeling-and-schema-design]] — data-layer conventions for tenant-scoped tables and repositories.
- [[commit-pipeline]] — when committing schema/RLS changes (Conventional Commits + gitmoji).
