---
name: internationalization-and-localization
description: Triggers when externalizing UI strings, handling plurals/gender/RTL, formatting dates/numbers/currency per locale, fixing Unicode handling, or building a translation pipeline.
---

# Internationalization and Localization

A senior engineer's process for making software speak every user's language without rewriting it per market. Internationalization (i18n) is the engineering work done once; localization (l10n) is the per-locale content that flows through it.

## 0. Decide the scope before touching code

Answer these first; they change the architecture:

- **Which locales at launch, which are planned?** RTL (Arabic, Hebrew) and CJK change layout and font stacks. East-Asian plurals collapse categories; Slavic/Arabic explode them.
- **Is content static (UI labels) or dynamic (user/DB data)?** Static goes through resource bundles. Dynamic needs a per-row translation strategy in the database.
- **Who translates, and how?** A vendor + TMS, a community, or machine translation post-edited. This decides the file format and the pipeline.

Red flag: starting to extract strings before knowing if RTL is in scope. Retrofitting bidirectional layout is far more expensive than designing for it.

## 1. Externalize every string

No user-facing literal lives in code. Each string gets a stable **key**, not the English text, so copy edits don't churn translation files.

Flutter (ARB + `gen-l10n`):

```dart
// lib/l10n/app_en.arb
{
  "cartItemCount": "{count, plural, =0{Your cart is empty} =1{1 item} other{{count} items}}",
  "@cartItemCount": { "placeholders": { "count": { "type": "int" } } },
  "greeting": "Hello, {name}",
  "@greeting": { "placeholders": { "name": { "type": "String" } } }
}
```

```dart
// Usage — never concatenate sentence fragments.
Text(AppLocalizations.of(context).cartItemCount(items.length));
```

TypeScript (ICU MessageFormat via `i18next`/`formatjs`):

```ts
t('cart.itemCount', { count: items.length });
// en.json: "cart.itemCount": "{count, plural, =0 {Empty} one {# item} other {# items}}"
```

Rules:
- One key = one full sentence. Never build sentences by `+` or template glue across languages — word order differs.
- Keep placeholders named (`{name}`), never positional, so translators can reorder.
- Keys are namespaced by feature (`checkout.payment.cta`), not by screen pixel position.

## 2. Handle plurals and gender with the message format, not `if`

Never branch on `count == 1` in code. Languages have up to six plural categories (`zero one two few many other`). Let ICU/ARB pick the category from the locale's CLDR rules.

```ts
// Gender: use select, not nested ternaries.
// "invite": "{gender, select, female {She invited you} male {He invited you} other {They invited you}}"
t('invite', { gender: user.gender });
```

Red flag: a translation string with no `other` branch — it will throw on locales you didn't test.

## 3. Format dates, numbers, and currency by locale — never by hand

Delegate to the platform. Hand-rolled `dd/MM/yyyy` is a localization bug.

```dart
import 'package:intl/intl.dart';
DateFormat.yMMMd(locale).format(date);          // "Jun 19, 2026" vs "19 juin 2026"
NumberFormat.currency(locale: locale, name: 'EUR').format(1234.5);
```

```ts
new Intl.DateTimeFormat(locale, { dateStyle: 'long' }).format(date);
new Intl.NumberFormat(locale, { style: 'currency', currency: 'EUR' }).format(1234.5);
```

Hard rules:
- **Store** timestamps as UTC (`timestamptz` in Supabase), money as integer minor units + ISO-4217 currency code. **Format** only at the presentation edge.
- Currency symbol and decimal separator are locale-dependent; the stored amount and currency code are not.
- Never assume the user's locale equals their currency. A French speaker may pay in USD.

## 4. Get Unicode right

- Use UTF-8 end to end: DB columns, HTTP headers, file encodings. Postgres/Supabase default to UTF-8 — keep it.
- Normalize user input to **NFC** before storing or comparing, so "é" composed and decomposed compare equal.

```ts
const clean = input.normalize('NFC');
```

- Count grapheme clusters, not code units, for length limits and truncation. Dart's `String.length` counts UTF-16 units; emoji and combining marks break naive limits. Use `characters` package (`str.characters.length`).
- Do case-insensitive comparison with locale-aware folding (`localeCompare` / `Intl.Collator`), never `toLowerCase()` for sorting — Turkish dotless-i will bite you.

## 5. Lay out for RTL and text expansion

- Use **start/end**, never **left/right**, for padding, alignment, and icons. Flutter `EdgeInsetsDirectional`; CSS logical properties (`margin-inline-start`).
- Mirror directional icons (back arrows, progress) but not logos or media controls.
- Budget for **+30-40% text expansion** (German, Finnish). Test with the longest locale, not English. Avoid fixed-width buttons that clip.
- Flutter handles `Directionality` automatically from the locale; verify with `Directionality.of(context)` in custom render code.

Red flag: any hardcoded `Alignment.centerLeft` or `padding-left` in shared widgets.

## 6. Localize dynamic / database content

For user- or admin-authored content needing translation, prefer a sidecar table over JSON columns when you need to query or moderate per language:

```sql
create table product_translations (
  product_id uuid references products(id) on delete cascade,
  locale     text not null,
  name       text not null,
  description text,
  primary key (product_id, locale)
);
```

Resolve with a fallback chain at query time: requested locale, then base language (`pt-BR` -> `pt`), then default locale. Never show a raw key or empty string to the user.

## 7. Build the translation pipeline

1. **Extract** source strings to the canonical file (ARB / JSON) in CI.
2. **Push** to the TMS or vendor; pull translated files back.
3. **Validate** in CI: every locale has all keys, all ICU placeholders match the source, no unresolved `{...}` mismatches. Fail the build on a missing or malformed key.
4. **Pseudo-localize** in a debug build: wrap each string (`[!! Ｈéllô Wörld !!]`) to surface hardcoded strings, clipping, and concatenation before real translation exists.

```bash
flutter gen-l10n   # regenerate typed accessors; run in CI to catch drift
```

Treat the source-locale file as the contract: code may only reference keys that exist in it.

## Definition of done

- No user-facing literal in code; every key resolves in all shipped locales.
- Plurals/gender via message format; dates/numbers/money via platform formatters.
- UTF-8 + NFC throughout; grapheme-aware lengths.
- Layout uses start/end and survives the longest locale and RTL.
- CI fails on missing keys or placeholder mismatch; pseudo-locale build passes a visual scan.

## Related

- Persisting translations and timestamps cleanly: see [[data-modeling-and-schema-design]] for the data-layer conventions.
- Committing extracted strings and locale files: follow [[commit-pipeline]].
