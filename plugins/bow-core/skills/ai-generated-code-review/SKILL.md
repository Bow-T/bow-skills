---
name: ai-generated-code-review
description: Trigger when reviewing or merging code an AI/agent produced — hunting for hallucinated APIs, subtle correctness gaps, security holes, and unjustified complexity.
---

# Reviewing AI-Generated Code

AI-written diffs are confident, well-formatted, and frequently wrong in ways human-written code rarely is. Review them differently. Assume the code *compiles and looks plausible* and that the bugs are hiding under that polish.

## 0. Before reading a line

- Re-read the original task. Does the diff solve *that*, or a nearby-but-different problem?
- Note scope: how many files, how many lines. Flag scope creep early (see §4).
- If tests are included, read the tests last — AI tests often assert the buggy behavior.

## 1. Hallucinated APIs — verify everything that "looks real"

The single most common failure. The agent invents method names, named parameters, packages, columns, or RPCs that read perfectly but do not exist.

Checklist:
- Every imported package → confirm it's in `pubspec.yaml` / `package.json` and the symbol exists in that version.
- Every method/named-arg on a third-party type → confirm against installed source, not memory.
- Every Supabase table, column, and RPC → confirm against the actual schema.

```dart
// RED FLAG: looks idiomatic, but does .eq() take a third "type" arg? does this column exist?
final rows = await supabase.from('orders')
    .select('id, total_cents')
    .eq('status', 'paid', 'enum'); // hallucinated 3rd param
```

Fast verifiers:

```bash
flutter analyze && flutter pub deps --no-dev | grep -i <package>
npx tsc --noEmit
```

For Supabase, check the live schema rather than trusting the diff:

```bash
# does the column/table actually exist as written?
grep -rn "create table" supabase/migrations/
```

If a symbol can't be located in real source within ~30s, treat it as hallucinated until proven otherwise.

## 2. Subtle correctness gaps

The logic is usually 90% right. Audit the missing 10%:

- **Boundary conditions**: empty list, single element, null, zero, max int, end-of-month dates.
- **Off-by-one / inclusive-exclusive ranges** in pagination, slicing, retries.
- **Async ordering**: missing `await`, fire-and-forget `Future`s, races between two awaited calls that must be sequential.
- **Error swallowing**: `catch (_) {}` or `try/catch` that returns a default and hides failure.
- **State mutation**: AI loves to copy-then-mutate-original, or mutate a list during iteration.

```dart
// RED FLAG: unawaited side effect; caller thinks the write happened
void save(Order o) {
  repo.persist(o); // returns Future<void>, not awaited
}
```

```typescript
// RED FLAG: filter then index — empty result throws / returns undefined silently
const user = users.filter(u => u.id === id)[0]; // no empty-case handling
```

Decision point: for any non-trivial branch, ask "what input makes this wrong?" If you can't construct one in your head, write the test before approving.

## 3. Security review

AI optimizes for "works in the happy path," which routinely drops security.

- **Injection**: raw string interpolation into SQL or shell. Demand parameterized queries / RPCs.
- **Authorization**: a new Supabase table or query path with no RLS policy, or a query that trusts a client-supplied `user_id` instead of `auth.uid()`.
- **Secrets**: hardcoded keys, service-role keys shipped to client code, `.env` values inlined.
- **Input validation**: trusting request bodies in edge functions; missing length/type checks.
- **Over-broad permissions**: `select('*')` returning columns the client shouldn't see.

```sql
-- RED FLAG: new table, no RLS — every authenticated user reads everyone's rows
create table notes (id uuid primary key, owner uuid, body text);
-- MISSING: alter table notes enable row level security; + owner = auth.uid() policy
```

```typescript
// RED FLAG: trusting client-provided id instead of the session
const { userId } = await req.json();
await db.from('profiles').update(patch).eq('id', userId);
```

Never wave through a diff that touches auth, RLS, or user input without explicit verification. When in doubt, run [[security-and-hardening]].

## 4. Unjustified complexity

AI pads. Strip what isn't earning its place.

Red flags:
- A new abstraction/interface/generic with exactly one implementation.
- A config flag, strategy map, or factory for a thing that never varies.
- Reimplementing something the stdlib, the framework, or an existing helper already does.
- Defensive `try/catch` and null checks around values that can't be null here.
- Comments restating the code line-by-line.

Decision point: for each added file or class, ask "what breaks if I inline/delete this?" If the answer is "nothing," remove it. Prefer the smallest diff that satisfies the task. See [[code-simplification]] if it exists in this repo for the reuse pass.

## 5. Consistency with the codebase

- Does it match existing naming, folder structure, and state-management patterns?
- Did it import a *new* HTTP client / date lib / DI approach when the repo already has one?
- Does Dart code follow the existing model/serialization convention? Cross-check [[data-modeling-and-schema-design]] for the data layer.

A second dependency that duplicates an existing one is a defect, not a style nit.

## 6. Tests last

- Do the tests exercise the boundary cases from §2, or only the happy path?
- Are there tautological assertions (`expect(x, x)`, mocking the unit under test)?
- Does coverage of new branches actually exist, or just line coverage?

If the AI wrote both the bug and the test, the test will pass. Add at least one adversarial case yourself.

## Approval gate

Block the merge if any of these are true:
- An API/column/package can't be verified to exist.
- A new data path lacks RLS or trusts client-supplied identity.
- A correctness question in §2 has no test proving the answer.
- Complexity was added with no varying requirement to justify it.

Otherwise: request the minimal fix, re-verify only the changed lines, then merge. Follow [[commit-pipeline]] for the commit message (Conventional Commits + gitmoji).
