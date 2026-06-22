---
name: api-pagination-and-bulk-access
description: Triggers when exposing list endpoints at scale — choosing cursor vs offset pagination, designing bulk/batch reads and writes, streaming large result sets, and stable ordering under concurrent writes.
---

# API pagination and bulk access

A list endpoint that works for the demo dataset is a production incident waiting for the table to grow. The job is to bound every response, keep ordering stable while rows churn, and give clients a sane way to read or write in bulk.

## Step 0 — Refuse the unbounded query

Before anything else, find every endpoint that returns a collection and confirm it has a hard cap.

- No `SELECT ... ` without a `LIMIT`. No `.select()` without `.range()` or `.limit()`.
- A default page size (try 25–50) AND a max page size (e.g. 100). Clamp, don't trust the client.
- Red flag: "we only have a few hundred rows." You are sizing for the row count in 18 months, not today.

## Step 1 — Pick the pagination model

Decide once per endpoint. Don't mix.

| Need | Use |
|---|---|
| Jump to arbitrary page N, total count, small/slow-growing table | **Offset** |
| Infinite scroll, feeds, sync, large or hot table, stable results | **Cursor (keyset)** |
| Export everything, server-driven | **Streaming / batch fetch** |

Default to **cursor**. Reach for offset only when a user genuinely needs "page 47" and the table is calm.

### Why offset rots
`LIMIT 20 OFFSET 100000` makes the database walk and discard 100k rows — cost grows with page depth. Worse, if a row is inserted or deleted between page loads, every later page **shifts**: items get skipped or shown twice. Offset is acceptable only when the ordering key is effectively frozen during browsing.

## Step 2 — Build a keyset cursor

Sort by something unique and monotonic. If your sort key isn't unique (e.g. `created_at`), append a tiebreaker (the primary key) so the ordering is total and the cursor is unambiguous.

```sql
-- page 1
select id, title, created_at
from articles
order by created_at desc, id desc
limit 25;

-- next page: feed the LAST row's (created_at, id) back as the cursor
select id, title, created_at
from articles
where (created_at, id) < ($1, $2)   -- row-value comparison, matches the sort
order by created_at desc, id desc
limit 25;
```

The row-value comparison `(created_at, id) < ($1, $2)` is the part people get wrong with hand-rolled `OR` chains. Keep it as a single tuple comparison; it stays correct and uses a composite index on `(created_at desc, id desc)`.

**Encode the cursor as an opaque token.** Clients must not parse or fabricate it — that frees you to change the internal sort later.

```ts
// TypeScript — opaque, URL-safe, tamper-evident enough for "don't hand-edit this"
type Cursor = { createdAt: string; id: string };

const encode = (c: Cursor) =>
  Buffer.from(JSON.stringify(c)).toString("base64url");
const decode = (s: string): Cursor =>
  JSON.parse(Buffer.from(s, "base64url").toString());

// response shape
type Page<T> = { items: T[]; nextCursor: string | null };
```

Return `nextCursor: null` when fewer rows than the limit come back. Don't make clients guess.

### Supabase keyset

```ts
let q = supabase
  .from("articles")
  .select("id,title,created_at")
  .order("created_at", { ascending: false })
  .order("id", { ascending: false })
  .limit(pageSize);

if (cursor) {
  const { createdAt, id } = decode(cursor);
  // PostgREST has no tuple comparison; use the .or() keyset expansion:
  q = q.or(
    `created_at.lt.${createdAt},and(created_at.eq.${createdAt},id.lt.${id})`,
  );
}
```

If the `.or()` form gets unwieldy, push the query into a Postgres RPC that does the clean row-value comparison and call it from the client.

### Flutter consumer

```dart
Future<Page<Article>> fetchArticles({String? cursor}) async {
  final res = await api.get('/articles', query: {
    if (cursor != null) 'cursor': cursor,
    'limit': '25',
  });
  return Page.fromJson(res, Article.fromJson);
}
// ViewModel holds nextCursor; the list view requests more when it nears the end,
// and stops once nextCursor is null. (See [[flutter-mvvm]].)
```

## Step 3 — Handle counts honestly

`COUNT(*)` over a large filtered set is expensive and grows with the table.

