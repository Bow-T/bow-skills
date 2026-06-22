---
name: data-governance-and-lineage
description: Triggers when managing a data platform's trust layer — cataloging datasets, tracking column-level lineage, ownership and stewardship, data contracts, quality SLAs, and access classification across pipelines.
---

# Data Governance and Lineage

Governance is the trust layer over a data platform: who owns a dataset, where its columns came from, what it promises, and who may read it. The goal is that any consumer can answer "can I trust this number, and am I allowed to use it?" without asking a human. Build it as metadata that lives next to the pipelines, not a wiki that rots.

## 1. Establish the catalog as the source of truth

- Every queryable dataset gets one **catalog entry**: a stable URN (e.g. `db.public.orders`, `warehouse.finance.revenue_daily`), an owning team, a steward person, a tier, and a one-line purpose. No entry, no production read.
- Treat the catalog as **code, not a UI**. Store entries as versioned files (YAML/JSON) in the repo beside the pipeline, validated in CI. A catalog only people can edit through a web form drifts the day after launch.
- Make the catalog **derivable where possible**. Crawl the warehouse for tables, columns, and types automatically; humans add only the judgement fields (owner, tier, classification). Reconcile on a schedule and flag orphans — tables with no entry — and ghosts — entries with no table.

Red flag: a dataset whose owner is "the data team." Ownership must resolve to a single team accountable for its correctness.

## 2. Classify data before anyone queries it

- Tag every **column** with a sensitivity class: `public`, `internal`, `confidential`, `pii`, `phi`, `financial`. Default to the most restrictive when unsure, then downgrade with evidence.
- Derive table-level classification from its columns: a table is at least as sensitive as its hottest column. A `users` table with one `email` column is `pii` even if 20 other columns are `internal`.
- Wire classification to **access**, don't just document it. In Supabase, this means RLS policies and column grants keyed off the class; PII columns live behind a view that masks or omits them for non-privileged roles. See [[authn-authz-design]] and [[security-and-hardening]].
- Track **derived sensitivity**: if a `confidential` column feeds an aggregate, decide whether the aggregate inherits the class or is genuinely anonymized (small-group suppression, k-anonymity). Lineage (section 4) is what makes this checkable.

## 3. Make data contracts explicit and enforced

A data contract is the producer's promise to consumers about a dataset's shape and semantics. Without one, every downstream join is a guess.

- Pin the contract per dataset: column names, types, nullability, units, allowed enum values, primary key, and freshness expectation. Express it as a schema file consumers can read.
- Version contracts with semver semantics. Adding a nullable column is a minor bump; dropping or retyping a column is **breaking** and follows [[deprecation-and-migration]] — announce, dual-write, migrate, then remove.
- Enforce the contract at the **boundary**: validate producer output against the schema in CI and at write time. A pipeline that violates its own contract should fail loudly, not silently emit bad rows. For TypeScript producers, generate the validator from the contract (e.g. a Zod schema) so the type system and the contract cannot disagree; see [[contract-testing]] and [[type-safety-and-schema-validation]].

```yaml
# contracts/revenue_daily.yaml
dataset: warehouse.finance.revenue_daily
version: 2.1.0
owner: team-finance
tier: gold
freshness: { max_lag: 6h, measured_on: report_date }
columns:
  - { name: report_date, type: date, nullable: false, pk: true }
  - { name: org_id,      type: uuid, nullable: false, class: internal }
  - { name: gross_cents, type: bigint, nullable: false, unit: cents_usd, class: financial }
  - { name: currency,    type: text, nullable: false, enum: [USD, EUR, GBP] }
```

## 4. Capture lineage at column granularity

Table-level lineage ("revenue depends on orders") is too coarse to answer the questions that matter. Push to columns.

- Record, for each output column, the **input columns and the transform** that produced it: `revenue_daily.gross_cents <- sum(orders.amount_cents) where status='paid'`. Capture it from the transformation layer (SQL parse, dbt manifest, pipeline DAG), not by hand.
- Store lineage as a **directed graph** of `(column) -> (column)` edges with the transform expression on the edge. This is what powers the three queries you actually need:
  - **Impact analysis** (downstream): "if I drop `orders.coupon_code`, what breaks?" Walk edges forward.
  - **Root-cause / provenance** (upstream): "this dashboard number looks wrong — what feeds it?" Walk edges backward to source columns.
  - **Sensitivity propagation**: a `pii` source column must not surface in a `public` output without an explicit, recorded masking transform on the path.
- Refresh lineage **automatically on every pipeline change**. Hand-maintained lineage is wrong within a week and worse than none, because people trust it.

Red flag: lineage that stops at the table boundary, or that only exists for the "important" datasets. Coverage gaps are exactly where bad data hides.

## 5. Define quality SLAs and measure them continuously

A dataset's tier (e.g. bronze/silver/gold) sets the promises; quality checks prove them.

- Attach concrete checks to each contract: **freshness** (rows for today exist by 06:00), **volume** (row count within expected band), **uniqueness** (PK has no dupes), **referential** (every `org_id` exists in `orgs`), **validity** (enums in range, no negative `gross_cents`), **null rate** (within threshold per column).
- Express checks as assertions that run on a schedule and on every write. A failed gold-tier check pages the owner; a failed bronze check files a ticket. Map this onto [[slos-and-error-budgets]] — quality is an SLO and stale data burns budget.
- Surface results in the catalog entry: last-checked time, pass/fail, and a freshness badge. A consumer should see "stale, 11h behind" before they build on it. Feed failures into [[observability-and-instrumentation]] and [[incident-response-and-postmortems]] for gold-tier breaches.
- Quarantine on failure where you can: write to a staging table, run checks, then atomically promote. Never let a failed batch become the live dataset.

## 6. Assign stewardship and keep it alive

- Separate **owner** (the team accountable) from **steward** (the named person who answers questions and approves contract changes). Both live in the catalog entry.
- Require steward sign-off on breaking contract changes and classification downgrades. Route it through normal review; record the decision rationale per [[documentation-and-adrs]].
- Run a periodic **staleness sweep**: entries unverified in 90 days, datasets with no reads in 60 days (candidates for deprecation), and columns whose classification was never set. Triage the backlog like any other debt — see [[technical-debt-management]].

## 7. Close the loop on access and audit

- Grant access by **classification and purpose**, not by individual table requests. A role like `analyst_internal` reads everything up to `internal`; reading `pii` requires an explicit, time-boxed, logged grant.
- Log every access to `confidential`+ data with who, what columns, and when. Lineage tells you the blast radius when a credential leaks; the access log tells you what was actually touched.
- Tie revocation to lineage: when a source is reclassified upward, walk the graph forward and re-check that every downstream consumer is still authorized. Reclassification is a migration, not a flag flip.

## Definition of done

- Every production dataset has a catalog entry with owner, steward, tier, and column-level classification.
- A versioned, CI-validated data contract exists and the producer fails when it violates it.
- Column-level lineage is generated automatically and answers impact and provenance queries.
- Quality checks run on a schedule, results show in the catalog, and gold-tier failures alert the owner.
- Access is granted by classification, and `confidential`+ reads are logged.

When committing catalog, contract, or lineage changes, follow [[commit-pipeline]].
