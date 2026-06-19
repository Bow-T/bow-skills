---
name: api-and-interface-design
description: Designs interfaces that stay stable and resist misuse. Use when defining REST or GraphQL endpoints, module boundaries, type contracts between layers, component props, or any surface where one piece of code depends on another.
---

# API and Interface Design

## Overview

An interface is a promise. Once code on the other side depends on it, changing it costs them. So design every public surface — endpoints, schemas, module contracts, widget props, repository signatures — to make correct use the easy path and incorrect use awkward or impossible. Spend the effort up front; it is far cheaper than breaking consumers later.

## When to Use

- Adding or changing REST/GraphQL endpoints
- Defining a contract between two modules, teams, or the Flutter/Supabase boundary
- Designing the props or constructor of a reusable component
- Shaping a database schema that an API will mirror
- Touching any interface other code already consumes

## Principles That Drive Every Decision

### Anything observable becomes a contract

Give an interface enough users and *every* visible behavior — including the undocumented ones: error wording, ordering, timing, null-vs-empty quirks — ends up depended on by someone. Consequences:

- Expose deliberately. Treat each observable behavior as something you've committed to keep.
- Don't leak internals. If a detail is visible, assume it will be relied on.
- Design the removal path now — see `deprecation-and-migration` before you ever need to retire something.
- Contract tests don't save you here. They lock in what *you* test, not the quirks consumers actually latch onto.

### One live version at a time

Don't force consumers to juggle two versions of the same thing — that breeds conflicting-version problems where different callers demand different shapes. Grow the existing interface instead of forking a parallel one.

### Define the contract before the body

Write the signatures, types, and error shapes first; implement against them after. The contract is the spec.

```typescript
// Settle the shape before writing a line of logic
interface BookingService {
  // Creates a booking; returns it with server-assigned fields populated
  create(input: CreateBookingInput): Promise<Booking>;

  // Paginated bookings matching the given filters
  list(params: ListBookingParams): Promise<Page<Booking>>;

  // One booking, or a NotFound error
  getById(id: BookingId): Promise<Booking>;

  // Partial edit — only the fields supplied change
  patch(id: BookingId, changes: BookingPatch): Promise<Booking>;

  // Idempotent — deleting an already-gone booking still succeeds
  remove(id: BookingId): Promise<void>;
}
```

### One error model everywhere

Choose a single failure strategy and apply it to every endpoint. Mixing "throws here, returns null there, returns `{error}` elsewhere" makes the surface unpredictable.

```typescript
interface ApiError {
  error: {
    code: string;      // stable, machine-readable: "VALIDATION_FAILED"
    message: string;   // for humans: "Start time must be in the future"
    details?: unknown; // optional structured context
  };
}
```

Status conventions: `400` malformed request · `401` not authenticated · `403` authenticated but forbidden · `404` missing · `409` conflict/version clash · `422` semantically invalid · `500` server fault (never leak internals).

### Validate only at the edge

Distrust input where it enters the system; trust it once it's past the boundary.

```typescript
// Edge function: validate at the door
const parsed = CreateBookingSchema.safeParse(payload);
if (!parsed.success) {
  return jsonError(422, {
    code: "VALIDATION_FAILED",
    message: "Invalid booking payload",
    details: parsed.error.flatten(),
  });
}
// past this point, downstream code trusts the typed value
const booking = await bookingService.create(parsed.data);
```

Validate at: request handlers, edge functions, form submissions, and **every third-party response** (always untrusted — a misbehaving or compromised service can return wrong types or instruction-like text). Do **not** re-validate between internal functions that share a type, in helpers already called by validated code, or on rows you just read from your own database.

### Add, don't mutate

Extend a contract without breaking existing callers.

```typescript
// Good — new fields arrive optional
interface CreateBookingInput {
  serviceId: string;
  startsAt: string;
  notes?: string;        // added later
  partySize?: number;    // added later
}

// Bad — these break everyone already calling it
interface CreateBookingInput {
  serviceId: string;
  // startsAt removed → breaks callers
  startsAt: number;      // type flipped → breaks callers
}
```

