---
name: using-agent-skills
description: Picks the right skill for the task at hand. Use at the start of a session, or any time you're unsure which skill applies. This is the index skill that routes you to every other skill in this marketplace.
---

# Using Agent Skills

## What this is

This marketplace bundles **110 project-agnostic skills** (plus an optional `flutter-supabase` stack plugin), each a workflow for one engineering concern. Your first move on any non-trivial task: find the skill that fits, then follow its steps. The catalog below is grouped by area to route you fast.

## Route by category

Find the line closest to what you're doing, open that skill, and follow its steps. For browser runtime checks there is no skill — drive the app with the Chrome DevTools MCP.

### Discover & plan
- `interview-me` — Pulls out the real goal behind a request rather than the request itself, by running a one-question-at-a-time interview until you can predict the user'
- `idea-refine` — Turns a fuzzy idea into a sharp, buildable concept by first widening the option space, then narrowing it under honest scrutiny.
- `spec-driven-development` — Write an agreed specification, linked to a tracker ticket, before any implementation.
- `planning-and-task-breakdown` — Turn an approved spec or clear requirements into a small, ordered list of verifiable tasks before writing code.
- `estimation-and-scoping` — Trigger when asked how long something will take, sizing a task or epic, or breaking unknowns into estimable pieces with explicit uncertainty.

### Architecture & system design
- `system-architecture-design` — Triggers when shaping a new service or major subsystem before building components — choosing monolith vs microservices vs serverless, defining compone
- `api-and-interface-design` — Designs interfaces that stay stable and resist misuse.
- `data-modeling-and-schema-design` — Triggers when creating or altering tables, choosing normalization vs denormalization, modeling relationships and cardinality, picking keys and constra
- `multi-tenancy-design` — Trigger when building software that serves multiple customers/orgs — tenant isolation, data partitioning, per-tenant config/limits, and noisy-neighbor
- `event-driven-and-messaging` — Triggers when introducing a broker, choosing pub/sub vs queues, handling at-least-once delivery, ordering/partitioning, dead-letters, or moving sync c
- `scalability-and-capacity-planning` — Triggers when estimating capacity, choosing horizontal vs vertical scaling, hunting bottlenecks under projected load, planning sharding/partitioning,
- `error-handling-and-exception-design` — Triggers when deciding how code reports and propagates failure — error types vs exceptions vs result types, what to wrap/retry/swallow, user-facing me
- `event-sourcing-and-cqrs` — Triggers when persisting state as an immutable event log with separate read/write models — designing event stores, aggregates, snapshots, projections,
- `distributed-transactions-and-sagas` — Triggers when a business operation spans multiple services or databases needing consistency without 2PC — saga orchestration/choreography, compensatin

### Build & implement
- `incremental-implementation` — Delivers changes in small, verified steps instead of one big drop.
- `context-engineering` — Curates what an agent sees so its output stays accurate.
- `source-driven-development` — Backs every framework-specific decision with current official documentation and a citation.
- `type-safety-and-schema-validation` — Trigger when validating data at a boundary — parsing untrusted input, defining a shared schema, adding runtime validation (Zod/Pydantic/JSON Schema),
- `concurrency-and-async-correctness` — Trigger when sharing mutable state across threads/tasks, using locks/async-await/futures/isolates, debugging race conditions or deadlocks, ordering si
- `state-management-and-data-flow` — Triggers when structuring client-side or app state — choosing local vs global state, normalizing stores, optimistic updates, cache sync, and avoiding
- `datetime-timezone-and-money-correctness` — Trigger when handling dates, times, timezones, durations, currency, rounding, or any value where locale and precision cause silent off-by-one or off-b
- `code-migration-and-language-upgrades` — Triggers when upgrading a runtime/framework/language version or porting between them — assessing breaking changes, codemods, incremental cutover, and
- `offline-sync-and-conflict-resolution` — Triggers when clients work offline and must reconcile divergent state — sync protocols, CRDTs/operational-transform, last-writer-wins vs merge policie

