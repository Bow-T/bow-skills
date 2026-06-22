# BOW Skills

**An open marketplace of production-grade engineering skills for Claude Code.**

Skills are *workflows the agent activates by context* — not docs you read. Each one declares a trigger; when your task matches, Claude applies that process automatically. Install once and your whole team shares the same working agreement with Claude.

**94 project-agnostic skills** in `bow-core`, plus an optional `flutter-supabase` stack plugin — all original, English, MIT-licensed, and rendered to every major AI assistant.

---

## Install

```bash
/plugin marketplace add Bow-T/bow-skills
/plugin install bow-core@bow-skills
# optional, for Flutter + Supabase projects:
/plugin install flutter-supabase@bow-skills
```

Skills activate by context. Prefer a stack/workflow skill over generic advice when a task lands in its area. The `using-agent-skills` meta-skill helps route to the right one.

---

## `bow-core` — 94 skills

### Discover & plan (5)

| Skill | Use when |
| :-- | :-- |
| `interview-me` | Pulls out the real goal behind a request rather than the request itself, by running a one-question-at-a-time interview until you can predict the user' |
| `idea-refine` | Turns a fuzzy idea into a sharp, buildable concept by first widening the option space, then narrowing it under honest scrutiny. |
| `spec-driven-development` | Write an agreed specification, linked to a tracker ticket, before any implementation. |
| `planning-and-task-breakdown` | Turn an approved spec or clear requirements into a small, ordered list of verifiable tasks before writing code. |
| `estimation-and-scoping` | Trigger when asked how long something will take, sizing a task or epic, or breaking unknowns into estimable pieces with explicit uncertainty. |

### Architecture & system design (7)

| Skill | Use when |
| :-- | :-- |
| `system-architecture-design` | Triggers when shaping a new service or major subsystem before building components — choosing monolith vs microservices vs serverless, defining compone |
| `api-and-interface-design` | Designs interfaces that stay stable and resist misuse. |
| `data-modeling-and-schema-design` | Triggers when creating or altering tables, choosing normalization vs denormalization, modeling relationships and cardinality, picking keys and constra |
| `multi-tenancy-design` | Trigger when building software that serves multiple customers/orgs — tenant isolation, data partitioning, per-tenant config/limits, and noisy-neighbor |
| `event-driven-and-messaging` | Triggers when introducing a broker, choosing pub/sub vs queues, handling at-least-once delivery, ordering/partitioning, dead-letters, or moving sync c |
| `scalability-and-capacity-planning` | Triggers when estimating capacity, choosing horizontal vs vertical scaling, hunting bottlenecks under projected load, planning sharding/partitioning, |
| `error-handling-and-exception-design` | Triggers when deciding how code reports and propagates failure — error types vs exceptions vs result types, what to wrap/retry/swallow, user-facing me |

### Build & implement (8)

| Skill | Use when |
| :-- | :-- |
| `incremental-implementation` | Delivers changes in small, verified steps instead of one big drop. |
| `context-engineering` | Curates what an agent sees so its output stays accurate. |
| `source-driven-development` | Backs every framework-specific decision with current official documentation and a citation. |
| `type-safety-and-schema-validation` | Trigger when validating data at a boundary — parsing untrusted input, defining a shared schema, adding runtime validation (Zod/Pydantic/JSON Schema), |
| `concurrency-and-async-correctness` | Trigger when sharing mutable state across threads/tasks, using locks/async-await/futures/isolates, debugging race conditions or deadlocks, ordering si |
| `state-management-and-data-flow` | Triggers when structuring client-side or app state — choosing local vs global state, normalizing stores, optimistic updates, cache sync, and avoiding |
| `datetime-timezone-and-money-correctness` | Trigger when handling dates, times, timezones, durations, currency, rounding, or any value where locale and precision cause silent off-by-one or off-b |
| `code-migration-and-language-upgrades` | Triggers when upgrading a runtime/framework/language version or porting between them — assessing breaking changes, codemods, incremental cutover, and |

