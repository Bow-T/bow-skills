---
name: payments-and-billing-integration
description: Triggers when integrating payments or subscriptions — idempotent charges, PSP webhooks, proration, dunning, tax, refunds, reconciliation, and PCI scope minimization.
---

# Payments and Billing Integration

Money is the one subsystem where a bug is a chargeback, a tax audit, or a double-charge email
thread. Treat the payment provider (PSP) as the source of truth for money movement, and your
database as a *projection* of it that you keep in sync via webhooks. Never invent state locally
that the PSP could later contradict.

## Step 0 — Frame the integration before any code

Answer these out loud first; the wrong answer here is expensive to unwind:

- **One-off charge or recurring subscription?** Subscriptions pull in proration, dunning, and
  billing-cycle math — don't build them if a one-time charge suffices.
- **Who owns money state?** The PSP. Your DB mirrors it. Decide which PSP objects you persist
  (customer, subscription, invoice, payment-intent) and which you always re-fetch.
- **What is the idempotency key for each money-moving action?** No charge ships without one.
- **PCI scope:** are raw card numbers (PAN) ever touching your servers? They must not. See last
  section — this constrains the whole design.

## Keep card data off your servers (PCI scope minimization)

The cheapest PCI posture is the smallest one. Use the PSP's client-side tokenization so a raw PAN
goes browser/app → PSP, never through your backend. You only ever see opaque tokens
(`pm_...`, `tok_...`).

- Flutter: use the PSP's official SDK to collect card details in a native sheet; your app receives
  a payment-method token, sends *that* to your backend.
- Never log, store, or forward PAN, CVV, or full track data. Not in app logs, not in Supabase rows,
  not in edge-function logs.
- Backend stores only: PSP customer id, payment-method id, last4, brand, expiry. That is safe to
  persist and display.

Red flag: any code path where a card number is a string variable on your server. Stop and redesign.

## Idempotent charges

Every create-charge call carries a client-generated idempotency key so a retry (timeout, double-tap,
queue redelivery) never charges twice. Derive the key from the *intent*, not a random value, so the
same logical action reuses it.

```ts
// edge function — create or reuse a payment intent
const idempotencyKey = `order:${orderId}:charge`; // stable per order
const intent = await psp.paymentIntents.create(
  { amount, currency, customer: customerId, payment_method: pmId, confirm: true },
  { idempotencyKey },
);
```

Guard at your DB layer too: a `unique` constraint on `(order_id, kind)` in your payments table means
even if two requests slip past, only one row wins.

```sql
create unique index payments_order_kind_uniq on payments (order_id, kind);
```

Decision: generate the key on the client and pass it through, or generate it server-side from a
stable order id? Prefer server-side derivation — clients lie and retry inconsistently.

## Webhooks are the real source of truth

The confirm-call response is a hint; the webhook is the truth. Do not mark an order paid from the
synchronous API response alone — confirm via the `payment_intent.succeeded` (or equivalent) event.

Webhook handler checklist, in order:

1. **Verify the signature** against the raw request body using the signing secret. Reject on
   mismatch. Use the raw bytes — re-serializing JSON breaks the signature.
2. **Idempotent processing.** Store each `event.id` in a `processed_events` table; if it exists,
   return 200 immediately. Providers redeliver.
3. **Handle out-of-order delivery.** Events can arrive late or reordered. Re-fetch the object from
   the PSP or compare against a version/timestamp rather than blindly applying.
4. **Return 2xx fast.** Do heavy work async; a slow handler triggers redelivery storms.

```ts
// Supabase edge function (Deno)
const sig = req.headers.get("webhook-signature")!;
const raw = await req.text();                 // RAW body, not parsed
const event = psp.webhooks.constructEvent(raw, sig, signingSecret);

const { error } = await supabase
  .from("processed_events")
  .insert({ id: event.id });
if (error?.code === "23505") return new Response("ok", { status: 200 }); // already handled

await handle(event);                          // upsert order/subscription state
return new Response("ok", { status: 200 });
```

