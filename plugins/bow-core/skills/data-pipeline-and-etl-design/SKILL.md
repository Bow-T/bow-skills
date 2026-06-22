---
name: data-pipeline-and-etl-design
description: Trigger when moving or transforming data in batch or stream — building an ingestion/ETL/ELT pipeline, ensuring idempotent loads, schema evolution, or data quality checks.
---

# Data Pipeline & ETL Design

A senior engineer's process for moving data without corrupting it, losing it, or double-counting it.

## 0. Frame the pipeline before writing code

Answer these on one line each. If you can't, stop and find out.

- **Source contract**: Where does data come from, and can it change shape without warning?
- **Cadence**: Batch (cron/hourly) or stream (events)? Latency budget?
- **Volume & growth**: rows/day now, and in a year?
- **Grain**: What does one output row mean? (one order? one order-line? one daily snapshot?)
- **Delivery semantics**: at-least-once, at-most-once, or exactly-once-effective?
- **Reprocessing**: Will you ever need to replay history? (Answer is almost always yes — design for it now.)

## 1. Choose ETL vs ELT

- **ELT** (load raw first, transform in the warehouse/DB): default when the destination has compute (Postgres/Supabase, a warehouse). Cheap to replay, easy to debug, raw data is auditable.
- **ETL** (transform before load): only when the destination is dumb storage, when you must strip PII pre-landing, or when transform reduces volume by orders of magnitude before an expensive write.

Red flag: doing heavy joins in app code (Dart/TS) that the database could do in SQL. Push compute to the data.

## 2. Layer the data (medallion-ish)

Keep transforms staged, never one monolithic step:

```
raw      → exactly as received, append-only, immutable
staged   → typed, deduped, validated, conformed names
mart     → business-grain aggregates the app reads
```

Each layer is independently replayable from the one before it. Never let the app read `raw`.

## 3. Make every load idempotent

Re-running a job must not duplicate or corrupt. This is non-negotiable — pipelines retry.

**Strategy A — upsert on a natural/derived key:**

```sql
insert into staged.orders (order_id, customer_id, amount, updated_at)
select order_id, customer_id, amount, updated_at
from raw.orders_batch
on conflict (order_id) do update
set amount = excluded.amount,
    customer_id = excluded.customer_id,
    updated_at = excluded.updated_at
where excluded.updated_at > staged.orders.updated_at;  -- last-write-wins, no stale overwrite
```

**Strategy B — partition replace:** delete the partition (e.g. one day) then insert. Atomic per partition, trivial to replay one day.

```sql
delete from mart.daily_sales where sales_date = :day;
insert into mart.daily_sales select ... where sales_date = :day;
```

Wrap delete+insert in one transaction so readers never see an empty partition.

**Stream dedup:** carry an event id; reject seen ids via a dedup table or a unique constraint.

```ts
const { error } = await supabase
  .from("events")
  .upsert({ event_id: e.id, ...payload }, { onConflict: "event_id", ignoreDuplicates: true });
```

Red flag: a job whose correctness depends on running exactly once. It won't.

## 4. Incremental loads with a watermark

Don't reprocess everything every run. Track high-water marks and read forward.

```ts
const { data: state } = await supabase
  .from("etl_state").select("watermark").eq("pipeline", "orders").single();

const rows = await source.query(
  `select * from orders where updated_at > $1 order by updated_at limit 5000`,
  [state.watermark],
);
// ... load rows ...
const newMark = rows.at(-1)?.updated_at ?? state.watermark;
await supabase.from("etl_state").update({ watermark: newMark }).eq("pipeline", "orders");
```

Rules:
- Use a **monotonic, server-set** column (`updated_at` set by DB, not client clock).
- Use `>=` plus dedup, or `>` with overlap, to avoid skipping rows sharing a timestamp.
- Only advance the watermark **after** the load commits. Crash mid-load → safe re-read.

## 5. Schema evolution — expect the source to mutate

Treat the source schema as a hostile, changing interface.

- **Land raw as JSON/JSONB** when the source is external or volatile; parse into typed columns in `staged`. New source fields then never break ingestion.
- **Additive-only** in your own schemas: add nullable columns, never repurpose or drop in place. Backfill, then deprecate.
- **Detect drift**: on each run, diff observed keys against expected; log unknown fields, alert on missing required ones.

```sql
create table raw.events (
  event_id text primary key,
  received_at timestamptz default now(),
  payload jsonb not null            -- whole record, untyped
);
-- staged extracts and types it:
select payload->>'id'                   as id,
       (payload->>'amount')::numeric    as amount,
       (payload->>'ts')::timestamptz    as occurred_at
from raw.events;
```

Migrations: do expand → migrate → contract. Ship the additive change, dual-write/backfill, switch reads, then remove the old path in a later release. Defer all git steps to [[commit-pipeline]]; coordinate DB migration files with [[octopus-model]] if data-layer conventions apply.

## 6. Data quality gates (fail loud, fail early)

Run checks at the `staged` boundary, before anything reaches `mart`. Classify each as **block** (abort load) or **warn** (load + alert).

| Check | Example | Action |
|-------|---------|--------|
| Not-null on keys | `order_id is null` count = 0 | block |
| Uniqueness | distinct `order_id` = row count | block |
| Referential | every `customer_id` exists | warn/block |
| Range/sanity | `amount >= 0`, dates not future | warn |
| Volume anomaly | today's rows within ±X% of trailing avg | warn |
| Freshness | max(`updated_at`) within SLA | block |

```sql
-- abort the transaction if duplicates slipped in
do $$
declare dupes int;
begin
  select count(*) - count(distinct order_id) into dupes from staged.orders;
  if dupes > 0 then raise exception 'DQ fail: % duplicate order_id', dupes; end if;
end $$;
```

Write check results to a `dq_runs` table so quality is observable over time, not just a thrown error.

## 7. Make it observable & operable

- **Run ledger**: row per run — pipeline, start/end, rows in/out, watermark before/after, status.
- **Structured logs** keyed by a `run_id`; emit counts, not just "done".
- **Metrics**: rows processed, lag (now − max source ts), DQ pass rate, duration.
- **Idempotent backfill command**: one parameterized invocation reprocesses any date range from `raw`. Test it before you need it at 2 a.m.
- **Alerts** on: stalled watermark, DQ blocks, volume anomalies, freshness breach.

## 8. Scheduling & failure

- Prefer **small frequent runs** over giant nightly ones — smaller blast radius, faster recovery.
- Make jobs **resumable**: checkpoint progress; on restart, continue from the last committed watermark.
- **Bound retries** with backoff; route poison records to a **dead-letter** table instead of crashing the whole batch.
- Guard against **overlap**: take an advisory lock or a `running` flag so two runs don't process the same window.

## Red flags checklist

- [ ] Load isn't idempotent (re-run duplicates rows).
- [ ] Watermark advances before the commit.
- [ ] App reads `raw` / unvalidated data.
- [ ] No grain defined — "one row means..." is fuzzy.
- [ ] Source schema change silently drops fields.
- [ ] No backfill path; history can't be replayed.
- [ ] DQ failures only show up downstream in the app.
- [ ] Transform logic duplicated across batch and stream paths.

## Definition of done

Idempotent loads, incremental via committed watermark, raw layer immutable and replayable, DQ gates blocking bad data before `mart`, schema drift detected, every run recorded in a ledger, and a tested backfill command exists.