### Frontend & UX
- `frontend-ui-engineering` — Builds production-grade user interfaces — accessible, responsive, and visually polished.
- `design-system-and-component-library` — Triggers when building or extending a shared UI component library — tokens, theming, variants/composition APIs, documentation, versioning, and prevent
- `accessibility-engineering` — Triggers when building or remediating UI that must meet WCAG — keyboard navigation, ARIA semantics, focus management, color contrast, or screen-reader
- `internationalization-and-localization` — Triggers when externalizing UI strings, handling plurals/gender/RTL, formatting dates/numbers/currency per locale, fixing Unicode handling, or buildin

### Data & databases
- `database-query-optimization` — Triggers when database access is slow or wasteful — N+1 loops, missing/unused indexes, full table scans, ugly EXPLAIN plans, unbounded result sets, or
- `zero-downtime-database-migrations` — Trigger when changing a production schema under live traffic — adding/dropping columns, backfills, renames, or index builds without locks or downtime.
- `caching-strategy` — Triggers when adding a cache layer, choosing TTL vs event-based invalidation, debugging stale data, designing cache keys, or hardening against stamped
- `data-pipeline-and-etl-design` — Trigger when moving or transforming data in batch or stream — building an ingestion/ETL/ELT pipeline, ensuring idempotent loads, schema evolution, or
- `full-text-and-vector-search-infrastructure` — Triggers when standing up search infra itself — indexing pipelines, analyzers/tokenizers, sharding, freshness-vs-cost trade-offs, and operating Elasti
- `search-and-relevance-engineering` — Trigger when building or tuning search — indexing, analyzers, ranking/relevance, filters/facets, typo tolerance, or evaluating search quality.
- `data-warehouse-and-dimensional-modeling` — Triggers when modeling for analytics/OLAP — star/snowflake schemas, fact and dimension tables, slowly-changing dimensions, grain definition, and colum
- `data-governance-and-lineage` — Triggers when managing a data platform's trust layer — cataloging datasets, tracking column-level lineage, ownership and stewardship, data contracts,

### APIs, messaging & integration
- `api-pagination-and-bulk-access` — Triggers when exposing list endpoints at scale — choosing cursor vs offset pagination, designing bulk/batch reads and writes, streaming large result s
- `api-versioning-and-evolution` — Trigger when evolving a published API — adding fields, choosing a versioning strategy, deprecating endpoints, or keeping old clients alive through a b
- `rate-limiting-and-quota-design` — Trigger when designing or fixing request throttling, API quotas, abuse prevention, or protecting a downstream service from overload.
- `webhook-design-and-delivery` — Trigger when you are the provider sending/delivering webhooks to consumers — event contract, signing, retries, ordering, and replay protection.
- `webhook-receiving-and-verification` — Triggers when consuming inbound webhooks from third parties — signature verification, replay protection, ordering, retries, idempotent handling, and f
- `idempotency-and-exactly-once` — Trigger when an operation must survive retries — payments, webhook handlers, message consumers, or any write that at-least-once delivery or client ret
- `background-jobs-and-queues` — Trigger when offloading work to async jobs — designing a queue/worker, scheduling, retries, dead-letter handling, visibility timeouts, or preventing j
- `streaming-and-realtime-systems` — Triggers when delivering live updates — WebSockets/SSE/long-poll choice, presence, backpressure, reconnection, fan-out scaling, and ordering/dedup for
- `file-upload-and-media-handling` — Triggers when accepting user file/image/video uploads — validation, size/type limits, virus scanning, presigned URLs, storage layout, transcoding, and
- `payments-and-billing-integration` — Triggers when integrating payments or subscriptions — idempotent charges, PSP webhooks, proration, dunning, tax, refunds, reconciliation, and PCI scop
- `email-and-notification-delivery` — Triggers when sending transactional email/SMS/push — deliverability (SPF/DKIM/DMARC), templating, user preferences, rate/throttle, bounce handling, an
- `graphql-schema-and-resolver-design` — Triggers when designing a GraphQL schema or resolvers — modeling types/connections, batching with DataLoader to kill N+1, query depth/complexity limit
- `webrtc-and-realtime-media` — Triggers when building peer-to-peer audio/video/data — WebRTC signaling, ICE/STUN/TURN/NAT traversal, SFU/MCU topologies, codec/bitrate adaptation, an
- `sdk-and-client-library-design` — Triggers when building or publishing an SDK others depend on — language-idiomatic ergonomics, auth/retry/pagination helpers, semantic versioning and b