Red flags: parsing the body before verifying the signature; updating state without an
`event.id` dedup; returning 500 on a business-logic error you can't recover from (the PSP will
hammer you — return 200 and dead-letter it instead).

## Subscriptions: proration and billing-cycle math

Let the PSP compute proration — don't reinvent it. When a customer upgrades mid-cycle, the PSP
issues a prorated credit/charge automatically. Your job is to reflect the resulting state.

- On plan change, update the subscription via the PSP and store the returned `current_period_end`,
  `status`, and price id. Drive entitlements off `status` + `current_period_end`, never off a date
  you computed.
- Decide upgrade vs downgrade behavior explicitly: upgrade now (immediate proration) vs downgrade at
  period end (schedule the change). Make this a product decision, not an accident of defaults.
- Entitlement check: a subscription grants access while `status in ('active','trialing')` and now <
  `current_period_end + grace`. Persist these so a logged-in user isn't blocked by a webhook lag.

## Dunning: failed recurring payments

A card that worked last month fails this month — that's normal, not an emergency. Dunning is the
retry-and-recover flow.

- Lean on the PSP's smart retry schedule rather than building your own retry loop.
- Track subscription `status` transitions: `active → past_due → canceled`. Trigger user comms
  (email/in-app) on `past_due`, not on `canceled` — by cancel it's usually too late.
- Define a grace window where access continues during `past_due` so a transient failure doesn't
  lock out a paying customer mid-session.
- Provide a one-tap "update payment method" path; most dunning recovery is just a fresh card token.

See [[event-driven-and-messaging]] for handling these status events reliably and
[[resilience-and-fault-tolerance]] for retry/backoff when calling the PSP.

## Refunds

- Refund through the PSP referencing the original charge/payment-intent id; carry an idempotency key
  (`refund:${paymentId}:${reason}`) so a retried refund doesn't double-refund.
- Refunds also arrive as webhooks (`charge.refunded`) — update local state from the event, not just
  the API response, for consistency with everything else.
- Partial refunds: track refunded-amount per payment; reject a refund that would exceed the captured
  amount before calling the PSP.

## Tax

- Don't hardcode tax rates. Use the PSP's tax engine or a dedicated tax service; rates and nexus
  rules change constantly and vary by buyer location and product category.
- Capture the data the tax engine needs at checkout: buyer address/country, product tax category.
- Store the computed tax amount and the tax-determination snapshot on the invoice for audit. You
  must be able to explain *why* a given tax was charged.

## Reconciliation

Trust nothing; verify daily. Run a scheduled job that compares your DB against the PSP's record of
truth and alerts on drift.

- Pull the PSP's settlement/payout report or charge list for the window; compare totals and
  per-transaction status against your `payments` table.
- Flag: charges the PSP has but you don't (missed webhook), statuses that disagree, amount
  mismatches, refunds you recorded that the PSP didn't.
- A nonzero drift is a bug or a lost event — investigate, don't auto-correct silently.

```sql
-- payments your DB thinks succeeded but no matching settled charge synced today
select p.* from payments p
left join psp_charges_sync s on s.charge_id = p.psp_charge_id
where p.status = 'succeeded' and s.charge_id is null;
```

## Data model essentials

- Store amounts as integer minor units (cents) with an explicit `currency`. Never float money.
- Tables: `customers`, `payment_methods`, `payments` (charges), `subscriptions`, `invoices`,
  `processed_events`. Keep PSP ids as the join keys.
- Enforce RLS so a user sees only their own payment rows; webhook writes use the service role.

## Before you ship

- Run the PSP in test mode end to end: success, decline, 3-D-Secure challenge, refund, failed
  renewal, signature-mismatch webhook.
- Confirm idempotency by replaying the same charge request and the same webhook event — exactly one
  effect each.
- Verify no PAN/CVV appears anywhere in logs or rows.
- Reconciliation job runs and reports zero drift on the test data.

For committing this work, follow [[commit-pipeline]]. Pair with [[threat-modeling]] before launch
and [[observability-and-instrumentation]] to alert on webhook lag, decline spikes, and drift.
