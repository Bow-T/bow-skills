---
name: multi-region-and-data-residency
description: Triggers when deploying across regions for latency, failover, or legal residency — active-active vs active-passive, cross-region replication and conflict handling, geo-routing, and pinning data to jurisdictions.
---

# Multi-Region and Data Residency

Going multi-region buys you three different things — latency, failover, and legal
residency — and they pull in opposite directions. Decide which one you are buying
*first*. Optimising for low write latency everywhere fights the consistency you need
for failover; pinning data to a jurisdiction fights the global replication you want
for latency. Name the driver, then pick the topology that serves it.

## 1. Separate the three drivers, then size each

State the real requirement before choosing a topology:

- **Latency** — users feel slow round-trips. The fix is reads near the user, not
  necessarily writes. Often a read replica plus edge caching beats a full active-active
  rebuild.
- **Failover** — survive a region outage with a bounded **RPO** (data you can lose) and
  **RTO** (time to recover). See [[backup-and-disaster-recovery]] for the targets and
  drill cadence; this skill covers the cross-region *placement*.
- **Residency** — law requires certain records physically stay in a jurisdiction (EU,
  India, Australia, etc.). This is a *correctness* constraint, not a performance one —
  violating it is a compliance incident, see [[data-privacy-and-compliance]].

Write down which driver dominates. If you can't, you'll build the most expensive
topology to hedge all three and operate none of them well.

## 2. Choose the topology deliberately

- **Active-passive (warm standby).** One region serves writes; a second replicates and
  waits. Simplest to reason about — no write conflicts ever. Cost is failover time and a
  small RPO from replication lag. Default choice for failover-driven systems.
- **Active-active.** Every region takes writes. Best latency and zero-RTO failover, but
  you *must* solve write conflicts (step 4). Only pay this complexity when low write
  latency or instant failover is the explicit goal.
- **Read-local, write-global.** Reads served from regional replicas, all writes routed
  to one home region. A pragmatic middle ground: kills read latency without conflict
  resolution. Strong default for read-heavy apps.

Map each to your stack. With Supabase, a single primary plus **read replicas** in other
regions gives you read-local/write-global cheaply. True active-active means an external
globally-distributed store or a sharded set of primaries — a large jump in operational
load. Don't reach for it reflexively.

## 3. Make the data placement explicit, not incidental

Residency must be a property of the *data*, decided at write time — never an accident of
which server happened to handle the request.

- Add a **region/jurisdiction column** to residency-bound tables (`data_region text not
  null` constrained to an allowed set). Make it part of the routing key, not metadata.
- **Partition by tenant or user home region.** A tenant created under EU residency keeps
  *all* its rows in EU storage. Don't co-mingle jurisdictions in one physical table if
  any of them carry residency law.
- Classify columns: which fields are residency-bound PII versus globally-replicable
  (product catalogues, feature flags, public reference data). Replicate the global stuff
  freely; pin the regulated stuff.
- In Postgres, enforce placement at the boundary with a CHECK plus RLS so a row can't be
  written into the wrong region's schema. Belt and braces — code routing *and* a
  database constraint that fails the insert.

```sql
alter table profiles add column data_region text not null default 'eu'
  check (data_region in ('eu','us','apac'));
-- residency guard: app sets current_setting('app.region') per connection
create policy region_pin on profiles
  using (data_region = current_setting('app.region', true));
```

## 4. Pick a conflict strategy before you need one

Active-active and any multi-writer setup *will* produce concurrent edits to the same
key. Decide the rule up front:

- **Last-write-wins (LWW).** Simple, lossy. Acceptable only for fields where losing a
  concurrent edit is harmless (a presence flag, a cached preference). Requires a reliable
  clock — use **hybrid logical clocks** or a version counter, never raw wall-clock time,
  which skews across regions.
- **Partition ownership.** Each key has a home region that owns writes; other regions
  forward. No conflicts by construction. Best when you can shard by tenant cleanly.
- **CRDTs / mergeable types.** For counters, sets, collaborative text. Converges without
  a coordinator but constrains your data model — only adopt where the type genuinely fits.
- **Application merge.** Domain-specific resolution (e.g. union two carts, max two
  balances). Most correct, most code. Reserve for money and inventory where silent loss
  is unacceptable.

Never let the default be "whichever replica wrote last with the database's internal
ordering." That's invisible data loss. See [[idempotency-and-exactly-once]] for keeping
cross-region retries from double-applying.

## 5. Route requests to the right region

Two routing concerns, kept separate:

- **Latency routing** (geo-DNS / anycast) sends a user to the nearest *healthy* region
  for reads. Health checks must drain a failing region within your RTO.
- **Residency routing** sends a request to the region that legally owns *that user's
  data*, regardless of where they physically are. An EU user travelling in the US still
  hits EU storage for their regulated records. Encode the home region in the auth token
  or a lookup table; never infer it from request IP.

When the two conflict, residency wins. A Flutter or TypeScript client should carry the
user's home-region claim and target the residency endpoint for writes, while still
reading public data from the nearest edge.

## 6. Handle the failover path as a real procedure

- Define promotion: how a passive replica becomes primary, who triggers it, and how
  writes are fenced off from the old primary to prevent **split-brain** (two primaries
  accepting divergent writes).
- Set and measure replication lag — it *is* your RPO. Alert when lag exceeds the budget.
  See [[observability-and-instrumentation]] for the signals and [[slos-and-error-budgets]]
  for turning lag into a promise.
- Write the steps as a [[runbooks-and-oncall-readiness]] runbook and rehearse with a game
  day — see [[chaos-and-resilience-testing]]. An untested failover is a hope, not a plan.
- Plan failback: returning to the recovered region without losing writes taken during the
  outage is harder than the failover itself. Script it.

## 7. Verify before trusting

- **Residency test:** write a tenant in each jurisdiction, then assert at the storage
  layer that no row landed outside its allowed region. Make this a CI check, not a manual
  audit.
- **Conflict test:** in a staging active-active setup, issue concurrent writes to one key
  from two regions and assert the documented resolution actually happened.
- **Failover drill:** kill the primary in a controlled window and measure real RTO/RPO
  against the target. A drill that "passed" on its first run with no measured numbers
  proves nothing.
- **Lag under load:** replication that keeps up when idle can fall hours behind under
  write bursts — test the failover RPO at peak write volume, see [[load-and-stress-testing]].

## Anti-patterns

- Replicating residency-bound PII to a global store "for performance" — the leak is the
  whole compliance failure.
- Choosing active-active for failover when active-passive would do, then shipping with
  LWW and silently losing edits.
- Geo-routing on IP for residency, so a travelling user's regulated data gets written to
  the wrong jurisdiction.
- Treating replication lag as an ops detail instead of the literal definition of your RPO.
- Building all three drivers' worth of topology and exercising none of the failover paths.

When you commit region/residency changes, follow [[commit-pipeline]].
