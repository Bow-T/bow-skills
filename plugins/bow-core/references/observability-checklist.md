# Observability Reference

A scannable checklist for making a feature debuggable in production before it ships. Pair this with the `observability-and-instrumentation` skill.

## Contents

- [Frame it as questions](#frame-it-as-questions)
- [Logs](#logs)
- [Metrics](#metrics)
- [Traces](#traces)
- [Alerts](#alerts)
- [Dashboards](#dashboards)
- [Prove the instrumentation works](#prove-the-instrumentation-works)
- [Ship gate](#ship-gate)

## Frame it as questions

Instrumentation only earns its keep when it answers a real on-call question. Start here, not with the SDK.

- [ ] Wrote down the 2–4 questions whoever gets paged will ask ("is it failing? for everyone? since when? where?")
- [ ] Each question is assigned to the signal that answers it best
- [ ] Remember the division of labor: **metrics tell you something is wrong, traces tell you where, logs tell you why**

## Logs

- [ ] Emitted as structured records (JSON) with a stable `event` name — not interpolated sentences
- [ ] A request/correlation ID is attached to every line, created at the edge or read from an inbound header
- [ ] That ID rides along on outbound HTTP calls and queue messages so a request stays joinable across services
- [ ] Levels mean the same thing everywhere:

  | Level | Meaning |
  |---|---|
  | `error` | an invariant broke; a human may need to act |
  | `warn` | handled, but degraded |
  | `info` | a noteworthy business event |
  | `debug` | diagnostic detail, off by default in prod |

- [ ] Zero secrets, tokens, passwords, or raw PII in any field (non-negotiable; see `security-and-hardening`)
- [ ] Logged fields are an explicit allowlist — never dump whole request/response bodies or auth headers
- [ ] Outbound dependency calls log metadata only: target, status, latency, retry count, sanitized IDs
- [ ] Looked at the actual output once — real fields, not `[object Object]` or `Instance of 'Foo'`
- [ ] For Supabase Edge Functions / Postgres, confirmed the function logs reach the project log views and carry the correlation ID

## Metrics

- [ ] Request-facing surfaces carry **rate, error count, and latency** (per endpoint and per external dependency)
- [ ] Finite resources (pools, queues, hosts) carry **utilization, saturation, and errors**
- [ ] Latency is recorded as a histogram so p50/p95/p99 are queryable — never store only an average
- [ ] Label values come from small fixed sets (route template, status class, dependency name)
- [ ] No high-cardinality labels: keep out user IDs, tenant IDs, emails, full URLs, request IDs, and raw error strings
- [ ] Status codes are bucketed by class (`5xx`), not emitted per exact code
- [ ] Every worker/queue reports backlog depth and processing time

## Traces

- [ ] Tracing (OpenTelemetry or equivalent) is initialized at startup, before the modules it needs to wrap
- [ ] Auto-instrumentation is on for HTTP, DB, and RPC clients
- [ ] W3C trace context is injected on outbound calls and extracted on inbound — including across queue boundaries
- [ ] Manual spans wrap only meaningful internal work, and carry the attributes you'd actually filter on
- [ ] No secrets or PII land in span attributes
- [ ] Sampling keeps the default rate low but retains error traces (tail sampling if available)

## Alerts

- [ ] Each alert fires on a **symptom** users feel (error rate, p99 latency, queue age) — causes like CPU or restarts belong on dashboards
- [ ] Each alert is actionable; if the response is "it self-heals, ignore it," delete the alert
- [ ] Each alert links to a runbook with at least: what it means, the first query to run, who to escalate to
- [ ] Thresholds trace back to an SLO or historical data, not a round number someone liked
- [ ] Only two severities exist: **page** (user impact, now) and **ticket** (degradation, this week)
- [ ] Test-fired each new alert once — it landed in the right channel and the runbook link resolves
- [ ] No alert that fires daily and gets acknowledged with no action

## Dashboards

- [ ] A service-health view shows error rate, p99 latency, traffic, and saturation at a glance
- [ ] A dependency view breaks down error rate and latency per downstream service
- [ ] The dashboard directly answers the questions from the top of this file
- [ ] Default time window is operational (roughly 1–6h), not a month

## Prove the instrumentation works

Instrumentation is code and ships with its own bugs. Confirm it, don't assume it:

- [ ] Triggered a failure in staging and found it in the logs via its correlation ID
- [ ] Sent synthetic traffic and watched the metric series appear with the expected labels and believable values
- [ ] Followed a single request end to end in the trace UI with no broken or orphaned spans
- [ ] Diagnosed an injected fault using telemetry alone, without opening the source

## Ship gate

All true before the feature reaches production:

- [ ] Structured logs are arriving in the aggregator
- [ ] Rate/error/latency metrics are visible for each new endpoint and dependency
- [ ] At least one symptom alert exists, has a runbook, and was test-fired
- [ ] A request can be traced across every hop it makes
- [ ] On-call knows where the runbooks live

For the launch-window watch sequence and rollback triggers, see the `shipping-and-launch` skill.
