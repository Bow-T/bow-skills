---
name: fraud-and-abuse-prevention
description: Triggers when defending against malicious-but-authenticated misuse — account takeover, bot/scraping defense, payment fraud, fake signups, velocity rules, device fingerprinting, and risk scoring.
---

# Fraud and Abuse Prevention

Authentication answers "is this a valid account?" Fraud defense answers "is this valid account being used the way a real owner would use it?" The two are different problems. A logged-in session, a correct password, a paid invoice — all can be hostile. This skill is about the second question, where every actor is authenticated and the signal lives in *behavior*, not credentials.

Do not start by writing rules. Start by naming the abuse and what it costs you.

## 1. Name the abuse and its economics

Write one line per threat before any code:

> "**\<actor\>** wants **\<gain\>**; each success costs us **\<loss\>**; they can retry **\<cheaply / expensively\>**."

Common shapes:

- **Account takeover (ATO)** — attacker has valid credentials (phished, credential-stuffed, leaked). Gain: drain wallet, steal data, send spam. Signal: the session does not look like the owner.
- **Fake signups / multi-accounting** — one human spins up many accounts to farm referral bonuses, free trials, or review rings. Signal: many "different" accounts sharing hidden identity.
- **Payment fraud** — stolen card, friendly fraud (legit buyer disputes), triangulation. Loss includes the chargeback *fee* and dispute-rate penalties, not just the goods.
- **Scraping / bot abuse** — automated extraction of your catalog, prices, or content; inventory hoarding; credential-stuffing probes. Signal: machine cadence and breadth.

The economics decide your spend. If a success nets the attacker $2 and costs you $200, invest heavily. If retries are free (no cost to the attacker per attempt), you must make them expensive — that is half the job.

## 2. Defend in layers, scored — not a single gate

Never build one boolean "is_fraud" check. Build independent signals that each contribute to a **risk score**, then act on the score. A single hard rule is trivially probed and bypassed; a sum of weak signals is not.

Layers, cheapest first:

1. **Identity reputation** — is this email/phone/card/IP/device known-bad or brand-new?
2. **Velocity** — how fast and how many, per identity dimension, over a window?
3. **Behavioral / device** — does the session, device, and interaction look human and consistent with the owner?
4. **Network / graph** — does this actor cluster with known-bad actors via shared attributes?

Each layer outputs points. The action threshold is config, not code, so you can tune without deploying.

## 3. Velocity rules — your highest-ROI layer

Most abuse is *volume*. Count events per identity dimension across sliding windows and act when a count is implausible for a real human.

Pick dimensions that are hard to rotate: device fingerprint and payment instrument are stickier than IP or email (which are cheap to change).

In Supabase, a velocity check inside the write path:

```sql
-- Block the 4th distinct card tried by one account in 10 minutes
create or replace function check_card_velocity(p_user uuid, p_card_hash text)
returns boolean language sql stable as $$
  select count(distinct card_hash) < 3
  from payment_attempts
  where user_id = p_user
    and created_at > now() - interval '10 minutes'
    and card_hash <> p_card_hash;
$$;
```

Velocity must be enforced **server-side** — in an edge function or RLS-guarded write, never in the Flutter client, which an attacker controls. Track at least: signups per IP/subnet, login failures per account *and* per IP (stuffing hits many accounts from few IPs), password resets per account, payment attempts per card and per device, and high-value actions (withdrawals, invites) per account.

Tune thresholds against real percentiles. Pull the 99th-percentile honest user from your own data; set the limit above them, not at a guessed round number.

## 4. Device fingerprinting and session continuity

A stable device signal is the backbone of multi-accounting and ATO defense.

- Combine signals into one fingerprint: platform, model, OS version, locale, screen metrics, and a **persisted app-install ID** you generate on first launch and store in secure storage (`flutter_secure_storage`). The install ID survives more than cookies; the passive signals catch resets.
- Treat the fingerprint as a *probabilistic* hint, never proof. Real users share devices and reinstall. Feed it into the score; do not hard-block on it alone.
- For ATO, score **continuity**: a session from a new device + new country + new ASN for an account that has only ever used one phone in one city is high-risk. Step up auth (re-verify), do not silently allow or silently block.
- Never ship the raw fingerprinting logic where a bot can read and forge it. Compute the decision server-side from submitted attributes plus server-observed ones (IP, ASN, TLS/JA signals, request timing).

## 5. Risk scoring and the action ladder

Map the score to a graduated response. Binary allow/deny wastes good users and teaches attackers exactly where the line is.

| Band | Response |
|------|----------|
| Low | Allow silently. |
| Medium | Add friction: step-up MFA, email/phone re-verify, a CAPTCHA, or a hold. |
| High | Block the action, queue for review, but keep the account open. |
| Severe | Suspend and alert, only on multiple independent severe signals. |

Prefer **invisible challenges and delays** over outright blocks for the gray zone. A 24-hour hold on a first withdrawal from a new device stops most ATO cash-out with near-zero harm to honest users. Shadow actions (accept the spam post but show it to no one) deny the attacker the feedback they need to adapt.

## 6. Make retries expensive

If an attacker learns nothing and pays nothing per attempt, they brute-force your scoring. Counter it:

- **Hide the reason.** Return the same generic outcome for blocked and allowed-but-monitored. Do not leak which signal fired.
- **Add asymmetric cost.** Proof-of-work, escalating delays, or a small verification step costs a real user seconds and costs a bot farm real money at scale.
- **Decay reputation slowly, build trust slowly.** A new account earns capabilities over time and clean behavior; it cannot buy them instantly.

## 7. Measure with a confusion matrix, never accuracy

"Accuracy" is meaningless when 99.5% of traffic is legitimate — a do-nothing model scores 99.5%. Track the four cells:

- **False positives** (blocked good users) — the silent revenue killer; instrument an appeal/override path and watch its volume.
- **False negatives** (missed fraud) — measured by chargebacks, abuse reports, and downstream cleanup.
- Watch **chargeback rate** and **dispute rate** as hard business limits — payment processors penalize or terminate accounts above a threshold, so these are not just metrics, they are existential.

Log every decision with its score, the contributing signals, and the action taken, so you can replay and retune. Without that audit trail you are tuning blind.

## 8. Operating discipline

- **Start in shadow mode.** Run new rules in log-only for a week, measure what they *would* have blocked, confirm the honest-user hit rate is acceptable, *then* enforce.
- **Expect adaptation.** Fraud is adversarial; a rule that works today decays as attackers probe it. Schedule review, not set-and-forget.
- **Keep humans in the loop for severe actions.** Auto-suspend on clear signals; route ambiguous high-value cases to review rather than punishing real customers.
- **Never log raw PII, card numbers, or full fingerprints** in plaintext — hash and salt identity values; see [[secrets-and-config-management]] and [[logging-hygiene]].

Related: [[rate-limiting-and-quota-design]] for the throttling primitives velocity rules build on, [[authn-authz-design]] for the credential layer beneath this, [[threat-modeling]] to enumerate abuse cases up front, and [[observability-and-instrumentation]] for the decision telemetry. Commit any rule changes via [[commit-pipeline]].
