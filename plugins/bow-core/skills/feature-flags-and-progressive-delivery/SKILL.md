---
name: feature-flags-and-progressive-delivery
description: Trigger when decoupling deploy from release — shipping behind flags, running canary or percentage rollouts, A/B experiments, kill-switches for risky features, or managing flag lifecycle and cleanup.
---

# Feature Flags & Progressive Delivery

Deploy is not release. Code merges and ships dark; a flag decides who sees it and when. This skill is the process for getting risky code into production safely and removing the flag before it rots.

## Step 1 — Decide if you even need a flag

Add a flag only when the answer to one of these is yes:

- **Release gate** — code must merge before it's ready for users (decouple deploy from release).
- **Risk control** — feature touches money, auth, data writes, or a hot path; you want an instant off-switch.
- **Gradual exposure** — you want to ramp 1% → 100% and watch metrics.
- **Experiment** — you're measuring whether a variant moves a metric.

If none apply, ship it plainly. Every flag is a branch in your code and a row in your config — it has a carrying cost.

## Step 2 — Pick the flag type up front

Different intents have different lifetimes. Name and track them differently.

| Type | Lifetime | Removal trigger |
|------|----------|-----------------|
| Release toggle | days–weeks | 100% + soak period passed |
| Experiment | one experiment cycle | result called, winner shipped |
| Ops / kill-switch | permanent | never (it's infrastructure) |
| Permission / entitlement | permanent | belongs in authz, not flags |

Red flag: a "temporary" release toggle that's been at 100% for three months. That's dead code with a config dependency.

## Step 3 — Model the flag evaluation

Evaluate flags through a single typed interface. Never scatter `if (config.someBool)` reads across the codebase — you lose the ability to target, ramp, or audit.

A flag evaluation needs: a **key**, a **context** (who/what is asking), and a **default** that is correct if the flag service is unreachable.

TypeScript edge function (Supabase) reading flags from a table with RLS:

```ts
type FlagContext = { userId?: string; cohort?: string };

async function isEnabled(
  key: string,
  ctx: FlagContext,
  fallback = false, // safe default if lookup fails
): Promise<boolean> {
  const { data, error } = await supabase
    .from("feature_flags")
    .select("enabled, rollout_pct, allow_cohorts")
    .eq("key", key)
    .maybeSingle();

  if (error || !data) return fallback;
  if (!data.enabled) return false;
  if (data.allow_cohorts?.includes(ctx.cohort)) return true;
  return bucket(ctx.userId ?? "anon", key) < data.rollout_pct;
}

// Deterministic, sticky bucketing: same user always lands the same place.
function bucket(unit: string, salt: string): number {
  const h = hashFnv32(`${salt}:${unit}`);
  return (h % 100) + 1; // 1..100
}
```

The bucketing must be **deterministic and sticky** — hash `(flagKey, stableId)`, never `Math.random()`. Random bucketing flickers a user in and out between requests and ruins both UX and experiment validity.

## Step 4 — Wire the client (Flutter)

Fetch flags once at session start, expose them through a provider, and **cache the last-known values** so a cold start with no network still renders something sane.

```dart
class FeatureFlags {
  FeatureFlags(this._values);
  final Map<String, bool> _values;

  bool isOn(String key, {bool fallback = false}) =>
      _values[key] ?? fallback;
}

// Gate UI on the flag; keep the old path until the flag is retired.
final flags = ref.watch(featureFlagsProvider);
if (flags.isOn('new_checkout_flow')) {
  return NewCheckout();
}
return LegacyCheckout();
```

Rules for the client:
- **Default off / default to the old path.** A failed fetch must never expose unfinished UI.
- **Read the flag once per render path**, not deep inside widgets, so behavior is consistent within a screen.
- **Never gate a destructive migration purely client-side** — the server must enforce the same gate, or an old app build bypasses it.

## Step 5 — Roll out progressively

Ramp on a schedule with explicit checkpoints, not vibes:

1. **Internal / dev cohort** — `allow_cohorts: ['staff']`. Dogfood it.
2. **Canary 1%** — watch error rate, latency p95, and the feature's own success metric.
3. **5% → 25% → 50% → 100%**, holding at each step long enough to clear your slowest signal (often a full business cycle, not 10 minutes).
4. At each step, compare the flagged cohort against the rest — not against yesterday.

Define **abort criteria before you start**: e.g. error rate > 2× baseline, or p95 latency regression > 20%. Hitting them flips the kill-switch automatically or pages someone.

## Step 6 — Kill-switches must be instant and isolated

A kill-switch is only real if it works when everything else is on fire.

- Flipping it is a **config change, not a deploy** — no rebuild, no release pipeline.
- The off-path must not depend on the thing you're killing (no calling the broken service to decide whether to call the broken service).
- Test the off-path in CI like any other branch. An untested fallback is not a fallback.

## Step 7 — Experiments (A/B) need a measurement contract

If the flag is an experiment, decide before launch:

- The **single primary metric** and the minimum effect worth shipping.
- The **unit of assignment** (user, session, account) and stick to it.
- A **guardrail metric** (latency, error rate, churn) that vetoes a "winning" variant.

Don't peek-and-stop the moment it looks good — call the result at the pre-committed sample or duration. Emit an exposure event the instant a user is bucketed, joined to outcomes downstream.

## Step 8 — Retire the flag (the step everyone skips)

A flag at 100% with a passed soak window is a cleanup ticket, not a feature.

1. Delete the dead branch and the losing variant's code.
2. Remove the flag read and its provider plumbing.
3. Delete the flag row / config entry **last**, after the code referencing it is gone.
4. Commit per [[commit-pipeline]].

Run a periodic flag audit: list every flag, its age, its last evaluation, and its owner. Anything stale or unowned gets a removal ticket. Cross-link DB-side flag tables and RLS to your data conventions via [[octopus-model]].

## Red flags

- A flag with no owner and no removal date.
- Nested flags gating other flags — combinatorial states no one has tested.
- Client-only enforcement of a server-side risk.
- `Math.random()` bucketing or non-sticky assignment.
- A "kill-switch" that requires a deploy to flip.
- Default-on fallbacks that expose half-built features when the flag service is down.
- Reading raw config booleans instead of going through the evaluation interface.
