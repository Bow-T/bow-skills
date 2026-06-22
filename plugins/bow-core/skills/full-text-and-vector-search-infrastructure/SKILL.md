---
name: full-text-and-vector-search-infrastructure
description: Triggers when standing up search infra itself — indexing pipelines, analyzers/tokenizers, sharding, freshness-vs-cost trade-offs, and operating Elasticsearch/OpenSearch/pgvector in production.
---

# Full-Text and Vector Search Infrastructure

You are building or operating the search *plumbing*, not the query UX. The job is to
turn a source of truth into a queryable index that stays fresh, correct, and affordable
under load. Relevance tuning and ranking live in [[search-and-relevance-engineering]];
this skill is about the engine and the pipeline that feeds it.

## 0. Decide whether you even need a search cluster

Before reaching for a dedicated engine, prove the cheaper option fails.

| Need | Reach for | Stop here if... |
|---|---|---|
| Keyword search over < ~1M rows, modest QPS | Postgres `tsvector` + GIN | A `WHERE plainto_tsquery(...)` query stays sub-100ms |
| Semantic / similarity search, moderate scale | `pgvector` (HNSW index) | Recall and latency hold at your row count |
| Both, plus facets, typo-tolerance, high QPS, huge corpus | Elasticsearch / OpenSearch | — |

**Red flag:** spinning up a 3-node cluster for 50k documents. The operational tax
(snapshots, version upgrades, JVM heap, shard math) is real. Earn it.

## 1. Model the index, not the table

The index is a *projection* for query, denormalized on purpose. Decide up front:

- **Document granularity.** One document per searchable unit. Don't index a parent and
  expect to query its children — flatten or use a join type deliberately.
- **Which fields are searched vs. returned vs. filtered.** Searched fields get analyzers;
  filter fields stay `keyword`/exact; large blobs you only display can be `stored` but not
  indexed.
- **Source of truth stays in Postgres.** The index is rebuildable and disposable. Never
  let it be the only copy of anything.

```ts
// An explicit Elasticsearch mapping beats dynamic mapping in production.
const mapping = {
  properties: {
    title:      { type: "text", analyzer: "english" },
    body:       { type: "text", analyzer: "english" },
    tags:       { type: "keyword" },              // exact filter + facet
    tenant_id:  { type: "keyword" },              // ALWAYS filter on this
    created_at: { type: "date" },
    embedding:  { type: "dense_vector", dims: 768, index: true, similarity: "cosine" },
  },
} as const;
```

**Red flag:** dynamic mapping in production. The first document's shape silently becomes
the schema; a stray numeric string locks a field to the wrong type and reindexing is the
only fix.

## 2. Get analyzers and tokenizers right (the part everyone skips)

Bad search is usually a bad analyzer, not a bad query. The analyzer that builds the index
**must match** the one that processes the query, or terms won't line up.

- **Tokenizer** splits text into terms (standard, whitespace, n-gram, edge-n-gram for
  prefix/autocomplete).
- **Filters** lowercase, strip accents (`asciifolding`), stem (`english` stemmer), and drop
  stopwords.
- Use **edge-n-gram at index time only**, never at query time — otherwise "cat" matches
  "category" *and* every prefix of the query token. Set `search_analyzer` separately.
- For non-English content, pick the right language analyzer or you lose stemming and
  folding. CJK needs a dedicated tokenizer; whitespace splitting destroys it.

In Postgres the equivalent is the text-search configuration:

```sql
-- The config in to_tsvector and to_tsquery MUST match.
ALTER TABLE docs ADD COLUMN fts tsvector
  GENERATED ALWAYS AS (to_tsvector('english', coalesce(title,'') || ' ' || coalesce(body,''))) STORED;
CREATE INDEX docs_fts_idx ON docs USING GIN (fts);
-- query: WHERE fts @@ websearch_to_tsquery('english', $1)
```

**Decision point:** generated `tsvector` column (simple, indexed, always in sync) vs. an
expression index (no extra column but recomputed per query). Prefer the generated column.

## 3. Build the indexing pipeline

This is where most production pain lives. Two phases:

**Backfill (one-time / rebuild):** bulk, paginated, idempotent. Use the bulk API in
batches of a few hundred to low thousands of docs; tune by payload size, not count.
Disable/relax refresh during the load, then restore.

**Continuous (keeps it fresh):** capture changes from the source of truth and stream them
to the index. Order of preference:

1. **Change Data Capture** (logical replication / a queue) — most robust, survives app
   crashes, replays.
2. **Outbox table** the app writes to in the same transaction as the data change; a worker
   drains it. Survives partial failures; gives at-least-once delivery.
