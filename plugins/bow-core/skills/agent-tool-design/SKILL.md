---
name: agent-tool-design
description: Triggers when defining tools/functions an LLM agent can call — naming, parameter schemas, descriptions, return shapes, error surfaces, and guardrails so the model invokes them reliably.
---

# Agent Tool Design

A tool is a prompt with a side effect. The model reads the name, description, and
schema; decides whether to call it; fills the arguments; and interprets whatever you
return. Every one of those is a place the model can go wrong. Design the tool so the
*easy* path is the *correct* path.

## When to reach for this

- Defining functions for a tool-calling agent (chat agent, MCP server, edge-function backend).
- The model calls the wrong tool, skips a required one, or hallucinates arguments.
- A tool "works" in isolation but the agent misuses it in a multi-step flow.

## Step 1 — Decide whether the tool should exist

Fewer, sharper tools beat a large undifferentiated menu. Before adding one:

- **Collapse near-duplicates.** Three tools `getUserById`, `getUserByEmail`,
  `getActiveUsers` invite mis-selection. One `findUsers({ id?, email?, status? })`
  is clearer — *if* the parameters are genuinely alternatives.
- **Split overloaded verbs.** A single `manageOrder({ action })` where `action`
  switches between cancel/refund/ship hides intent. Separate verbs the model can
  reason about distinctly: `cancelOrder`, `refundOrder`.
- **Red flag:** more than ~15–20 tools in one context. The model's selection accuracy
  degrades. Group by sub-agent or load tools by task phase.

Heuristic: a tool should map to one user-meaningful action with one clear precondition.

## Step 2 — Name for the model, not the codebase

The name is the strongest selection signal. Use `verbNoun`, lowercase-camel, no
internal jargon.

```
searchInvoices        // good: action + domain object
getData               // bad: which data?
svc_inv_q             // bad: internal abbreviation
doStuff               // bad: meaningless
```

Names must be mutually distinct at a glance. If two names share a prefix and the
model could confuse them, rename one.

## Step 3 — Write the description as a contract

The description tells the model *when* to call and *what it does* — not how it's
implemented. Lead with the trigger condition.

```ts
// Good — trigger first, then behavior, then boundary
description:
  "Call when the user wants to cancel an order they placed. " +
  "Cancels an order that is still in 'pending' or 'paid' status and issues no refund. " +
  "Does NOT work on shipped orders — use refundOrder for those.",

// Bad — implementation noise, no trigger
description: "Updates the orders table status column via the cancel RPC.",
```

State the negative space explicitly ("does NOT…", "use X instead when…"). Most
mis-selection comes from missing boundaries, not missing capabilities.

## Step 4 — Make the schema do the validating

Constrain inputs so a malformed call is structurally impossible. The model respects
enums, required-vs-optional, and field descriptions far better than prose.

```ts
// TypeScript / JSON-schema-style tool definition
{
  name: "createTask",
  parameters: {
    type: "object",
    properties: {
      title:    { type: "string", description: "Short imperative title, <= 80 chars" },
      priority: { type: "string", enum: ["low", "medium", "high"] },  // not free text
      dueDate:  { type: "string", format: "date", description: "ISO 8601 date, no time" },
      assignee: { type: "string", description: "User UUID. Omit to leave unassigned." },
    },
    required: ["title", "priority"],
    additionalProperties: false,  // reject hallucinated extra fields
  },
}
```

Rules:

- **Enums over strings** for any closed set. The model picks valid values reliably.
- **Flat over nested.** Deeply nested objects raise the chance of malformed args.
  One level deep is usually enough.
- **No magic IDs the model can't know.** If a tool needs a UUID, either a prior tool
  must have returned it, or accept a human-readable key and resolve it server-side.
  A model *will* invent a plausible-looking UUID if you require one it never saw.
- **`additionalProperties: false`** to catch invented fields.
- Mark truly optional things optional; over-requiring forces the model to guess.

