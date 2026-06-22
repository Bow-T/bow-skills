---
name: analytics-and-product-instrumentation
description: Triggers when adding product analytics/event tracking — naming taxonomy, event schema, consent gating, identity stitching, and avoiding double-counting or PII leakage in events.
---

# Analytics and Product Instrumentation

Instrumentation is a data contract, not a side effect. A wrong event is worse than
a missing one: it silently corrupts every dashboard built on it. Treat each event
like a public API — name it once, schema it, version it, and gate it on consent.

## 0. Before you fire a single event

Answer these or stop:

- **What decision does this event inform?** No decision, no event. "Might be useful
  later" produces noise that buries the signal.
- **Who reads it?** A funnel chart, a retention cohort, an alert? The reader dictates
  the shape.
- **Is it client-side or server-side truth?** Money, entitlements, and anything a user
  could spoof must be emitted server-side. UI intent (taps, scrolls, page views) is
  client-side.

If requirements are fuzzy, run [[interview-me]] first — analytics specs rot fast when
guessed.

## 1. Lock a naming taxonomy

Pick ONE convention and enforce it in code review forever. Mixing
`SignupCompleted`, `signup_complete`, and `user signed up` for the same action is
the most common self-inflicted wound.

Recommended: `object_action`, snake_case, past tense, present-tense verbs banned.

```
checkout_started        // good: object, action, past tense
order_completed         // good
cart                    // bad: no action
clicked_buy_button      // bad: action-first, UI-coupled
OrderCompleted          // bad: casing drift
```

Rules of thumb:
- **Name the business event, not the widget.** `subscription_upgraded`, not
  `gold_button_tapped`. The button moves; the meaning doesn't.
- **Properties are snake_case nouns:** `plan_tier`, `payment_method`, `amount_cents`.
- **Reserve a prefix for lifecycle vs feature** if the volume warrants it
  (`app_opened`, `app_backgrounded`).

## 2. Define the schema as a typed source of truth

Free-form `Map<String, dynamic>` calls scattered across the codebase guarantee drift.
Centralize every event behind a typed facade so the compiler is your schema validator.

Dart/Flutter:

```dart
sealed class AnalyticsEvent {
  String get name;
  Map<String, Object?> get props;
}

final class CheckoutStarted extends AnalyticsEvent {
  CheckoutStarted({required this.cartId, required this.amountCents, required this.itemCount});
  final String cartId;
  final int amountCents;   // always integer minor units — never floats for money
  final int itemCount;

  @override
  String get name => 'checkout_started';
  @override
  Map<String, Object?> get props =>
      {'cart_id': cartId, 'amount_cents': amountCents, 'item_count': itemCount};
}

abstract interface class Analytics {
  void track(AnalyticsEvent event);
}
```

Now a typo is a compile error and the property set is documented in one place. Call
sites read `analytics.track(CheckoutStarted(...))` — no stringly-typed maps.

For server-side events in TypeScript, mirror the same idea with a discriminated union
and validate at the boundary (see [[type-safety-and-schema-validation]]):

```ts
type Event =
  | { name: 'checkout_started'; cart_id: string; amount_cents: number; item_count: number }
  | { name: 'order_completed'; order_id: string; amount_cents: number };
```

Keep a versioned registry (a checked-in file or table) listing every event, its
properties, types, and owner. New event = PR to the registry first. See
[[documentation-and-adrs]] for recording why an event exists.

## 3. Gate on consent — before the SDK loads, not after

No event may leave the device until the user's consent state permits it. This is a
correctness and legal requirement, not a feature flag.

- **Default closed.** Until consent is known, buffer or drop — never send.
- **Initialize the SDK lazily** so it cannot phone home on boot.
- **Honor categories** (analytics vs marketing vs functional) separately; a user may
  allow one and not another.
- **On withdrawal,** stop emission immediately and trigger any required deletion.

```dart
class ConsentGatedAnalytics implements Analytics {
  ConsentGatedAnalytics(this._inner, this._consent);
  final Analytics _inner;
  final ConsentState _consent;

  @override
  void track(AnalyticsEvent event) {
    if (!_consent.allows(ConsentCategory.analytics)) return; // hard stop
    _inner.track(event);
  }
}
```

