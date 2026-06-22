---
name: flutter-performance-and-rebuild-optimization
description: Triggers when the UI janks or rebuilds excessively — minimizing rebuild scope, using const/RepaintBoundary, profiling with the DevTools timeline, fixing dropped frames, shader jank, or expensive build methods.
---

# Flutter Performance and Rebuild Optimization

Make the frame budget. At 60 Hz you have ~16 ms per frame (8 ms on 120 Hz devices)
split between the UI thread (build + layout + paint) and the raster thread (GPU).
Optimize on evidence, not vibes: profile first, fix the proven bottleneck, re-measure.

## Measure before touching anything

Run in **profile mode** — `flutter run --profile`. Debug mode is 2-10x slower and
its numbers lie; release mode strips the tooling you need.

- Open DevTools → **Performance** tab. Record an interaction that janks.
- Red bars in the frame chart = over-budget frames. Click one to see the flame chart.
- A tall **UI track** = expensive `build`/layout/paint on the Dart side.
- A tall **Raster track** = the GPU is the bottleneck (overdraw, big saveLayers, shaders).
- Turn on **Track Widget Builds** to see which widgets rebuild and how often.
- Use the **CPU Profiler** to find the hot Dart function inside a fat UI frame.

State the hypothesis before fixing: "ListView rebuilds every item on scroll because
the whole page rebuilds on each animation tick." Then prove it with the timeline.

## Shrink the rebuild blast radius

The cardinal sin: a `setState` or provider change at the top of the tree rebuilds a
huge subtree. Push state down or lift the static parts out.

```dart
// BAD: animation rebuilds the entire subtree, including the static heavy child.
class _Bad extends State<Spinner> {
  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: _controller.value * 2 * pi,
      child: const ExpensiveChild(), // rebuilt for nothing every tick
    );
  }
}

// GOOD: AnimatedBuilder rebuilds only the Transform; child is captured once.
AnimatedBuilder(
  animation: _controller,
  child: const ExpensiveChild(), // built once, passed through
  builder: (context, child) => Transform.rotate(
    angle: _controller.value * 2 * pi,
    child: child,
  ),
);
```

The `child` parameter pattern works for `AnimatedBuilder`, `ValueListenableBuilder`,
`StreamBuilder`, and consumer widgets: anything inside `builder` rebuilds; anything
passed as `child` does not.

## Make widgets `const` and split them out

A `const` widget is canonicalized — Flutter skips rebuilding and re-element-ing it
entirely. Enable the lint and let the analyzer find them:

```yaml
# analysis_options.yaml
linter:
  rules:
    - prefer_const_constructors
    - prefer_const_constructors_in_immutables
    - prefer_const_literals_to_create_immutables
```

Extracting a subtree into its own `StatelessWidget` (not a helper method) lets Flutter
short-circuit it when its inputs are unchanged. A `Widget _buildHeader()` method always
re-runs with the parent; a `const Header()` class does not.

```dart
// Helper method: re-runs on every parent build.
Widget _buildHeader() => Padding(padding: ..., child: Text(title));

// Widget class: can be const, skipped when parent rebuilds with same args.
class Header extends StatelessWidget {
  const Header({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(padding: ..., child: Text(title));
}
```

## Isolate repaints with `RepaintBoundary`

When a small region animates (a progress bar, a cursor, a like button), wrap it so its
repaints don't dirty the whole layer. Each boundary gets its own GPU layer.

```dart
RepaintBoundary(
  child: CircularProgressIndicator(value: progress),
)
```

Use the DevTools **Highlight Repaints** toggle: flashing borders show what repaints.
If a static area flashes alongside an animation, add a boundary. Don't carpet-bomb
boundaries — each one costs a layer and memory; place them only where repaint churn
is proven.

## Lists: lazy, keyed, and cheap per-item

- Use `ListView.builder` / `SliverList`, never `ListView(children: [...])` for long
  or unbounded lists — the latter builds every child up front.
- Give list items stable `ValueKey`s so reorders/inserts don't rebuild everything.
- Keep `itemBuilder` cheap: no sorting, no `DateFormat` parsing, no decoding per build.
  Precompute in the model or a memoized field.
- For fixed-height rows, set `itemExtent` (or `prototypeItem`) so the framework skips
  per-child layout measurement.
- `addAutomaticKeepAlives: false` and `addRepaintBoundaries` defaults are usually fine;
  override only with measurement.

## Keep `build` pure and cheap

`build` can run many times per second. It must do no I/O, allocate little, and never
trigger side effects. Common offenders to hoist out of `build`:

- `MediaQuery.of(context)` reads that rebuild on every keyboard/rotation change — read
  only the slice you need (`MediaQuery.sizeOf(context)` in Flutter 3.10+) to avoid
  over-subscribing.
- Recreating controllers, `Paint`, gradients, or regexes each build — make them
  `final` fields or `static const`.
- Heavy sync work (JSON parse, image decode, sorting 10k items): move to an `Isolate`
  via `compute()` or `Isolate.run()` so the UI thread keeps hitting frames.

```dart
final parsed = await Isolate.run(() => parseHugePayload(raw));
```

## Raster-thread and shader jank

If the **Raster** track is the tall one, the GPU is struggling:

- **Overdraw / opacity**: prefer `Opacity` only on leaf widgets; for fades use
  `FadeTransition`/`AnimatedOpacity`. Avoid `Opacity` wrapping large subtrees — it
  forces an offscreen `saveLayer`. Same for `ClipRRect` over big animated content.
- **Shader compilation jank** (a stutter the *first* time an effect appears) is largely
  resolved by Impeller, the default engine on iOS and Android in current Flutter. Verify
  Impeller is on; if you must stay on the legacy engine, precompile with an SkSL bundle:
  capture during `flutter run --profile --cache-sksl --purge-persistent-cache`, then
  ship via `flutter build --bundle-sksl-path`.
- Avoid `BackdropFilter`/blur over large or frequently-changing areas — it's expensive
  per frame.

## Verify the fix

Re-record the same interaction in the Performance tab. Confirm: fewer/no red frames,
shorter UI or Raster bars, and lower build counts in **Track Widget Builds**. A fix you
can't see in the timeline isn't a fix — revert speculative changes that didn't move the
numbers. When committing, follow [[commit-pipeline]].

## Related

- [[performance-optimization]] — language-agnostic measure-fix-remeasure discipline.
- [[flutter-mvvm]] — structuring view-models so state changes don't over-notify.
- [[load-and-stress-testing]] — proving capacity assumptions with measurement.
