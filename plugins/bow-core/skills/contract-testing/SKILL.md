---
name: contract-testing
description: Triggers when independently deployed services integrate, an API change might break a consumer, you set up consumer-driven contracts, or mocks have drifted from real provider behavior.
---

# Contract Testing

A contract is a machine-checkable promise: "if a consumer sends *this* request, the provider returns *that* response shape." Contract tests catch integration breakage at build time instead of in production — without spinning up the whole stack.

Use this when two units deploy on independent schedules: a Flutter app and a Supabase Edge Function, a TypeScript API and a worker, a mobile client and a REST/GraphQL backend.

## Decide what kind of contract you need

- **Consumer-driven (preferred for internal services).** Each consumer records the exact interactions it relies on. The provider must satisfy the union of all consumer expectations. Best when you control both sides.
- **Provider-driven / schema-first.** The provider publishes a schema (OpenAPI, JSON Schema, generated Supabase types). Consumers validate against it. Best when the provider has many unknown consumers or is third-party.
- **Bidirectional.** Provider publishes a schema; consumer publishes its expectations; a broker checks compatibility between the two. Use when you cannot run the provider in CI.

Red flag: if your "contract test" boots a real database and a real network, it is an end-to-end test wearing a costume. Contract tests run against a *mock* on one side and a *replay* on the other.

## The consumer-driven loop

```
consumer test  →  generates pact/contract file  →  shared broker
                                                         │
provider verify  ←  reads contract, replays requests  ←──┘
```

1. Consumer writes a test describing one interaction (request + minimal expected response).
2. The framework stands up a stub provider, runs the consumer code against it, and emits a contract artifact.
3. The artifact is published (broker, or committed for small teams).
4. The provider's CI replays every recorded request against the *real* provider and asserts the response still matches.
5. Provider deploys only if verification passes for every consumer pinned to that environment.

## Consumer side (Dart / Flutter)

Test what your code actually parses, not the full payload. Match on *type and structure*, never on hardcoded values that will rot.

```dart
test('fetches active subscription', () async {
  // provider stub primed with this expected interaction
  await mockProvider.given('user 42 has an active subscription')
    .uponReceiving('a request for the current subscription')
    .withRequest(method: 'GET', path: '/v1/subscriptions/current',
                 headers: {'Authorization': matchRegex(r'Bearer .+')})
    .willRespondWith(status: 200, body: {
      'id': like('sub_abc'),            // any string
      'status': term(matcher: r'active|trialing', generate: 'active'),
      'renews_at': like('2026-01-01T00:00:00Z'),
      'seats': like(5),                 // any int
    });

  final sub = await SubscriptionApi(mockProvider.url).current();
  expect(sub.status, 'active');
});
```

Rules:
- Use matchers (`like`, `term`, `eachLike`) so the contract pins *shape*, not data.
- One interaction per behavior your client depends on. Do not assert fields you never read — that over-constrains the provider.
- The `given(...)` string is a **provider state**: a named precondition the provider must be able to set up.

## Provider side (TypeScript / Supabase)

Verification replays each recorded request. The only custom work is implementing provider states — usually seeding a row, then tearing it down.

```ts
await verifyContract({
  provider: 'subscriptions-api',
  baseUrl: localFunctionUrl,
  contracts: brokerUrl,
  stateHandlers: {
    'user 42 has an active subscription': async () => {
      await supabaseAdmin.from('subscriptions').upsert({
        id: 'sub_seed', user_id: 42, status: 'active',
        renews_at: '2026-01-01T00:00:00Z', seats: 5,
      });
    },
  },
  afterEach: async () => { await truncate('subscriptions'); },
});
```

State handlers seed the **minimum** to satisfy the matcher. Run against a throwaway Supabase branch or local stack — never a shared dev database, or parallel verifications corrupt each other's state.

## Schema-first alternative (no consumer framework)

When you only have a generated schema, validate boundaries with it directly:

```ts
import { generated } from './supabase-types'; // mcp generate_typescript_types
// Assert the real response satisfies the schema the client compiled against.
const parsed = SubscriptionSchema.parse(await res.json()); // zod from the schema
```

Regenerate types in CI and diff them. A non-empty diff on a public column is a contract change — treat removals and type narrowing as breaking.

## Wire it into CI

- **Consumer CI:** run consumer tests → publish contract tagged with the branch/commit and the target environment.
- **Provider CI:** verify against all contracts whose consumers are deployed to environments the provider is about to enter.
- **Deploy gate:** before promoting the provider, run a "can-I-deploy" check — block if any active consumer's contract is unverified against the new provider version.
- Tag verification results with the provider version so the broker can answer "is this pair compatible" without re-running.

## Evolving a contract without an outage

Breaking changes ship in two deploys, never one:

1. **Expand.** Provider adds the new field / new endpoint while keeping the old. Verify: old contracts still pass.
2. Consumers migrate, publish new contracts.
3. **Contract.** Once no active consumer depends on the old shape (the broker proves this), remove it.

Safe in one step: adding optional response fields, adding new endpoints, loosening request validation. Breaking: removing/renaming a field a consumer reads, narrowing a type, making an optional request field required, changing status-code semantics.

## Red flags

- Contract asserts literal values (`'sub_abc'`, exact timestamps) → brittle; use matchers.
- Provider verification boots the full app with real third-party calls → that is E2E; mock downstreams.
- Provider states share a live database → flaky parallel runs; isolate per branch.
- Consumer mock is hand-written and edited independently of the contract → guaranteed drift; the mock and the contract must be the *same* artifact.
- A green client test suite but production 4xx/5xx on integration → your mock never reflected a real provider verify. The loop is not closed until the provider verifies.
- "We'll add contract tests later" between two teams shipping independently → this is exactly when you need them now.

## Related

- [[commit-pipeline]] for committing contract artifacts and verification config (Conventional Commits + gitmoji).
- [[data-modeling-and-schema-design]] for the data-layer types your consumer parses into.
