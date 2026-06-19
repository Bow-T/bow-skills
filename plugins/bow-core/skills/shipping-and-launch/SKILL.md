---
name: shipping-and-launch
description: Drives a safe production launch. Trigger when preparing to deploy, when you need a pre-launch checklist, when wiring up launch monitoring, when planning a phased rollout, or when you need a rollback plan ready before you push.
---

# Shipping and Launch

## Overview

The aim of a launch is not "it's deployed" — it's "it's deployed, we can see it working, and we can take it back in under a minute." Hold every release to three properties: reversible, observable, incremental. A change that has none of those is not a launch, it's a gamble.

## When to Use

- Putting a feature into production for the first time
- Rolling out a meaningful change to real users
- Moving data or infrastructure
- Opening a beta or limited-access cohort
- Any deploy that carries risk (that is all of them)

## Pre-Launch Gate

Walk these groups before you push. A red item is a blocker, not a note for later.

**Correctness**
- [ ] Unit, integration, and end-to-end tests green
- [ ] Build clean, no warnings
- [ ] Lint and type checks pass
- [ ] Reviewed and approved
- [ ] No leftover debug prints or unresolved blocking TODOs
- [ ] Known failure modes are handled, not just the happy path

**Security** — depth lives in `security-and-hardening`
- [ ] No secrets committed
- [ ] Dependency audit shows no critical/high issues
- [ ] User input validated at every entry point
- [ ] Auth and authorization enforced on protected paths
- [ ] Security headers and per-origin CORS configured (no wildcard)
- [ ] Rate limiting on auth and abuse-prone endpoints

**Performance** — depth lives in `performance-optimization`
- [ ] Core Web Vitals in "Good" range
- [ ] No N+1 queries on hot paths; indexes present
- [ ] Images sized, compressed, and lazy-loaded below the fold
- [ ] Bundle within budget
- [ ] Caching set for static assets and repeated reads

**Accessibility**
- [ ] Every interactive element reachable by keyboard
- [ ] Screen reader conveys structure and content
- [ ] Text contrast meets WCAG 2.1 AA (4.5:1)
- [ ] Focus is managed for modals and dynamic regions
- [ ] Form errors are descriptive and tied to their fields

**Infrastructure & observability**
- [ ] Production environment variables set
- [ ] Migrations applied or staged to apply
- [ ] DNS, TLS, CDN configured
- [ ] Health endpoint live and responding
- [ ] Logs, metrics, and error reporting flowing (see `observability-and-instrumentation`)

**Docs** — see `documentation-and-adrs`
- [ ] Setup/README updated for any new requirements
- [ ] API docs current
- [ ] ADR written for any architectural choice
- [ ] Changelog and user-facing docs updated where relevant

## Decouple Deploy from Release with Flags

Ship the code dark, switch it on later.

```dart
// Read the flag, fall back to existing behavior
final flags = await featureFlags.forUser(userId);
if (flags.taskSharing) {
  return TaskSharingPanel(task: task);
}
return const SizedBox.shrink();
```

Flag lifecycle:

```
deploy OFF      code in prod, inactive
team/beta ON    dogfood in the real environment
ramp ON         5% -> 25% -> 50% -> 100%
watch each step error rate, latency, feedback
retire          delete the flag AND the dead branch
```

Rules: every flag has an owner and an expiry; retire it within roughly two weeks of full rollout; never nest flags (the state space explodes); exercise both states in tests.

## Phased Rollout

```
1. Staging          full suite + manual smoke of critical flows
2. Prod, flag OFF   confirm deploy succeeded; no new errors
3. Team ON          internal use in prod; watch ~24h
4. Canary 5%        compare canary vs. baseline; watch 24-48h;
                    advance only if the table below stays green
5. Ramp             25% -> 50% -> 100%, same checks each step,
                    able to drop back a tier at any moment
6. Full ON          watch ~1 week, then retire the flag
```

### Advance / Hold / Roll Back

| Metric | Advance (green) | Hold (yellow) | Roll back (red) |
|---|---|---|---|
| Error rate | within 10% of baseline | 10-100% over | > 2x baseline |
| p95 latency | within 20% | 20-50% over | > 50% over |
| Client JS errors | no new types | new at < 0.1% of sessions | new at > 0.1% |
| Business metric | flat or up | dip < 5% (maybe noise) | dip > 5% |

Roll back immediately, without debate, on: error rate past 2x baseline, p95 past 50% over, a spike in user reports, any data-integrity problem, or a security finding.

## Watch the Launch

Track three layers: **application** (error rate by endpoint, p50/p95/p99 latency, request volume, active users, key business metrics), **infrastructure** (CPU/memory, DB pool usage, disk, queue depth), and **client** (Core Web Vitals, JS errors, client-side API error rate). The instrumentation that produces these signals belongs to `observability-and-instrumentation`; this skill is about reading them during a release.

Catch and report errors at both ends:

```typescript
// Supabase Edge Function: report, but never leak internals to the caller
try {
  return await handle(req);
} catch (err) {
  reportError(err, { route: new URL(req.url).pathname, requestId });
  return new Response(
    JSON.stringify({ error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' } }),
    { status: 500, headers: { 'content-type': 'application/json' } },
  );
}
```

### First Hour After Launch

```
1. Health endpoint returns 200
2. Error dashboard: no new error types
3. Latency dashboard: no regression
4. Manually run the critical user flow
5. Confirm logs are flowing and legible
6. Sanity-check the rollback path (dry run if you can)
```

## Rollback Plan

Write this before the deploy, not during the incident.

```markdown
## Rollback: <feature/release>

### Triggers
- error rate > 2x baseline
- p95 latency > <X>ms
- user reports of <specific symptom>

### Steps
1. Flip the feature flag off   (preferred, < 1 min)
   — or — redeploy the prior release  (< 5 min)
2. Verify: health check + error dashboard
3. Notify the team

### Data
- migration <X> reversal: <command / "forward-only, compensating fix is Y">
- rows written by the new path: <kept / cleaned up>
```

Reverting a release commit follows the `commit-pipeline` skill. Forward-only migrations need a compensating change, not a destructive down-migration on live data — coordinate with `deprecation-and-migration`.

## Common Rationalizations

| Excuse | Reality |
|---|---|
| "It worked in staging" | Prod has different data, traffic, and edges. Watch it after deploy. |
| "This doesn't need a flag" | Every feature benefits from a kill switch; "simple" changes break things too. |
| "Monitoring is overhead" | Without it you learn of failures from users, not dashboards. |
| "We'll add monitoring later" | You cannot debug what you cannot see — add it before launch. |
| "Rolling back admits failure" | Rolling back is the responsible move; shipping a broken feature is the failure. |

## Red Flags

- Deploying with no rollback plan
- No monitoring or error reporting in prod
- Big-bang release straight to everyone
- Flags with no owner or expiry
- Nobody watching the first hour
- Prod config set from memory instead of code
- "It's Friday, let's ship it"

## Verification

Before deploy:
- [ ] Pre-launch gate fully green
- [ ] Flag configured if used
- [ ] Rollback plan written
- [ ] Dashboards ready
- [ ] Team notified

After deploy:
- [ ] Health check 200
- [ ] Error rate normal
- [ ] Latency normal
- [ ] Critical flow works
- [ ] Logs flowing
- [ ] Rollback verified ready

## See Also

- Security pre-launch detail: `references/security-checklist.md`
- Performance pre-launch detail: `references/performance-checklist.md`
- Accessibility pre-launch detail: `references/accessibility-checklist.md`