3. **Dual-write from app code** — simplest, but the index drifts the moment a write
   succeeds and the index call fails. Only acceptable with a reconciliation job.

```ts
// Outbox drain worker: idempotent upsert keyed by document id + version.
for (const evt of await claimOutboxBatch(200)) {
  await es.index({
    index: "docs",
    id: evt.docId,
    version: evt.rowVersion,      // external versioning rejects stale writes
    version_type: "external",
    document: toSearchDoc(evt),
  });
  await markOutboxDone(evt.id);
}
```

**Red flags:**
- Indexing inside the request path → user waits on the search cluster; a slow index node
  becomes a slow checkout.
- No version/sequence guard → out-of-order events resurrect deleted docs.
- Deletes not propagated → tombstones accumulate; search returns rows that no longer exist.

Pair retries, backoff, and dead-lettering here with [[resilience-and-fault-tolerance]] and
[[idempotency-and-exactly-once]].

## 4. Freshness vs. cost — the dial you must set on purpose

Every refresh, merge, and replica costs CPU/IO. Tune to the actual requirement.

- **Refresh interval.** ES default makes docs visible ~1s after write. If "new doc visible
  within a minute" is fine, set `refresh_interval: 30s` and cut indexing cost sharply.
  Never call `?refresh=true` per write in a loop.
- **Bulk over single.** One bulk request of 500 docs beats 500 requests, always.
- **Replicas for read throughput, not durability of the source.** Add replicas to serve
  more QPS; the source of truth already lives elsewhere.

Tie capacity decisions to [[scalability-and-capacity-planning]] and the spend lens in
[[cost-and-finops-optimization]].

## 5. Sharding and vector indexes

**Shards:** a shard is a Lucene index and has fixed overhead. Aim for shards in the tens
of GB, not hundreds of tiny ones. Estimate `primary_shards ≈ total_index_size / target_shard_size`,
then validate. **Over-sharding is the most common self-inflicted wound** — thousands of
shards exhaust heap and slow every cluster operation. You cannot change primary shard count
without reindexing, so size for projected growth, not today.

**Vector indexes (HNSW):**
- Build cost and memory grow with `m` and `ef_construction`; recall improves with
  `ef_search` at query time (latency cost). Tune `ef_search` per query, not per index.
- HNSW is memory-resident — budget RAM for the whole vector set, or recall/latency collapse
  when it spills.
- In `pgvector`, build the HNSW index *after* bulk load, and `SET maintenance_work_mem` high
  for the build.

```sql
CREATE INDEX ON items USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
SET hnsw.ef_search = 100;  -- raise for recall, lower for speed
```

**Decision point — hybrid search:** combine BM25 (lexical) with vector (semantic) when
either alone misses. Run both, fuse with Reciprocal Rank Fusion rather than hand-tuned
score addition (raw scores aren't on the same scale). Scoring/fusion tuning belongs to
[[search-and-relevance-engineering]].

## 6. Reindexing without downtime

Mapping changes, analyzer changes, and shard-count changes all require a rebuild. Do it
behind an alias so reads never break:

1. Create `docs_v2` with the new mapping.
2. Backfill from the source of truth (not from `docs_v1` — the SoT is canonical).
3. Keep the continuous pipeline writing to **both** indices during the cutover.
4. Atomically flip the read alias: `docs → docs_v2`.
5. Verify, then drop `docs_v1`.

Always query through an alias, never a raw index name. This is migration discipline —
align with [[zero-downtime-database-migrations]] and [[deprecation-and-migration]].

## 7. Operate it

- **Monitor:** heap usage, GC pauses, indexing/search latency percentiles, rejected-thread
  queues, segment counts, and pipeline lag (outbox depth / replication slot bytes). Wire
  these into [[observability-and-instrumentation]].
- **Snapshots:** schedule them; periodically *test a restore* into a scratch cluster. An
  untested snapshot is a guess. See [[backup-and-disaster-recovery]].
- **Multi-tenant:** filter every query by `tenant_id` and enforce it server-side, not in
  client code. A missing tenant filter is a data-leak incident, not a bug.
- **Reconciliation job:** periodically diff index counts/checksums against the source of
  truth to catch silent drift from dropped events.

## Red flags summary

- The index is the only copy of the data.
- Per-write `refresh=true`, or single-document indexing in a hot loop.
- Index-time analyzer ≠ query-time analyzer (terms never match).
- Thousands of tiny shards; or one giant shard you can't split without a full reindex.
- Vector set larger than RAM.
- Indexing on the request path with no async buffer.
- Deletes and tenant scoping handled "later."

For committing any of this, follow [[commit-pipeline]].
