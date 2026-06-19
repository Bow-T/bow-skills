---
name: observability-and-instrumentation
description: Builds the telemetry that lets you operate a system in production. Trigger when you add logs, metrics, traces, or alerts; when you ship anything that runs in production and need proof it behaves; or when an incident dragged on because nobody could tell what the system was doing.
---

# Observability and Instrumentation

## Overview

A system you cannot observe is a system you cannot run. Instrumentation is the part of a feature that lets an engineer — at 3am, without the author — answer "what is it doing, and why?" purely from the signals it emits. Treat it like tests: written with the feature, not bolted on after the first outage. Ship a feature with no telemetry and the first bug report turns into a dig through source instead of a query.

## When to Use

- Writing any feature destined for production
- Adding an endpoint, background worker, queue consumer, or third-party integration
- A postmortem concluded "we were flying blind"
- Creating or auditing alert rules
- Reviewing a change that introduces I/O, retries, fan-out, or cross-service calls

**Not this skill for:**

- A fire happening right now — use `debugging-and-error-recovery`. Good observability is what makes that skill quick next time.
- Fixing measured slowness — use `performance-optimization`.
- Launch-window monitoring and rollback triggers — use `shipping-and-launch`. This skill produces the signals those checklists read.

## Process

### 1. Write the questions first

Telemetry with no question behind it is just cost. Before emitting anything, list the 2-4 things an on-call engineer will ask about this feature:

```
FEATURE: invoice charge with one retry
ON-CALL WILL ASK:
  - How many charges clear on the first try vs. the retry?
  - When a charge fails for good, what was the cause? (declined / timeout / bad input)
  - Is the payment gateway responding slower than its baseline?
EVERY signal I add must serve one of these.
```

Cannot name the questions? You are not ready to instrument — you will emit everything and learn nothing.

### 2. Match each question to a signal type

| Signal | Best at answering | Cost shape | Example |
|---|---|---|---|
| Structured log | "What happened in this one case?" | Per event; scales with traffic | `charge_failed` carrying the gateway code |
| Metric | "How often / how fast, across all cases?" | Fixed per series; cheap to read | p99 of gateway call duration |
| Trace | "Where did the time go between services?" | Per request; usually sampled | one slow checkout split by hop |

Mental model: metrics say *that* it broke, traces say *where*, logs say *why*.

### 3. Log events, not sentences

Each log line is a structured record with a stable event key and machine-readable fields — never an interpolated string.

```dart
// Weak: a sentence you cannot filter or aggregate
log.info('charge $id failed for user $userId after $attempt tries');

// Strong: stable event name plus typed fields
log.warning({
  'event': 'charge_failed',
  'charge_id': id,
  'gateway': 'stripe',
  'reason': err.code,
  'attempt': attempt,
});
```

Use levels with intent:

| Level | Meaning | On-call response |
|---|---|---|
| error | An invariant broke; someone may need to act | Investigate |
| warn | Degraded but recovered (retry won, fallback used) | Trend-watch |
| info | Notable business event (order placed, job done) | None |
| debug | Diagnostics, off in prod by default | None |

**Carry a correlation ID everywhere.** Mint or accept a request ID at the system edge and attach it to every log, span, and outbound call. Without it you cannot stitch one request out of interleaved output.

```typescript
// Supabase Edge Function: derive a request id and thread it through
const requestId = req.headers.get('x-request-id') ?? crypto.randomUUID();
const log = (fields: Record<string, unknown>) =>
  console.log(JSON.stringify({ request_id: requestId, ...fields }));
```

**Never emit secrets, tokens, full PII, or raw request bodies.** Telemetry is a classic leak path — see `security-and-hardening`. Allowlist the fields you log; do not dump whole objects.

### 4. Metrics with bounded labels

For request-serving code, capture **rate, errors, and duration** on every endpoint and every dependency. Record duration as a histogram so you can read p50/p95/p99 — an average buries the unlucky 1%. For pools and queues, track utilization, saturation, and error count instead.

