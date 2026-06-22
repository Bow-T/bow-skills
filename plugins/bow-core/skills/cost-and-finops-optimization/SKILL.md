---
name: cost-and-finops-optimization
description: Trigger when cloud, infra, or LLM spend spikes or needs forecasting — attribute cost, right-size, kill waste, and add guardrails.
---

# Cost & FinOps Optimization

A spend investigation is a debugging session, not a budgeting meeting. Find the
top contributors, prove the cause, fix the biggest one, then add a guardrail so
it cannot silently return.

## 0. Frame the problem before touching dashboards

Answer these first — they decide the whole approach:

- **What changed?** A step-up usually beats a slow drift. Pin the date.
- **Is it volume or unit cost?** More requests vs. each request got pricier.
- **Is it a fire or a forecast?** A doubled bill this month is triage; "will we
  survive scale" is modeling. Do not mix the two in one pass.

Red flag: someone proposes a fix before anyone has named the top-3 line items.
Stop and measure.

## 1. Attribute: split the bill until one number dominates

You cannot optimize what you cannot attribute. Slice the bill along axes until
~80% of the delta lands in a few buckets.

Slice by: **service** (DB, storage, egress, functions, LLM) → **environment**
(prod/staging/preview) → **feature/tenant** → **unit** (per-user, per-request).

Make cost queryable instead of staring at provider UIs. Log a cost-relevant
event next to the work itself:

```ts
// Emit one row per billable unit of work; aggregate later in SQL.
await supabase.from('usage_events').insert({
  tenant_id: tenantId,
  surface: 'chat.completion',
  model: 'claude-haiku',
  input_tokens: usage.input_tokens,
  output_tokens: usage.output_tokens,
  cached_input_tokens: usage.cache_read_input_tokens ?? 0,
  cost_usd: estimateCost(usage),     // compute from a pinned price table
  occurred_at: new Date().toISOString(),
});
```

```sql
-- Where does the money actually go this week?
select surface, model,
       sum(cost_usd)              as spend,
       count(*)                   as calls,
       sum(cost_usd) / count(*)   as cost_per_call
from usage_events
where occurred_at >= now() - interval '7 days'
group by 1, 2
order by spend desc
limit 20;
```

Tag everything at the source. Untagged resources are the dark matter of every
cloud bill — chase them down before modeling anything.

## 2. Diagnose the dominant bucket

Match the top line item to its usual cause:

- **Database** — idle compute on an oversized instance; missing indexes forcing
  scans; bloated connection pools; storage never reclaimed. Check
  `get_advisors` for unindexed/sequential-scan hot paths before resizing.
- **Egress / bandwidth** — cross-region chatter, unbatched calls, no CDN in
  front of static or media. Egress is the silent killer; map it explicitly.
- **Edge functions / serverless** — cold-start retries, runaway recursion, a
  cron firing far more often than intended, fan-out with no concurrency cap.
- **Storage** — old versions, orphaned uploads, logs/backups with no retention.
- **LLM** — wrong model tier for the job, no caching, oversized context, and
  retries that re-pay full price. See §4.

## 3. Fix: right-size and remove waste

Order fixes by **dollars saved per hour of work**, not by ease or elegance.

1. **Delete waste** (free wins): stop idle/zombie resources, set retention on
   logs and backups, drop unused preview environments and old branches.
2. **Right-size** (measure, then cut): downsize the over-provisioned tier; add
   the missing index; cache the hot read. Confirm headroom on real peak load,
   not averages — averages hide the spike that triggers a costly scale-up.
3. **Re-architect** (only if 1–2 are exhausted): batch, debounce, move to a
   pull/queue model, add a CDN, or shift cold data to cheaper storage.

Right-sizing rule: cut to the tier where peak utilization sits near 60–70%.
Tighter than that and the next spike pages you; looser and you are paying for
air. Change one variable at a time so you can read the result on the bill.

```sql
-- Reclaim storage: find orphaned uploads with no owning row.
select o.name, o.metadata->>'size' as bytes
from storage.objects o
left join documents d on d.storage_path = o.name
where d.id is null
  and o.created_at < now() - interval '30 days';
```

## 4. LLM-specific levers (high leverage, easy to misjudge)

LLM bills move on four dials — pull them in this order:

1. **Right-size the model.** Most calls do not need your most capable tier.
   Route by task difficulty: cheap/fast model for classification, extraction,
   and routing; the strong model only for hard reasoning or final synthesis.
2. **Cache the stable prefix.** Long system prompts, tool definitions, and
   few-shot examples re-sent every call are pure waste — cached input is far
   cheaper than fresh input. Order context stable-first so the cache hits.
3. **Shrink context.** Retrieve top-k chunks instead of stuffing documents;
   trim conversation history; summarize old turns. Output tokens usually cost
   more than input — cap `max_tokens` and ask for terse, structured output.
4. **Stop paying twice.** Retries, agent loops, and judge passes silently
   multiply cost. Cap loop iterations and log token spend per loop.

For exact model ids, current prices, and caching mechanics, defer to the
**[[claude-api]]** skill — never hardcode prices from memory; pin them in one
table and reference it.

Red flag: a single agent run with no iteration cap. One bad loop can outspend a
month of normal traffic in an afternoon.

## 5. Guardrails: make the regression impossible to miss

A fix without a guardrail is a fix that silently reverts. Add at least one:

- **Budget alert at a threshold below the limit** (e.g. 70% of monthly cap) so
  you act before, not after, the overage.
- **Per-tenant / per-key rate or spend cap** to contain abuse and runaway loops.
- **A daily cost-delta report** in CI or a scheduled job that flags week-over-
  week jumps by surface.

```sql
-- Daily guardrail: flag surfaces whose cost jumped >40% vs. prior day.
with d as (
  select surface, occurred_at::date as day, sum(cost_usd) as spend
  from usage_events
  where occurred_at >= now() - interval '2 days'
  group by 1, 2
)
select t.surface, y.spend as yesterday, t.spend as today,
       round((t.spend - y.spend) / nullif(y.spend, 0) * 100) as pct_change
from d t
join d y on y.surface = t.surface and y.day = t.day - 1
where t.spend > y.spend * 1.4;
```

```ts
// Hard ceiling per request so a bad input cannot run up the bill.
const MAX_OUTPUT_TOKENS = 1024;
const MAX_AGENT_STEPS = 8;
if (step >= MAX_AGENT_STEPS) throw new Error('agent step budget exceeded');
```

## 6. Forecast (only when asked to model growth)

Tie spend to a business driver, not to wall-clock time. Pick the driver that
actually moves cost (active users, requests, GB stored), compute current
**cost-per-driver-unit**, then project against the growth plan.

```
projected_monthly = cost_per_unit * projected_units * (1 - expected_efficiency)
```

State assumptions explicitly and give a range, not a single number. Flag every
cost that scales super-linearly (egress, cross-region, unbounded retries) — those
break naive linear forecasts and are where the budget actually dies.

## Done checklist

- [ ] Top-3 cost buckets named and attributed to a cause.
- [ ] Biggest waste deleted or right-sized; result visible on the bill.
- [ ] At least one guardrail (alert, cap, or daily delta report) live.
- [ ] Price tables pinned, not memorized; LLM model routing reviewed.
- [ ] Changes committed per **[[commit-pipeline]]**.

Resist gold-plating: ship the fix for the dominant bucket and the guardrail,
then stop. A 2% line item is not worth a refactor.