### Frontend & UX (4)

| Skill | Use when |
| :-- | :-- |
| `frontend-ui-engineering` | Builds production-grade user interfaces — accessible, responsive, and visually polished. |
| `design-system-and-component-library` | Triggers when building or extending a shared UI component library — tokens, theming, variants/composition APIs, documentation, versioning, and prevent |
| `accessibility-engineering` | Triggers when building or remediating UI that must meet WCAG — keyboard navigation, ARIA semantics, focus management, color contrast, or screen-reader |
| `internationalization-and-localization` | Triggers when externalizing UI strings, handling plurals/gender/RTL, formatting dates/numbers/currency per locale, fixing Unicode handling, or buildin |

### Data & databases (6)

| Skill | Use when |
| :-- | :-- |
| `database-query-optimization` | Triggers when database access is slow or wasteful — N+1 loops, missing/unused indexes, full table scans, ugly EXPLAIN plans, unbounded result sets, or |
| `zero-downtime-database-migrations` | Trigger when changing a production schema under live traffic — adding/dropping columns, backfills, renames, or index builds without locks or downtime. |
| `caching-strategy` | Triggers when adding a cache layer, choosing TTL vs event-based invalidation, debugging stale data, designing cache keys, or hardening against stamped |
| `data-pipeline-and-etl-design` | Trigger when moving or transforming data in batch or stream — building an ingestion/ETL/ELT pipeline, ensuring idempotent loads, schema evolution, or |
| `full-text-and-vector-search-infrastructure` | Triggers when standing up search infra itself — indexing pipelines, analyzers/tokenizers, sharding, freshness-vs-cost trade-offs, and operating Elasti |
| `search-and-relevance-engineering` | Trigger when building or tuning search — indexing, analyzers, ranking/relevance, filters/facets, typo tolerance, or evaluating search quality. |

### APIs, messaging & integration (11)

| Skill | Use when |
| :-- | :-- |
| `api-pagination-and-bulk-access` | Triggers when exposing list endpoints at scale — choosing cursor vs offset pagination, designing bulk/batch reads and writes, streaming large result s |
| `api-versioning-and-evolution` | Trigger when evolving a published API — adding fields, choosing a versioning strategy, deprecating endpoints, or keeping old clients alive through a b |
| `rate-limiting-and-quota-design` | Trigger when designing or fixing request throttling, API quotas, abuse prevention, or protecting a downstream service from overload. |
| `webhook-design-and-delivery` | Trigger when you are the provider sending/delivering webhooks to consumers — event contract, signing, retries, ordering, and replay protection. |
| `webhook-receiving-and-verification` | Triggers when consuming inbound webhooks from third parties — signature verification, replay protection, ordering, retries, idempotent handling, and f |
| `idempotency-and-exactly-once` | Trigger when an operation must survive retries — payments, webhook handlers, message consumers, or any write that at-least-once delivery or client ret |
| `background-jobs-and-queues` | Trigger when offloading work to async jobs — designing a queue/worker, scheduling, retries, dead-letter handling, visibility timeouts, or preventing j |
| `streaming-and-realtime-systems` | Triggers when delivering live updates — WebSockets/SSE/long-poll choice, presence, backpressure, reconnection, fan-out scaling, and ordering/dedup for |
| `file-upload-and-media-handling` | Triggers when accepting user file/image/video uploads — validation, size/type limits, virus scanning, presigned URLs, storage layout, transcoding, and |
| `payments-and-billing-integration` | Triggers when integrating payments or subscriptions — idempotent charges, PSP webhooks, proration, dunning, tax, refunds, reconciliation, and PCI scop |
| `email-and-notification-delivery` | Triggers when sending transactional email/SMS/push — deliverability (SPF/DKIM/DMARC), templating, user preferences, rate/throttle, bounce handling, an |

### Testing & quality (9)

