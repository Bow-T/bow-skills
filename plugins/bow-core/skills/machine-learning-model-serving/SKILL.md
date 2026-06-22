---
name: machine-learning-model-serving
description: Triggers when deploying a trained model to production — packaging, batching, GPU/CPU sizing, versioning, shadow/canary, latency budgets, and monitoring drift and inputs.
---

# Machine Learning Model Serving

A trained model is not a product. Serving it is — and that means a contract: a fixed input schema, a latency budget, a version you can roll back, and telemetry that tells you when reality has drifted away from training. Work the steps below in order; skipping the contract is how you ship a model nobody can debug at 2am.

## 1. Define the serving contract first

Before any container, pin these down in writing:

- **Input schema** — exact feature names, types, units, allowed ranges. This is the boundary that catches drift.
- **Output schema** — class labels + score, or regression value + confidence. Include the model version in every response.
- **Latency budget** — p50 and p99 targets at the *call site*, not the GPU. A recommendation widget might allow 80ms p99; a fraud check inline in checkout might allow 30ms.
- **Throughput** — peak requests/sec you must absorb without queueing past budget.
- **Failure mode** — what the caller gets when the model is down or slow. Decide now: fall back to a heuristic, return a cached/default prediction, or hard-fail. Never let an unbounded model call block a user flow.

Encode the schema as a validated type, not a comment. In a TypeScript edge function:

```ts
import { z } from "zod";

const PredictRequest = z.object({
  features: z.object({
    account_age_days: z.number().int().nonnegative(),
    txn_amount: z.number().positive(),
    country: z.string().length(2),
  }),
});
type PredictRequest = z.infer<typeof PredictRequest>;
```

See [[type-safety-and-schema-validation]] and [[api-and-interface-design]] for the boundary contract.

## 2. Choose where inference runs

Decision points, cheapest viable option first:

- **In-process / on-device** — small model (tree ensemble, tiny net), tight latency, no network hop. On Flutter, export to a mobile runtime (e.g. a `.tflite`-style asset) and run via a platform channel. Best privacy, zero serving infra.
- **Serverless function (CPU)** — model under ~100ms CPU inference, spiky traffic, no GPU. A Supabase edge function or small container scales to zero. Watch cold starts: load the model once at module scope, never per-request.
- **Dedicated CPU service** — steady traffic, model too big for serverless memory limits, want pinned warm instances.
- **GPU service** — large transformer / vision / generative model where CPU latency blows the budget. Most expensive; justify it with a measured CPU baseline, not a hunch.

Red flag: reaching for a GPU before you've measured CPU latency. Quantized small models often hit budget on CPU at a tenth of the cost.

## 3. Package the model immutably

A served model is an artifact, not a file someone scp'd. Bundle:

- The serialized weights.
- The **exact** preprocessing code (same library versions as training — skew here is the #1 silent bug).
- A version string (`model_name:semver+gitsha`).
- A manifest: training data window, feature list, metrics at training time.

Pin runtime deps with a lockfile so the inference environment is reproducible. See [[dependency-and-supply-chain]].

Skew check: run the same 100 rows through the training pipeline and the serving pipeline; assert predictions match within tolerance. This is a unit test, not a manual ritual — wire it per [[test-driven-development]].

## 4. Batch for throughput, bound for latency

Single-request inference wastes GPU/CPU vectorization. Dynamic batching collects requests for a few milliseconds, runs them as one tensor, then scatters results back.

```ts
class MicroBatcher {
  private queue: { input: number[]; resolve: (v: number) => void }[] = [];
  private timer: ReturnType<typeof setTimeout> | null = null;

  constructor(private maxBatch = 32, private maxWaitMs = 5) {}

  predict(input: number[]): Promise<number> {
    return new Promise((resolve) => {
      this.queue.push({ input, resolve });
      if (this.queue.length >= this.maxBatch) this.flush();
      else this.timer ??= setTimeout(() => this.flush(), this.maxWaitMs);
    });
  }

  private async flush() {
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    const batch = this.queue.splice(0, this.maxBatch);
    const outputs = await runModel(batch.map((b) => b.input)); // one tensor call
    batch.forEach((b, i) => b.resolve(outputs[i]));
  }
}
```

`maxWaitMs` is your latency tax: it adds directly to p99. Tune it against the budget — never set it blind. Under load, also cap the queue depth and shed (return the fallback) rather than letting latency climb unbounded; see [[resilience-and-fault-tolerance]].

## 5. Size capacity from measurement

1. Load one warm instance. Measure single-request and batched latency at several batch sizes.
2. Find the batch size where latency still fits p99 — that sets max throughput per instance.
3. Instances needed ≈ `peak_rps / per_instance_rps`, plus headroom for the slowest 1% and for one instance dying.
4. For GPU, watch memory: batch size × activation size must fit VRAM, or you get OOM under load, not in testing.

Validate with a real load test ([[load-and-stress-testing]]) before trusting the math. Capacity planning detail lives in [[scalability-and-capacity-planning]].

## 6. Version and roll out safely

Every deployed model carries a version, and every prediction logs which version produced it. Never hot-swap weights in place — you lose the ability to attribute a metric regression.

Rollout ladder, gated on metrics at each rung:

1. **Shadow** — send live traffic to the new model *in parallel*, serve the old model's answer, log both. Compare prediction distributions and latency. The new model affects nobody yet. This is the single most valuable step and the most often skipped.
2. **Canary** — route a small slice (1–5%) to the new model. Watch business metric + error rate + latency.
3. **Progressive** — ramp 5 → 25 → 50 → 100% with a hold at each step.
4. **Rollback** — flip the route back to the previous version in one config change. Keep the old version warm until the new one has proven itself over a full traffic cycle.

Drive the percentage split with a flag, not a redeploy — see [[feature-flags-and-progressive-delivery]] and [[deprecation-and-migration]] for retiring the old version.

Red flag: a canary judged only on "no errors." A model can return 200 OK with quietly worse predictions. Gate on a prediction-quality signal too.

## 7. Monitor inputs, outputs, and drift

Errors and latency are table stakes ([[observability-and-instrumentation]]). For models you also watch the *data*:

- **Input drift** — does each feature's live distribution still match training? Track mean/quantiles per feature; alert when a population statistic moves beyond a threshold. A feature that was 0–100 in training now arriving as 0–1 means an upstream unit change broke you silently.
- **Schema violations** — count requests rejected by validation. A spike means a caller changed.
- **Prediction drift** — does the output class balance or score distribution shift? Sudden change without a model deploy points at upstream data.
- **Outcome / label lag** — when ground truth arrives later (did the flagged transaction actually charge back?), join it back to log accuracy over time. This is your real "is the model still good" signal.
- **Confidence** — track the share of low-confidence predictions; a rise often precedes an accuracy drop.

Persist prediction logs (with version, features hash, score, eventual label) to a table for offline analysis:

```sql
create table prediction_log (
  id           bigint generated always as identity primary key,
  model_version text not null,
  features      jsonb not null,
  score         double precision not null,
  predicted     boolean not null,
  actual        boolean,          -- backfilled when ground truth lands
  created_at    timestamptz not null default now()
);
create index on prediction_log (model_version, created_at);
```

Never log raw PII features in clear text — hash or tokenize per [[data-privacy-and-compliance]] and [[logging-hygiene]].

## Red flags

- Preprocessing code differs between training and serving — guaranteed silent skew.
- No model version in the response or logs — you cannot attribute a regression.
- GPU chosen before a CPU baseline was measured — burning money.
- Canary gated only on HTTP errors, not prediction quality.
- Unbounded inference call inside a user-facing request with no timeout or fallback.
- Model file loaded per-request instead of once at startup — kills cold-start latency.
- No drift monitoring — the model rots and nobody notices until the business metric tanks.

## Commit

When committing serving code or model artifacts, follow [[commit-pipeline]] — Conventional Commits with a gitmoji, no AI-authorship trailer.
