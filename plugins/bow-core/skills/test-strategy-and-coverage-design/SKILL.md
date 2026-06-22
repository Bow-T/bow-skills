---
name: test-strategy-and-coverage-design
description: Triggers when deciding what and how to test — shaping the test pyramid, drawing unit/integration/e2e boundaries, choosing what to mock, triaging flaky tests, and setting coverage targets that mean something. Use before writing a suite, when a suite is slow or flaky, or when coverage numbers are gamed.
---

# Test Strategy and Coverage Design

## Why this exists

A test suite is a budget: every test costs authoring time, run time, and maintenance drag forever. Spend that budget where defects are likely and expensive, not where coverage is easy. This skill decides *what* to test and at *which level*; [[test-driven-development]] decides *how* to write each test once the level is chosen.

## Step 1 — Classify the code before choosing a level

Ask what kind of risk the code carries, then pick the cheapest level that exercises that risk:

| Code shape | Real risk | Test at |
|---|---|---|
| Pure logic: pricing, parsing, date math, state reducers | Wrong output for an input | Unit |
| Code that talks to a DB, queue, or third-party API | Wrong query, wrong serialization, schema drift | Integration |
| A full user journey across screens/services | Wiring, auth, navigation, contracts | E2E (few) |
| RLS policy, DB trigger, CHECK constraint | Security/data integrity at the boundary | Integration against real Postgres |

Decision rule: **push every test down to the lowest level that can still catch the bug.** A bug catchable by a unit test does not belong in an e2e test.

## Step 2 — Shape the pyramid for this codebase

Aim for many fast unit tests, a meaningful band of integration tests, and a thin layer of e2e. Rough starting ratio: 70 / 25 / 5 — but treat it as a smell detector, not a quota.

Red flags:
- **Ice-cream cone** (mostly e2e): slow, flaky, vague failures. Move logic down into testable units.
- **Hourglass** (units + e2e, no integration): the riskiest seams — DB queries, RLS, serialization — go untested. Fill the middle.
- **All units, zero integration**: every collaborator is mocked, so the suite proves your mocks agree with each other, not that the system works.

## Step 3 — Decide what to mock (and what never to)

Mock to remove **nondeterminism, cost, and unavailability** — not to avoid integration.

Mock these:
- Wall-clock time, random, UUIDs → inject a clock/seed.
- Third-party paid or rate-limited APIs (payment, email, push) at the network boundary.
- Slow external systems you do not own.

Do **not** mock:
- Your own database. Run integration tests against real Postgres (a throwaway local Supabase instance or a transactional test DB). Mocking the DB hides constraint, RLS, and SQL errors — the exact bugs integration tests exist to catch.
- The unit under test, or pure functions.

Mock at the **edge** (the HTTP/SDK boundary), not three layers deep. Deep mocks couple tests to internal structure and rot on every refactor.

```dart
// Inject the seam; do not reach for a global singleton inside the unit.
class CheckoutService {
  CheckoutService({required this.clock, required this.payments});
  final Clock clock;            // fake in tests → deterministic timestamps
  final PaymentGateway payments; // fake at the boundary → no real charges
}
```

```ts
// TS: fake at the network edge, keep real logic in the path.
const gateway: PaymentGateway = useFake ? new FakeGateway() : new StripeGateway(key);
// Test asserts the request we BUILD, not a mock we wrote that mirrors our own code.
```

## Step 4 — Test behavior at boundaries, not implementation

- Assert observable outcomes (return value, persisted row, emitted event), never private internals.
- For each unit, cover: the happy path, each boundary value, one representative error, and the empty/null case. Skip exhaustive permutations.
- For Supabase: an integration test must assert that an **unauthorized** caller is denied, not only that the authorized one succeeds — RLS bugs are silent on the happy path.

```ts
test('rls: tenant A cannot read tenant B rows', async () => {
  const a = clientAs(userA);
  const { data, error } = await a.from('invoices').select().eq('tenant_id', tenantB);
  expect(error ?? data).toSatisfy(() => data?.length === 0); // denied or empty, never B's data
});
```

## Step 5 — Set coverage targets that resist gaming

- Coverage finds **untested** code; it never proves code is **correctly** tested. A line is "covered" by a test with zero assertions.
- Target ~80% line coverage as a floor, not a goal — and **gate on diff/patch coverage** (new code in a change), not the global number. Global coverage rewards old code and punishes nobody for shipping untested new code.
- Track **branch coverage** on logic-heavy modules; track **mutation score** on the few modules where correctness is critical (money, auth, permissions). A surviving mutant means a test that asserts nothing meaningful.
- Exclude generated files (`*.g.dart`, generated Supabase types) from the denominator.

Red flag: coverage rises while bug rate holds steady — tests are exercising lines without asserting behavior.

## Step 6 — Triage flaky tests as defects, not noise

A flaky test is a failed test until proven otherwise. Quarantine it (tag + exclude from the gate), file it, and fix within a bounded window — never `retry: 3` it into silence, which hides real intermittent product bugs.

Common causes and fixes:
- **Time/order dependence** → inject a clock; never `sleep`. Wait on a condition (`pump_and_settle`, poll-until), not a duration.
- **Shared mutable state between tests** → reset DB per test (transaction rollback) and isolate fixtures; no test may depend on another's leftovers.
- **Async race** → await the actual signal, not an arbitrary delay.
- **Test pollution** → run the suite in random order in CI to surface hidden coupling.

```dart
// Bad: time-based, racy.
await Future.delayed(const Duration(seconds: 2));
expect(find.text('Saved'), findsOneWidget);

// Good: settle on the real async work.
await tester.pumpAndSettle();
expect(find.text('Saved'), findsOneWidget);
```

## Step 7 — Keep the suite fast and trustworthy

- Unit suite should run in seconds; if it does not, collaborators are too heavy or you are doing integration work labeled as unit.
- Split fast (pre-commit, every push) from slow (e2e nightly or pre-merge) so the fast loop stays under a minute.
- Delete tests that assert nothing, duplicate a lower-level test, or pin a refactor-fragile internal. A redundant test is negative value.

## Definition of done

- Each risk is tested at the lowest level that catches it; no bug-class is only covered by e2e.
- DB/RLS/serialization paths have integration tests against real Postgres, including a denied-access case.
- Mocks live at external edges only; the DB is not mocked.
- Diff coverage gate is green; critical modules carry branch or mutation checks.
- Zero known flaky tests in the gating suite; any flake is quarantined and filed.

Commit test work following [[commit-pipeline]]. Pairs with [[test-driven-development]], [[contract-testing]], and [[debugging-and-error-recovery]].