| Skill | Use when |
| :-- | :-- |
| `test-driven-development` | Let tests drive the code — write the failing test first (Flutter *_test.dart, TS *.spec.ts), then the implementation. |
| `test-strategy-and-coverage-design` | Triggers when deciding what and how to test — shaping the test pyramid, drawing unit/integration/e2e boundaries, choosing what to mock, triaging flaky |
| `contract-testing` | Triggers when independently deployed services integrate, an API change might break a consumer, you set up consumer-driven contracts, or mocks have dri |
| `load-and-stress-testing` | Trigger when establishing a performance baseline, finding a breaking point, verifying autoscaling, running soak/spike/stress tests, or proving a capac |
| `chaos-and-resilience-testing` | Trigger when proactively validating failure handling — injecting faults, killing dependencies, simulating latency or partitions, or running a game day |
| `code-review-and-quality` | Reviews a change across correctness, readability, architecture, security, and performance before it merges. |
| `ai-generated-code-review` | Trigger when reviewing or merging code an AI/agent produced — hunting for hallucinated APIs, subtle correctness gaps, security holes, and unjustified |
| `code-simplification` | Make working code clearer without changing what it does. |
| `doubt-driven-development` | Cross-examines every non-trivial decision with a fresh-context adversarial reviewer before it stands. |

### Debugging & performance (3)

| Skill | Use when |
| :-- | :-- |
| `debugging-and-error-recovery` | Find and fix the root cause systematically across the whole stack — Flutter app, Supabase (CHECK/FK/trigger/RLS), edge functions, and browser. |
| `memory-and-resource-leak-diagnosis` | Triggers when a process grows unbounded or exhausts resources — heap/leak profiling, GC tuning, file-descriptor and connection-pool exhaustion, and OO |
| `performance-optimization` | Finds and fixes real performance problems through measurement. |

### Security & privacy (7)

| Skill | Use when |
| :-- | :-- |
| `security-and-hardening` | Harden APP-LAYER code — mobile, web, and third-party/payment integrations — against attack. |
| `threat-modeling` | Triggers when designing a new system, feature, or trust boundary; handling sensitive data; preparing a security-sensitive launch; or asked what could |
| `authn-authz-design` | Designs who-you-are and what-you-can-do correctly — triggers when implementing login, sessions/tokens (JWT/OAuth/OIDC), refresh flows, RBAC/ABAC permi |
| `secrets-and-config-management` | Use when handling API keys or credentials, separating config from code, managing per-environment values, rotating or revoking secrets, preventing secr |
| `dependency-and-supply-chain` | Use when adding or upgrading a library, auditing for CVEs or license conflicts, pinning and locking versions, deciding whether to adopt a dependency, |
| `data-privacy-and-compliance` | Trigger when handling PII/PHI, implementing GDPR/CCPA rights (deletion, export, consent), data retention, or building any system subject to regulatory |
| `networking-and-tls-fundamentals` | Triggers when debugging or designing connectivity — DNS, TLS/mTLS, certificates and rotation, proxies/load balancers, timeouts, keep-alive, and diagno |

### Reliability & operations (7)

| Skill | Use when |
| :-- | :-- |
| `observability-and-instrumentation` | Builds the telemetry that lets you operate a system in production. |
| `logging-hygiene` | Trigger when adding, reviewing, or cleaning up log statements — picking levels, structuring fields, blocking PII/secret leakage, and controlling log v |
| `slos-and-error-budgets` | Use when defining SLIs/SLOs, choosing reliability targets to promise, computing or burning error budgets, trading features against stability, or negot |
| `resilience-and-fault-tolerance` | Triggers when calling networks or external services and you need retries with backoff/jitter, timeouts, circuit breakers, bulkheads, idempotent retrie |
| `incident-response-and-postmortems` | Use when production is down or degraded, when coordinating a live response, declaring severity and comms, or writing a blameless postmortem with corre |
| `runbooks-and-oncall-readiness` | Triggers when authoring runbooks for known failure modes, defining alert response procedures, preparing on-call handoffs, documenting escalation paths |
| `backup-and-disaster-recovery` | Triggers when defining backup policy, setting RPO/RTO targets, testing restores, planning failover or replication, or preparing for region loss and da |