### Testing & quality
- `test-driven-development` — Let tests drive the code — write the failing test first (Flutter *_test.dart, TS *.spec.ts), then the implementation.
- `test-strategy-and-coverage-design` — Triggers when deciding what and how to test — shaping the test pyramid, drawing unit/integration/e2e boundaries, choosing what to mock, triaging flaky
- `contract-testing` — Triggers when independently deployed services integrate, an API change might break a consumer, you set up consumer-driven contracts, or mocks have dri
- `load-and-stress-testing` — Trigger when establishing a performance baseline, finding a breaking point, verifying autoscaling, running soak/spike/stress tests, or proving a capac
- `chaos-and-resilience-testing` — Trigger when proactively validating failure handling — injecting faults, killing dependencies, simulating latency or partitions, or running a game day
- `code-review-and-quality` — Reviews a change across correctness, readability, architecture, security, and performance before it merges.
- `ai-generated-code-review` — Trigger when reviewing or merging code an AI/agent produced — hunting for hallucinated APIs, subtle correctness gaps, security holes, and unjustified
- `code-simplification` — Make working code clearer without changing what it does.
- `doubt-driven-development` — Cross-examines every non-trivial decision with a fresh-context adversarial reviewer before it stands.

### Debugging & performance
- `debugging-and-error-recovery` — Find and fix the root cause systematically across the whole stack — Flutter app, Supabase (CHECK/FK/trigger/RLS), edge functions, and browser.
- `memory-and-resource-leak-diagnosis` — Triggers when a process grows unbounded or exhausts resources — heap/leak profiling, GC tuning, file-descriptor and connection-pool exhaustion, and OO
- `performance-optimization` — Finds and fixes real performance problems through measurement.

### Security & privacy
- `security-and-hardening` — Harden APP-LAYER code — mobile, web, and third-party/payment integrations — against attack.
- `threat-modeling` — Triggers when designing a new system, feature, or trust boundary; handling sensitive data; preparing a security-sensitive launch; or asked what could
- `authn-authz-design` — Designs who-you-are and what-you-can-do correctly — triggers when implementing login, sessions/tokens (JWT/OAuth/OIDC), refresh flows, RBAC/ABAC permi
- `secrets-and-config-management` — Use when handling API keys or credentials, separating config from code, managing per-environment values, rotating or revoking secrets, preventing secr
- `dependency-and-supply-chain` — Use when adding or upgrading a library, auditing for CVEs or license conflicts, pinning and locking versions, deciding whether to adopt a dependency,
- `data-privacy-and-compliance` — Trigger when handling PII/PHI, implementing GDPR/CCPA rights (deletion, export, consent), data retention, or building any system subject to regulatory
- `networking-and-tls-fundamentals` — Triggers when debugging or designing connectivity — DNS, TLS/mTLS, certificates and rotation, proxies/load balancers, timeouts, keep-alive, and diagno
- `encryption-and-key-management` — Triggers when encrypting data at rest or in transit beyond TLS basics — choosing AES-GCM/envelope encryption, integrating a KMS/HSM, key rotation and
- `audit-logging-and-tamper-evidence` — Triggers when building an audit trail that must survive scrutiny — append-only immutable records, hash chaining or Merkle proofs, who-did-what-when ca
- `fraud-and-abuse-prevention` — Triggers when defending against malicious-but-authenticated misuse — account takeover, bot/scraping defense, payment fraud, fake signups, velocity rul
- `privacy-engineering-and-anonymization` — Triggers when data must be de-identified for analytics, sharing, or ML — k-anonymity, differential privacy, pseudonymization, tokenization, re-identif
- `content-moderation-and-trust-safety` — Triggers when handling user-generated content at scale — classifier and human-review pipelines, CSAM/illegal-content handling and reporting, appeals,