```typescript
// duration histogram with a SMALL, fixed label set
recordDuration('http_server_duration_ms', elapsedMs, {
  route: '/api/tasks/:id',   // template, not the live URL
  status: '5xx',             // class, not '503'
});
```

**Cardinality is the trap.** Each distinct label combination is its own time series. Labels must come from small fixed sets — route template, status class, gateway name. User IDs, raw URLs, emails, and error text belong in logs and traces, never as labels, or the metrics store buckles.

### 5. Tracing across boundaries

Adopt a vendor-neutral tracer (OpenTelemetry). Auto-instrumentation covers HTTP and most DB clients with almost no code. Add manual spans only around meaningful internal work (`applyDiscount`, `callGateway`) and tag them with the attributes on-call will filter on. The critical rule: **propagate context across every async hop** — HTTP headers, queue message metadata — or the trace snaps at the gap. Sample at a low rate by default but keep 100% of error traces if the backend supports tail sampling.

### 6. Alert on pain, not on causes

Page on symptoms users actually feel; leave causes on dashboards.

```
PAGE-WORTHY (user pain):        DASHBOARD ONLY (a cause):
  error rate > 1% for 5m          CPU at 85%
  p99 latency > 2s                 a pod restarted
  queue age > 10m                  disk at 70%
```

Cause alerts fire when nothing is wrong and miss the failure mode you never imagined. Every alert must: (a) be actionable — if the answer is "ignore, it self-heals", delete it; (b) link a runbook, even three lines (what it means, first query, who to escalate to); (c) have a threshold and duration justified by an SLO or history, not a hunch. Use exactly two tiers: **page** (act now) and **ticket** (fix this week). A third tier teaches people to ignore all of them.

### 7. Prove the telemetry works

Instrumentation is code and can be wrong. Before you call it done:

- Force an error in staging, then find it by correlation ID — confirm fields are structured, not `[object Object]`.
- Drive test traffic and confirm the metric series appear with the right labels and sane values.
- Follow one request end-to-end in the trace UI with no broken spans.
- Temporarily lower each new alert's threshold so it fires once — confirm it reaches the right channel and the runbook link resolves.

## Common Rationalizations

| Excuse | Reality |
|---|---|
| "I'll add logging once it works" | "Once" becomes "after the first incident" — the worst moment to learn you are blind. |
| "More logs means more visibility" | Unstructured volume slows incidents. Three queryable events beat 300 prose lines. |
| "print/console is fine for now" | Unstructured output cannot be filtered, correlated, or alerted on. The structured logger costs five minutes once. |
| "Dashboards will tell us when it breaks" | Dashboards built without questions show everything except the answer. Start from on-call questions. |
| "Alert on everything, tune later" | A noisy pager trains people to ignore it; the tuning never happens and the real page gets missed. |
| "User ID as a label helps debugging" | It also melts the metrics store. High-cardinality lookups live in logs and traces. |
| "Two services don't need tracing" | Two services already raise cross-service latency questions logs can't answer; auto-instrumentation makes it nearly free. |

## Red Flags

- A PR with retries/queues/external calls and zero new telemetry
- Log lines assembled by string interpolation
- No correlation ID — every line is an orphan
- Metrics labeled by user ID, raw URL, or error text
- Latency reported only as an average
- Alerts acknowledged daily with no action taken
- Causes (CPU, memory) paging humans while user-facing error rate goes unwatched
- Secrets or full bodies showing up in logs
- "Works on my machine" offered as the only health evidence

## Verification

- [ ] On-call questions for the feature are written down and every signal maps to one
- [ ] All log output is structured with stable event names and a correlation ID per line
- [ ] No secrets, tokens, or raw PII in any line (checked against real output)
- [ ] Rate/errors/duration exist for each endpoint and dependency, with bounded labels
- [ ] Latency is a histogram; p95/p99 are queryable
- [ ] One request can be followed end-to-end with no broken spans
- [ ] Each new alert is symptom-based, runbook-linked, and was test-fired once
- [ ] An induced staging failure was located from telemetry alone

For the condensed version of this list plus the pre-launch instrumentation gate, see `references/observability-checklist.md`.

When committing instrumentation changes, follow the `commit-pipeline` skill.
