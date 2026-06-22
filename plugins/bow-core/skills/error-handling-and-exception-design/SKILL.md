---
name: error-handling-and-exception-design
description: Triggers when deciding how code reports and propagates failure — error types vs exceptions vs result types, what to wrap/retry/swallow, user-facing messages, and consistent error taxonomies.
---

# Error Handling and Exception Design

A failure handling strategy is a design decision, not an afterthought. Decide it per boundary, write it down, and apply it consistently. Inconsistent error handling is how silent data loss and unactionable bug reports happen.

## Step 1 — Classify the failure first

Before choosing a mechanism, name what kind of failure this is:

- **Expected/recoverable** — the caller can plausibly do something about it. Empty search result, validation failure, "row not found", payment declined. These are *domain outcomes*, not exceptions.
- **Programmer error** — a bug. Null where there shouldn't be one, broken invariant, illegal argument. These should crash loudly in development, not be caught.
- **Unexpected/environmental** — network down, disk full, timeout, third-party 500. The caller usually can't fix it but may retry or degrade.

The classification drives everything below. Misclassifying — e.g. modeling "not found" as a thrown exception, or swallowing a programmer error — is the root cause of most bad error handling.

## Step 2 — Choose the mechanism per category

| Category | Mechanism |
|---|---|
| Expected/recoverable | Return a value: result type, sealed/union type, nullable, or typed enum. No throw. |
| Programmer error | Assert / let it crash. Don't catch broadly. |
| Unexpected/environmental | Throw a typed exception; handle at a boundary that can retry or degrade. |

Rule of thumb: **if it's part of the function's contract, it's a return value; if it violates the contract, it's an exception.**

### Result types for expected failures (TypeScript)

```ts
type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };

type FetchUserError = "not_found" | "forbidden";

async function fetchUser(id: string): Promise<Result<User, FetchUserError>> {
  const { data, error } = await supabase.from("users").select().eq("id", id).single();
  if (error?.code === "PGRST116") return { ok: false, error: "not_found" };
  if (error) throw new RepositoryError("fetchUser failed", { cause: error }); // unexpected → throw
  return { ok: true, value: data };
}
```

The caller is *forced* to handle `not_found` because it's in the type. Network/DB faults still throw, because the caller can't sensibly branch on every Postgres error code.

### Sealed results in Dart

```dart
sealed class SignInResult {}
class SignInOk extends SignInResult { final Session session; SignInOk(this.session); }
class SignInInvalidCredentials extends SignInResult {}
class SignInRateLimited extends SignInResult { final Duration retryAfter; SignInRateLimited(this.retryAfter); }

// Exhaustive switch at the call site — the compiler catches a missed case.
final result = await authRepo.signIn(email, password);
switch (result) {
  case SignInOk(:final session): goHome(session);
  case SignInInvalidCredentials(): showError('Email or password is incorrect.');
  case SignInRateLimited(:final retryAfter): showError('Too many attempts. Try again in ${retryAfter.inSeconds}s.');
}
```

## Step 3 — Build one error taxonomy, not ad hoc strings

Define a small, closed set of error categories shared across the codebase. Every thrown exception and every result error maps to one. A practical base set:

- `validation` — bad input, 400-class. User can correct it.
- `unauthorized` / `forbidden` — authn vs authz. (See [[authn-authz-design]].)
- `not_found`
- `conflict` — version/uniqueness/state conflict, 409-class.
- `rate_limited`
- `transient` — retryable upstream/network/timeout.
- `internal` — unexpected; a bug or unhandled state. Never show details to users.

Carry a stable machine-readable `code` plus a category. This is what logs, metrics, and clients branch on — not the human message, which will change.

```ts
class AppError extends Error {
  constructor(
    readonly category: "validation" | "forbidden" | "not_found" | "conflict" | "rate_limited" | "transient" | "internal",
    readonly code: string,          // stable, e.g. "user.email_taken"
    message: string,                // for logs/devs
    readonly options?: { cause?: unknown; retryable?: boolean },
  ) {
    super(message, { cause: options?.cause });
    this.name = "AppError";
  }
}
```