### Ship & release (9)

| Skill | Use when |
| :-- | :-- |
| `ci-cd-and-automation` | Sets up and maintains automated build, test, and deploy pipelines. |
| `shipping-and-launch` | Drives a safe production launch. |
| `feature-flags-and-progressive-delivery` | Trigger when decoupling deploy from release — shipping behind flags, running canary or percentage rollouts, A/B experiments, kill-switches for risky f |
| `commit-pipeline` | Commit and push changes following the team commit convention — optional staged safety scan (RLS/CORS/secrets), static analysis, a Conventional-Commit |
| `git-workflow-and-branching` | Triggers when establishing or untangling version-control practice — branching model, rebase vs merge, conflict resolution, recovering lost work, bisec |
| `pull-request-authoring` | Trigger when opening a pull request — scoping it reviewably, writing the description and test plan, sequencing stacked PRs, and pre-empting reviewer q |
| `release-notes-and-semver` | Use when cutting a release — picking a semver bump, writing a changelog or release notes, or deciding whether a change is breaking. |
| `deprecation-and-migration` | Retires old code and moves users onto its replacement safely. |
| `mobile-release-and-app-store` | Trigger when shipping a mobile app — store submission, phased rollout, forced/optional update gates, crash monitoring, and recovering from an un-recal |

### Infra, cloud & cost (4)

| Skill | Use when |
| :-- | :-- |
| `infrastructure-as-code` | Triggers when provisioning cloud resources declaratively — writing/structuring Terraform/Pulumi/CDK, managing state, modules, drift detection, and saf |
| `containerization-and-orchestration` | Triggers when packaging services into containers and running them — lean Dockerfiles, multi-stage builds, image hardening, Kubernetes/compose manifest |
| `capacity-cost-tradeoff-and-rightsizing` | Triggers when tuning resource allocation against spend — rightsizing compute/storage, autoscaling policies, spot/reserved choices, and load-vs-cost tr |
| `cost-and-finops-optimization` | Trigger when cloud, infra, or LLM spend spikes or needs forecasting — attribute cost, right-size, kill waste, and add guardrails. |

### AI & LLM engineering (6)

| Skill | Use when |
| :-- | :-- |
| `prompt-design-and-engineering` | Trigger when writing, refactoring, or debugging an LLM prompt — system prompts, few-shot examples, output formatting, or reducing hallucination and re |
| `rag-system-engineering` | Use when building or debugging retrieval-augmented generation — designing chunking/embedding, choosing a vector store and retrieval method, tuning hyb |
| `llm-evaluation-and-testing` | Trigger when measuring LLM or agent output quality — building eval sets, LLM-as-judge graders, prompt regression suites, or catching quality drift bef |
| `agent-tool-design` | Triggers when defining tools/functions an LLM agent can call — naming, parameter schemas, descriptions, return shapes, error surfaces, and guardrails |
| `machine-learning-model-serving` | Triggers when deploying a trained model to production — packaging, batching, GPU/CPU sizing, versioning, shadow/canary, latency budgets, and monitorin |
| `ml-data-and-feature-pipelines` | Triggers when preparing data for training or inference — feature engineering, train/serve skew, leakage prevention, labeling, dataset versioning, and |

### Product & analytics (2)

| Skill | Use when |
| :-- | :-- |
| `analytics-and-product-instrumentation` | Triggers when adding product analytics/event tracking — naming taxonomy, event schema, consent gating, identity stitching, and avoiding double-countin |
| `experimentation-and-ab-testing` | Triggers when running an experiment to decide a change — hypothesis, metric and guardrail selection, sample-size/power, assignment, and reading result |

### Engineering practice & repo (6)

