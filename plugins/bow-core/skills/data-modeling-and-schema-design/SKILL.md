---
name: data-modeling-and-schema-design
description: Triggers when creating or altering tables, choosing normalization vs denormalization, modeling relationships and cardinality, picking keys and constraints, or designing a schema that must evolve without breaking consumers.
---

# Data Modeling and Schema Design

A schema is a contract that outlives the code reading it. Design for the access patterns you have and the migrations you will need, not for theoretical purity.

## 1. Pin down the domain before drawing tables

- List the **entities** (nouns the business cares about) and the **events** (things that happen). Events usually become append-only tables; entities become mutable rows.
- For each entity write its **identity rule**: what makes two rows the same thing? That rule becomes your natural key or uniqueness constraint, even if you store a surrogate key alongside.
- Capture the **top 5 read queries** and the **top 5 write paths** in plain sentences. Model toward those. A schema with no known query is a guess.

Red flag: you cannot name a single query that a table serves. Stop and find the consumer.

## 2. Pick keys deliberately

- Default to a **surrogate primary key**. Prefer `uuid` (specifically time-sortable like `uuidv7`) over `bigserial` when rows are created across clients/devices or exposed in URLs. Sequential integers leak volume and invite enumeration.
- Always declare the **natural key as a separate `UNIQUE` constraint**. The surrogate is for joins; the unique constraint protects the data.
- Composite keys belong on **join/junction tables**, not as the primary identity of a core entity.

```sql
create table memberships (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references orgs(id) on delete cascade,
  user_id     uuid not null references users(id) on delete cascade,
  role        text not null,
  created_at  timestamptz not null default now(),
  unique (org_id, user_id)            -- natural key, enforced
);
```

## 3. Model relationships by cardinality

- **1:N** — foreign key on the child (`order.customer_id`). Decide the delete behavior explicitly: `cascade`, `set null`, or `restrict`. Never leave it to the default.
- **N:N** — a junction table with its own row. Add columns to it the moment the relationship itself has attributes (joined-at, role, weight).
- **1:1** — rare and usually a smell. Justify it (column-level access control, optional heavy blob, slow-changing extension). Otherwise inline the columns.
- **Polymorphic "belongs to many types"** — avoid a `target_type`/`target_id` pair with no FK. Prefer separate nullable FK columns with a check constraint, or separate join tables. You lose referential integrity with the loose pair.

```sql
-- One nullable FK column per allowed parent, exactly one must be set:
alter table comments add constraint one_parent check (
  num_nonnulls(post_id, photo_id) = 1
);
```

## 4. Normalize first, denormalize on evidence

- Start at **3NF**: every non-key column depends on the key, the whole key, and nothing but the key. This is the safe default and the easiest to evolve.
- Denormalize only when a real, measured read pattern demands it. When you do:
  - Treat the duplicate as a **cache**, not a source of truth.
  - Keep it correct with a **trigger** or a derived/generated column, never application code scattered across call sites.
  - Document the source column it derives from.

```sql
-- Generated column: derivation lives in the schema, can't drift.
alter table invoices
  add column total_cents bigint
  generated always as (subtotal_cents + tax_cents) stored;
```

Red flag: the same fact is updated in two places by hand. That fact will diverge.

## 5. Constrain at the database, not just the app

The database is the last line of defense and the only one that survives a buggy client.

- `NOT NULL` is a decision, not a default. Make every column justify nullability.
- Encode enums as a lookup table with an FK, or a `CHECK (... in (...))`. Prefer a lookup table when values carry metadata or change at runtime.
- Use `CHECK` for invariants (`amount >= 0`, `ends_at > starts_at`).
- Add **partial unique indexes** for conditional uniqueness (e.g. one active row per user).

```sql
create unique index one_default_address_per_user
  on addresses (user_id) where is_default;
```

## 6. Timestamps, soft deletes, and tenancy

- Every table gets `created_at` and `updated_at` (`timestamptz`, UTC). Keep `updated_at` fresh with a trigger.
- Prefer hard deletes plus an audit/event table over a `deleted_at` flag smeared across every query. If you must soft-delete, add partial indexes that exclude deleted rows so they stay fast.
- For multi-tenant data, put `org_id`/`tenant_id` on every owned table and enforce isolation with **Row Level Security**, not just `WHERE` clauses in the client.

```sql
alter table memberships enable row level security;
create policy member_reads_own_org on memberships
  for select using (org_id = (select auth.org_id()));
```

## 7. Design for evolution (expand / contract)

Schema changes ship before all consumers update. Never break a column out from under a live reader.

1. **Expand** — add the new column/table, nullable or with a default. Backfill in batches.
2. **Migrate** — dual-write old and new; update readers to prefer new.
3. **Contract** — once no reader uses the old shape, drop it in a later migration.

- Rename = add new + backfill + switch + drop. A bare `RENAME COLUMN` is a breaking change.
- Adding a `NOT NULL` column to a populated table: add nullable, backfill, then set `NOT NULL`.
- One concern per migration; migrations are forward-only and immutable once merged.

## 8. Keep the type layer in sync

- After every schema change regenerate the typed client so the application catches drift at compile time:
  - `supabase gen types typescript --linked > src/types/db.ts`
  - In Dart/Flutter, regenerate the generated models/serializers (e.g. `dart run build_runner build --delete-conflicting-outputs`) so the data layer matches.
- A schema change that does not update generated types is incomplete. See [[data-modeling-and-schema-design]] for the data-layer mapping conventions.

## Pre-merge checklist

- [ ] Every table has a primary key and an explicit `created_at`/`updated_at`.
- [ ] Natural keys enforced with `UNIQUE`; surrogate key used for joins.
- [ ] Every FK declares its `ON DELETE` behavior intentionally.
- [ ] Nullability and `CHECK` invariants are deliberate, not accidental.
- [ ] Tenant tables have RLS, not just client-side filters.
- [ ] Migration follows expand/contract; no in-place rename or surprise `NOT NULL`.
- [ ] Generated types regenerated and committed.
- [ ] Commit per [[commit-pipeline]] (Conventional Commits + gitmoji).

## Red flags

- A column named `data` or `meta` holding unindexed JSON that something filters on.
- Booleans multiplying (`is_active`, `is_archived`, `is_draft`) where one `status` enum belongs.
- Foreign keys stored as `text` instead of the referenced key type.
- "We'll add the constraint later" — later is after the bad data is in.
- A migration that both adds and drops in the same step against a live table.
