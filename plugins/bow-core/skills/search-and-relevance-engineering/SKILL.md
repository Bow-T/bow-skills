---
name: search-and-relevance-engineering
description: Trigger when building or tuning search — indexing, analyzers, ranking/relevance, filters/facets, typo tolerance, or evaluating search quality.
---

# Search & Relevance Engineering

> Scope: query **recall + ranking/relevance**. For the indexing/serving **plumbing** (clusters, analyzers, sharding, ops), see [[full-text-and-vector-search-infrastructure]].

Search is two problems wearing one trench coat: **recall** (did we retrieve the right docs?) and **precision/ranking** (are the best ones on top?). Solve them in that order. Never tune ranking on a query that returns zero hits.

## 0. Frame the job before touching an index

Answer these first — they decide everything downstream:

- **What is a "document"?** A product, a user, an order line? Pick the unit the user expects to click.
- **What fields do users actually type?** Title, brand, SKU, free text? Pull real queries from logs, not your imagination.
- **What's the latency budget?** Sub-50ms autocomplete vs. 300ms results page are different architectures.
- **What's "correct"?** You cannot tune what you cannot measure. Define a judgement set early (see §6).

Decision: if data is small (<100k rows), changes rarely, and queries are mostly exact/prefix — **start with Postgres**, not a search engine. Reach for a dedicated engine only when you need typo tolerance, faceting at scale, or millisecond ranked search over millions of docs.

## 1. Indexing: the source of truth → search projection

The index is a derived read model, never the system of record. Build a one-way pipeline.

- Make indexing **idempotent**: re-running a full reindex must produce identical state.
- Emit a **deterministic doc id** equal to the primary key so updates upsert, deletes delete.
- Reindex on write via an outbox/CDC stream, not a fragile dual-write. With Supabase, a trigger that enqueues changed ids is reliable.

```sql
-- Supabase: queue rows for the indexer instead of dual-writing
create table search_outbox (
  id bigint generated always as identity primary key,
  entity text not null,
  entity_id uuid not null,
  op text not null check (op in ('upsert','delete')),
  enqueued_at timestamptz not null default now()
);

create or replace function enqueue_search() returns trigger language plpgsql as $$
begin
  insert into search_outbox(entity, entity_id, op)
  values (tg_argv[0], coalesce(new.id, old.id),
          case when tg_op = 'DELETE' then 'delete' else 'upsert' end);
  return coalesce(new, old);
end $$;

create trigger products_search after insert or update or delete on products
  for each row execute function enqueue_search('product');
```

A worker (TypeScript edge function) drains the outbox in batches and pushes to the index. Red flag: indexing inside the request handler — it couples write latency to search availability.

## 2. Analyzers: text → tokens (this is where most relevance lives)

Garbage tokenization beats any ranking formula into the ground. Decide per field:

- **Lowercase + fold accents** for human text (`Café` matches `cafe`).
- **Don't analyze identifiers** — SKUs, slugs, enums go in a `keyword`/exact field, untokenized.
- **Stemming** maps `running → run`; helpful for prose, harmful for brand names. Use selectively.
- **n-grams / edge-grams** power prefix and infix matching for autocomplete — but they bloat the index, so apply only to fields that need them.

Index the same source field two ways when needed: an analyzed `name` for matching and a raw `name.exact` for boosting exact hits and for sorting.

```ts
// Normalizer reused by indexer AND query builder — they MUST agree
export const normalize = (s: string) =>
  s.toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '').trim();
```

Red flag: index-time and query-time analysis differ. If you fold accents when indexing but not when querying, recall silently collapses.

## 3. Postgres full-text search (the default for this stack)

For most Supabase apps this is enough and avoids a second system.

```sql
alter table products add column fts tsvector
  generated always as (
    setweight(to_tsvector('simple', coalesce(name,'')), 'A') ||
    setweight(to_tsvector('simple', coalesce(brand,'')), 'B') ||
    setweight(to_tsvector('simple', coalesce(description,'')), 'C')
  ) stored;

create index products_fts_idx on products using gin (fts);

-- typo tolerance via trigram similarity (pg_trgm)
create extension if not exists pg_trgm;
create index products_name_trgm on products using gin (name gin_trgm_ops);
```

Query: rank with `ts_rank_cd`, fall back to trigram when FTS returns nothing.

