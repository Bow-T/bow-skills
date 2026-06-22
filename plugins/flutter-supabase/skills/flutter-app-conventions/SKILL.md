---
name: flutter-app-conventions
description: Follow the app's house UI conventions in apps/mobile — reuse the component library, use AppColor/appStyle/spacing tokens (never raw values), route assets through AppAsset/CachedImage, and put every user-facing string through generated l10n. Use when building any screen or widget and choosing colors, text styles, spacing, assets, components, or copy.
---

# App Conventions — the house UI rules

Goal: a new screen is indistinguishable from the existing ones — same tokens, same components,
same localization. **Reuse before you build; use a token before a raw value.**

> Names below follow the project defaults; read real paths from `.conventions.json`.
> Pairs with [[flutter-mvvm]]. For framework-level theming/i18n see [[flutter-theming-and-material3]]
> and [[flutter-internationalization]] — this skill is the app's *specific* tokens and components.

## 1. Reuse the component library first
Before writing a widget, search `apps/mobile/lib/src/components/` — there is almost always
something to reuse: the `App…Button` family, `AppTextField`/`AppPasswordField`/`AppSearchField`,
`AppDialog`/`ModalConfirm`/`AppModal`/`AppSnackBar`, `AppBarWidget`, `AppRefreshIndicator`,
`PagedBuilder`, `CachedImage`/`CachedImageCircle`, `ItemNoFound`, `ServerError`/`PageError`,
`AppLoading`/`AppCircularProgress`, and more.

```bash
grep -ri "class App" apps/mobile/lib/src/components
```
Extend or parameterise a near-match instead of cloning. Only add a new component when nothing
fits — shared ones in `components/`, screen-local ones in a `widgets/` folder next to the page.

## 2. Tokens, never raw values
- **Colors:** `AppColor.*` (e.g. `AppColor.primaryText`, `AppColor.background`). Never `Color(0x…)` or `Colors.*`.
- **Text:** `context.appStyle.<token>` (e.g. `context.appStyle.display14Bold`). Never an inline bespoke `TextStyle` when a token exists.
- **Spacing:** the num extensions — `12.sizedHeight`, `10.sizedWidth` — and `EdgeInsets` constants. Prefer these over ad-hoc `SizedBox`.
- **Icons/images:** assets via `AppAsset.icons.*`; remote images via `CachedImage` / `CachedImageCircle`, never a bare `Image.network`.

```dart
Text(S.of(context).rideTitle, style: context.appStyle.display14Bold),
SizedBox(height: 12.sizedHeight),
CachedImage(url: ride.thumbnailUrl, width: 48.sizedWidth),
```

## 3. Localize every user-facing string
All copy goes through generated l10n — no hardcoded display strings.
1. Add the key to **both** `apps/mobile/lib/src/l10n/intl_en.arb` and `intl_fr.arb`.
2. Regenerate: `cd apps/mobile && fvm flutter gen-l10n`.
3. Use `S.of(context).<key>` (or `S.current.<key>` off-context).

Plurals/placeholders use ICU in the ARB entry — don't concatenate translated fragments.

## 4. Standard screen states
Use the shared state widgets so every screen behaves the same:
- Empty → `ItemNoFound` · Error → `ServerError` / `PageError` · Loading → `AppLoading` / `AppCircularProgress`
- Pull-to-refresh → wrap in `AppRefreshIndicator(onRefresh: provider.refresh)`
- Long/paginated lists → `PagedBuilder` (driven by the bounded query reads in [[flutter-supabase-queries]])

## Red flags — stop and fix before commit
- ✗ `Color(0x…)` / `Colors.*` → use `AppColor.*`.
- ✗ inline `TextStyle(...)` where a token exists → use `context.appStyle.*`.
- ✗ ad-hoc `SizedBox(height: 12)` → `12.sizedHeight`.
- ✗ `Image.network(...)` → `CachedImage`.
- ✗ a hardcoded user-facing string → add an l10n key in both ARBs, regenerate, use `S.of(context)`.
- ✗ a brand-new widget that duplicates a component already in `components/` → reuse/extend it.

Then run `cd apps/mobile && fvm flutter analyze` (zero errors and warnings) before handing off to
[[commit-pipeline]].
