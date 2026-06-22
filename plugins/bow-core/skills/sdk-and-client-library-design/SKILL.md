---
name: sdk-and-client-library-design
description: Triggers when building or publishing an SDK others depend on — language-idiomatic ergonomics, auth/retry/pagination helpers, semantic versioning and breaking-change policy, codegen from specs, and multi-language release/publishing.
---

# SDK and Client Library Design

An SDK is a public contract you cannot redeploy. Once `import your_pkg` runs in someone else's build, every symbol you exposed is load-bearing. The job is to make the easy path obvious, the wrong path impossible, and the upgrade path boring.

## Step 0 — Decide whether you even ship an SDK

A hand-written SDK is a permanent maintenance liability per language. Before committing, justify it:

- **A typed thin wrapper** over the HTTP/RPC surface — worth it when auth, retries, and pagination are fiddly enough that every consumer reinvents them badly.
- **Generated client only** — when the API is large, regular, and well-specified. Let codegen carry it (Step 6).
- **Nothing** — if the API is three endpoints and a bearer token, a curl example beats an SDK you must version forever.

Pick the smallest thing that removes real friction. Each language you support is a release pipeline, a docs set, and a deprecation clock you own indefinitely.

## Step 1 — Design the surface from the call site backward

Write the code you wish a consumer could write, then build inward to satisfy it. The first five lines of the README are the actual product.

```dart
// What a Flutter consumer should be able to write on day one:
final client = OrdersClient(apiKey: env.ordersKey);
final order  = await client.orders.get('ord_123');
await for (final o in client.orders.list(status: OrderStatus.open)) { ... }
```

Rules that fall out of starting here:
- **One constructor, sane defaults.** Required auth is a positional/named-required arg; everything else (base URL, timeout, retry policy) is optional with production-safe defaults.
- **Group by resource, not by HTTP verb.** `client.orders.cancel(id)`, never `client.post('/orders/:id/cancel')`.
- **Return domain types, not raw maps.** A consumer should never touch `json['total']`. Parse defensively at the boundary (tolerate unknown keys — see [[api-versioning-and-evolution]]).
- **Make illegal states unconstructable.** Use enums, sealed/union types, and required params so a wrong call fails at compile time, not at runtime in their production.

## Step 2 — Be idiomatic in each target language, not uniform across them

A "consistent API across languages" that fights every language's grammar is worse than divergence. The shared thing is the resource model and naming; the surface is local.

- **Dart/TypeScript:** `async`/`await` and `Future`/`Promise`; streams/async-iterators for pagination; named params; null-safety honored.
- **Errors:** throw typed exceptions in languages that expect them (Dart, TS, Python); return result tuples/values where that is the convention (Go). Do not bolt Go-style error returns onto Dart.
- **Naming:** `snake_case` on the wire, but expose `camelCase` (Dart/TS) or the host convention in the SDK. Map at the serialization layer.
- **Nullability and time:** never hand back a raw timestamp string — parse to the language's datetime type at the boundary.

## Step 3 — Build the three helpers every consumer otherwise gets wrong

These are the reason a thin wrapper earns its keep. Centralize them so no consumer has to.

**Auth.** Accept a credential, not a raw header. Refresh transparently when the SDK can; never log the secret; let a key be supplied by callback so consumers can rotate without reconstructing the client. Defer secret handling rules to [[secrets-and-config-management]].

**Retries.** Retry only idempotent operations and only on transient failures (network, 429, 5xx). Exponential backoff with jitter; honor `Retry-After`; hard cap on attempts and total elapsed time. Make POSTs safe with an idempotency key the SDK generates and replays.

```ts
async function call(req: Request, attempt = 0): Promise<Response> {
  const res = await fetch(req);
  if (RETRYABLE.has(res.status) && attempt < cfg.maxRetries && isIdempotent(req)) {
    const wait = retryAfter(res) ?? backoffWithJitter(attempt);
    await sleep(wait);
    return call(req, attempt + 1);
  }
  return res;
}
```

See [[resilience-and-fault-tolerance]] for the backoff and circuit-breaker details.

**Pagination.** Never expose cursors to the caller. Hand back a lazy stream that fetches pages under the hood.

```dart
Stream<Order> list({OrderStatus? status}) async* {
  String? cursor;
  do {
    final page = await _get('/orders', {'status': status?.wire, 'cursor': cursor});
    yield* Stream.fromIterable(page.items);
    cursor = page.nextCursor;
  } while (cursor != null);
}
```

## Step 4 — Make failure legible and the SDK observable

Consumers debug your SDK in their stack traces. Help them.

