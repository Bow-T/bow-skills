---
name: design-system-and-component-library
description: Triggers when building or extending a shared UI component library — tokens, theming, variants/composition APIs, documentation, versioning, and preventing one-off divergence.
---

# Design System and Component Library

A design system is a contract, not a folder of widgets. The job is to make the
right component the easiest thing to reach for, and divergence expensive. Build
from primitives up; never start at the screen.

## Decide the layer before you write code

Place every change in one of three layers. Mixing them is the root cause of
brittle libraries.

1. **Tokens** — raw decisions: color ramps, spacing scale, type ramp, radii,
   durations. No semantics, no components.
2. **Semantic aliases** — intent mapped onto tokens: `surface`, `onSurface`,
   `danger`, `spacingInline`. Components consume *these*, never raw tokens.
3. **Components** — composition of semantics into Button, Card, Field.

Red flag: a Button referencing `Color(0xFF1A73E8)` or `EdgeInsets.all(16)`
directly. It must read `theme.semantic.accent` and `theme.space.md`.

## Step 1 — Token architecture

Make tokens a typed, immutable structure, not loose constants. Two-tier so
themes (light/dark/brand) swap aliases without touching primitives.

```dart
// Tier 1: primitives — never used directly in components
class Primitives {
  static const blue500 = Color(0xFF2563EB);
  static const space1 = 4.0, space2 = 8.0, space4 = 16.0;
}

// Tier 2: semantic, lives on ThemeExtension so it travels with BuildContext
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({required this.accent, required this.danger, required this.spaceMd});
  final Color accent;
  final Color danger;
  final double spaceMd;

  @override
  AppTokens copyWith({Color? accent, Color? danger, double? spaceMd}) => AppTokens(
        accent: accent ?? this.accent, danger: danger ?? this.danger,
        spaceMd: spaceMd ?? this.spaceMd,
      );

  @override
  AppTokens lerp(AppTokens? o, double t) => o == null ? this : AppTokens(
        accent: Color.lerp(accent, o.accent, t)!,
        danger: Color.lerp(danger, o.danger, t)!,
        spaceMd: lerpDouble(spaceMd, o.spaceMd, t)!,
      );
}
```

In TypeScript, emit the same tokens as the single source and generate per-target
artifacts (CSS variables, a TS object) from one file so web and native cannot drift.

```ts
export const tokens = {
  color: { accent: 'var(--accent)', danger: 'var(--danger)' },
  space: { md: 16 },
} as const; // `as const` makes keys autocompletable and misuse a type error
```

Decision point: **scale by name, not by number.** `space.md` survives a redesign;
`space16` becomes a lie the day 16 changes.

## Step 2 — Variant and composition API

Choose variants over boolean soup. Three booleans give eight states, most invalid.

```dart
enum ButtonVariant { primary, secondary, ghost, danger }
enum ButtonSize { sm, md, lg }

class AppButton extends StatelessWidget {
  const AppButton({super.key, required this.label, required this.onPressed,
    this.variant = ButtonVariant.primary, this.size = ButtonSize.md, this.leading});
  // ...
}
```

Red flag: `AppButton(isPrimary: true, isDanger: true, isSmall: true, isOutline: false)`.
Collapse to one `variant` + one `size`; let the type system forbid nonsense.

Composition rules:
- **Prefer slots over flags.** Take a `leading`/`trailing` Widget instead of
  `iconName` + `iconColor` + `iconSize`. Slots scale; flags multiply.
- **Expose escape hatches deliberately.** One optional `style`/`className`
  override is fine; ten one-off props mean the variant set is wrong.
- **Keep components stateless about business logic.** A `UserAvatar` renders a
  URL; it does not fetch from Supabase. Data fetching lives in the view model —
  see [[frontend-ui-engineering]].

## Step 3 — Theming

Themes are alias sets over the same primitives. Light, dark, and any brand are
data, not code branches. Resolve through context so a component never knows which
theme is active.

```dart
extension TokensX on BuildContext {
  AppTokens get tk => Theme.of(this).extension<AppTokens>()!;
}
// usage: color: context.tk.accent
```

Verify both themes render every component before claiming done — a screenshot of
each variant × each theme. "Looks right in light mode" is not done.

## Step 4 — Document where the component lives

A component nobody can find gets rebuilt. Every public component needs, colocated:
- A one-line intent + when **not** to use it.
- Every variant rendered (a gallery/storybook page, a Flutter `Widget` catalog
  route, or a golden-test snapshot set).
- Props table with defaults and accessibility notes (see [[accessibility-engineering]]).

Keep docs in the repo next to the code so they version together; a wiki rots out
of sync within a sprint.

## Step 5 — Versioning and rollout

The library is a published contract. Breaking a prop signature breaks every app.

- Apply semantic versioning: a removed/renamed prop or changed default is a major.
  Pair releases with notes — see [[release-notes-and-semver]].
- **Deprecate, don't delete.** Mark old API, keep it working one minor cycle,
  point to the replacement.

```dart
@Deprecated('Use AppButton(variant: ButtonVariant.danger). Removed in v3.')
const AppButton.destructive({required String label}) ...
```

- For wide renames/removals across consumers, follow [[deprecation-and-migration]]
  and [[large-scale-refactoring]] — ship a codemod, don't file a hand-fix ticket.
- Commit per the [[commit-pipeline]] skill (Conventional Commits + gitmoji).

## Step 6 — Prevent one-off divergence

This is the recurring failure. Guard it actively:

- **Lint against raw values.** Fail CI when component files import `Primitives`
  directly or use hex literals / magic `EdgeInsets`. A custom analyzer rule or a
  grep gate in [[ci-cd-and-automation]] catches it.
- **Make the library the path of least resistance.** If a screen reimplements a
  card, the missing variant is the bug — add it to the library, don't patch the
  screen.
- **Visual regression gate.** Golden tests on the catalog fail the build when a
  token change shifts rendering unexpectedly.
- **One owner per primitive.** Tokens change by review, not by whoever needs a
  color today.

## Red flags checklist

- Hex colors, magic numbers, or `Primitives.*` inside a component.
- A new screen-local widget that duplicates an existing component with tweaks.
- Boolean props that combine into invalid states.
- A variant added by copy-pasting a component file.
- Docs that describe props that no longer exist.
- A breaking prop change shipped as a patch version.
- Tokens defined twice (once for web, once for native) instead of generated from one source.

## Definition of done

Every variant renders in light and dark; the catalog/golden tests pass; no raw
values leak past the semantic layer; the change is versioned with notes and any
removed API is deprecated, not deleted; the lint gate is green.