```sql
select id, name, ts_rank_cd(fts, q) as rank
from products, websearch_to_tsquery('simple', $1) q
where fts @@ q
order by rank desc, similarity(name, $1) desc
limit 20;
```

Use `websearch_to_tsquery` (handles quotes/`-`/`or`) over raw `to_tsquery`. The `setweight` A/B/C tiers are your ranking knobs — a title match should outrank a description match.

## 4. Ranking: combine signals, don't worship one score

Relevance = textual match × business value × freshness × personalization. Compute a final score from weighted, **normalized** signals (each scaled 0–1 before combining — raw text scores and raw sales counts are not comparable).

```ts
const score =
  4.0 * textMatch +      // exact/title hits dominate
  1.5 * popularity +     // log-scaled sales or clicks
  1.0 * recencyDecay +   // exp decay on age
  2.0 * inStock;         // hard business rule as a soft boost
```

Decision points:
- **Hard filter vs. soft boost.** "Out of stock" — hide it (filter) or sink it (boost)? Filter when the user can't act on it; boost when it's still useful context.
- **Tie-breakers must be deterministic** (e.g., id) so pagination is stable.
- **Popularity needs decay**, or last year's hit dominates forever. Apply `exp(-age/halflife)`.

Red flag: a single magic relevance score with no breakdown. You'll never debug "why is this #1?" Log per-signal contributions for the top results.

## 5. Filters, facets, and typo tolerance

- **Facets** (counts per category/brand/price-bucket) must reflect the *query+other filters* but not the facet's own selection — otherwise selecting a brand drops every other brand's count to zero. Most engines have a "disjunctive facet" mode; in Postgres, compute facet counts with the brand filter excluded from the brand facet's own subquery.
- **Filters are exact, not ranked** — keep them on keyword fields and apply before scoring to shrink the candidate set.
- **Typo tolerance**: allow edit distance 1 for short terms, 2 for long ones; never fuzz numbers or codes. Prefer the engine's built-in typo tolerance over trigram hacks once you outgrow Postgres.

## 6. Evaluate quality — make it a number, not a vibe

This is the step everyone skips and the one that actually moves relevance.

1. **Build a judgement set**: ~50–200 real queries from logs, each with a few known-relevant doc ids (graded 0–3 or binary).
2. **Compute offline metrics** on every change: `Recall@k` (did we retrieve them) and `nDCG@10` / `MRR` (are they ranked well).
3. **Gate changes**: a ranking tweak that lifts one query and tanks five is a regression. Diff metrics before merge.
4. **Watch online signals**: zero-result rate, click-through on top-3, "search → no click → refine" loops, search-to-conversion.

```ts
const dcg = (rels: number[]) =>
  rels.reduce((s, r, i) => s + (2 ** r - 1) / Math.log2(i + 2), 0);
const ndcg = (ranked: number[], ideal: number[]) =>
  dcg(ranked) / (dcg([...ideal].sort((a, b) => b - a)) || 1);
```

Red flag: shipping a relevance change because it looks better on one demo query. Always run the judgement set.

## 7. Performance & operations

- **Filter before you score.** Cheap exact filters cut the candidate set; ranking runs on what survives.
- **Cache the hot head** of queries; the long tail is uncacheable and that's fine.
- **Reindex with zero downtime**: build into a new alias/index, validate metrics, then atomically swap. Never reindex in place on a live index.
- **Cap fan-out**: paginate with stable cursors, not deep `OFFSET` (which scans and discards).

## When to escalate beyond keyword search

Add **semantic / vector search** (embeddings + `pgvector` or a vector index) when queries are conceptual ("warm jacket for hiking") rather than lexical. Then run **hybrid**: keyword for precision on exact terms, vector for recall on intent, fused with reciprocal-rank fusion. Don't start here — keyword search well-tuned beats a naive vector index for most product/catalog search.

## Cross-links

- Data modeling and migrations for the source tables: [[data-modeling-and-schema-design]].
- Committing index migrations and tuning changes: follow [[commit-pipeline]].

## Definition of done

- [ ] Index is idempotent and rebuildable from the source of truth.
- [ ] Index-time and query-time analysis use the *same* normalizer.
- [ ] Filters are exact; ranking signals are normalized and weighted with a logged breakdown.
- [ ] Facet counts are disjunctive (selecting one value doesn't zero the others).
- [ ] A judgement set exists and metrics are diffed before every relevance change.
- [ ] Zero-result rate and top-3 CTR are monitored in production.
