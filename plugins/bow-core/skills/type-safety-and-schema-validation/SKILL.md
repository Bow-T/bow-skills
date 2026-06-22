---
name: type-safety-and-schema-validation
description: Trigger when validating data at a boundary — parsing untrusted input, defining a shared schema, adding runtime validation (Zod/Pydantic/JSON Schema), or hunting down any/unknown leaks.
---

# Type Safety & Schema Validation

Static types describe what the compiler believes. Schemas describe what is actually
true at runtime. Use both, and validate exactly where data crosses a trust boundary.

## Step 1 — Locate the boundaries

A boundary is any point where data you did not construct enters your program:

- Network responses (REST/GraphQL/Edge Function payloads).
- Database rows (a Supabase select returns `unknown`-shaped JSON until proven).
- User input, form bodies, query params, file contents.
- Environment variables and config files.
- Message queues, webhooks, third-party SDK callbacks.

Inside a boundary, types are guarantees. Outside, they are wishes. Validate once at
the edge, then trust the parsed type everywhere downstream.

## Step 2 — Parse, don't cast

The cardinal rule: turn raw data into a typed value through a *validator that can
fail*, never through a cast that silently lies.

Red flags (all of these are casts pretending to be parsing):

- TypeScript: `data as User`, `<User>data`, `JSON.parse(s) as Config`.
- Dart: `json as Map<String, dynamic>` then blind `['field']` access.
- Any function returning `any` whose result flows into typed code.

```ts
// BAD — a lie the compiler can't catch
const user = (await res.json()) as User; // any field could be missing

// GOOD — a parse that fails loudly
const user = UserSchema.parse(await res.json()); // throws on mismatch
```

## Step 3 — Define one schema, derive the type

The schema is the source of truth. Derive the static type from it so they can never
drift apart.

```ts
import { z } from "zod";

export const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  displayName: z.string().min(1).max(80),
  role: z.enum(["owner", "member", "viewer"]),
  createdAt: z.coerce.date(),
});

export type User = z.infer<typeof UserSchema>; // type follows schema, always
```

Decision point: **schema-first** (Zod/Pydantic) when the type and runtime check must
match exactly. **Type-first with a guard** only when a runtime library is overkill
(e.g. a one-field internal flag).

Python edge (Pydantic):

```python
class User(BaseModel):
    id: UUID
    email: EmailStr
    role: Literal["owner", "member", "viewer"]
```

## Step 4 — Validate at the edge, return Result not throw (when expected to fail)

For *expected* failures (user input, external APIs), prefer a safe parse that returns
a discriminated result. Reserve throwing for *programmer* errors.

```ts
const parsed = UserSchema.safeParse(input);
if (!parsed.success) {
  return { ok: false, issues: parsed.error.issues }; // caller handles it
}
return { ok: true, user: parsed.data };
```

In Dart, model the failure in the return type instead of relying on `null`:

```dart
sealed class Parsed<T> {}
class Ok<T> extends Parsed<T> { final T value; Ok(this.value); }
class Err<T> extends Parsed<T> { final String message; Err(this.message); }

Parsed<User> parseUser(Map<String, dynamic> json) {
  final email = json['email'];
  if (email is! String || !email.contains('@')) {
    return Err('invalid email');
  }
  return Ok(User(email: email /* ... */));
}
```

## Step 5 — Share schemas across the stack

Avoid three definitions of "User" (DB, API, client) drifting apart.

- Supabase: generate DB row types from the live schema and treat them as the *storage*
  shape — then layer a domain schema on top for what the app actually needs. Do not
  ship raw row types to the UI; map and validate.
- Keep a single validation package importable by both the Edge Function (TypeScript)
  and the web client. The Dart/Flutter client cannot import TS, so mirror the schema
  with a generated model + a hand-checked `fromJson`/`toJson` and a contract test that
  asserts both ends agree on the same JSON fixture.

```ts
// Edge Function: validate request AND response against shared schemas
const body = CreateOrderRequest.parse(await req.json());
const row = await insertOrder(body);
return Response.json(OrderResponse.parse(row)); // never leak an unvalidated row
```

## Step 6 — Tighten the type system itself

- TypeScript: enable `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`.
  Forbid `any` via lint (`no-explicit-any`); force `unknown` at boundaries so the
  compiler *makes* you narrow.
- Dart: keep analysis strict (`strict-casts`, `strict-raw-types`); avoid `dynamic`
  and prefer sealed classes for closed sets so `switch` is exhaustive.
- Narrow `unknown` with guards, never with a blanket cast.

```ts
function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === "object" && x !== null;
}
```

## Step 7 — Make invalid states unrepresentable

Push correctness into the type, not into runtime `if`s.

- Replace `{ loading: boolean; data?: T; error?: E }` with a discriminated union:
  `{ status: "loading" } | { status: "ok"; data: T } | { status: "fail"; error: E }`.
- Use branded/opaque types for validated primitives so a raw `string` cannot be passed
  where an `Email` is required.

```ts
type Email = string & { readonly __brand: "Email" };
const toEmail = (s: string): Email => EmailSchema.parse(s) as Email;
```

## Red flags checklist

- `as` casts on external data, or `json['x']` access without a guard.
- A type and its runtime validator defined separately (they will drift).
- `catch (e) {}` swallowing a validation failure into a default value.
- `any` or `dynamic` appearing in a function signature at a boundary.
- Optional-everything models (`field?: T` everywhere) hiding missing validation.
- The same entity defined three times across DB, API, and client with no contract test.

## Definition of done

- Every external input passes through a failing validator before typed use.
- Static types are derived from (or contract-tested against) the runtime schema.
- Expected failures return a typed Result; only bugs throw.
- No `any`/`as`/`dynamic` leaks survive across a boundary.

Related: [[data-modeling-and-schema-design]] for the data-layer modeling conventions, and
[[commit-pipeline]] for committing these changes (Conventional Commits + gitmoji).
