---
name: experimentation-and-ab-testing
description: Triggers when running an experiment to decide a change — hypothesis, metric and guardrail selection, sample-size/power, assignment, and reading results without p-hacking.
---

# Experimentation and A/B testing

An experiment is a tool for making a decision under uncertainty, not a ritual that
blesses a change you already shipped in your head. Run it only when the decision is
genuinely reversible-on-data and the lift is worth the wait. Otherwise just ship and watch.

## Step 0 — Decide whether you even need a test

Skip the experiment when:

- The change is a bug fix or correctness issue — you don't A/B test "is the app crashing".
- Traffic is too low to ever reach significance (see Step 3). A test you can't power is theatre.
- The decision is one-way-door risky regardless of metrics (pricing, legal, data deletion).

Run it when there's a real, measurable behavioral question and enough traffic to answer it.

## Step 1 — Write the hypothesis BEFORE touching code

Lock this down first, in writing, so you can't reinterpret it later:

```
Because [observation], we believe [change] will cause [primary metric] to move
[direction] by at least [minimum detectable effect] for [population].
We are wrong if [guardrail] degrades or the metric doesn't move.
```

Concrete: "Because checkout drop-off spikes at the address step, we believe a single-field
autocomplete will lift checkout-completion rate by ≥2pp for mobile users. We're wrong if
median checkout latency rises >200ms or refund rate climbs."

Red flag: a hypothesis you can't state before seeing results. If you can't predict the
sign and rough size of the effect, you're exploring, not confirming — label it that way.

## Step 2 — Pick exactly one primary metric, plus guardrails

- **Primary metric** — one. The thing the decision hinges on. Make it a rate or mean per
  user, not a raw count (counts move with traffic, not behavior). Prefer metrics close to
  the change; "revenue" is too noisy and lagging for a button-color test.
- **Guardrails** — 2 to 4 metrics that must NOT regress: latency, error rate, crash rate,
  unsubscribe/refund, a north-star like retention. A "win" that wrecks a guardrail is a loss.
- **Diagnostic metrics** — everything else, for understanding *why*, never for deciding.

Avoid composite "OEC" math until you've run a few clean single-metric tests; it hides
which lever actually moved.

## Step 3 — Compute sample size BEFORE launch

You need: baseline rate `p`, minimum detectable effect (MDE), power (0.8), alpha (0.05).
If you can't hit the required N in a reasonable window, stop — redesign or skip.

```ts
// Two-proportion sample size per arm (alpha=0.05 two-sided, power=0.8).
function sampleSizePerArm(baseline: number, mde: number): number {
  const z = 1.96 + 0.84;            // z_{1-α/2} + z_{1-β}
  const p1 = baseline;
  const p2 = baseline + mde;        // absolute MDE, e.g. 0.02 for +2pp
  const pBar = (p1 + p2) / 2;
  const numerator = z * z * 2 * pBar * (1 - pBar);
  return Math.ceil(numerator / ((p2 - p1) ** 2));
}
// e.g. baseline 0.30, MDE +0.02 -> ~8,400 users per arm.
```

Then: `requiredDays = (perArm * numArms) / dailyEligibleUsers`. Round UP to whole weeks to
cover weekday/weekend cycles. Write the planned end date down now.

## Step 4 — Assignment: deterministic, sticky, isolated

- **Deterministic hashing**, not a coin flip per request. Same user → same bucket forever,
  so behavior is consistent and re-renders don't reshuffle.
- Hash a **stable unit** (user id, or a persisted anonymous id) — never session or device
  that rotates. Salt with the experiment key so users aren't correlated across experiments.

```dart
int _bucket(String unitId, String experimentKey, {int buckets = 100}) {
  final digest = sha256.convert(utf8.encode('$experimentKey:$unitId')).bytes;
  // First 4 bytes -> unsigned int -> bucket.
  final n = (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3];
  return (n & 0x7fffffff) % buckets;
}

bool inTreatment(String unitId) => _bucket(unitId, 'checkout_autocomplete_v1') < 50;
```

