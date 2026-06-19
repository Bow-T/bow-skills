---
name: database-query-optimization
description: Triggers when database access is slow or wasteful — N+1 loops, missing/unused indexes, full table scans, ugly EXPLAIN plans, unbounded result sets, or pagination that rots as the table grows.
---

# Database Query Optimization

A senior engineer's loop for finding and fixing the query that is actually hurting you — not the one that looks scary.

## 0. Confirm there is a real problem

Do not optimize on a hunch. Get a number first.

- Reproduce against production-shaped data volume, not 50 seed rows.
- Capture the slow statement and its `EXPLAIN (ANALYZE, BUFFERS)` output.
- Note the call frequency. A 40 ms query fired 800 times per request beats a 900 ms query fired once.

Red flag: "the app feels slow" with no measured statement. Stop and measure.

## 1. Classify the symptom

Match what you see to one of these. Each has a different fix.

| Symptom | Tell | Section |
|---|---|---|
| N+1 queries | One outer query, then a loop of near-identical inner queries | §2 |
| Missing index | `Seq Scan` on a big table with a selective filter | §3 |
| Unused / wrong index | Index exists but planner ignores it, or writes are slow | §4 |
| Unbounded result set | `SELECT *` with no `LIMIT`; memory spikes | §5 |
| Pagination decay | Page 1 fast, page 5000 slow | §6 |

## 2. Kill N+1 patterns

The most common and most expensive client-side mistake.

Spot it in app logs: a burst of identical queries differing only by one id.

```dart
// RED FLAG: one query per post to fetch its author
final posts = await supabase.from('posts').select();
for (final p in posts) {
  final author = await supabase
      .from('users').select().eq('id', p['author_id']).single();
}
```

Fix by fetching related data in one round trip via a join/embed:

```dart
// One query, related rows embedded
final posts = await supabase
    .from('posts')
    .select('id, title, author:users(id, name)')
    .order('created_at');
```

In TypeScript/ORM code, the same fix is eager loading or a batched `IN` query:

```ts
const ids = posts.map((p) => p.authorId);
const authors = await db.from('users').select('id, name').in('id', ids);
const byId = new Map(authors.map((a) => [a.id, a]));
```

Decision point: if relations fan out wide (one post -> hundreds of comments),
do NOT embed everything. Fetch the page of parents, then one batched child
query keyed by parent id.

## 3. Add the index that the filter needs

Read the plan, not the table definition.

- `Seq Scan` + a `Filter` that removes most rows = candidate for an index.
- Index the columns in `WHERE`, `JOIN ON`, and `ORDER BY` — in that order of leftmost selectivity.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE customer_id = $1 AND status = 'open';

-- Composite index: equality columns first, then range/sort columns
CREATE INDEX CONCURRENTLY idx_orders_customer_status
  ON orders (customer_id, status);
```

Rules that save reworks:
- Use `CREATE INDEX CONCURRENTLY` on live tables so you do not lock writes.
- Put equality columns before range columns in a composite index.
- For queries that always filter a flag, a **partial index** is smaller and faster:
  `CREATE INDEX ... ON orders (created_at) WHERE status = 'open';`
- A **covering** index (`INCLUDE (...)`) can turn a heap fetch into an index-only scan.

Re-run `EXPLAIN ANALYZE`. Confirm the node flipped to `Index Scan` and actual
rows roughly match the planner's estimate. If estimates are wildly off, run
`ANALYZE <table>` to refresh statistics before blaming the index.

## 4. Remove indexes that cost more than they earn

Indexes are not free — every one slows inserts/updates and consumes cache.

- Find never-used indexes (Postgres): query `pg_stat_user_indexes` for `idx_scan = 0`.
- On Supabase, run the database advisor / `get_advisors` lint to surface unused
  and duplicate indexes plus missing-index hints.
- Drop redundant prefixes: an index on `(a, b)` makes a separate index on `(a)`
  unnecessary.

Decision point: a write-heavy table with a read query that runs hourly may be
better served by accepting the scan than by maintaining the index.

## 5. Bound every result set

Unbounded reads are a latency and memory bomb that only detonates in production.

- Never ship `SELECT *` from a growing table without a `LIMIT`.
- Select only the columns the caller renders.
- Stream or page large exports instead of loading them into one list.

```dart
// RED FLAG: loads the entire table into memory
final all = await supabase.from('events').select();

// Bounded and projected
final page = await supabase
    .from('events')
    .select('id, type, created_at')
    .order('created_at', ascending: false)
    .range(0, 49); // 50 rows
```

## 6. Use keyset pagination, not OFFSET

`OFFSET n` scans and discards `n` rows. It degrades linearly: deep pages crawl.

```sql
-- RED FLAG: cost grows with page number
SELECT * FROM events ORDER BY created_at DESC OFFSET 100000 LIMIT 50;
```

Page by the last seen sort key instead (constant cost per page):

```sql
SELECT * FROM events
WHERE created_at < $last_seen_created_at
ORDER BY created_at DESC
LIMIT 50;
```

```dart
// Supabase keyset pagination
final next = await supabase
    .from('events')
    .select('id, type, created_at')
    .lt('created_at', lastSeenCreatedAt)
    .order('created_at', ascending: false)
    .limit(50);
```

Make the sort key a unique, indexed tuple (e.g. `(created_at, id)`) so ties do
not skip or duplicate rows across pages.

## 7. Verify the win and lock it in

- Re-run `EXPLAIN (ANALYZE, BUFFERS)`; compare total time and `shared read`/`hit`
  buffer counts before vs after.
- Confirm the app-level metric (request count, p95 latency) actually moved.
- Add the fix as a migration, not a console hotfix, so it ships reproducibly.
- Guard against regression: assert the expected query count in a test where the
  N+1 used to live.

## Quick red-flag checklist

- A `for`/`map` loop with an `await` query inside it.
- `Seq Scan` on any table you expect to grow past a few thousand rows.
- `OFFSET` with a large or user-controlled value.
- `SELECT *` crossing a network boundary.
- Planner estimated rows off by 10x or more from actual.
- An index that `pg_stat_user_indexes` says has never been scanned.

## Related skills

- [[octopus-model]] — shape the data layer so relations are cheap to fetch.
- [[commit-pipeline]] — commit migrations and query fixes (Conventional Commits + gitmoji).
