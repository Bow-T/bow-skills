---
name: datetime-timezone-and-money-correctness
description: Trigger when handling dates, times, timezones, durations, currency, rounding, or any value where locale and precision cause silent off-by-one or off-by-a-cent bugs.
---

# Datetime, Timezone & Money Correctness

These bugs do not crash. They ship, then surface as a duplicated charge, a booking on the wrong day, or a reconciliation that is off by one cent across a million rows. Treat every date and every amount as hostile until you have pinned its zone, its unit, and its rounding mode.

## Core rules (memorize)

1. **Store instants in UTC. Always.** The database column is `timestamptz`. The wire format is ISO-8601 with a `Z` or explicit offset. Convert to local time only at the moment of display.
2. **A date is not an instant.** "2026-06-19" (a birthday, a due date, a holiday) has no timezone. Store it as `date`, never `timestamptz`. Forcing a zone onto a calendar date is the #1 off-by-one source.
3. **Money is never a float.** Store and compute in integer minor units (cents) or a decimal type. `0.1 + 0.2 != 0.3` in every IEEE-754 language, including Dart and JS.
4. **A money value is incomplete without its currency.** `1000` means nothing; `1000 + USD` means $10.00, while `1000 + JPY` means ¥1000 (zero decimal places).
5. **Carry the zone, do not assume the server's.** Server `TZ` is an accident of deployment. Never let `DateTime.now()` or `new Date()` semantics leak into business logic.

## Decision: which type do I need?

```
Is it a point on the global timeline (created_at, event start)?  -> instant, UTC timestamptz
Is it a calendar day with no time (invoice_date, dob)?           -> date (no zone)
Is it a wall-clock time recurring locally (store opens 09:00)?   -> local time + IANA zone name
Is it an elapsed span (session length, TTL)?                     -> integer duration in a fixed unit
Is it an amount of money?                                        -> integer minor units + ISO-4217 code
```

## Timezone workflow

1. **Capture the zone at the source.** Persist the IANA name (`Australia/Sydney`), never a fixed offset (`+10:00`). Offsets change twice a year under DST; the name encodes the rules.
2. **Compute in UTC, render in the user's zone.** Do arithmetic on instants in UTC; apply the zone only for display and for "what local day is this".
3. **Anchor "today" to a zone explicitly.** "Did this happen today?" depends on *whose* today. Pass the zone in.
4. **Never build a local datetime by string concatenation.** Use a zone-aware constructor so DST gaps and overlaps are handled.

```dart
// Dart — get the user's local calendar day for an instant, given their zone.
// Use the `timezone` package; the device default is not the user's chosen zone.
import 'package:timezone/timezone.dart' as tz;

DateTime localDayStart(DateTime instantUtc, String ianaZone) {
  final loc = tz.getLocation(ianaZone);
  final local = tz.TZDateTime.from(instantUtc, loc);
  return tz.TZDateTime(loc, local.year, local.month, local.day); // 00:00 local
}
```

```sql
-- Supabase/Postgres — "what local date was this row created?"
-- AT TIME ZONE shifts a timestamptz into a zone, yielding a local timestamp; cast to date.
select id, (created_at at time zone 'Australia/Sydney')::date as local_day
from orders;
```

- **Red flag:** a `timestamptz` column being filtered with `::date` against a literal date *without* `at time zone` — you are silently using UTC midnight as the day boundary.
- **Red flag:** storing offsets like `+07:00` in a "timezone" column.
- **Red flag:** `DateTime.parse(s)` on a naive string in Dart — it returns local time unless the string carries `Z`. Prefer `DateTime.parse(s).toUtc()` only when `s` is genuinely UTC, and assert the format.

## DST and arithmetic traps

- "Add one day" is **not** "add 24 hours" near a DST transition. Use calendar arithmetic for calendar intent, duration arithmetic for elapsed intent. Decide which you mean.
- Some local wall-clock times do not exist (spring-forward gap) or exist twice (fall-back overlap). Decide the policy: shift-forward, or pick the earlier/later instant.
- Recurring schedules ("every day at 09:00 local") must be expanded in the local zone, then converted to instants — never the reverse.

## Money workflow

1. **Pick the representation once.** Integer minor units for transport and storage; a decimal library for intermediate math when fractional cents matter (tax, interest, FX).
2. **Track the currency alongside the amount.** Reject arithmetic between mismatched currencies at the type level.
3. **Round last, and round on purpose.** Choose the mode (banker's/half-even vs half-up) and apply it once, at the final step. Each currency's minor-unit exponent differs (USD=2, JPY=0, BHD=3).
4. **Never let a float touch a balance.** Parse user input as a decimal/string, convert to minor units immediately.

```typescript
// TypeScript — money as integer minor units. No floats anywhere.
type Money = { amount: bigint; currency: "USD" | "JPY" | "BHD" };

const MINOR_UNITS: Record<Money["currency"], number> = { USD: 2, JPY: 0, BHD: 3 };

function add(a: Money, b: Money): Money {
  if (a.currency !== b.currency) throw new Error("currency mismatch");
  return { amount: a.amount + b.amount, currency: a.currency }; // bigint, exact
}

// Format for display only — never round during computation.
function format(m: Money, locale: string): string {
  const exp = MINOR_UNITS[m.currency];
  const value = Number(m.amount) / 10 ** exp; // safe only at the display edge
  return new Intl.NumberFormat(locale, { style: "currency", currency: m.currency }).format(value);
}
```

```sql
-- Supabase/Postgres — store money exactly.
-- numeric for arithmetic precision; or bigint cents. Never float8/real for money.
create table invoices (
  id         uuid primary key default gen_random_uuid(),
  amount     bigint      not null,           -- minor units
  currency   char(3)     not null,           -- ISO-4217
  invoice_at date        not null            -- calendar date, no zone
);
```

- **Splitting a total** (e.g. 3-way split of 1000 cents): distribute the remainder deterministically (give the leftover cents to the first N payees) so the parts sum back to the total. Naive division loses cents.
- **FX conversion:** multiply minor units by the rate in decimal, then round once to the target currency's exponent. Store the rate and timestamp you used.
- **Red flag:** `double`/`float`/`real`/`number` holding a balance; `toFixed(2)` used as if it were rounding logic; tax computed per-line then summed differently than total-then-allocated.

## Test checklist

- Cross a DST boundary in both directions for any local-time logic.
- Run one test with the process `TZ` set to a non-UTC zone (e.g. `TZ=Pacific/Kiritimati`, UTC+14) to expose hidden server-zone assumptions.
- Assert sums are exact: split a value, recombine, compare to the original — no tolerance.
- Test a zero-decimal (JPY) and a three-decimal (BHD) currency, not only USD.
- Test the year/month-end rollovers and Feb 29.

## Related

- [[data-modeling-and-schema-design]] — keep `timestamptz`, `date`, currency code, and minor-unit columns typed correctly at the data layer.
- [[commit-pipeline]] — for committing these fixes (Conventional Commits + gitmoji).