- Store the assignment as data, not just a runtime branch, so analysis joins cleanly:

```sql
create table experiment_exposure (
  experiment_key text not null,
  unit_id        uuid not null,
  variant        text not null,           -- 'control' | 'treatment'
  exposed_at     timestamptz not null default now(),
  primary key (experiment_key, unit_id)
);
-- Log exposure only when the user actually REACHES the changed surface.
```

Gate the rollout itself behind a flag (see [[feature-flags-and-progressive-delivery]]) so
you can kill it instantly without a deploy.

## Step 5 — Log exposure at the decision point, not at app open

The denominator is "users who could have been affected." Fire the exposure event the moment
the user hits the experimented surface — not on login. Logging too early dilutes the effect
with users who never saw the change and silently kills your power.

Make exposure logging idempotent (upsert on the primary key) and fire it from the same code
path that renders the variant, so assignment and exposure can never disagree.

## Step 6 — Run it clean. Do not peek-and-stop.

The cardinal sin: refreshing the dashboard daily and stopping the instant p < 0.05.
That inflates the false-positive rate far past 5% — you'll "win" tests that are pure noise.

Rules while running:

- **Decide the duration up front and wait it out.** No early stop on a fixed-horizon test.
- If you genuinely need to monitor continuously, use a method built for it: sequential
  testing / always-valid p-values or a pre-registered group-sequential plan with alpha
  spending. Don't bolt peeking onto a fixed-horizon test.
- **Run an A/A sanity check** first or alongside (two identical arms). If A/A shows a
  "significant" difference, your pipeline or randomization is broken — fix before trusting A/B.
- Watch for a **sample-ratio mismatch (SRM)**: if a 50/50 split lands at 48/52 on large N,
  a chi-square test will flag it. SRM means broken assignment or biased exposure logging —
  the whole result is untrustworthy. Stop and debug, don't analyze around it.

## Step 7 — Read results honestly

Report the **effect size with a confidence interval**, not just a p-value. "+1.8pp,
95% CI [0.3, 3.3]" tells you the decision; "p=0.04" alone does not.

- Compare against the **MDE**, not zero. A statistically significant +0.1pp when you needed
  +2pp to justify the work is a practical no.
- **Don't slice until you find a winner.** Subgroup hunting (mobile + new users + Tuesday)
  manufactures false positives. Pre-register any subgroup you'll analyze; otherwise treat
  slices as hypotheses for the *next* test, not conclusions from this one.
- If you test multiple metrics or variants, **correct for multiplicity** (e.g. Bonferroni:
  divide alpha by the number of comparisons) or accept that some "wins" are noise.
- A flat result is a real, valuable answer: the change didn't matter — ship the simpler arm.

## Decision matrix

| Primary | Guardrails | Decision |
|---|---|---|
| Moved ≥ MDE, CI excludes 0 | All healthy | Ship treatment |
| Moved ≥ MDE | A guardrail regressed | Don't ship; investigate trade-off |
| Below MDE / CI spans 0 | Healthy | Ship the cheaper/simpler arm |
| Inconclusive at planned N | — | Extend ONLY if pre-decided; else call it flat |

## Red flags

- No written hypothesis or MDE before launch — you'll rationalize whatever you see.
- Stopping the moment it goes green ("we hit significance!").
- Primary metric chosen *after* looking at the data.
- Exposure logged at app open instead of at the changed surface.
- Sample-ratio mismatch ignored.
- Reporting p-values with no effect size or confidence interval.
- Reusing the same hash salt across experiments, correlating assignments.

## Related

- [[feature-flags-and-progressive-delivery]] — the delivery mechanism and kill switch.
- [[observability-and-instrumentation]] — trustworthy event pipeline for metrics.
- [[data-modeling-and-schema-design]] — exposure/event tables that join cleanly.
- [[slos-and-error-budgets]] — guardrail thresholds grounded in real targets.
- For committing the experiment code, follow [[commit-pipeline]].
