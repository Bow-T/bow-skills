---
name: graphql-schema-and-resolver-design
description: Triggers when designing a GraphQL schema or resolvers — modeling types/connections, batching with DataLoader to kill N+1, query depth/complexity limits, pagination cursors, federation, and persisted queries.
---

# GraphQL Schema & Resolver Design

A GraphQL endpoint is one URL the whole client tree fans out from. The schema is a public contract you cannot un-ship, and every field is a place a resolver can quietly run a query per row. Design the graph first, then make the resolvers cheap and the surface safe.

## 1. Model the graph, not the tables

The schema is for clients, not for your storage layout. Shape it around how the UI navigates.

- Name types by domain nouns (`Order`, `Member`), never by table (`order_row`, `tbl_user`).
- Make nullability mean something. A non-null field is a promise — if the underlying column can be missing or the join can fail, the field is nullable. A single null in a non-null field nulls the whole parent object up the chain.
- Prefer enums over free strings for closed sets (`status: OrderStatus!`), so the type system, not a runtime check, rejects bad values.
- Push side effects into mutations with explicit input and payload types. Never let a query mutate.

**Red flag:** a type that mirrors a database row one-to-one, including columns clients never read. You are leaking schema migrations into your API contract.

## 2. Make every mutation return a typed payload, not a bare entity

A mutation that returns `Order!` cannot express a domain failure without throwing. Wrap it.

```graphql
type PlaceOrderPayload {
  order: Order
  errors: [UserError!]!
}
type UserError { field: [String!]!  message: String! }

type Mutation {
  placeOrder(input: PlaceOrderInput!): PlaceOrderPayload!
}
```

Reserve thrown GraphQL errors for the unexpected (auth, infra, bugs). Expected, recoverable outcomes ("card declined", "out of stock") are data — return them in `errors` so the client renders them instead of crashing the whole response.

## 3. Resolve relations through DataLoader — assume every field is N+1

A field resolver that fetches per parent runs once per item in the list above it. List 50 orders, ask for each order's customer, and a naive resolver fires 50 customer queries. Batch them.

```ts
// One loader per request, keyed by id. Batches all calls in a tick into one query.
const customerLoader = new DataLoader(async (ids: readonly string[]) => {
  const rows = await db.from('customers').select('*').in('id', ids);
  const byId = new Map(rows.data!.map((r) => [r.id, r]));
  return ids.map((id) => byId.get(id) ?? null); // MUST be same length & order as ids
});

// Resolver stays trivial:
Order: { customer: (order) => customerLoader.load(order.customerId) }
```

Non-negotiables:

- **One loader instance per request**, created in context. A loader shared across requests is a cross-tenant cache-poisoning bug.
- The batch function **must return one result per key, in input order** — return `null` for misses, never a shorter array.
- For one-to-many edges (an order's line items), key the loader by parent id and group inside the batch function.

**Red flag:** an `await` to the database directly inside a field resolver. That is the N+1 signature.

## 4. Paginate with cursor connections, not offsets

Offset pagination (`limit`/`offset`) drifts when rows are inserted or deleted mid-scroll and forces the DB to scan and discard. Use opaque, stable cursors.

```graphql
type OrderConnection {
  edges: [OrderEdge!]!
  pageInfo: PageInfo!
  totalCount: Int        # nullable — counting can be expensive; omit if it is
}
type OrderEdge { node: Order!  cursor: String! }
type PageInfo { hasNextPage: Boolean!  endCursor: String }
```

- The cursor encodes the **sort key**, not a row number — e.g. base64 of `(created_at, id)`. The trailing `id` breaks ties so the sort is total and stable.
- Translate `first: 20, after: cursor` into a keyset `WHERE (created_at, id) > (:ts, :id) ORDER BY created_at, id LIMIT 21` — fetch one extra to compute `hasNextPage`.
- Treat the cursor as opaque to clients. Never let them construct one; never leak the raw primary key through it if that is sensitive.

## 5. Bound the query before it runs — depth, complexity, and time

A single request can ask for `posts → author → posts → author …` and walk your whole database. The client controls the query shape, so you must cap it server-side.

- **Depth limit**: reject queries nested past a sane ceiling (e.g. 10). Stops recursive cycles cold.
- **Complexity scoring**: assign each field a cost, multiply list fields by their requested `first:`, and reject above a budget. A query asking `first: 1000` on three nested connections should be denied before a single row is read.
- **Timeout + row caps**: every resolver path needs an upper bound on rows; pagination arguments must have a hard `max(first)`.
- **Disable introspection in production** for non-public APIs, and turn off field suggestions in errors so you stop handing attackers your schema.

**Red flag:** a `first` argument with no maximum, or no complexity gate. That is an unauthenticated resource-exhaustion vector.

## 6. Lock the production surface with persisted queries

In a closed client/server pair (your Flutter app talking to your backend), clients should not send arbitrary query text.

- Register the exact set of operations the app ships with; clients send a **hash**, the server maps it to the stored query. Unknown hash is rejected.
- This shrinks request payloads, makes complexity analysis a one-time offline job, and turns the API into an allow-list — an attacker cannot run a query you did not author.
- Version the manifest alongside the client release so old app versions keep working after deploys.

## 7. Federate only when teams, not files, force it

Splitting one schema across independently deployed subgraphs (federation) buys team autonomy at the cost of a gateway, cross-subgraph reference resolvers, and distributed debugging.

- Stay with a **single schema** until separate teams own separate domains and ship on separate cadences. A modular monolith schema is almost always the boring, correct answer.
- When you do federate: each entity has **one owning subgraph**; others extend it by key reference and resolve only the fields they own.
- The gateway is now a hot path and a single point of failure — it inherits the depth/complexity limits from step 5, not just the subgraphs.

## 8. Authorize per field, in resolvers and context — never in the gateway alone

The graph lets a client reach a sensitive field through many paths, so a route-level check is not enough.

- Resolve the principal once in `context`; check authorization at the resolver that exposes protected data, by record, not just by type.
- With Supabase, let row-level security be the backstop: run resolver DB calls under the caller's JWT so RLS filters rows even if a resolver forgets a check. Defense in depth, not a substitute. See [[authn-authz-design]] and [[supabase-security-review]].
- Field-level errors should mask, not confirm — return `null` on a forbidden field where the schema allows, rather than revealing the row exists.

## Before you ship

- Every list/relation field goes through a DataLoader; verified by query count, not by eyeballing.
- Depth, complexity, and `max(first)` limits are enforced and tested with a deliberately abusive query.
- Cursors are opaque, stable, and keyset-backed; offset pagination removed.
- Schema changes are additive or run through a deprecation path — see [[api-versioning-and-evolution]] and [[deprecation-and-migration]].
- Resolver auth verified against RLS as a backstop; introspection off where it should be.
- Commit via [[commit-pipeline]].

Related: [[database-query-optimization]] for the queries your loaders run, [[api-and-interface-design]] for contract stability, [[load-and-stress-testing]] to prove the complexity gate holds.
