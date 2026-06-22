---
name: email-and-notification-delivery
description: Triggers when sending transactional email/SMS/push — deliverability (SPF/DKIM/DMARC), templating, user preferences, rate/throttle, bounce handling, and avoiding spam classification.
---

# Email and notification delivery

A notification is not "sent" when your code returns 200. It is sent when it lands
in the right inbox, on the right channel, for a user who agreed to receive it.
Treat delivery as a pipeline with explicit state, not a fire-and-forget call.

## 0. Frame the message first

Answer before writing code:

- **Transactional or marketing?** Transactional (password reset, receipt, OTP) is
  triggered by a user action and needs no opt-in. Marketing needs consent and an
  unsubscribe. Mixing them on one sending domain poisons deliverability of both.
- **Which channel, and what is the fallback?** Push can be silently dropped by the
  OS; SMS costs money and has length limits; email is cheap but slow. Pick one
  primary per intent; only fan out to a second channel on a real failure signal.
- **Is it idempotent?** A retry must not send twice. See [[idempotency-and-exactly-once]].

Red flag: "send an email" with no answer to "what happens if it bounces?"

## 1. Lock down deliverability before sending anything

You cannot fix a burned domain quickly. Set DNS first, on a **subdomain** dedicated
to sending (e.g. `mail.example.com`) so reputation is isolated from your root domain.

- **SPF** — TXT record authorizing your provider's IPs to send as your domain.
- **DKIM** — provider gives a public key as a CNAME/TXT; it signs each message so
  receivers verify it was not tampered with. Rotate keys periodically.
- **DMARC** — TXT at `_dmarc.mail.example.com`. Start at `p=none` with an `rua=`
  aggregate-report address, watch reports for a week, then move to `p=quarantine`
  and finally `p=reject`. Jumping straight to reject silently kills legitimate mail.

Verify before launch:

```bash
dig +short txt example.com | grep spf1
dig +short txt _dmarc.mail.example.com
# Send one message to a seed inbox and read raw headers:
# Authentication-Results: spf=pass dkim=pass dmarc=pass
```

If all three do not show `pass`, stop — nothing downstream matters yet.

## 2. Persist intent, then deliver asynchronously

Never call the provider inline in a request handler. Write a row, return, and let a
worker deliver. This gives you retries, auditing, and back-pressure for free. See
[[background-jobs-and-queues]] and [[event-driven-and-messaging]].

```sql
create table notification (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id),
  channel       text not null check (channel in ('email','sms','push')),
  template      text not null,
  payload       jsonb not null default '{}',
  dedupe_key    text,                          -- idempotency guard
  status        text not null default 'queued'
                  check (status in ('queued','sending','sent','failed','suppressed')),
  attempts      int  not null default 0,
  provider_id   text,                          -- message id for bounce correlation
  created_at    timestamptz not null default now()
);
create unique index on notification (dedupe_key) where dedupe_key is not null;
```

The partial unique index makes a duplicate enqueue a no-op insert conflict, not a
second message. Enable RLS so a user can only read their own rows.

## 3. Check preferences and suppression at send time

Two gates, both checked in the worker — not in the caller, which may not know the
current state:

1. **User preference** — did they opt out of this *category* (not just globally)?
2. **Suppression list** — is this address/number hard-bounced or marked spam?

```sql
create table suppression (
  channel    text not null,
  address    text not null,        -- email or E.164 number
  reason     text not null,        -- 'hard_bounce' | 'complaint' | 'unsubscribe'
  created_at timestamptz not null default now(),
  primary key (channel, address)
);
```

If suppressed, set the notification `status = 'suppressed'` and stop. Sending to a
known-bad address is the fastest way to wreck sender reputation.

## 4. Template with care

- Keep templates in version control, not in a vendor UI you cannot diff or review.
- Separate content from data; pass typed values, never raw user HTML.
- **Always ship a plaintext part** alongside HTML — HTML-only mail scores as spam.
- Escape every interpolated value. A user's display name in a subject line is an
  injection vector for header splitting and content spoofing.

