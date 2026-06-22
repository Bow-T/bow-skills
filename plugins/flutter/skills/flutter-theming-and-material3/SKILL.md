---
name: flutter-theming-and-material3
description: Triggers when defining or refactoring app visual identity — ColorScheme/seed colors, ThemeData and component themes, Material 3 vs Cupertino, dark mode, design tokens, and avoiding hard-coded colors/text styles.
---

# Flutter Theming and Material 3

Centralize visual identity in one `ThemeData` so widgets stay free of literal colors,
sizes, and `TextStyle`s. A widget that reads `Theme.of(context)` automatically responds
to dark mode, accessibility text scaling, and a future rebrand. A widget with
`Color(0xFFAA0000)` baked in does none of that.

## Workflow

### 1. Generate a ColorScheme from a seed, do not list 30 colors by hand

Material 3 derives a full tonal palette from one seed color. Let it.

```dart
final seed = const Color(0xFF4A6CF7);

final lightScheme = ColorScheme.fromSeed(seedColor: seed);
final darkScheme = ColorScheme.fromSeed(
  seedColor: seed,
  brightness: Brightness.dark,
);
```

`ColorScheme.fromSeed` guarantees WCAG-aware contrast between role pairs
(`primary`/`onPrimary`, `surface`/`onSurface`, …). Always paint foreground content with
the matching `on*` role — never assume white text on `primary`.

If a brand requires exact hex values the seed won't produce, override only those roles:

```dart
final scheme = ColorScheme.fromSeed(seedColor: seed).copyWith(
  error: const Color(0xFFB3261E),
  tertiary: const Color(0xFF7D5260),
);
```

When you have a full Material color export, prefer `ColorScheme.fromImageProvider` (for
dynamic art) or hand-build with `ColorScheme(...)` only as a last resort — listing all
roles is error-prone.

### 2. Build one ThemeData per brightness; enable Material 3

```dart
ThemeData buildTheme(ColorScheme scheme) => ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Drives default surface tints and ripple shapes from the scheme.
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

MaterialApp(
  theme: buildTheme(lightScheme),
  darkTheme: buildTheme(darkScheme),
  themeMode: ThemeMode.system, // honor OS-level dark mode
  home: const HomePage(),
);
```

`ThemeMode.system` is the right default. Expose a manual override only if the product
needs it, and persist the choice — see [[secrets-and-config-management]] patterns for
where simple user prefs belong (local storage, not a secret store).

### 3. Type ramp: define text styles once via TextTheme

Never write `TextStyle(fontSize: 18, fontWeight: FontWeight.w600)` inline. Read the role.

```dart
Text('Section title', style: Theme.of(context).textTheme.titleLarge);
```

Customize the ramp centrally, and apply a font through `ThemeData`:

```dart
final base = ThemeData(useMaterial3: true, colorScheme: lightScheme);
final theme = base.copyWith(
  textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
    headlineSmall: GoogleFonts.inter(fontWeight: FontWeight.w700),
  ),
);
```

Apply `MediaQuery.textScalerOf(context)` respect by default — Material widgets already
do. Don't cap text scaling globally; if you must clamp, clamp narrowly on a single
overflow-prone widget, not the whole app.

### 4. Component themes, not per-widget styling

When every button or card looks the same, theme the component once. This is the single
biggest lever against drift.

```dart
ThemeData buildTheme(ColorScheme scheme) => ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(),
      ),
    );
```

Now `FilledButton(onPressed: ..., child: ...)` is correct everywhere with zero local
style. A one-off variant uses `.styleFrom` at the call site — that's a deliberate
exception, not the norm.

### 5. Design tokens that ColorScheme can't hold: use ThemeExtension

Spacing scales, brand gradients, semantic colors like "success", and custom radii don't
fit `ColorScheme`. Put them in a typed `ThemeExtension` so they interpolate on theme
animation and stay null-safe.

```dart
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({required this.success, required this.gap});

  final Color success;
  final double gap;

  @override
  AppTokens copyWith({Color? success, double? gap}) =>
      AppTokens(success: success ?? this.success, gap: gap ?? this.gap);

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      success: Color.lerp(success, other.success, t)!,
      gap: lerpDouble(gap, other.gap, t)!,
    );
  }
}

// Register per brightness:
theme.copyWith(extensions: const [AppTokens(success: Color(0xFF2E7D32), gap: 8)]);

// Read it (define an extension getter to keep call sites clean):
final tokens = Theme.of(context).extension<AppTokens>()!;
Container(color: tokens.success, padding: EdgeInsets.all(tokens.gap));
```

### 6. Material vs Cupertino: pick a strategy, don't half-mix

- **One design language everywhere** (most apps): use Material `ThemeData` on all
  platforms. Set `MaterialApp.theme` and move on.
- **Platform-adaptive**: keep Material as the base, and let specific widgets adapt —
  `Switch.adaptive`, `CircularProgressIndicator.adaptive`, `showAdaptiveDialog`. These
  render Cupertino on iOS/macOS and Material elsewhere from the same call.
- **Fully Cupertino**: use `CupertinoApp` with `CupertinoThemeData`. Don't try to drive
  Cupertino widgets from `ThemeData` — they read `CupertinoTheme`, not `Theme`.

Decide once at the architecture level; ad-hoc mixing produces inconsistent ripples,
fonts, and dialogs.

### 7. Verify, then enforce

- Toggle dark mode at runtime and on the OS; confirm no white-on-white or invisible
  icons. The fix is almost always "use the `on*` role".
- Crank text scale to 200% in device settings and check critical screens for clipping.
- Grep the diff for regressions before committing:

```bash
# Hard-coded colors and inline text sizing outside the theme layer.
grep -rnE 'Color\(0x|Colors\.(red|blue|green|grey|black|white)|fontSize:' \
  lib/ --include='*.dart' | grep -v 'lib/theme/'
```

Wire that grep into review per [[code-review-and-quality]], and reach for
[[frontend-ui-engineering]] when the work spans layout and interaction beyond pure
theming. Commit through [[commit-pipeline]].

## Anti-patterns

- `color: Colors.blue` in a widget — unreachable by dark mode or rebrand. Use a scheme
  role.
- `Theme.of(context).copyWith(...)` rebuilt inside `build()` every frame — define themes
  once at app construction.
- Branching on `Theme.of(context).brightness == Brightness.dark` to pick colors — that's
  what the two `ColorScheme`s already encode. Let the scheme decide.
- A god `TextStyle` constants file parallel to `TextTheme` — pick `TextTheme` as the
  single source and delete the duplicate.
- `useMaterial3: false` on a new app — you lose the seed palette, dynamic color, and
  modern component shapes for no benefit.
