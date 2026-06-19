---
name: threat-modeling
description: Triggers when designing a new system, feature, or trust boundary; handling sensitive data; preparing a security-sensitive launch; or asked what could go wrong adversarially.
---

# Threat Modeling

Find the attacks before the attacker does. Do this at design time, on a whiteboard or in a doc, before the code that crosses a trust boundary is written. The output is a short list of concrete threats and the mitigation for each. If you finish and have no defensive work to add to the backlog, you modeled too shallow.

## When to run this

- A new feature reads or writes data the user does not own.
- A new entry point appears: an edge function, a webhook, a file upload, a deep link, a third-party callback.
- Auth, roles, payments, PII, secrets, or money movement are involved.
- Before a launch that would be embarrassing or expensive to get breached.

If none of these are true, skip it. Threat modeling a static marketing page is theater.

## The five passes

Run these in order. Each pass takes inputs from the previous one.

### Pass 1 — Draw the data flow, mark the boundaries

Sketch the system as boxes (processes), arrows (data flows), and stores (databases, buckets, caches). Then draw a line wherever **trust level changes**: client to server, your server to a third party, authenticated to anonymous, one tenant to another.

> A trust boundary is any place where data crosses from a context you control into one you do not, or vice versa. Every arrow that crosses a line is an attack surface.

Red flag: you cannot draw the diagram because nobody knows where the data goes. That is the first finding.

### Pass 2 — Enumerate assets and entry points

For each, write one line.

**Assets** (what an adversary wants): user PII, session tokens, service-role keys, billing data, the ability to act as another user, the ability to write arbitrary rows.

**Entry points** (where untrusted input arrives): HTTP routes, edge functions, realtime channels, deep links, push payloads, uploaded files, SQL accepting client-supplied filters, env-injected config.

Rank assets by blast radius if compromised. You will spend your time on the top three.

### Pass 3 — Find threats per boundary (STRIDE-style prompts)

Walk each boundary and ask the six questions. Skip the ones that do not apply; do not skip a category just because it is uncomfortable.

| Prompt | Concrete question for this stack |
| --- | --- |
| **Spoofing** | Can a caller pretend to be another user or service? Is the JWT actually verified server-side, or trusted because it exists? |
| **Tampering** | Can the client change a field it should not — `role`, `price`, `user_id`, `is_admin`? |
| **Repudiation** | If a user disputes an action, do we have an immutable audit trail? |
| **Information disclosure** | Can one tenant read another's rows? Do error messages leak stack traces, IDs, or secrets? |
| **Denial of service** | Can one caller exhaust a quota, a connection pool, or your bill? |
| **Elevation of privilege** | Can an authenticated user reach an admin-only path or call a service-role operation? |

Write each real threat as a sentence: **"An attacker who [position] can [action] because [weakness]."** Vague threats produce vague fixes.

### Pass 4 — Decide a response for each threat

Every threat gets exactly one of: **Mitigate** (build a control), **Accept** (document why the risk is tolerable and who signed off), **Transfer** (push to a provider/insurance), or **Eliminate** (cut the feature). "We'll think about it later" is not a response.

### Pass 5 — Turn mitigations into backlog items

Each mitigation becomes a ticket or a test, not a paragraph nobody reads. A threat without a tracked mitigation is an accepted risk whether you meant it or not.

## Stack-specific traps

**Supabase / Postgres — the row that escapes its owner.**
The default failure mode is a table with RLS disabled or a policy that checks nothing. Enable RLS on every table holding user data and write the policy as part of the same migration. See [[octopus-model]] for the data-layer conventions this fits into.

```sql
-- THREAT: any authenticated user reads every row (information disclosure + cross-tenant).
alter table public.invoices enable row level security;

create policy "owner reads own invoices"
  on public.invoices for select
  using (auth.uid() = owner_id);
```

Red flags: a query that runs from the client using the `service_role` key; a policy with `using (true)`; an edge function that takes `user_id` from the request body instead of the verified JWT.

```ts
// WRONG — trusts client-supplied identity (spoofing + elevation).
const { userId } = await req.json();

// RIGHT — derive identity from the verified token.
const { data: { user } } = await supabase.auth.getUser(jwt);
if (!user) return new Response("unauthorized", { status: 401 });
```

**TypeScript edge functions — the unvalidated entry point.**
Treat every byte off the wire as hostile. Parse and validate at the boundary; reject on mismatch. A typed function signature is not validation — the type is a lie until something checks it.

```ts
import { z } from "zod";

const Body = z.object({
  amountCents: z.number().int().positive().max(1_000_000),
  currency: z.enum(["usd", "eur"]),
});

const parsed = Body.safeParse(await req.json());
if (!parsed.success) return new Response("bad request", { status: 400 });
// THREAT mitigated: client cannot send a negative amount to credit itself (tampering).
```

**Flutter / Dart — the client is not a trust boundary.**
Anything in the app binary is readable: API keys, feature flags, the "hidden" admin screen. Never enforce authorization in the widget tree; enforce it on the server.

```dart
// THREAT: shipping a secret in the client (information disclosure).
const stripeSecret = 'sk_live_...'; // never — extract from any APK in minutes.

// Client-side role checks are UX, not security. The server must re-check.
if (user.isAdmin) showAdminButton(); // hides the button; does NOT protect the endpoint.
```

Also model the transport: pin or verify TLS for high-value flows, and assume deep links (`myapp://pay?to=...`) arrive from untrusted sources — validate their params like any other entry point.

## Decision points

- **Authenticated but not authorized?** Spoofing is solved, but pass 3 elevation/disclosure questions still apply per row and per route. Most real breaches live here.
- **Third-party callback (payment webhook, OAuth redirect)?** Verify the signature and treat replay as a first-class threat (use idempotency keys + a nonce store).
- **Handling money or PII?** Repudiation matters: add an append-only audit log before launch, not after the first dispute.

## Red flags that mean stop and model now

- "The frontend already checks that."
- "We use the service-role key on the server, it's fine." (Fine until that path takes user input.)
- A new table merged with no RLS policy in the same change.
- An endpoint that accepts an `id` and returns the object with no ownership check (IDOR).
- Errors returned to the client with full stack traces or internal IDs.
- Rate limiting described as "we'll add it if it becomes a problem."

## Done criteria

You are finished when: the diagram shows every trust boundary; the top assets each have at least one named threat; every threat has a response (mitigate/accept/transfer/eliminate); and each mitigation is a tracked ticket or a test. Record accepted risks explicitly with a name attached.

Commit the threat model doc and any policy migrations following [[commit-pipeline]].