## Step 4 — Wrap at boundaries, preserve the cause

When an error crosses a layer boundary (DB → repository → service → API), wrap it in a domain error **and always attach the original as `cause`**. Wrapping without the cause destroys the stack trace and makes debugging guesswork.

- Wrap to add context the caller needs ("could not load invoice 42").
- Never wrap just to rethrow the same thing one level up — that's noise.
- Don't leak low-level types (a raw `PostgrestException`, a driver error) past the layer that owns them. Translate to the taxonomy.

```dart
try {
  return await _client.from('invoices').select().eq('id', id).single();
} on PostgrestException catch (e, st) {
  if (e.code == 'PGRST116') throw NotFoundException('invoice', id);
  Error.throwWithStackTrace(RepositoryException('load invoice $id', cause: e), st);
}
```

## Step 5 — Decide retry vs swallow vs propagate

For each catch, answer one question: **can I recover here?**

- **Retry** only `transient` errors, only when the operation is idempotent, with backoff + jitter and a cap. Retrying a non-idempotent write duplicates data. See [[resilience-and-fault-tolerance]] and [[idempotency-and-exactly-once]].
- **Swallow** only when the failure is genuinely irrelevant to the result (e.g. a best-effort analytics ping). Always log it. A swallowed error with no log is invisible data loss.
- **Propagate** everything else. The default is to let it travel to a boundary that knows what to do.

```ts
// ❌ swallows everything, hides bugs and network faults alike
try { await save(x); } catch { /* ignore */ }

// ✅ best-effort, explicit, logged
try { await track("saved", x); }
catch (e) { logger.warn("analytics track failed", { code: "telemetry.track", cause: e }); }
```

## Step 6 — Two messages: one for users, one for engineers

Every surfaced error has two faces. Keep them separate:

- **User-facing**: what happened + what they can do, in plain language. No codes, no stack traces, no internal IDs. Localize it (see [[internationalization-and-localization]]).
- **Engineer-facing**: full message, `code`, `cause` chain, request/correlation ID, structured fields. Goes to logs/telemetry, never to the screen.

Map `internal`/`transient` to a generic "Something went wrong, please try again" — exposing internals is both a UX failure and a security leak (see [[security-and-hardening]]). Map `validation`/`conflict`/`not_found` to specific, actionable text. Always log with a correlation ID so a user report ("error at 3pm") maps to one log line. See [[observability-and-instrumentation]] and [[logging-hygiene]].

## Step 7 — Centralize the top-level handler

Have exactly one place per entry point that converts any unhandled error into a response: an API/edge-function handler, a Flutter `runZonedGuarded` + `FlutterError.onError`, a global error boundary. It logs the full detail, maps category → status/UX, and never lets a raw exception reach the user.

```ts
// Supabase edge function boundary
try {
  return json(await handle(req));
} catch (e) {
  const err = e instanceof AppError ? e : new AppError("internal", "unhandled", String(e), { cause: e });
  logger.error(err.message, { code: err.code, category: err.category, cause: err.cause });
  return json({ code: err.code, message: userMessage(err) }, statusFor(err.category));
}
```

## Red flags

- `catch (e) {}` or `catch (_) {}` with no log and no rethrow — silent loss.
- Catching the base `Exception`/`Error`/`Throwable` broadly outside the top-level boundary — you'll swallow programmer errors too.
- Control flow by exception for expected cases (`try { find() } catch { create() }`).
- Stringly-typed errors: branching on `e.message.includes("not found")`.
- Rethrowing without `cause` / losing the stack trace.
- Showing raw exception text, stack traces, or SQL errors to end users.
- Retrying non-idempotent operations, or retrying `validation`/`forbidden` errors.
- Different layers inventing their own error shapes — no shared taxonomy.

## Definition of done

- Every failure path is classified and uses the matching mechanism.
- Errors map to the shared taxonomy with a stable `code`.
- Boundaries wrap with `cause` preserved; low-level types don't leak.
- User messages are actionable and safe; engineer logs are complete and correlated.
- Retries are bounded and idempotency-checked; swallows are logged and justified.

When committing, follow [[commit-pipeline]].