### Reliability & operations
- `observability-and-instrumentation` — Builds the telemetry that lets you operate a system in production.
- `logging-hygiene` — Trigger when adding, reviewing, or cleaning up log statements — picking levels, structuring fields, blocking PII/secret leakage, and controlling log v
- `slos-and-error-budgets` — Use when defining SLIs/SLOs, choosing reliability targets to promise, computing or burning error budgets, trading features against stability, or negot
- `resilience-and-fault-tolerance` — Triggers when calling networks or external services and you need retries with backoff/jitter, timeouts, circuit breakers, bulkheads, idempotent retrie
- `incident-response-and-postmortems` — Use when production is down or degraded, when coordinating a live response, declaring severity and comms, or writing a blameless postmortem with corre
- `runbooks-and-oncall-readiness` — Triggers when authoring runbooks for known failure modes, defining alert response procedures, preparing on-call handoffs, documenting escalation paths
- `backup-and-disaster-recovery` — Triggers when defining backup policy, setting RPO/RTO targets, testing restores, planning failover or replication, or preparing for region loss and da

### Ship & release
- `ci-cd-and-automation` — Sets up and maintains automated build, test, and deploy pipelines.
- `shipping-and-launch` — Drives a safe production launch.
- `feature-flags-and-progressive-delivery` — Trigger when decoupling deploy from release — shipping behind flags, running canary or percentage rollouts, A/B experiments, kill-switches for risky f
- `commit-pipeline` — Commit and push changes following the team commit convention — optional staged safety scan (RLS/CORS/secrets), static analysis, a Conventional-Commit
- `git-workflow-and-branching` — Triggers when establishing or untangling version-control practice — branching model, rebase vs merge, conflict resolution, recovering lost work, bisec
- `pull-request-authoring` — Trigger when opening a pull request — scoping it reviewably, writing the description and test plan, sequencing stacked PRs, and pre-empting reviewer q
- `release-notes-and-semver` — Use when cutting a release — picking a semver bump, writing a changelog or release notes, or deciding whether a change is breaking.
- `deprecation-and-migration` — Retires old code and moves users onto its replacement safely.
- `mobile-release-and-app-store` — Trigger when shipping a mobile app — store submission, phased rollout, forced/optional update gates, crash monitoring, and recovering from an un-recal

### Infra, cloud & cost
- `infrastructure-as-code` — Triggers when provisioning cloud resources declaratively — writing/structuring Terraform/Pulumi/CDK, managing state, modules, drift detection, and saf
- `containerization-and-orchestration` — Triggers when packaging services into containers and running them — lean Dockerfiles, multi-stage builds, image hardening, Kubernetes/compose manifest
- `capacity-cost-tradeoff-and-rightsizing` — Triggers when tuning resource allocation against spend — rightsizing compute/storage, autoscaling policies, spot/reserved choices, and load-vs-cost tr
- `cost-and-finops-optimization` — Trigger when cloud, infra, or LLM spend spikes or needs forecasting — attribute cost, right-size, kill waste, and add guardrails.
- `multi-region-and-data-residency` — Triggers when deploying across regions for latency, failover, or legal residency — active-active vs active-passive, cross-region replication and confl

### AI & LLM engineering
- `prompt-design-and-engineering` — Trigger when writing, refactoring, or debugging an LLM prompt — system prompts, few-shot examples, output formatting, or reducing hallucination and re
- `rag-system-engineering` — Use when building or debugging retrieval-augmented generation — designing chunking/embedding, choosing a vector store and retrieval method, tuning hyb
- `llm-evaluation-and-testing` — Trigger when measuring LLM or agent output quality — building eval sets, LLM-as-judge graders, prompt regression suites, or catching quality drift bef
- `agent-tool-design` — Triggers when defining tools/functions an LLM agent can call — naming, parameter schemas, descriptions, return shapes, error surfaces, and guardrails
- `machine-learning-model-serving` — Triggers when deploying a trained model to production — packaging, batching, GPU/CPU sizing, versioning, shadow/canary, latency budgets, and monitorin
- `ml-data-and-feature-pipelines` — Triggers when preparing data for training or inference — feature engineering, train/serve skew, leakage prevention, labeling, dataset versioning, and
- `recommendation-and-ranking-systems` — Triggers when building personalized recommendation or ranking — candidate generation, feature signals, collaborative/content filtering, learning-to-ra
- `ml-monitoring-and-drift-detection` — Triggers when keeping a deployed model healthy over time — detecting data/concept/prediction drift, monitoring feature distributions and label delay,

