---
name: zero-downtime-database-migrations
description: Trigger when changing a production schema under live traffic — adding/dropping columns, backfills, renames, or index builds without locks or downtime.
---

# Zero-Downtime Database Migrations

A live schema change has two clocks running at once: the migration and the app code that reads/writes the table. The golden rule: **old code and new code must both be valid against every intermediate schema state.** Never ship a migration and the code that depends on it in the same deploy.

## Core principle: expand → migrate → contract

Split every breaking change into three deploys that are each individually safe:

1. **Expand** — add the new shape (nullable column, new table, new index). Old code ignores it.
2. **Migrate** — backfill data + dual-write from app code so both old and new shapes stay correct.
3. **Contract** — once nothing reads the old shape, drop it.

Each phase is a separate PR and a separate release. If you cannot describe the rollback for a phase in one sentence, it is too big.

## Decision tree

```
Adding a column?              → nullable / has DEFAULT? safe. NOT NULL + no default? expand-migrate-contract.
Dropping a column?            → stop reading in code FIRST, deploy, then drop next release.
Renaming a column/table?      → NEVER rename in place. Add new, dual-write, backfill, cut over, drop old.
Changing a type?              → new column with new type, backfill, swap reads, drop old.
Adding an index?              → CONCURRENTLY, always.
Adding a constraint/FK?       → add NOT VALID, then VALIDATE in a second step.
Backfilling millions of rows? → batch it, off the migration transaction.
```

## Red flags — stop if you see these

- A single migration that both alters the schema **and** the deploy ships matching code. Split it.
- `ALTER TABLE ... ADD COLUMN ... NOT NULL` with no `DEFAULT` on a non-empty table → full rewrite + long `ACCESS EXCLUSIVE` lock.
- `CREATE INDEX` without `CONCURRENTLY` → blocks writes for the whole build.
- `UPDATE big_table SET ...` with no `WHERE` batching → one giant transaction, bloated WAL, lock contention.
- Renaming anything that running code still references.
- A migration that takes a lock and then waits on a slow sub-step while a queue of queries piles up behind it.

## Recipes

### Add a NOT NULL column (Postgres / Supabase)

A plain default is fast (metadata-only on modern Postgres), but combining NOT NULL + backfill of a *computed* value still needs the expand path.

```sql
-- Phase 1 (expand): nullable, no table rewrite
ALTER TABLE orders ADD COLUMN currency text;

-- Phase 2 (migrate): backfill in batches, then validate
-- (run backfill out of band, see below)
ALTER TABLE orders ADD CONSTRAINT orders_currency_not_null
  CHECK (currency IS NOT NULL) NOT VALID;
ALTER TABLE orders VALIDATE CONSTRAINT orders_currency_not_null;

-- Phase 3 (contract, optional): promote to real NOT NULL
-- Postgres can use the validated CHECK to skip the scan.
ALTER TABLE orders ALTER COLUMN currency SET NOT NULL;
ALTER TABLE orders DROP CONSTRAINT orders_currency_not_null;
```

### Batched backfill (idempotent, restartable)

Keep each batch in its own short transaction so locks release and replicas keep up.

```sql
-- Run repeatedly until it affects 0 rows. Index the predicate column.
WITH batch AS (
  SELECT id FROM orders
  WHERE currency IS NULL
  ORDER BY id
  LIMIT 5000
  FOR UPDATE SKIP LOCKED
)
UPDATE orders o
SET currency = 'USD'
FROM batch b
WHERE o.id = b.id;
```

Driver loop (TypeScript / Supabase service role):

```ts
let affected = 1;
while (affected > 0) {
  const { data } = await supabase.rpc('backfill_currency_batch'); // wraps the SQL above
  affected = data?.rows ?? 0;
  await new Promise(r => setTimeout(r, 200)); // throttle: let WAL/replicas breathe
}
```

### Rename a column without breaking clients

```sql
-- Phase 1: add the new name
ALTER TABLE profiles ADD COLUMN full_name text;
```

Dual-write from app code so both columns stay consistent during the transition:

```ts
// During the migrate window, write both. Read prefers the new column.
await supabase.from('profiles').update({
  display_name: name, // old
  full_name: name,    // new
}).eq('id', id);
```

```sql
-- Phase 2: backfill (batched), then deploy code that reads full_name only
-- Phase 3: stop writing display_name, then drop it next release
ALTER TABLE profiles DROP COLUMN display_name;
```

### Build an index without locking writes

```sql
CREATE INDEX CONCURRENTLY idx_orders_user_id ON orders (user_id);
-- CONCURRENTLY cannot run inside a transaction block.
-- If it fails it leaves an INVALID index — clean up before retry:
DROP INDEX CONCURRENTLY IF EXISTS idx_orders_user_id;
```

### Add a foreign key safely

```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_user
  FOREIGN KEY (user_id) REFERENCES users(id) NOT VALID;  -- fast, no scan, enforced for new rows
ALTER TABLE orders VALIDATE CONSTRAINT fk_orders_user;    -- only takes SHARE UPDATE EXCLUSIVE
```

## Lock hygiene

- Set a lock timeout so a migration fails fast instead of stampeding the queue:
  ```sql
  SET lock_timeout = '3s';
  SET statement_timeout = '30s';
  ```
- Acquire heavy locks last, and keep the locked transaction tiny — never do a backfill inside it.
- Watch contention live during a migration:
  ```sql
  SELECT pid, state, wait_event_type, left(query, 80)
  FROM pg_stat_activity WHERE state <> 'idle' ORDER BY query_start;
  ```

## Client-code rules (Dart / Flutter + TypeScript)

- After expand, regenerate types so old code still compiles against the superset schema (`supabase gen types`).
- Make Dart models tolerant during the transition: new fields nullable until contract completes.
  ```dart
  factory Order.fromJson(Map<String, dynamic> j) => Order(
    id: j['id'] as String,
    currency: j['currency'] as String? ?? 'USD', // safe before backfill finishes
  );
  ```
- Verify the app against both schema states before contracting — see [[verify]].
- Never let a Flutter client crash on an unexpected extra column; deserialize by key, not by position.

## Pre-flight checklist

- [ ] Change split into expand / migrate / contract PRs.
- [ ] Each phase rolls back without touching the others.
- [ ] No `NOT NULL`/type change forces a table rewrite under lock.
- [ ] Indexes use `CONCURRENTLY`; constraints use `NOT VALID` + `VALIDATE`.
- [ ] Backfill is batched, idempotent, and restartable.
- [ ] `lock_timeout` / `statement_timeout` set.
- [ ] Tested on a Supabase preview branch with production-scale data, not an empty schema.
- [ ] Code reading the old shape is fully deployed *before* contract runs.

## Related

- [[commit-pipeline]] — commit each phase separately with Conventional Commits + gitmoji.
- [[octopus-model]] — keep data-layer models in sync as the schema evolves.
- [[verify]] — confirm both schema states behave before contracting.
