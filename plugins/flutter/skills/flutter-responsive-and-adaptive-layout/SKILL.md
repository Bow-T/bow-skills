---
name: flutter-responsive-and-adaptive-layout
description: Triggers when a Flutter UI must adapt across phone/tablet/desktop/web/foldable — breakpoints, LayoutBuilder/MediaQuery, safe areas/insets, adaptive vs responsive choices, and platform-conventional widgets.
---

# Flutter Responsive & Adaptive Layout

Build one UI that looks deliberate on a 360 dp phone, a 1024 dp tablet, a 1920 dp desktop window, and a hinged foldable — without forking the codebase per form factor.

## Two distinct problems — name which you are solving

- **Responsive** = the *same* widgets reflow as available space changes (column → row, list → grid, font/padding scale). Driven by **size**.
- **Adaptive** = *different* widgets/behaviors per platform or input model (Material switch vs Cupertino switch, mouse hover vs touch, menu bar vs bottom nav). Driven by **platform/capability**.

A polished app needs both. Decide per component before coding.

## Measure from the right source

Never branch on raw screen size when you mean *available* space. Prefer `LayoutBuilder` constraints (local box) over `MediaQuery.sizeOf` (whole window) unless you truly need the window.

```dart
// Local available space — survives split-view, side panels, embedding.
LayoutBuilder(
  builder: (context, constraints) {
    final wide = constraints.maxWidth >= 600;
    return wide ? _TwoPane() : _SinglePane();
  },
);
```

Use the granular `MediaQuery.*Of` accessors so a rebuild fires only on the property you read — `MediaQuery.sizeOf(context)`, `MediaQuery.paddingOf(context)`, `MediaQuery.viewInsetsOf(context)`. Reading the whole `MediaQuery.of(context)` rebuilds on every metric change (keyboard, rotation, brightness).

## Breakpoints: define once, reason in dp

Pick semantic tiers, not device names. A common Material-aligned set:

```dart
enum FormFactor { compact, medium, expanded }

FormFactor formFactorOf(double width) => switch (width) {
      < 600 => FormFactor.compact,   // phone portrait
      < 840 => FormFactor.medium,    // phone landscape / small tablet
      _     => FormFactor.expanded,  // tablet / desktop / web
    };
```

All widths are **logical pixels (dp)**, already DPR-normalized — never compare against physical pixels. Centralize tiers so every screen agrees; scattered magic numbers are the #1 cause of inconsistent breakpoints.

## Let layout widgets do the work before you branch

Many "responsive" needs require zero size checks:

- `Wrap` — chips/buttons flow to the next line when they run out of width.
- `Flexible`/`Expanded` with `flex` — proportional panes.
- `FittedBox` — scale a fixed-design child to fit.
- `GridView` with `SliverGridDelegateWithMaxCrossAxisExtent` — column count derives from a target tile width, so it adapts continuously:

```dart
GridView.builder(
  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 240, // each tile up to 240 dp; count auto-derived
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: 3 / 4,
  ),
  itemBuilder: (_, i) => _Card(items[i]),
  itemCount: items.length,
);
```

Cap line length on wide screens with `ConstrainedBox(maxWidth: 720)` centered — full-bleed body text on a desktop is a readability bug, not a feature.

## Adaptive navigation — the canonical responsive scaffold

Switch the navigation chrome by tier: bottom bar on compact, rail on medium, extended rail/drawer on expanded.

```dart
LayoutBuilder(builder: (context, c) {
  final ff = formFactorOf(c.maxWidth);
  if (ff == FormFactor.compact) {
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index, onDestinationSelected: onSelect,
        destinations: destinations,
      ),
    );
  }
  return Scaffold(
    body: Row(children: [
      NavigationRail(
        extended: ff == FormFactor.expanded,
        selectedIndex: index, onDestinationSelected: onSelect,
        destinations: railDestinations,
      ),
      const VerticalDivider(width: 1),
      Expanded(child: pages[index]),
    ]),
  );
});
```

Keep navigation **state** lifted above this branch so rotating a phone or resizing a window does not reset the selected tab.

## Safe areas, insets, and the keyboard

Three different paddings — do not conflate them:

- `padding` — notches, status bar, home indicator. Wrap content in `SafeArea`.
- `viewInsets` — space the keyboard takes. Used to push content above the keyboard.
- `viewPadding` — system intrusions ignoring keyboard.

`SafeArea` only consumes `padding`, not `viewInsets`. For keyboard avoidance let `Scaffold` resize (`resizeToAvoidBottomInset: true`, the default) and use `SingleChildScrollView` for forms. To pad a sticky footer above the keyboard:

```dart
Padding(
  padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
  child: _SubmitBar(),
);
```

On expanded layouts, disable `SafeArea`'s horizontal insets where a rail already offsets content, to avoid double padding.

## Platform-conventional widgets (the adaptive axis)

Prefer `.adaptive` constructors that render Cupertino on iOS/macOS and Material elsewhere:

```dart
Switch.adaptive(value: on, onChanged: setOn);
Slider.adaptive(value: v, onChanged: setV);
CircularProgressIndicator.adaptive();
showAdaptiveDialog(context: context, builder: ...);
```

Branch on `defaultTargetPlatform` — never `dart:io Platform` (it throws on web and ignores `debugDefaultTargetPlatformOverride`):

```dart
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

final isApple = !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
     defaultTargetPlatform == TargetPlatform.macOS);
```

## Input model, not just size

Desktop/web add pointer, hover, keyboard, and right-click. Adapt interaction, not only layout:

- `MouseRegion` for hover affordances; gate them on `kIsWeb || isDesktop` so touch devices do not get dead hover states.
- `Focus`/`Shortcuts`/`Actions` and `FocusTraversalGroup` for keyboard navigation — mandatory on desktop/web.
- Increase tap targets to ≥ 48 dp on touch; pointer can go smaller.
- Honor `MediaQuery.textScalerOf(context)` — never hardcode font sizes that ignore OS text scaling, and test at 2.0× to catch overflow.

## Foldables and hinges

Use the `display_features` from `MediaQuery` to avoid placing content under a hinge, or adopt a dual-screen package that exposes `TwoPane`. Treat an unfolded inner screen as `expanded` tier and route to the two-pane layout automatically.

## Verify across the matrix

- Resize a desktop/web window live and watch for overflow stripes — do not test only at fixed sizes.
- `flutter run` with device preview / DevTools device toolbar; toggle text scale, rotation, and locale (RTL via [[internationalization-and-localization]]).
- Add golden tests at representative widths (e.g. 360, 768, 1280) so reflow regressions fail CI.
- Watch for the classic crashes: unbounded height in a `Column` inside a scroll view, `Expanded` outside a flex parent, and `Row` overflow on narrow widths — fix with `Flexible`/`Wrap`, not by hardcoding sizes.

## Cross-links

- Widget composition, theming, and component reuse: [[frontend-ui-engineering]].
- Keyboard traversal, focus order, contrast, and screen readers: [[accessibility-engineering]].
- Locale/RTL/text-scale formatting: [[internationalization-and-localization]].
- Committing the change: [[commit-pipeline]].
