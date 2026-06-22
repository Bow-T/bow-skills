---
name: ml-monitoring-and-drift-detection
description: Triggers when keeping a deployed model healthy over time — detecting data/concept/prediction drift, monitoring feature distributions and label delay, setting retraining triggers, and closing ground-truth feedback loops.
---

# ML Monitoring and Drift Detection

A model is correct on the day you ship it and slightly wrong every day after. The world moves, your inputs move with it, and accuracy decays silently because nothing throws an exception. This skill is about catching that decay before users do — and proving, with measurement, when it's time to retrain.

## When to use

- A model is in production and you need to know it still works.
- Inputs are shifting (new user segment, seasonal traffic, a renamed upstream field).
- Offline accuracy was great but online behavior feels off.
- You're deciding *when* to retrain instead of retraining on a calendar.
- Labels arrive late (fraud confirmed weeks later, churn known only at renewal) and you need a feedback loop.

**Not this skill:** building the model (that's training work); serving latency/throughput (use `performance-optimization` and `load-and-stress-testing`); the telemetry plumbing itself (use `observability-and-instrumentation`, which carries these signals).

## The core distinction: name the drift before you chase it

Three failures wear the same costume — a falling metric — but have different fixes.

| Drift type | What moved | Symptom you can see immediately | Fix |
|---|---|---|---|
| **Data / covariate** | P(X), the input distribution | feature histograms shift; no labels needed | retrain on new data, or fix the pipeline |
| **Prediction** | P(ŷ), the output distribution | score histogram or class mix shifts | investigate cause — often downstream of data drift |
| **Concept** | P(y\|X), the input→label relationship | accuracy drops while inputs look normal | retrain; old patterns no longer hold |

Prediction drift is your **early warning** — you get it in real time, with no ground truth. Concept drift is the **truth** — but you only see it once labels land. Most monitoring effort should buy you signal in the gap between those two.

## Process

### 1. Snapshot the training distribution as the reference

You cannot detect drift without a baseline. At training time, persist a *reference profile*: per-feature histograms (fixed bins), null rate, cardinality for categoricals, and the prediction-score distribution on the validation set. Version it next to the model artifact — `model_v7` ships with `reference_v7`. Comparing live traffic against last week's live traffic only tells you it changed, not that it left the regime the model was trained for.

### 2. Log every prediction as an event you can rejoin later

Each inference writes one row, keyed so the eventual label can be stitched back.

```sql
create table prediction_log (
  prediction_id uuid primary key default gen_random_uuid(),
  model_version text not null,
  features jsonb not null,          -- the exact input vector scored
  score numeric not null,           -- raw probability/output
  predicted_label text not null,
  served_at timestamptz not null default now(),
  actual_label text,                -- filled in by the feedback loop, later
  labeled_at timestamptz
);
create index on prediction_log (model_version, served_at);
```

Log the features *as scored*, after preprocessing — a drift you can't trace to a concrete input vector is unactionable.

### 3. Measure feature drift with the right test per type

Pick a divergence metric and a threshold per feature; don't eyeball charts.

- **Continuous features** → Population Stability Index (PSI) over fixed bins, or a KS-test. PSI rule of thumb: `< 0.1` stable, `0.1–0.25` watch, `> 0.25` material shift.
- **Categorical features** → PSI on category proportions, or chi-square; alert on *new* categories (a value the model never saw is silent poison).
- **Embeddings / high-dim** → don't test 768 dims independently. Track distance between the reference centroid and the live centroid, or a small set of summary stats.

```ts
function psi(expected: number[], actual: number[]): number {
  // expected/actual are per-bin proportions, same bin edges, summing to 1
  return expected.reduce((sum, e, i) => {
    const a = Math.max(actual[i], 1e-6), exp = Math.max(e, 1e-6);
    return sum + (a - exp) * Math.log(a / exp);
  }, 0);
}
```

Compute on a rolling window (e.g. daily over the last 7 days vs. reference), not per request — single-request "drift" is just noise.

### 4. Guard against alert fatigue

A dashboard that cries drift every Monday gets muted, and a muted monitor is worse than none.

- **Rank, don't spray.** A model has 50 features; 50 PSI alarms tell you nothing. Surface the top-k drifted features by importance × PSI. A drifted feature the model barely uses is a footnote.
- **Require persistence.** Alert only when a feature breaches threshold for *N consecutive windows*, not one spike.
- **Separate "investigate" from "page."** Data drift is a ticket; a measured accuracy drop past your SLO floor is a page. Wire the latter into `slos-and-error-budgets` thinking.

### 5. Close the ground-truth loop and budget for label delay

Drift on inputs is a hypothesis; a fall in real accuracy is the verdict. You need labels back.

- **Identify the label source and its delay.** Fraud labels via chargebacks (30–90 days), churn at renewal, click-through within minutes. Write the expected delay down — it sets how long you must wait before trusting any accuracy number.
- **Backfill `actual_label`** by joining the outcome to `prediction_id`. A nightly job or Supabase edge function reconciles outcomes into `prediction_log`.
- **Beware the feedback trap.** If the model's decision changes which labels you observe (you only learn outcomes for loans you *approved*), your live accuracy is computed on a biased slice. Reserve a small random holdout that bypasses the model — or always shows a default action — to get unbiased ground truth. Without it, a model can look perfect while quietly failing on everything it rejected.
- **Watch label delay itself drift.** If labels suddenly arrive faster or slower, your accuracy window is lying before any model issue exists.

### 6. Define the retraining trigger explicitly

Retraining on a fixed schedule wastes compute when stable and lags reality when volatile. Trigger on conditions, recorded before they fire:

```
RETRAIN model_v7 WHEN any of:
  - top-3-importance feature PSI > 0.25 for 3 consecutive days
  - measured accuracy on labeled holdout < 0.88 (SLO floor)
  - new categorical value exceeds 2% of traffic on a key feature
  - 60 days elapsed (staleness backstop)
```

Each fired trigger names *which* signal and *which* slice, so the retrain has a target instead of a vibe.

### 7. Roll out the retrained model as a challenger, not a swap

A fresh model can be worse — overfit to the very drift you reacted to. Shadow the challenger on live traffic (score, log, don't act), compare against the incumbent on the labeled holdout, then ramp behind a flag. Lean on `feature-flags-and-progressive-delivery` for the rollout and `shipping-and-launch` for rollback criteria. Promote only when the challenger beats the incumbent on the *same* recent slice — not on stale validation data.

## Anti-patterns

- **Monitoring only accuracy.** It's the last thing to move and the latest to arrive. Input drift warns you weeks earlier.
- **Comparing live to live.** You detect change but lose the anchor to what the model can actually handle. Always keep the training reference.
- **One global drift number.** Aggregate stability hides a collapsed segment — a new region or device class can rot while the mean looks fine. Slice by the cohorts that matter.
- **Treating any drift as a retrain trigger.** Some drift is benign (a feature the model ignores). Gate on impact, not mere movement.
- **Trusting accuracy before labels mature.** Computing "live accuracy" on the 10% of labels that came back fast skews toward easy cases.

## Done when

- Every prediction is logged and rejoinable to its eventual label.
- A versioned reference distribution ships with each model.
- Per-feature drift, prediction drift, and labeled accuracy are tracked on rolling windows, sliced by key cohort.
- Retraining triggers are written down as conditions, and challengers are validated against the incumbent on a recent, unbiased slice before promotion.

Commit and ship monitoring changes via [[commit-pipeline]].