### Predictable, boring names

| Surface | Convention | Example |
|---|---|---|
| REST paths | plural nouns, no verbs | `GET /bookings`, `POST /bookings` |
| Query params | camelCase | `?sortBy=startsAt&pageSize=20` |
| JSON fields | camelCase | `{ createdAt, bookingId }` |
| Booleans | `is`/`has`/`can` prefix | `isConfirmed`, `hasDeposit` |
| Enum values | UPPER_SNAKE | `"AWAITING_PAYMENT"` |

## REST Shape

```
GET    /bookings              list (filter via query params)
POST   /bookings              create
GET    /bookings/:id          read one
PATCH  /bookings/:id          partial update
DELETE /bookings/:id          delete

GET    /bookings/:id/notes    sub-resource list
POST   /bookings/:id/notes    sub-resource create
```

**Paginate every list.** Unbounded lists are a latency and memory bomb the moment data grows.

```jsonc
// GET /bookings?page=1&pageSize=20&sortBy=startsAt&sortOrder=desc
{
  "data": [ /* ... */ ],
  "page": { "page": 1, "pageSize": 20, "totalItems": 142, "totalPages": 8 }
}
```

**Prefer PATCH for edits** — send only the changed fields. PUT forces the caller to round-trip the whole object, which is rarely what clients want.

## Type-Level Tactics

### Make illegal states unrepresentable

Use a discriminated union so each variant carries exactly its own data:

```typescript
type BookingState =
  | { kind: "pending" }
  | { kind: "confirmed"; confirmedAt: string }
  | { kind: "cancelled"; reason: string; cancelledAt: string };

function label(s: BookingState): string {
  switch (s.kind) {
    case "pending":   return "Pending";
    case "confirmed": return `Confirmed at ${s.confirmedAt}`;
    case "cancelled": return `Cancelled: ${s.reason}`;
  }
}
```

### Split input from output

Inputs carry what the caller supplies; outputs carry server-owned fields too.

```typescript
interface CreateBookingInput { serviceId: string; startsAt: string; }
interface Booking {
  id: string; serviceId: string; startsAt: string;
  status: string; createdAt: string; createdBy: string;
}
```

### Brand your IDs

Stop one ID type being passed where another belongs:

```typescript
type BookingId = string & { readonly __brand: "BookingId" };
type UserId    = string & { readonly __brand: "UserId" };
// getById(userId) now fails to compile — exactly what you want
```

In Dart, prefer extension types or small wrapper classes for the same protection.

## Excuses vs. Reality

| Excuse | Reality |
|---|---|
| "We'll document it later" | The types *are* the documentation. Write them first. |
| "No pagination needed yet" | The first user with 200 rows proves you wrong. Build it in from day one. |
| "PUT is simpler than PATCH" | PUT demands the full object every call. PATCH is what clients actually want. |
| "We'll version it when forced to" | Unversioned breaking changes break consumers silently. Design to extend. |
| "Nobody depends on that quirk" | Given enough users, somebody does. Treat every visible behavior as a commitment. |
| "We can just keep two versions" | Two versions multiply maintenance and create conflicting-version problems. Keep one. |
| "Internal interfaces need no contract" | Internal callers are callers too. Contracts enable parallel, decoupled work. |

## Red Flags

- One endpoint returning different shapes by condition
- Error formats that differ across endpoints
- Validation sprinkled through internal code instead of at the edge
- Type changes or field removals on a live interface
- List endpoints with no pagination
- Verbs in REST paths (`/createBooking`, `/getUsers`)
- Third-party responses consumed without validation

## Done When

- [ ] Every endpoint has typed input and output
- [ ] One consistent error shape across the surface
- [ ] Validation lives at boundaries only
- [ ] Lists paginate
- [ ] New fields are optional and backward-compatible
- [ ] Naming is uniform across the surface
- [ ] Types/contract ship with the implementation