In Dart/Flutter, define the same shape as a typed model so the client side stays
honest (see [[type-safety-and-schema-validation]] and [[flutter-data-model]]).

## Step 5 — Shape the return for the model to read

The return value is context the model must parse, not a raw DB dump. Return the
minimum it needs to take the next step.

```ts
// Good — compact, self-describing, next-step ready
return {
  ok: true,
  order: { id: "...", status: "cancelled", refunded: false },
  message: "Order cancelled. No refund was due.",
};

// Bad — leaks rows, tokens, and nothing actionable
return { rows: [/* 200 columns of joined tables */], affected: 1 };
```

- **Echo what changed** so the model can confirm to the user without re-querying.
- **Cap result size.** Paginate or summarize large lists; truncating mid-JSON
  confuses the model. Return `{ items, nextCursor, total }`, not 5,000 rows.
- **Stable keys.** Don't rename fields between calls; the model learns the shape.

## Step 6 — Make errors instructive, not just true

An error is the model's chance to self-correct. Tell it *what to do next*.

```ts
// Good — names the problem and the fix
return {
  ok: false,
  error: "order_not_cancellable",
  message: "Order is already shipped. Call refundOrder instead.",
};

// Bad — opaque, model can only retry blindly
throw new Error("PGRST116");
```

- Use a stable machine `error` code plus a human/model-readable `message`.
- Distinguish **retryable** (transient/timeout) from **terminal** (bad input,
  forbidden) so the agent doesn't loop. See [[resilience-and-fault-tolerance]].
- Never surface raw stack traces, SQL, or secrets in the return — they pollute
  context and leak internals. See [[logging-hygiene]].

## Step 7 — Guardrails for tools with side effects

Treat every write tool as attacker-reachable: the model can be steered by injected
content in its context.

- **Server-side authorization, always.** The model's say-so is not authorization.
  Enforce the acting user's permissions in the function/RLS — never trust an
  `actorId` argument the model fills. See [[authn-authz-design]].
- **Idempotency** on mutations so a retried call doesn't double-charge. Accept an
  idempotency key or derive one. See [[idempotency-and-exactly-once]].
- **Confirmation gate** for destructive/expensive actions: split into a `preview`
  tool (read-only, returns what *would* happen) and a `commit` tool that requires a
  token from the preview.
- **Scope the blast radius.** A delete tool takes one specific ID, not a filter that
  could match everything.

```ts
// Supabase edge function: trust the JWT, not the arguments
const { data: { user } } = await supabase.auth.getUser(jwt);
if (!user) return json({ ok: false, error: "unauthenticated" }, 401);
// authorize against user.id + RLS — ignore any actorId the model passed
```

## Step 8 — Test the way the model actually uses it

Tool quality is an empirical question. Don't ship on inspection alone.

- Write eval cases: a user goal, the expected tool sequence, expected final state.
  See [[llm-evaluation-and-testing]].
- Probe the **trigger boundary** — phrasings that *should* and *should not* fire the
  tool. Mis-selection here is the most common failure.
- Feed back error returns and confirm the model recovers (picks the suggested
  alternative) rather than looping.
- Verify schema rejection: does an invented field actually get refused?

## Red flags

- A `data: any` / free-form `params` blob instead of a typed schema.
- The tool name or description references internal tables, RPC names, or ticket IDs.
- A required argument the model has no way to obtain (unseen UUID, opaque token).
- Errors thrown as raw exceptions with no machine code or recovery hint.
- One mega-tool gated by an `action` or `mode` string switch.
- Returns the full row set / unbounded list straight from the database.
- Authorization implied by an argument the model fills rather than enforced server-side.

## Done when

Each tool has a distinct verb-noun name, a trigger-first description with stated
boundaries, an enum-constrained schema with no unknowable required args, a compact
self-describing return, instructive error codes, server-enforced auth on writes, and
an eval that exercises both the happy path and the trigger boundary.

Commit per the [[commit-pipeline]] skill.