- Cursor pagination usually doesn't need a total. Don't compute one out of habit.
- If the UI needs "about N results," return an **estimate** (e.g. from `pg_class.reltuples` or a planner estimate) and label it as approximate.
- If an exact count is truly required, make it a separate, cacheable endpoint — not a tax on every page.

## Step 4 — Bulk reads (batch by ID)

For "fetch these 200 things," accept a list of IDs and return them in one round trip. This kills the N+1 pattern where a client loops and calls the single-item endpoint.

- Cap the batch size (e.g. 500 IDs) and reject oversized requests with `413`/`400`.
- Return results **keyed by ID**, not a positional array — callers shouldn't depend on order, and missing IDs should be visible.
- Decide the missing-ID contract explicitly: omit them, or return `{ id, found: false }`. Document it.

```ts
// POST /articles/batch  { ids: [...] }
const rows = await db.articles.whereIn("id", ids); // single query
const byId = new Map(rows.map((r) => [r.id, r]));
return { results: Object.fromEntries(ids.map((id) => [id, byId.get(id) ?? null])) };
```

## Step 5 — Bulk writes

Bulk mutation is where partial failure bites.

- Choose the failure mode up front and state it in the API: **all-or-nothing** (wrap in a transaction) or **per-item** (return a status array). Don't silently do half.
- For per-item results, echo each item's outcome: `{ id, status: "ok" | "error", error?: ... }`.
- Make bulk writes **idempotent**: accept a client-supplied key per item or per batch so retries after a timeout don't double-insert. See [[idempotency-and-exactly-once]] and [[resilience-and-fault-tolerance]].
- Cap batch size and apply rate/quota limits — a 50k-row insert is a denial-of-service vector. See [[rate-limiting-and-quota-design]].

```ts
// all-or-nothing
await db.transaction(async (tx) => {
  for (const item of batch) await tx.articles.insert(item);
});
```

## Step 6 — Stream the genuinely large exports

When a client must read the whole table (export, migration, sync), don't load it into memory or make them click "next page" 4,000 times.

- Server-side: stream rows with a server cursor / chunked response (NDJSON is friendly — one JSON object per line) instead of building a giant array.
- Keep the same keyset ordering so a dropped connection can resume from the last seen cursor.
- For very large or async exports, return a job: `202 Accepted` + a status URL, generate a file, hand back a signed download link. See [[background-jobs-and-queues]].

```ts
// NDJSON streaming export, batched by keyset
let cursor: Cursor | null = null;
for (;;) {
  const rows = await fetchBatch(cursor, 1000);
  if (rows.length === 0) break;
  for (const r of rows) res.write(JSON.stringify(r) + "\n");
  cursor = { createdAt: rows.at(-1)!.created_at, id: rows.at(-1)!.id };
}
res.end();
```

## Step 7 — Stability under concurrent writes

Decide what a paging session should see while rows are being inserted and deleted.

- **Keyset on an immutable-ish key** (creation order) gives a stable view of older data; new rows appear at the front and won't shift the pages you've already walked.
- If you paginate by a **mutable** column (e.g. `updated_at`, `priority`), a row can move between pages mid-session — be explicit that this is a "live" view, or snapshot into a read replica / materialized view for consistency.
- For exports that must be a true point-in-time snapshot, run inside a `REPEATABLE READ` transaction or against a snapshot, and document the trade-off (longer-lived read, more DB pressure).

## Red flags

- A list endpoint with no `LIMIT` / `.range()`.
- `OFFSET` on a hot or large table; offset depth driven by user input with no cap.
- Sorting by a non-unique key with no tiebreaker — duplicate or skipped rows across pages.
- Cursor is just the offset in disguise, or a parseable `id=123` the client can forge.
- `COUNT(*)` on every page of a big table.
- Bulk endpoint with no size cap, no idempotency key, and undefined partial-failure behavior.
- Export endpoint that buffers the entire result set in memory before responding.

## Done when

- Every collection response is bounded and ordered totally.
- Cursors are opaque and resumable; `nextCursor` is `null` at the end.
- Bulk read/write contracts (size cap, missing-ID, partial-failure, idempotency) are documented and tested.
- Large exports stream or run as jobs, not as one giant in-memory blob.
- You've decided and documented what a paging session sees under concurrent writes.

Commit via [[commit-pipeline]].