| Skill | Use when |
| :-- | :-- |
| `documentation-and-adrs` | Captures the reasoning behind technical work so future readers can rebuild context. |
| `technical-debt-management` | Triggers when the team is slowing down, when proposing cleanup, when weighing a shortcut against its future cost, or when ranking refactors against fe |
| `large-scale-refactoring` | Restructures code across many files without breaking it — touching dozens of call sites, splitting/merging modules, introducing a cross-cutting abstra |
| `monorepo-management` | Trigger when structuring a multi-package repo — workspace layout, shared deps, affected-only builds/tests, codeowners, and cross-package versioning. |
| `local-dev-environment-and-onboarding` | Triggers when setting up reproducible local development — one-command setup, seed data, service stubs, prod parity, and shrinking new-engineer time-to |
| `using-agent-skills` | Picks the right skill for the task at hand. |

### Slash commands

| Command | Skill |
| :-- | :-- |
| `/spec` | spec-driven-development |
| `/plan` | planning-and-task-breakdown |
| `/tdd` | test-driven-development |
| `/debug` | debugging-and-error-recovery |
| `/tidy` | code-simplification |
| `/harden` | security-and-hardening |

### Subagents

`plugins/bow-core/agents/`: `code-reviewer`, `security-auditor`, `test-engineer`, `web-performance-auditor`. Reference checklists live in `plugins/bow-core/references/`.

---

## `flutter-supabase` — optional stack plugin (3)

| Skill | Use when |
| :-- | :-- |
| `flutter-data-model` | Write Flutter data models and parsing the project way — every model is a @JsonSerializable class with a part '*.g.dart' file and _$FromJson/_$ToJson, |
| `flutter-mvvm` | Build or edit Flutter UI and pages in apps/mobile using the Flutter MVVM architecture — the BaseViewModel + MixinBasePage page+view-model pattern (Cha |
| `supabase-security-review` | Audit Supabase/backend changes (RLS, views, triggers, edge functions, SQL) for the recurring security issues the AI review gate penalises, before comm |

These read per-repo values from a `.conventions.json` at the repo root, so they adapt to your project instead of hardcoding paths.

---

## Enforcement & multi-assistant (`tooling/`)

Skills describe *how* to work; `tooling/` turns the machine-checkable parts into git hooks, and renders the conventions + skill index to every assistant from one source.

| File | Role |
| :-- | :-- |
| `tooling/commitlint.config.cjs` | Conventional Commits + `jira-key-present` (warn) + `no-ai-coauthor` (block). |
| `tooling/lefthook.yml` | Hooks: lint commit messages, block secret-like files. |
| `tooling/conventions.base.md` | Source of the multi-assistant conventions digest. |
| `tooling/render-rules.mjs` | Renders `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, Copilot, and Cursor rule files. |
| `tooling/conventions.example.json` | Template for per-repo `.conventions.json`. |

```bash
node tooling/render-rules.mjs   # regenerate every assistant's rule file
```

See [`tooling/README.md`](tooling/README.md) and [`docs/conventions-strategy.md`](docs/conventions-strategy.md).

---

## Use it your way

- **Install** via the marketplace (above) — fastest for Claude Code users.
- **Fork** and tune skills, commands, and `.conventions.json` to your team.
- **Copy** individual `SKILL.md` folders into your own `.claude/skills/` if you want just a few.
- **Any assistant** (Cursor, Copilot, Codex, Gemini): run `node tooling/render-rules.mjs`.

---

## Repository structure

```
.claude-plugin/marketplace.json   # marketplace + plugin list
plugins/
  bow-core/        # project-agnostic skills (everyone)
    commands/  skills/  agents/  references/
  flutter-supabase/ # optional stack plugin
tooling/            # commitlint + lefthook + render-rules + conventions
docs/               # strategy notes
```

## Contributing

- Project-agnostic skills go in `plugins/bow-core/skills/`; stack-specific ones in a stack plugin.
- Keep content neutral and original — read per-repo values from `.conventions.json`.
- A skill is one folder with `SKILL.md` carrying frontmatter `name` + `description` that states **when** it triggers.

## License

MIT — see [`LICENSE`](LICENSE). All skills, subagents, and reference checklists are original works.