### Product & analytics
- `analytics-and-product-instrumentation` — Triggers when adding product analytics/event tracking — naming taxonomy, event schema, consent gating, identity stitching, and avoiding double-countin
- `experimentation-and-ab-testing` — Triggers when running an experiment to decide a change — hypothesis, metric and guardrail selection, sample-size/power, assignment, and reading result

### Engineering practice & repo
- `documentation-and-adrs` — Captures the reasoning behind technical work so future readers can rebuild context.
- `technical-debt-management` — Triggers when the team is slowing down, when proposing cleanup, when weighing a shortcut against its future cost, or when ranking refactors against fe
- `large-scale-refactoring` — Restructures code across many files without breaking it — touching dozens of call sites, splitting/merging modules, introducing a cross-cutting abstra
- `monorepo-management` — Trigger when structuring a multi-package repo — workspace layout, shared deps, affected-only builds/tests, codeowners, and cross-package versioning.
- `local-dev-environment-and-onboarding` — Triggers when setting up reproducible local development — one-command setup, seed data, service stubs, prod parity, and shrinking new-engineer time-to
- `using-agent-skills` — Picks the right skill for the task at hand.

### Commit workflow
- `commit-pipeline` — committing/pushing: Conventional Commits + gitmoji, optional tracker footer, **no AI-authorship trailer**. Authoritative over any generic git advice.

### Optional stack plugin — `flutter-supabase`
Only when installed; authoritative in their area, otherwise ignore:
- `flutter-data-model` — Write Flutter data models and parsing the project way — every model is a @JsonSerializable class with a part '*.g.dart' file and _$FromJson/_$ToJson,
- `flutter-mvvm` — Build or edit Flutter UI and pages in apps/mobile using the Flutter MVVM architecture — the BaseViewModel + MixinBasePage page+view-model pattern (Cha
- `supabase-security-review` — Audit Supabase/backend changes (RLS, views, triggers, edge functions, SQL) for the recurring security issues the AI review gate penalises, before comm

## Behaviors that apply everywhere

These hold regardless of which skill you're in. They are not optional.

**Say your assumptions out loud.** Before any non-trivial work, list what you're assuming about requirements, architecture, and scope, and invite correction. The most common way work goes wrong is filling an ambiguous gap silently and running with it.

**Stop when you're confused.** If the spec contradicts the code, or two requirements conflict, do not pick one and hope. Name the specific conflict, present the trade-off or ask the question, and wait.

**Disagree when you should.** You are not a rubber stamp. If an approach has a real downside, state it plainly, quantify it where you can, offer an alternative, and accept the human's call once they've heard it.

**Default to simple.** The natural pull is to overbuild — resist it. Fewer lines, fewer abstractions, the boring obvious solution usually wins.

**Stay in scope.** Touch only what the task needs. Don't delete code you don't understand, refactor adjacent systems as a side effect, or add unrequested features.

**Verify with evidence.** Nothing is done on "looks right." Show the passing tests, the build output, the runtime behavior. Every skill ends in a verification step — honor it.

## Rules of use

1. **Check for a matching skill before you start.** Skills exist to prevent known mistakes.
2. **Treat a skill as a workflow.** Follow its steps in order; don't drop the verification step.
3. **More than one can apply.** A feature often chains several (see below).
4. **When unsure on something non-trivial, start with a spec** (`spec-driven-development`).
5. **Workflow & stack skills win in their area.** If a task touches committing — or an installed stack plugin's domain — the matching skill overrides generic advice.

## A typical feature, end to end

Not every task needs every step — a bug fix might be just `debugging-and-error-recovery` -> `test-driven-development` -> `code-review-and-quality`. A full feature usually runs:

```
interview-me -> idea-refine -> spec-driven-development -> planning-and-task-breakdown
 -> context-engineering -> source-driven-development -> incremental-implementation
 -> test-driven-development -> doubt-driven-development -> code-review-and-quality
 -> code-simplification -> commit-pipeline -> documentation-and-adrs -> shipping-and-launch
```
Run `observability-and-instrumentation` in parallel while building, not after.
