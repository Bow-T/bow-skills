---
name: ml-data-and-feature-pipelines
description: Triggers when preparing data for training or inference — feature engineering, train/serve skew, leakage prevention, labeling, dataset versioning, and reproducible training data.
---

# ML Data and Feature Pipelines

Models are mostly data. A clean architecture with a leaky dataset ships a model that
looks great in offline metrics and rots in production. Treat data as the artifact that
must be correct, reproducible, and identical between training and serving.

## Step 0 — Frame the prediction task as of a moment in time

Before any feature, answer: **at the instant we predict, what is actually known?**
Write it down as a point-in-time contract.

- Pick the **decision timestamp** `t` (e.g. when a checkout fraud score is requested).
- Every feature must be computable from data with `event_time <= t`. No exceptions.
- The **label** is observed strictly after `t` (e.g. chargeback within 30 days).

If you cannot state `t` precisely, stop — you will build a leaky dataset.

## Step 1 — Hunt for label leakage first

Leakage is the dominant failure mode. A feature leaks if it encodes the future or the
label. Symptoms: a single feature with suspiciously high importance, or offline AUC that
collapses in production.

Red flags:

- A column updated **after** the label is known (`updated_at`, `status='refunded'`,
  `closed_reason`).
- Aggregates computed over the **whole table** instead of `WHERE event_time < t`.
- Joining a dimension table whose row was mutated post-event (mutable Supabase rows are
  a classic trap — you read today's value for a historical event).
- Target encoding or normalization stats fit on the **full** dataset before the split.

Defensive query — compute a feature strictly from the past:

```sql
-- "orders in the 7 days BEFORE this decision" — no future rows
select
  d.user_id,
  d.decision_ts,
  count(o.id) as orders_prev_7d
from decisions d
left join orders o
  on o.user_id = d.user_id
 and o.created_at <  d.decision_ts            -- strictly before t
 and o.created_at >= d.decision_ts - interval '7 days'
group by d.user_id, d.decision_ts;
```

The `<` (not `<=`) and the explicit window are the whole point.

## Step 2 — Define each feature once, share the definition

Train/serve skew comes from computing a feature two ways: a batch SQL job for training
and hand-written app code for inference. They drift. Define the transform **once** and
call it from both paths.

In a TS/Supabase stack, put the pure transform in a shared module imported by the
training export script (edge function or job) and the serving edge function:

```ts
// features/recency.ts — single source of truth, no I/O
export function ordersPrev7d(orders: { createdAt: number }[], t: number): number {
  const lo = t - 7 * 24 * 3600_000;
  return orders.filter(o => o.createdAt < t && o.createdAt >= lo).length;
}
```

Both the offline backfill and the online request handler call `ordersPrev7d`. If a
feature genuinely cannot be shared (different runtime), pin its spec in a test that runs
the same fixtures through both implementations and asserts equality.

## Step 3 — Detect skew with a parity check, don't assume

Log the **exact feature vector used at serving time**, keyed by the decision id. Later,
recompute the same features offline for those ids and diff them.

```sql
-- offline vs online feature parity
select f.feature, count(*) filter (where f.online <> f.offline) as mismatches
from feature_audit f
group by f.feature
having count(*) filter (where f.online <> f.offline) > 0;
```

Any nonzero mismatch is a bug, not noise. Common causes: timezone handling, null vs 0,
integer vs float rounding, a default that differs between paths.

## Step 4 — Split before you fit anything

Choose the split by how the model will be used, then fit transforms **only on train**.

- **Temporal split** for anything time-dependent (almost always): train on `t < cutoff`,
  validate/test on `t >= cutoff`. This is the only split that surfaces drift and leakage.
- **Grouped split** when rows share an entity (same user in train and test = leakage).
  Split by `user_id`, not by row.
- Random split only for genuinely i.i.d. data — rare in product systems.

Fit scalers, encoders, vocabularies, and imputation values on train, then apply the
frozen values to val/test/serving. Re-fitting per split leaks distribution information.

## Step 5 — Labeling: make it auditable

- Define the label with a written rule and a fixed observation window; ambiguous labels
  poison everything downstream.
- Record **who/what** produced each label (model-assisted, rule, human) and a timestamp.
- Measure inter-annotator agreement on a sample for human labels; below ~0.7 agreement
  means the task definition is unclear, not that annotators are bad.
- Keep a frozen **golden set** of hand-verified labels you never retrain on — it is your
  honest evaluation anchor.

## Step 6 — Version the dataset, not just the code

A model is reproducible only if `(code, data, config)` are all pinned. Code in git
isn't enough.

- Snapshot training data to immutable storage (Parquet in object storage, or a
  read-only Supabase table tagged with a build id). Never train off a mutable live table.
- Record a manifest: source query, `t` cutoff, row count, content hash, feature
  definitions version, split seed.
- Name artifacts by content hash, not by date — `features_a91c4f.parquet`, so a rerun
  that produces identical data reuses the artifact and a changed input is obvious.

```json
{
  "dataset_id": "fraud_v3_a91c4f",
  "cutoff_ts": "2026-05-01T00:00:00Z",
  "rows": 482113,
  "feature_spec": "recency@2.1.0",
  "split": "temporal",
  "source_sha256": "a91c4f…"
}
```

## Step 7 — Validate the data before it trains

Gate the pipeline on schema and distribution checks; fail loud rather than train on
garbage.

- Schema: types, required columns, allowed enum values, no unexpected nulls.
- Ranges and rates: null rate per column, cardinality, min/max, class balance.
- Drift: compare this batch's distributions to the previous accepted dataset; alert on
  large shifts before, not after, a bad model ships.

## Decision points

- **Online lookups expensive or features reused across models?** Stand up a small
  feature store / materialized table keyed by entity + time. Otherwise compute inline —
  don't add infra before a second consumer ([[system-architecture-design]]).
- **Backfilling historical features?** Always point-in-time correct (Step 1). A naive
  `JOIN` on current dimension rows is the #1 silent leak.
- **Imbalanced labels?** Fix with class weights or threshold tuning before resampling;
  if you resample, do it **inside** the training fold only.

## Red flags

- Offline metric far better than the previous prod model "for free" → suspect leakage.
- Feature importance dominated by one column that mentions status/result/closed.
- Training reads a live mutable table; no snapshot, no hash, can't reproduce last month's model.
- Serving features written in app code that no test compares against the training transform.
- Normalization/encoding stats fit before the split.
- Labels with no observation window or no provenance recorded.

## Related

- [[data-modeling-and-schema-design]] for the event tables features read from.
- [[observability-and-instrumentation]] for logging served feature vectors and drift.
- [[data-pipeline-and-etl-design]] for the batch orchestration around backfills.
- [[test-driven-development]] for parity and point-in-time correctness tests.
- Commit pipeline changes via [[commit-pipeline]].
