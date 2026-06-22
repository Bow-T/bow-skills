---
name: data-warehouse-and-dimensional-modeling
description: Triggers when modeling for analytics/OLAP — star/snowflake schemas, fact and dimension tables, slowly-changing dimensions, grain definition, and columnar warehouse layout for BI queries.
---

# Data Warehouse and Dimensional Modeling

Analytics tables are not application tables. The OLTP schema optimizes for safe writes and point lookups; the warehouse optimizes for wide scans, aggregation, and humans slicing data they did not anticipate. Model for the question, not the transaction.

## 1. Declare the grain before anything else

The grain is the meaning of one fact row, stated as a sentence with no "and/or". Write it first; everything downstream is a consequence.

- Good: "one row per line item per order." "one row per device per day."
- Bad: "one row per order, or per shipment if split" — that is two grains pretending to be one. Split into two fact tables.
- The grain fixes which dimensions are even available. A daily-snapshot grain cannot answer "what time of day" — that information was averaged away on purpose.

Red flag: you cannot describe a fact row without listing exceptions. Stop and re-grain.

## 2. Separate facts from dimensions

- **Facts** are measurements: numeric, additive where possible, and tall (billions of rows). A fact table is mostly foreign keys plus measures.
- **Dimensions** are context: the who/what/where/when you filter and group by. Wide, descriptive, comparatively short.
- Push descriptive text out of facts into dimensions. A fact row holding `product_name` repeated a billion times is a modeling failure — store `product_key` and join.

Classify measures by additivity, because it dictates how BI tools may aggregate:
- **Additive** — sums across every dimension (revenue, quantity). Safe to `SUM`.
- **Semi-additive** — sums across some dimensions but not time (account balance, inventory on hand). Sum across stores, never across days; average or take last over time.
- **Non-additive** — ratios and percentages. Store the numerator and denominator as additive facts; compute the ratio at query time, never store and re-aggregate it.

## 3. Choose star over snowflake by default

- A **star** keeps each dimension as one flat denormalized table joined directly to the fact. One join hop, fast scans, readable SQL.
- A **snowflake** normalizes dimensions into sub-tables (product → category → department). It saves storage you do not care about and adds joins you pay for on every query.
- Snowflake only when a dimension branch is genuinely huge and shared, or a sub-hierarchy changes on its own cadence. Otherwise flatten.

```sql
-- star: fact references flat dimensions by surrogate key
create table fact_sales (
  date_key      int    not null references dim_date(date_key),
  product_key   bigint not null references dim_product(product_key),
  store_key     bigint not null references dim_store(store_key),
  customer_key  bigint not null references dim_customer(customer_key),
  quantity      int    not null,
  net_amount    numeric(12,2) not null,   -- additive
  discount_amt  numeric(12,2) not null    -- additive
);
```

## 4. Use surrogate keys, never business keys, in facts

- Every dimension gets an integer **surrogate key** as its primary key. Facts join on surrogates only.
- Keep the source system's **natural/business key** as a plain column for lineage and matching during loads — but never let a fact point at it.
- Surrogates decouple the warehouse from source-system churn (renumbered IDs, merged systems) and are what make slowly-changing dimensions possible at all.
- Reserve surrogate key `-1` (or `0`) per dimension for an "unknown / not yet arrived" member. Facts with a missing lookup point there instead of going `NULL` and silently dropping out of inner joins.

## 5. Pick a slowly-changing-dimension strategy per attribute

Decide per column, not per table, how to handle a source value changing over time:

- **Type 1 — overwrite.** No history. Use for corrections and attributes nobody reports on historically (fixing a typo in a name).
- **Type 2 — new row.** Preserves history: close the old row, insert a new one with a fresh surrogate key. Use when you must report facts against the attribute *as it was at the time*. This is the workhorse; most reporting attributes are Type 2.
- **Type 3 — prior-value column.** Keeps only "current" and "previous" in two columns. Niche; use for a single planned realignment (old region vs new region).

A Type 2 dimension carries history-tracking columns:

```sql
create table dim_customer (
  customer_key   bigint generated always as identity primary key, -- surrogate
  customer_id    text not null,            -- business key (repeats across versions)
  segment        text not null,            -- Type 2 attribute
  email          text,                     -- Type 1 attribute (overwrite)
  valid_from     timestamptz not null,
  valid_to       timestamptz not null default 'infinity',
  is_current     boolean not null default true,
  unique (customer_id, valid_from)
);
```

To resolve which version a fact belongs to, the load looks up the dimension row where the event timestamp falls in `[valid_from, valid_to)`. Indexing `(customer_id, valid_from desc)` makes that lookup cheap. See [[data-modeling-and-schema-design]] for the OLTP-side keys and constraints these loads read from.

## 6. Model time as a dimension, not a timestamp

- Build a **`dim_date`** table with one row per calendar day, keyed `YYYYMMDD` as an integer. Pre-compute weekday, fiscal period, holiday flag, quarter, week-of-year — every calendar attribute analysts ask for.
- Joining to `dim_date` turns "sales on weekends in Q3" into a filter instead of a wall of date arithmetic, and lets the warehouse partition-prune on the date key.
- Keep clock-of-day in a separate `dim_time` (one row per minute or second) only when intraday analysis is real. Do not cross-join date and time into one exploded dimension.

## 7. Lay out for columnar scans

Warehouses (and Postgres analytics extensions) reward storage that matches the query shape:

- **Partition the fact by the date key.** Almost every analytic query filters on time; partitioning lets the engine skip whole files.
- **Cluster / sort within partitions** by the next-most-common filter (store, region). Columnar formats prune row groups by min/max, so sorted data scans far less.
- **Keep facts narrow and typed tightly.** Use the smallest integer that fits a key; store money as fixed-precision `numeric`, never text.
- **Materialize common rollups** as summary fact tables at a coarser grain (daily-per-store from per-transaction) when dashboards repeatedly aggregate the same way. Treat each as a derived table with its own stated grain, refreshed from the base fact — not hand-maintained.

## 8. Validate before publishing

- **Grain test:** `count(*)` vs `count(distinct <grain columns>)` on the fact must match. A gap means duplicate grain — a fan-out bug in the load.
- **Referential test:** zero fact rows should resolve to the unknown-member key after a successful load; if many do, a dimension load ran late or a join key is malformed.
- **Additivity test:** re-derive one headline number (total revenue) directly from source and compare. Off-by-rounding is fine; off-by-magnitude means a duplicated join.
- **SCD test:** for any business key, exactly one row has `is_current = true`, and `valid_from`/`valid_to` ranges neither overlap nor leave gaps.

Ship the schema and its load only after these pass — wire them as the data-quality gate, mirroring [[test-driven-development]]. When committing the migrations and models, follow [[commit-pipeline]].
