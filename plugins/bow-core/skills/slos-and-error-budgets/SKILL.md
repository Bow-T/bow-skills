---
name: slos-and-error-budgets
description: Use when defining SLIs/SLOs, choosing reliability targets to promise, computing or burning error budgets, trading features against stability, or negotiating SLAs.
---

# SLOs and Error Budgets

A target without measurement is a wish. This is the process for turning "it should be reliable" into a number you can act on.

## 1. Find the journey, not the server

Pick the 3-5 critical user journeys (CUJs). Reliability is measured at the journey edge, not at internal components.

- "User opens the feed and sees their latest items"
- "User submits a payment and gets confirmation"
- "User uploads a photo and it appears"

Red flag: your SLI is "CPU < 80%" or "pod is healthy". Those are causes, not the user's experience. Measure the outcome.

## 2. Define each SLI as good / total

An SLI is a ratio of good events over valid events, in plain words first, then as a query.

- **Availability**: successful responses / valid requests.
- **Latency**: requests faster than threshold / valid requests.
- **Quality / correctness**: responses without a degraded fallback / total.
- **Freshness**: reads served data younger than T / total reads.

Decide what counts as *valid*. A 400 from a malformed client request is usually excluded; a 401 from your broken auth is not. Write the exclusion down — it is where arguments happen later.

Example: latency SLI over a Supabase-backed API, measured server-side.

```sql
-- good = served under 300ms; total = all non-4xx user requests
select
  count(*) filter (where duration_ms <= 300 and status < 500) as good,
  count(*) filter (where status not between 400 and 499)       as total
from request_logs
where ts >= now() - interval '28 days';
```

Measure at the point closest to the user you control. Client-side beats server-side for truth, but only if you can trust the telemetry pipeline.

## 3. Set the SLO target deliberately

The SLO is the threshold the SLI must stay above over a window.

- Use a rolling window (28 days is the sane default). Calendar months reset the budget on the 1st and hide bad weeks.
- Start from observed past performance, not an aspiration. If you currently do 99.5%, do not promise 99.99%.
- Add nines only when a user can perceive the difference *and* you will pay to maintain it.

| SLO | Downtime / 28 days | Downtime / day |
|------|-------------------|----------------|
| 99% | ~6.7 h | ~14.4 min |
| 99.5% | ~3.4 h | ~7.2 min |
| 99.9% | ~40 min | ~1.4 min |
| 99.95% | ~20 min | ~43 s |
| 99.99% | ~4 min | ~8.6 s |

Decision point: each extra nine roughly multiplies engineering cost. Pick the lowest SLO users will not complain about.

## 4. Compute the error budget

```
error_budget       = 1 - SLO
budget_consumed    = (1 - actual_SLI) / error_budget
budget_remaining   = 1 - budget_consumed
```

At SLO 99.9%, the budget is 0.1% of events. If you served 1M requests, you may fail 1000 before breaching.

```dart
double budgetRemaining({
  required double slo,        // 0.999
  required int totalEvents,
  required int badEvents,
}) {
  final allowedBad = (1 - slo) * totalEvents;
  return allowedBad == 0 ? 0 : 1 - (badEvents / allowedBad);
}
```

The budget is permission to take risk. A budget at 100% means you are over-investing in reliability and under-shipping.

## 5. Alert on burn rate, not on the raw SLI

Page on how *fast* the budget is burning, so noisy short blips don't wake anyone and slow leaks still get caught.

```
burn_rate = (bad_events / total_events) / error_budget
```

A burn rate of 1 exhausts the whole window's budget exactly on time. Use multi-window, multi-burn-rate alerts:

| Severity | Burn rate | Short window | Long window |
|----------|-----------|--------------|-------------|
| Page | 14.4 | 5 min | 1 h |
| Page | 6 | 30 min | 6 h |
| Ticket | 1 | 6 h | 24 h |

The short window confirms the problem is still happening; the long window confirms it's significant. Both must trip.

## 6. Enforce the policy

The error budget only matters if breaching it changes behavior. Agree this *before* an incident:

- **Budget healthy (> ~30% left)**: ship features, take deploy risk, run chaos tests.
- **Budget low (< ~30%)**: slow risky launches, prioritize reliability work.
- **Budget exhausted**: feature freeze on the affected service until burn stops and budget recovers; the next sprint's top item is the root cause.

Red flag: every breach is met with "let's just raise the SLO." That converts the budget into theater. Lower the SLO only with explicit sign-off and a written reason.

## 7. SLA vs SLO — keep a buffer

An SLA is an external promise with consequences (refunds, credits). An SLO is your internal target.

- Always set the SLO **stricter** than the SLA. If the SLA is 99.5%, run an internal SLO of 99.9%, so you start fixing things long before money is at stake.
- Never expose internal SLIs verbatim in a contract. Define SLA terms with their own measurement method, exclusions (maintenance windows, force majeure), and a clear claim process.
- Quote the SLA over the *contractual* window the customer cares about (usually monthly), even if you operate on a rolling internal window.

## 8. Operationalize

- Store SLI definitions as code/config next to the service, version-controlled, reviewed like any change.
- Render budget + burn rate on a dashboard everyone reads in standup.
- Re-baseline SLOs quarterly: if you've sat at 100% budget for two quarters, the target is too loose.

## Red flags checklist

- SLI measures a component (CPU, queue depth) instead of a user outcome.
- "100% uptime" anywhere — it is a lie and it removes the budget.
- Budget never moves: telemetry is broken or events are misclassified.
- Alerts fire on instantaneous error rate, paging on every transient spike.
- SLO equals SLA: no safety margin before penalties hit.
- No written policy for what an exhausted budget triggers.

## Related

- [[incident-response-and-postmortems]] — what to do when the budget burns fast.
- [[observability-and-structured-logging]] — the telemetry your SLIs depend on.
- [[commit-pipeline]] — for committing SLO definitions and policy changes.