Red flag: consent checked in the UI layer but the SDK auto-collects in the background.
The gate must wrap the transport, not the call site.

## 4. Identity stitching without PII leakage

You need to link the anonymous session to the logged-in user, then keep them linked —
without ever shipping personal data as an event property.

- **Anonymous-first.** Assign a random `anonymous_id` (a UUID) at first launch. Track
  against it before login.
- **Alias on auth.** When the user authenticates, alias `anonymous_id → user_id` ONCE
  so pre-login activity attributes correctly. Use a stable internal id (the Supabase
  `auth.users` UUID), never an email or phone number.
- **Never use raw PII as the identity key or any property.** No email, name, phone,
  raw IP, or device fingerprint in `props`. If you must segment by a PII-derived
  trait, send a coarse bucket (`age_band: "25-34"`), not the value.
- **Logout resets identity** back to a fresh anonymous id so the next user on a shared
  device isn't conflated.

```dart
void onLogin(String userId, String anonymousId) {
  analytics.alias(from: anonymousId, to: userId); // stitch history, fire once
  analytics.identify(userId, traits: {'plan_tier': 'gold'}); // no PII traits
}
```

Scrub by construction: route every payload through a serializer that strips a
denylist of keys (`email`, `phone`, `password`, `token`, `address`) and asserts in
debug builds. See [[secrets-and-config-management]] and [[security-and-hardening]].

## 5. Kill double-counting at the source

Double-counted events inflate every metric and are nearly impossible to detect after
the fact. Defend on three fronts:

- **Idempotency keys.** Stamp each event with a client-generated `event_id` (UUID).
  The pipeline dedupes on it, so retries and offline-queue flushes don't multiply.
  See [[idempotency-and-exactly-once]].
- **Fire-once UI events.** Guard view/impression events against rebuilds. In Flutter,
  a `build()` runs many times — emit from `initState`, a `didChangeDependencies`
  guard, or a visibility-debounced controller, never inline in `build`.
- **One side of the boundary owns each event.** If both client and server can emit
  `order_completed`, you will double-count. Decide once; the other side may emit a
  distinct event (`order_submitted` client, `order_completed` server).

```dart
class _CheckoutPageState extends State<CheckoutPage> {
  bool _viewLogged = false;
  @override
  void initState() {
    super.initState();
    if (!_viewLogged) {
      analytics.track(CheckoutViewed(cartId: widget.cartId));
      _viewLogged = true;
    }
  }
}
```

## 6. Make events reliable in flight

- **Buffer and batch** with a persistent queue so events survive an app kill or
  offline window — but cap retention to avoid stale floods replaying days later.
- **Deliver at-least-once, dedupe on `event_id`** rather than chasing exactly-once at
  the transport.
- **Stamp `client_ts` AND `server_ts`.** Client clocks lie; keep both and prefer
  server time for ordering. See [[datetime-timezone-and-money-correctness]].
- **Never block the user.** Tracking is fire-and-forget; a failed analytics call must
  not break a checkout.

## 7. Verify before trusting

A dashboard that renders is not a dashboard that's correct.

- **Debug sink in dev:** log every event locally and eyeball the name and props.
- **Schema test:** assert each typed event serializes to the registry-declared keys
  and types. See [[test-driven-development]].
- **Reconcile against ground truth:** compare `order_completed` count to the orders
  table for a day. A gap means dropped events or a consent bug; a surplus means
  double-counting.
- **Smoke the consent gate:** with consent denied, assert zero network calls leave
  the device.

## Red flags

- Event names drift in casing or tense → no enforced taxonomy.
- `track('thing', {...rawMap})` at call sites → no typed facade, schema will rot.
- Email or phone appearing in event props → PII leak, stop and scrub.
- SDK initialized at app boot before consent is read → consent bypass.
- View events fired inside `build()` → guaranteed double-count.
- Money sent as a float (`amount: 19.99`) → rounding corruption; use `amount_cents`.
- "We'll figure out the schema in the dashboard later" → unbounded cleanup cost.

## Commit

Stage only the instrumentation and registry changes, then follow [[commit-pipeline]]
for the Conventional Commit and push.