```typescript
// Dart caller enqueues; TS edge worker renders + delivers.
interface ResetPayload { name: string; link: string; expiresMin: number }

function renderReset(p: ResetPayload) {
  const name = escapeHtml(p.name);
  return {
    subject: `Reset your password`,            // no interpolation in subject
    text: `Hi ${p.name},\nReset: ${p.link}\nExpires in ${p.expiresMin} min.`,
    html: `<p>Hi ${name},</p><p><a href="${encodeURI(p.link)}">Reset password</a></p>`,
  };
}
```

Red flags in template content: ALL CAPS subjects, `!!!`, link-shortener URLs,
mismatched link text vs href, image-only body, spammy trigger words in the subject.

## 5. Deliver, classify the result, update state

```typescript
async function deliver(n: Notification) {
  await db.update(n.id, { status: "sending", attempts: n.attempts + 1 });
  try {
    const res = await provider.send(buildMessage(n));     // set per-request timeout
    await db.update(n.id, { status: "sent", provider_id: res.id });
  } catch (err) {
    if (isPermanent(err)) {                                // 5xx address/auth errors
      await suppressIfAddressInvalid(n, err);
      await db.update(n.id, { status: "failed" });         // do NOT retry
    } else if (n.attempts >= MAX_ATTEMPTS) {
      await db.update(n.id, { status: "failed" });
    } else {
      throw err;                                           // let the queue retry w/ backoff
    }
  }
}
```

Distinguish **permanent** (bad address, blocked, unsubscribed → suppress, no retry)
from **transient** (timeout, 429, greylisting → retry with exponential backoff and
jitter). Retrying a permanent failure burns reputation. See [[resilience-and-fault-tolerance]].

## 6. Rate and throttle

Receivers throttle senders that spike. Spread sends and cap concurrency.

- Cap per-recipient frequency (e.g. at most N of a category per user per hour) to
  avoid notification storms from a buggy trigger loop.
- Cap global send rate to your provider's and the receiver's tolerance; warm new
  IPs/domains gradually rather than blasting day one.
- Use a token-bucket or a `sending` quota on the worker. See [[rate-limiting-and-quota-design]].

Red flag: a code path that can enqueue one notification per database row in a loop
with no per-user cap — one bad deploy then mails a user 4,000 times.

## 7. Close the loop on bounces and complaints

Delivery state lives at the provider after handoff. Wire a webhook endpoint to
ingest async events (delivered, bounced, complained, opened). See [[webhook-design-and-delivery]].

```typescript
// Edge function: verify signature, then reconcile.
export async function onProviderEvent(req: Request) {
  if (!verifySignature(req)) return new Response("bad sig", { status: 401 });
  const ev = await req.json();
  if (ev.type === "hard_bounce" || ev.type === "complaint") {
    await upsertSuppression(ev.channel, ev.address, ev.type);
  }
  await db.updateByProviderId(ev.message_id, { status: mapStatus(ev.type) });
  return new Response("ok");                                // 200 fast; process async
}
```

- **Hard bounce** → suppress permanently.
- **Soft bounce** (mailbox full) → allow a few retries, then suppress.
- **Complaint** (marked spam) → suppress immediately and review why it was sent.
- Always verify the webhook signature; an unauthenticated endpoint lets anyone
  suppress your users or forge "delivered".

## 8. Observe and alarm

Track bounce rate, complaint rate, and send-to-delivered latency as first-class
metrics. Keep complaint rate well under the threshold receivers tolerate (a fraction
of a percent) — cross it and your domain gets throttled or blocked. See
[[observability-and-instrumentation]] and [[slos-and-error-budgets]].

Alert on: bounce-rate spike (bad list or template bug), DKIM/DMARC `pass` rate
dropping (DNS or key rotation broke), queue depth growing (worker stalled).

## Definition of done

- SPF, DKIM, DMARC all return `pass` on a seed message.
- Messages are persisted and delivered by a worker, with a dedupe key.
- Preference and suppression checks gate every send.
- Permanent vs transient failures are handled differently; suppression is automatic.
- A signature-verified webhook reconciles bounces/complaints.
- Per-user and global rate caps exist; bounce/complaint metrics are alarmed.

Commit via [[commit-pipeline]].
