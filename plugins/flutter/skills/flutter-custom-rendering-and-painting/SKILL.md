---
name: flutter-custom-rendering-and-painting
description: Triggers when default widgets can't express the layout or visuals — writing CustomPainter, custom RenderObjects/RenderBox, custom multi-child layout, or hand-rolled slivers for advanced scroll effects.
---

# Flutter Custom Rendering and Painting

Reach for this when composition of `Stack`, `Flex`, `CustomScrollView`, and friends
genuinely cannot express what you need: a free-form chart, an interlocking layout
where children depend on each other's geometry, or a scroll effect the stock slivers
don't give you. Most of the time they *can* — exhaust composition first. Custom
rendering trades reusability and correctness guarantees for control, so spend it only
where it pays.

## Decision ladder — climb only as high as you must

1. **Compose existing widgets.** `Transform`, `ClipPath`, `Stack` + `Positioned`,
   `Flow`, `Wrap`. Cheapest, most correct.
2. **`CustomPaint`** — pure pixels with no hit-testing of sub-regions and no layout
   participation from the drawing itself. Charts, gauges, signatures, backgrounds.
3. **`CustomMultiChildLayout`** — you have real child widgets and want to position
   them relative to each other, but each child's size is independent.
4. **Custom `RenderBox`** (via `RenderObjectWidget`) — you need to *control children's
   constraints*, intrinsic sizes, baselines, or custom hit-testing. The heavyweight option.
5. **Custom `RenderSliver`** — only for scroll-axis effects that `SliverPersistentHeader`,
   `SliverLayoutBuilder`, and existing slivers can't produce.

## CustomPainter — the common case

```dart
class RingGaugePainter extends CustomPainter {
  RingGaugePainter({required this.progress, required this.color})
      : super(repaint: null); // pass a Listenable here to repaint without rebuild

  final double progress; // 0..1
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 8;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..color = color.withValues(alpha: 0.15);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  // Return true ONLY when something visible changed. Compare every field.
  @override
  bool shouldRepaint(RingGaugePainter old) =>
      old.progress != progress || old.color != color;
}
```

Rules that bite if ignored:

- **`shouldRepaint` must compare all fields.** Returning `true` always = repaint every
  frame; returning `false` wrongly = stale pixels. Both are common bugs.
- **Animate via `repaint:`, not `setState`.** Pass the `AnimationController` (a
  `Listenable`) to `super(repaint: controller)`. The painter repaints without rebuilding
  the widget tree above it — far cheaper.
- **Give `CustomPaint` a `size` or wrap it.** A bare `CustomPaint` with no child sizes
  to zero. Use `size:` or a `SizedBox`/`LayoutBuilder` parent.
- **Cache expensive objects.** Build `Path`, `TextPainter`, gradients, and `Picture`s
  once (in the constructor or memoized) — not inside `paint`, which runs per frame.
- **Override `hitTest`** if the painted shape should be tappable along its true outline:
  `bool hitTest(Offset position) => myPath.contains(position);`

For static, frequently-repainted art, render once into a `ui.Picture` via
`PictureRecorder` and `drawPicture` it, or rasterize to a `ui.Image` for true static layers.

## Text inside a painter

`canvas.drawParagraph` is low-level; prefer `TextPainter`:

```dart
final tp = TextPainter(
  text: TextSpan(text: label, style: style),
  textDirection: TextDirection.ltr,
)..layout(maxWidth: size.width);
tp.paint(canvas, Offset(x - tp.width / 2, y));
```

Build and `layout()` it once when the text is constant; re-layout only on change.

## CustomMultiChildLayout — children that know about each other

Use a `LayoutDelegate` keyed by child id. The delegate lays out and positions each
child but does not paint.

```dart
class _BadgeOnAvatarDelegate extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final avatar = layoutChild('avatar', BoxConstraints.loose(size));
    positionChild('avatar', Offset.zero);
    if (hasChild('badge')) {
      final badge = layoutChild('badge', BoxConstraints.loose(size));
      positionChild('badge',
          Offset(avatar.width - badge.width, avatar.height - badge.height));
    }
  }

  @override
  bool shouldRelayout(_BadgeOnAvatarDelegate old) => false;
}

// Children: LayoutId(id: 'avatar', child: ...), LayoutId(id: 'badge', child: ...)
```

`layoutChild` must be called exactly once per id, before `positionChild`. Forgetting
either throws in debug.

## Custom RenderBox — when you need control over child constraints

Wire it with a `LeafRenderObjectWidget` (no children) or
`SingleChildRenderObjectWidget`. Implement the geometry contract:

```dart
class RenderAspectClamp extends RenderBox with RenderObjectWithChildMixin<RenderBox> {
  RenderAspectClamp(this._ratio);
  double _ratio;
  set ratio(double v) {
    if (v == _ratio) return;
    _ratio = v;
    markNeedsLayout(); // invalidate; don't relayout inline
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : 300.0;
    final target = BoxConstraints.tightFor(width: width, height: width / _ratio);
    child?.layout(target, parentUsesSize: true);
    size = constraints.constrain(child?.size ?? Size(width, width / _ratio));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position) ?? false;
}
```

Discipline that keeps the pipeline honest:

- **`size` must obey `constraints`** — always end layout with `constraints.constrain(...)`
  or you get overflow/assert failures.
- **Pass `parentUsesSize: true`** when you read the child's size after `layout`, so the
  framework knows to relayout you when the child changes.
- **Mutate via setters that call `markNeedsLayout` / `markNeedsPaint`** — never relayout
  or repaint directly. Use `markNeedsPaint` for visual-only changes (cheaper than layout).
- **Implement intrinsics** (`computeMinIntrinsicWidth`, etc.) if your box lives inside
  `IntrinsicHeight`/`Row`-with-baseline; otherwise they throw.
- **Use a custom `ParentData`** (`setupParentData` + a `*ParentData` subclass) to stash
  per-child offsets for multi-child boxes, mirroring `ContainerRenderObjectMixin`.

## Custom slivers — last resort for scroll effects

A `RenderSliver` consumes a `SliverConstraints` (scrollOffset, remainingPaintExtent,
viewport geometry) and emits `SliverGeometry`. Before writing one, try
`SliverPersistentHeader` (pinned/floating headers), `SliverLayoutBuilder`, or
`SliverToBoxAdapter` wrapping a custom `RenderBox`. Only drop to `RenderSliver` for
parallax, sticky behaviors, or stretch effects the stock set can't produce — and get
`paintExtent`, `maxPaintExtent`, and `scrollExtent` exactly right or scrolling stutters.

## Performance and verification

- **`RepaintBoundary`** around an independently-animating painter so its repaints don't
  dirty siblings. Confirm with the repaint-rainbow overlay (`debugRepaintRainbowEnabled`).
- **Profile in profile/release**, never debug — Skia/Impeller behave differently and
  debug is misleadingly slow. Watch raster and UI thread times for 16ms (60Hz) budget.
- **Avoid `saveLayer`** unless you truly need group opacity/blending; it allocates an
  offscreen buffer per frame. Prefer per-`Paint` alpha.
- **Test geometry, not just pixels.** Pump the widget, then assert sizes/positions via
  `tester.getSize` / `tester.getTopLeft`; use golden tests for the painted output.

State your assumptions about target devices and frame budget before committing to the
custom path, and back framework-API choices with current docs per
[[source-driven-development]]. Lean on [[flutter-mvvm]] to keep the painter's inputs as
plain typed values driven from a view model, [[performance-optimization]] to confirm the
custom path actually wins, and [[test-driven-development]] for golden and geometry tests.
Commit through [[commit-pipeline]].
