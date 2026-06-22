---
name: flutter-animations
description: Triggers when adding motion in Flutter — choosing implicit vs explicit animations, driving AnimationController/Tween/Curves, Hero/shared-element and page transitions, staggered sequences, and disposing controllers correctly.
---

# Flutter Animations

Motion is communication, not decoration. Animate to show cause-and-effect, spatial
continuity, and state change — never to make a still UI "feel premium". Default to the
cheapest tool that does the job, and never leak a controller.

## Decision: which tool

Walk down this list and stop at the first match.

1. **One property, fire-and-forget on state change** (size, color, opacity, padding,
   alignment) → an **implicit** `AnimatedFoo` widget. No controller, no `dispose`.
2. **Many widgets reacting to the same value change** → wrap them in a single
   `TweenAnimationBuilder` or `AnimatedContainer`-family — still implicit.
3. **You need to drive, reverse, repeat, pause, chain, or read progress** → **explicit**:
   an `AnimationController` plus `Tween`/`CurvedAnimation`.
4. **Same element moves between two routes** → `Hero`.
5. **Whole-screen entrance/exit** → a `PageRouteBuilder` transition or
   `AnimatedSwitcher` for in-place swaps.

If you reach for an `AnimationController` for a single hover/press fade, you over-built it.

## Implicit: the 80% case

```dart
// Rebuilds animate automatically — change the value, Flutter tweens to it.
AnimatedContainer(
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeOutCubic,
  width: _expanded ? 240 : 120,
  color: _expanded ? Colors.indigo : Colors.grey,
);

AnimatedOpacity(
  opacity: _visible ? 1 : 0,
  duration: const Duration(milliseconds: 200),
  child: const Badge(),
);
```

For a one-off tween of an arbitrary value with no controller, use `TweenAnimationBuilder`.
It animates from the *previous* `end` to the new `end` each time the target changes:

```dart
TweenAnimationBuilder<double>(
  tween: Tween(begin: 0, end: _rating),     // re-runs when _rating changes
  duration: const Duration(milliseconds: 400),
  curve: Curves.elasticOut,
  builder: (context, value, child) =>
      Transform.scale(scale: value, child: child),
  child: const Icon(Icons.star),            // built once, not per frame
);
```

Pass the static subtree via `child:` so it is not rebuilt 60 times a second.

## Explicit: controller + tween

Reach here when you own the timeline. The lifecycle is fixed: create in `initState`,
dispose in `dispose`, mix in a ticker provider.

```dart
class Pulse extends StatefulWidget {
  const Pulse({super.key});
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween(begin: 1.0, end: 1.15).animate(
    CurvedAnimation(parent: _c, curve: Curves.easeInOut),
  );

  @override
  void dispose() {
    _c.dispose();          // ALWAYS — a live ticker leaks and burns battery.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
        scale: _scale,
        child: const Icon(Icons.favorite, color: Colors.red),
      );
}
```

Rules that prevent the common bugs:

- **One ticker** → `SingleTickerProviderStateMixin`; **several controllers** →
  `TickerProviderStateMixin`. Using the multi-mixin for a single controller is harmless
  but using the single mixin for two controllers throws.
- Prefer the typed `*Transition` widgets (`FadeTransition`, `SlideTransition`,
  `RotationTransition`, `SizeTransition`) over `AnimatedBuilder` — they rebuild only the
  render object, not the widget. Use `AnimatedBuilder`/`ListenableBuilder` only for custom
  combinations, and keep the unchanging subtree in its `child:`.
- Never call `setState` from a controller listener to repaint — that rebuilds the whole
  subtree every frame. Let the `*Transition` widget listen instead.
- Drive with `forward()` / `reverse()` / `repeat()` / `animateTo()`; read state via
  `_c.status` and `_c.isAnimating`. Await `forward()` when you need to act on completion,
  but guard with `if (!mounted) return;` after the await.

## Curves and Tweens

`Curve` shapes time; `Tween` maps `0..1` to values. Use `Interval` to slice one
controller into phases. `TweenSequence` chains value segments on a single controller.

```dart
final Animation<Offset> _slide = Tween(
  begin: const Offset(0, 0.2), end: Offset.zero,
).animate(CurvedAnimation(
  parent: _c,
  curve: const Interval(0.0, 0.6, curve: Curves.easeOut),   // first 60% of the timeline
));
```

## Staggered sequences

Drive multiple children from ONE controller with overlapping `Interval`s — never spin up
a controller per item. This keeps everything frame-locked and disposes as a unit.

```dart
List<Widget> _items(AnimationController c, List<Widget> children) {
  final step = 1.0 / (children.length + 1);
  return [
    for (var i = 0; i < children.length; i++)
      FadeTransition(
        opacity: CurvedAnimation(
          parent: c,
          curve: Interval(i * step, (i + 2) * step, curve: Curves.easeOut),
        ),
        child: children[i],
      ),
  ];
}
```

## Hero and page transitions

Shared-element: same `tag` on both routes, and the tag must be unique per screen.

```dart
Hero(tag: 'product-$id', child: Image.network(url));   // list AND detail page
```

Custom route entrance — compose a transition in `PageRouteBuilder`:

```dart
Navigator.of(context).push(PageRouteBuilder(
  transitionDuration: const Duration(milliseconds: 300),
  pageBuilder: (_, __, ___) => const DetailPage(),
  transitionsBuilder: (_, animation, __, child) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(begin: const Offset(0, 0.05), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: child,
    ),
  ),
));
```

For in-place content swaps use `AnimatedSwitcher`, and give each child a distinct `key`
or the switcher cannot tell they differ:

```dart
AnimatedSwitcher(
  duration: const Duration(milliseconds: 200),
  child: _loading
      ? const CircularProgressIndicator(key: ValueKey('spin'))
      : Text(data, key: const ValueKey('data')),
);
```

## Performance and accessibility

- Animate `Transform`, `Opacity`, and color — they stay on the compositor and avoid
  layout. Animating `width`/`height`/`padding` triggers relayout each frame; acceptable
  for small widgets, costly inside long lists.
- Profile in **profile mode**, not debug, and watch the raster + UI threads. See
  [[performance-optimization]] for finding jank.
- Respect `MediaQuery.of(context).disableAnimations` (set by OS "reduce motion") — drop to
  instant or a simple fade. See [[accessibility-engineering]].
- Use `RepaintBoundary` around a continuously animating widget to stop it dirtying its
  neighbours.

## Before you commit

- Every `AnimationController` has a matching `dispose`.
- No `setState`-per-frame; `*Transition` widgets or `AnimatedBuilder.child` carry the load.
- Curves and durations are consistent across the app (centralize them as constants).
- `mounted` is checked after any awaited animation.

Commit via [[commit-pipeline]].
