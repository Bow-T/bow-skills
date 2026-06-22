---
name: flutter-internationalization
description: Triggers when localizing a Flutter app — intl + gen-l10n with ARB files, plural/gender/select messages, locale resolution, RTL/bidi layout, and locale-aware date/number/currency formatting.
---

# Flutter Internationalization

Use the official `gen_l10n` pipeline. It generates typed accessors from ARB files,
so missing keys are compile errors, not runtime surprises. Never scatter raw strings
across widgets and never hand-roll your own lookup map.

## Wire up the pipeline

`pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: ^0.20.2   # match the version Flutter ships; let pub upgrade resolve it for your SDK

flutter:
  generate: true   # turns on gen_l10n
```

`l10n.yaml` at the project root:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false   # getter returns non-null; cleaner call sites
```

Each `flutter pub get` (or `flutter gen-l10n`) regenerates
`AppLocalizations` into `.dart_tool/`. Treat it as generated — never edit it.

## ARB authoring

`lib/l10n/app_en.arb` is the template; every key here must exist in every other locale.

```json
{
  "@@locale": "en",
  "appTitle": "Orchard",
  "greeting": "Hello, {name}!",
  "@greeting": {
    "description": "Greeting on the home screen",
    "placeholders": { "name": { "type": "String" } }
  }
}
```

Then `app_ar.arb`, `app_vi.arb`, etc., supply translated values for the same keys.

Wire into `MaterialApp`:

```dart
MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const HomePage(),
);
```

Read it via context — never cache across rebuilds, since locale can change.
Import `AppLocalizations` from the generated output (default
`package:flutter_gen/gen_l10n/app_localizations.dart`, or your configured path):

```dart
final l10n = AppLocalizations.of(context);
Text(l10n.greeting('Mai'));
```

## Plurals, gender, and select

ICU MessageFormat lives inside the ARB string. The generator turns each into a typed method.

Plural — always provide `other`; English needs `one`/`other`, but Arabic and others
need `zero`/`two`/`few`/`many`. Let the translator fill the categories their locale uses:

```json
{
  "itemCount": "{count, plural, =0{No items} one{1 item} other{{count} items}}",
  "@itemCount": {
    "placeholders": { "count": { "type": "int" } }
  }
}
```

```dart
Text(l10n.itemCount(cart.length));
```

Gender via `select`:

```json
{
  "invited": "{gender, select, female{She invited you} male{He invited you} other{They invited you}}",
  "@invited": {
    "placeholders": { "gender": { "type": "String" } }
  }
}
```

Never build sentences by concatenating fragments — word order, agreement, and
spacing differ per language. Put the whole sentence in one message with placeholders.

## Locale resolution

Default resolution falls back to the first supported locale when the device locale
is unsupported. Control it explicitly so e.g. `pt_BR` falls back to `pt`, not `en`:

```dart
MaterialApp(
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  localeResolutionCallback: (deviceLocale, supported) {
    if (deviceLocale == null) return supported.first;
    for (final l in supported) {
      if (l.languageCode == deviceLocale.languageCode) return l;
    }
    return supported.first;
  },
);
```

For a user-chosen language, hoist a `locale` into state (Provider/Riverpod/Bloc)
and pass it to `MaterialApp(locale: ...)`. Persist the choice; on `null` let the
OS decide — hold this in your view-model / state layer.

## RTL and bidi

`Directionality` is set automatically from the active locale, so use
direction-agnostic widgets and properties:

- `EdgeInsetsDirectional.only(start:, end:)` instead of `left/right`.
- `AlignmentDirectional.centerStart` instead of `centerLeft`.
- `Positioned.directional`, `BorderRadiusDirectional`, `start`/`end` everywhere.

```dart
Padding(
  padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
  child: Text(l10n.greeting(name)),
);
```

Mirror only directional glyphs (back arrows, chevrons). Don't mirror logos,
clocks, or media controls. For mixed LTR/RTL runs (a phone number in an Arabic
sentence), wrap with `Bidi.wrapWithUnicode` or the `intl` `BidiFormatter` to stop
the layout from scrambling.

Test RTL without an Arabic build:

```dart
Directionality(
  textDirection: TextDirection.rtl,
  child: MyWidget(),
);
```

## Locale-aware formatting

Use `intl`'s formatters keyed by the active locale — never `DateTime.toString()`,
`'\$$amount'`, or manual thousands separators.

```dart
import 'package:intl/intl.dart';

final tag = Localizations.localeOf(context).toLanguageTag(); // 'vi-VN'

DateFormat.yMMMMd(tag).format(date);              // locale month names + order
NumberFormat.decimalPattern(tag).format(1234567); // correct grouping char
NumberFormat.currency(locale: tag, symbol: '₫').format(price);
NumberFormat.percentPattern(tag).format(0.0825);
```

Format currency by the value's currency, not the UI locale — money in USD stays
USD symbols even for a French-locale user; only grouping/decimal marks follow locale.
For relative times ("3 days ago"), use a localized package rather than rolling your own.

Initialize date symbols once at startup if you format before the first frame.
It is async, so await it in an `async main()` after `ensureInitialized()`:

```dart
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  runApp(const MyApp());
}
```

## Pitfalls

- A key in the template ARB missing from another locale fails generation — keep them in sync.
- Hardcoded layout widths break with longer translations (German, Finnish). Let text wrap;
  test with the longest target language and the pseudo-locale.
- Forgetting `@placeholders` metadata makes the generated method take `Object` — declare `type`.
- Strings in `Text` constructors that bypass `l10n` are invisible to translators; lint for them.
- Don't translate inside `build` from a network call — keep all copy in ARB, shipped with the app.

Commit ARB and config changes per [[commit-pipeline]]. For broader UI conventions
see [[frontend-ui-engineering]]; for accessible localized UI see [[accessibility-engineering]].
