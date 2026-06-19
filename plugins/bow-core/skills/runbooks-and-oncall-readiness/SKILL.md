---
name: runbooks-and-oncall-readiness
description: Triggers when authoring runbooks for known failure modes, defining alert response procedures, preparing on-call handoffs, documenting escalation paths, or making a new service operationally production-ready.
---

# Runbooks & On-Call Readiness

A service is not "done" when it ships. It is done when someone who has never
touched the code can keep it alive at 3 AM. This skill is the process for
getting there.

## 0. Readiness gate (run before declaring a service production-ready)

Answer every line. A "no" is a launch blocker, not a follow-up ticket.

- [ ] Every page-worthy alert links to a runbook section by anchor.
- [ ] The service has a named owner team and a documented escalation chain.
- [ ] A new on-call can find logs, dashboards, and the deploy/rollback path in under 2 minutes.
- [ ] At least the top 3 failure modes have written, tested recovery steps.
- [ ] There is a safe "do nothing yet" path for ambiguous alerts.

If you cannot fill the gate, the service is not ready. Stop and write the runbook.

## 1. Enumerate failure modes from real signals, not imagination

Do not brainstorm a hypothetical list. Mine reality:

1. Read the last 90 days of incidents and error logs.
2. List every external dependency and ask "what happens when this is slow / down / wrong?"
   - Supabase: connection pool exhaustion, RLS denial spikes, migration drift, expired JWT, rate limits on edge functions.
   - Flutter client: forced-upgrade gate, offline queue overflow, push token rotation.
   - TypeScript backend: unhandled promise rejection crash loop, queue backpressure, cold-start latency.
3. For each, classify: **detectable** (you have an alert) vs **silent** (you don't). Silent failures are the dangerous ones — add detection before writing a runbook.

Red flag: a runbook for a failure you have no way to detect. That is a monitoring gap wearing a runbook costume.

## 2. Write each runbook entry to a fixed shape

One entry per failure mode. Keep it skimmable under stress. Use this template:

```markdown
## [Alert name] — e.g. "Supabase connection pool >90%"

**Symptom**    What the on-call sees: alert text, user-facing impact.
**Severity**   SEV1 (outage) / SEV2 (degraded) / SEV3 (annoying).
**Verify**     Exact command/dashboard to confirm it is real, not a flap.
**Diagnose**   2-4 ranked hypotheses, most likely first.
**Mitigate**   Fastest action to stop the bleeding (often != root-cause fix).
**Rollback**   Exact command to revert the last deploy if relevant.
**Escalate**   When to wake someone, and who.
**After**      What to capture for the postmortem.
```

Worked example:

```markdown
## Edge function 5xx rate >5% for 5m

**Symptom**  Alert "edge-fn-checkout 5xx". Users see "payment failed".
**Severity** SEV1 if checkout, SEV2 otherwise.
**Verify**   supabase functions logs checkout --project-ref <ref> | tail -50
**Diagnose** 1) bad deploy in last 30m  2) downstream payment API down
             3) DB pool exhausted (check pool dashboard).
**Mitigate** If (1): roll back. If (2): flip `PAYMENTS_DISABLED` flag, show
             maintenance copy. If (3): see pool runbook.
**Rollback** supabase functions deploy checkout --version <prev>
**Escalate** Page payments-domain owner if downstream API confirmed down >10m.
**After**    Save log excerpt + flag timestamps to the incident doc.
```

Rules for good entries:
- **Commands must be copy-pasteable.** Placeholders in `<angle brackets>`, nothing else to guess.
- **Mitigation before root cause.** The job at 3 AM is to stop pain, then investigate.
- **One screen per entry.** If it scrolls, you split it.

## 3. Make mitigations real and reversible

Every "Mitigate" step should map to a mechanism that exists today:

- **Feature flags** for risky paths — default to the safe state.
- **Kill switches** for non-essential workloads (analytics, batch jobs) so they shed under load.
- **Idempotent rollback** — verify the previous deploy artifact is still available.

```dart
// Client honors a server-controlled kill switch, fails safe (closed) on error.
final disabled = await config.boolFlag('checkout_disabled', orElse: true);
if (disabled) return CheckoutClosedScreen();
```

Red flag: a runbook step that says "restart the service" with no explanation of why that helps. Restarting hides root cause and resets your evidence. Only use it when you know the mechanism (e.g. clearing a leaked connection pool) and you have captured state first.

## 4. Define alert response procedures (the alert IS the entry point)

An alert that does not link to its runbook is half-built. Wire it in the alert definition:

```yaml
- alert: SupabasePoolNearLimit
  expr: db_pool_in_use / db_pool_max > 0.9
  for: 3m
  annotations:
    summary: "Connection pool >90% on prod"
    runbook: "https://runbooks/<service>#supabase-connection-pool"
```

Calibrate before you trust:
- Every page-level alert must be **actionable** — if the only response is "watch it," it is a dashboard, not a page.
- Tune `for:` windows so transient spikes don't page. Track your **alert-to-action ratio**; if most pages need no action, you are training the on-call to ignore alarms.
- Distinguish **page now** (user impact) from **ticket** (degradation, business hours).

## 5. Escalation paths — make "who do I wake" unambiguous

```
L1  On-call engineer        responds within 5m, owns mitigation
L2  Service/domain owner     paged if L1 unresolved in 15m or scope unclear
L3  Engineering lead         paged for SEV1 >30m or cross-team impact
Side channels: data-loss -> security/compliance; payments -> finance owner
```

State the **trigger condition** for each hop, not just the names-by-role. "Escalate to L2" is useless without "when 15m have passed without mitigation." Include who declares an incident and who owns external/customer comms.

## 6. On-call handoff procedure

Run at every rotation change. A 5-minute handoff prevents a 2-hour rediscovery.

```markdown
### Handoff <date> — <outgoing role> -> <incoming role>
- Open incidents / watching: ...
- Deploys in flight or frozen: ...
- Known-flaky alerts to expect (and ignore): ...
- Recent changes that might bite: ...
- Anything fragile until <date>: ...
```

Red flags: silent handoffs; knowledge that lives only in one person's head; "ask me if it breaks" as the actual plan.

## 7. Keep runbooks alive (the part everyone skips)

A stale runbook is worse than none — it sends the on-call down a dead path with false confidence.

- **Touch on use.** Every incident must update the runbook it used (or note "no runbook existed" -> create one).
- **Drill quarterly.** Pick one entry, have someone unfamiliar follow it verbatim. If they get stuck, the runbook is wrong, not them.
- **Review on change.** When a command, dashboard URL, or dependency changes, the runbook changes in the same PR.
- **Date and own each entry.** An entry not verified in 6 months is suspect.

## 8. Commit & deliver

Land runbooks in version control alongside the service, reviewed like code.
Follow [[commit-pipeline]] for commit message format. Related: [[observability-and-instrumentation]] for the signals your alerts depend on, and [[incident-postmortems]] for turning incidents back into runbook entries.

---

**The one test:** hand the runbook to an engineer who has never seen the
service and simulate the alert. If they cannot mitigate it from the document
alone, it is not ready — and neither is the service.