- **Typed error hierarchy:** `AuthError`, `RateLimitError`, `ValidationError`, `ApiError`, `NetworkError`. Each carries the request id, HTTP status, and the server error code/message verbatim.
- **Preserve the request id** from the response on every error so a consumer can quote it in a support ticket.
- **Expose hooks, not print statements:** an optional logger/interceptor for request/response, and timeouts the consumer can set. Default to silent.
- **Never swallow.** A retry that ultimately fails must throw the underlying cause, not a generic "request failed."

## Step 5 — Write the versioning and breaking-change policy before v1.0.0

Semantic versioning is a promise to consumers; make it explicit and keep it.

- **MAJOR** = a consumer's compiling code might break. **MINOR** = additive, backward-compatible. **PATCH** = fixes only.
- The **public surface** = every exported symbol, type shape, default value, and documented behavior. Removing a field, renaming a method, tightening a type, or changing a default is MAJOR.
- **Pre-1.0** signals instability — but pin to it anyway in examples. Reach 1.0 once the surface is one you can defend for a year.
- **Internal escape hatch:** mark experimental/internal APIs clearly (a `internal`/`experimental` namespace or annotation) and exclude them from the SemVer promise in writing.

| Change | Bump | Notes |
|--------|------|-------|
| Add a new method or optional param | MINOR | Default must be backward-safe |
| Add a field to a returned type | MINOR | Consumers ignore unknown fields |
| Rename/remove a public symbol | MAJOR | Deprecate first, delete later |
| Change a default (timeout, retries) | MAJOR | Silent behavior change is the worst kind |
| Make an optional param required | MAJOR | — |
| Fix a bug that some relied on | judgment | Document; often MINOR with a note |

Deprecate loudly and delete slowly: annotate (`@Deprecated('use X; removed in 3.0')`), keep it working for a full major cycle, and point to the replacement. See [[deprecation-and-migration]].

## Step 6 — Generate from a spec where the surface is large and regular

Hand-writing fifty resources is how drift and typos enter. Generate the mechanical layer; hand-write only the ergonomic veneer.

- **Source of truth is the spec** (OpenAPI, protobuf, or `generate_typescript_types` from Supabase). Treat the generated client as build output — never edit it by hand.
- **Layer the hand-written niceties** (the helpers from Step 3, friendly names, convenience overloads) on top of the generated transport, in a separate non-generated module.
- **Pin the generator and spec version** and check generated output into review, so a spec change shows up as a reviewable diff (this is how you catch an accidental breaking change before publish — see [[contract-testing]]).
- **Regenerate in CI** and fail the build if committed output is stale.

## Step 7 — Test the contract, not just the code

- **Round-trip serialization tests:** every model serializes and parses back identically; saved response fixtures still parse after changes.
- **Helper behavior under fault:** assert retries fire on 429/5xx and *not* on 4xx; assert pagination streams every page exactly once and stops; assert auth refresh triggers once on 401.
- **Surface snapshot:** snapshot the public API (exported symbols/signatures) and diff it in CI; an unexpected diff with no MAJOR bump blocks the merge.
- **Smoke test the published artifact** in a clean project for each language before announcing — an install that fails on a fresh machine is the most common launch failure.

## Step 8 — Publish per language as a controlled release

Each ecosystem (pub.dev, npm, PyPI, Maven) is a separate pipeline with its own auth, metadata, and irreversibility.

- **Version in lockstep across languages** so consumers can reason about "SDK 2.3" once, even if a language skips a patch.
- **Publishing is one-way** — most registries forbid overwriting or unpublishing a version. Dry-run, verify the tarball contents, then release.
- **Ship the changelog with the release**, grouped by added/changed/deprecated/removed, naming every breaking change and its migration. See [[release-notes-and-semver]].
- **Automate it in CI** triggered by a tag, with registry tokens from the secret store, so releases are reproducible and not a laptop ritual. Defer commit/tag mechanics to [[commit-pipeline]].

## Quick red-flag scan

- Consumers reaching into raw JSON or building URLs by hand — the SDK is leaking.
- A changed default value or renamed symbol shipped as a MINOR/PATCH.
- Retries firing on non-idempotent POSTs, or on 4xx.
- Cursors or page tokens exposed to the caller.
- Secrets logged by a request interceptor, or no way to rotate a key without rebuilding the client.
- Generated client edited by hand.
- A language target with no fresh-install smoke test before publish.
- "Consistent across languages" code that ignores each language's idioms.

## Shipping

Land the surface, helpers, and generated layer in reviewable steps; snapshot the public API so reviewers see breaking changes; write the changelog with every breaking change named. Follow [[commit-pipeline]] for commits and tags.
