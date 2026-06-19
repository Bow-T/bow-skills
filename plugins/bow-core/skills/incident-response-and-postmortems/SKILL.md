---
name: incident-response-and-postmortems
description: Use when production is down or degraded, when coordinating a live response, declaring severity and comms, or writing a blameless postmortem with corrective actions.
---

# Incident Response and Postmortems

Two phases, opposite mindsets. During the incident: stop the bleeding, defer understanding. After: understand deeply, blame nothing.

## Phase 1: Triage (first 5 minutes)

Goal is a shared picture, not a fix. Do not theorize yet.

1. **Confirm it's real.** Reproduce the symptom or see it in two signals (dashboard + user report). One flaky alert is not an incident.
2. **Assign severity.** Pick the highest matching row; when unsure, round up.

| Sev | Meaning | Example |
|-----|---------|---------|
| SEV1 | Core flow broken for most users, or data loss/leak | Login down, payments failing, PII exposed |
| SEV2 | Major feature down or severe degradation for a segment | Push notifications dead, p99 latency 10x |
| SEV3 | Minor/partial, has a workaround | One report export fails, cosmetic break |

3. **Name an Incident Commander (IC).** One person. The IC coordinates and decides — they do NOT debug. Whoever declares is IC until handed off explicitly ("you are now IC, confirm?").
4. **Open one channel of record.** A dedicated thread. Every action, timestamp, and finding goes there. If it isn't written down, it didn't happen.

## Phase 2: Stabilize

The IC drives a loop: **observe -> hypothesize -> act -> verify -> repeat.** Roles: IC (coordinates), Ops (runs commands), Comms (talks to stakeholders), Scribe (timestamps the thread).

**Mitigate before you fix.** A revert that restores service beats a correct fix that takes an hour.

- Recent deploy? Roll back first, root-cause after.
- Feature-flag the suspect path off.
- Shed load: rate-limit, disable the heavy endpoint, scale out.

```sql
-- Supabase: who is holding connections / what is blocking?
select pid, now() - query_start as runtime, state, left(query, 80) as query
from pg_stat_activity
where state != 'idle'
order by runtime desc limit 20;

-- Kill a runaway query (note pid in the thread first)
select pg_terminate_backend(<pid>);
```

```ts
// Kill switch via remote flag beats a redeploy under fire
const flags = await getFlags();
if (flags.disable_recommendations) return res.json({ items: [] });
```

For a Supabase regression, check the advisor and logs before guessing — use `get_advisors` (security/performance) and `get_logs` for the failing service (api, postgres, auth, edge-function).

**Decision points**
- Mitigation not landing in ~15 min? Escalate / page the next owner. Don't be a hero.
- Multiple plausible causes? IC picks ONE to test at a time. Parallel uncoordinated changes corrupt the signal.
- Touching the database? One change, announced, reversible. No blind `UPDATE` without a `WHERE` you read aloud.

**Red flags during response**
- Everyone debugging, nobody coordinating -> appoint IC now.
- Silent fixing — a teammate ships a change not in the thread.
- Arguing root cause while users are down -> mitigate first, debate later.
- "Let's just restart it" repeatedly with no observation in between.

## Phase 3: Communicate

Stakeholders fear silence more than bad news. Comms posts on a clock even with nothing new.

- **SEV1:** update every 15-30 min. **SEV2:** every 30-60 min.
- Status-page template: *what's affected*, *impact*, *what we're doing*, *next update time*.
- Internal vs external: internal gets raw detail; external gets impact + ETA, never raw stack traces or guesses at cause.

> "Checkout is failing for some users. We've identified a likely cause and are rolling back. Next update by 14:30."

## Phase 4: Resolve and hand off

Declare resolved only when signals are green AND stable for a hold period (e.g. 15 min), not at the moment the graph dips.

On resolution, the IC posts: timeline summary, current state, any temporary mitigations still in place (these are follow-up debt), and who owns the postmortem.

## Phase 5: Blameless Postmortem

Write within ~48 hours while memory is fresh. Blameless means: assume everyone acted reasonably with the information they had. Hunt for the system gap, not the person.

**Reframe blame into systems:**
- "X deployed a bad config" -> "A bad config reached prod with no validation gate."
- "Someone forgot to add an index" -> "No alert exists for queries crossing a latency budget."

**Structure**

```markdown
# Postmortem: <short title>  (SEVn, YYYY-MM-DD)

## Summary
2-3 sentences: what broke, who was affected, how long, how it ended.

## Impact
Users/requests affected, duration, revenue/SLA breach, data integrity.

## Timeline (UTC)
- 13:02  Deploy of v1.4.2
- 13:09  Error rate alert fires
- 13:14  Incident declared, IC assigned
- 13:21  Rollback initiated
- 13:34  Error rate normal; monitoring
- 13:49  Resolved

## Root cause
The mechanism. Use "5 whys" to reach a systemic cause, not a person.

## Detection
How we found out and how long it took. Could a signal have caught it sooner?

## What went well / what hurt
Honest. Fast rollback = well. No staging parity = hurt.

## Action items
| Action | Owner | Due | Type |
|--------|-------|-----|------|
| Add CI schema-validation gate for configs | <role> | date | Prevent |
| Alert on p99 latency > budget | <role> | date | Detect |
| Document rollback runbook for service X | <role> | date | Mitigate |
```

**Action item rules**
- Each item has an owner and a date, tracked like any other work. An item with no owner is a wish.
- Prefer **prevent > detect > mitigate**. Aim for at least one that makes the class of failure impossible, not just this instance.
- Cap the list (~5). Ten low-priority items means none get done.
- Cross-check the cause class — if it's a data-model or query issue, route fixes through [[octopus-model]] conventions; if it's a config/test gap, add the missing check.

**Red flags in postmortems**
- A person's name as the root cause.
- "Be more careful" / "add more reviews" as an action — not actionable, not systemic.
- No action item that changes the system.
- Written but never read — schedule a short review so the lessons spread.

## Commit and follow-up

Land runbooks, alerts, and corrective code as normal changes — follow [[commit-pipeline]] for message format. Reference the incident date in the body so the fix is traceable to its cause.
