---
name: flutter-widget-composition-and-keys
description: Triggers when building widget trees — composing over inheriting, extracting widgets vs helper methods, lifting state, and choosing/placing Keys (ValueKey/ObjectKey/GlobalKey) to preserve or reset element state correctly.
---

# Flutter Widget Composition and Keys

Build trees that rebuild cheaply, reset state predictably, and stay readable. The two
recurring decisions: **how to factor a widget** and **whether/where a Key is needed**.

## Mental model: three trees

Flutter holds three parallel trees — **Widget** (immutable config you write), **Element**
(mutable, long-lived, holds `State`), and **RenderObject** (layout/paint). On rebuild,
Flutter walks the old Element tree and the new Widget tree side by side, position by position.
At each slot it asks: do `runtimeType` **and** `key` match the old widget?

- Match → reuse the Element and its `State`, update config in place.
- No match → throw away the old Element + State, build a fresh one.

Every composition and Key decision below is downstream of this one diffing rule.

## Compose, don't inherit

Build behavior by **nesting** widgets, not by subclassing them. There is almost never a
reason to `extends Container` or subclass a framework widget. Wrap instead.

```dart
// Avoid: subclassing to "add a feature".
// Prefer: wrap and pass children through.
class Card extends StatelessWidget {
  const Card({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(onTap: onTap, child: Padding(
        padding: const EdgeInsets.all(16), child: child,
      )),
    );
  }
}
```

Take a `Widget child` (or `List<Widget> children`) and let callers inject content. This is
how `Padding`, `Center`, and `InkWell` themselves work. See [[flutter-mvvm]] for how
composed widgets bind to view models.

## Extract a widget, not a helper method

A private `Widget _buildHeader()` method is the most common avoidable mistake. The method's
return value lives at its **call site's** position in the tree, with the parent's
`BuildContext` and `const`-ness — so it rebuilds whenever the parent rebuilds, and cannot be
`const`.

```dart
// Anti-pattern: helper method rebuilds with the whole page.
Widget _buildAvatar() => CircleAvatar(child: Text(initials));

// Prefer: a real widget. Its own Element; const-constructible; rebuilds independently.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});
  final String initials;
  @override
  Widget build(BuildContext context) => CircleAvatar(child: Text(initials));
}
```

Rule of thumb: if the subtree is non-trivial, has its own state, or is rebuilt under a
hot path, **make it a widget**. Reserve helper methods for tiny, throwaway fragments.

## Lift state to the lowest common owner

Put `State` at the **lowest** widget that is an ancestor of every reader and writer — no
higher. State lifted too high rebuilds half the screen; state buried too low can't be shared.

```dart
// Counter value is read by a label and a button — lift to their common parent only.
class _Stepper extends StatefulWidget {
  const _Stepper();
  @override State<_Stepper> createState() => _StepperState();
}
class _StepperState extends State<_Stepper> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$_count'),
    IconButton(onPressed: () => setState(() => _count++), icon: const Icon(Icons.add)),
  ]);
}
```

If unrelated siblings keep dragging state upward, that is a signal to reach for a
controller/notifier or your state-management layer — not to host everything in one giant
`State`. Shrink `setState` scopes by extracting the changing subtree into its own
`StatefulWidget`.

## Keys: the decision tree

**Default: no key.** You only need a Key when an Element's identity must survive a
reorder, or must be deliberately reset, in a list of **same-type siblings**.

The classic bug — swapping two stateful siblings keeps the wrong state:

```dart
// Two _ColorBox widgets hold their own random color in State.
// Without keys, reordering the list reuses Elements by POSITION,
// so the colors don't follow the items — they swap visually.
children: tiles.map((t) => _ColorBox(label: t.label)).toList();

// Fix: give each a stable identity so the diff matches by key, not position.
children: tiles.map((t) => _ColorBox(key: ValueKey(t.id), label: t.label)).toList();
```

Choosing the key type:

- **`ValueKey<T>(value)`** — when a simple, stable, equatable value identifies the item
  (an id, a slug). Most list keys are `ValueKey(model.id)`. Never key on the list index;
  index is just position and defeats the purpose.
- **`ObjectKey(model)`** — when identity is the object instance itself and it has no clean
  scalar id. Uses `identical`/`==` on the object.
- **`UniqueKey()`** — forces a **reset every build** (the key is never equal to itself next
  frame). Use to intentionally tear down and rebuild a subtree (e.g. restart an animation).
  Do not put it on list items — it destroys reuse and wrecreates state every frame.
- **`PageStorageKey`** — preserve scroll position of a list across navigation/tab switches.
- **`GlobalKey`** — see below; rarely the right answer.

Where to place the key: put it on the **topmost** widget of the subtree whose identity you
want to track — i.e. the element that moves. Keying a deep child while its parent stays
unkeyed does nothing for reordering.

## Deliberately resetting state with a key

Keys cut both ways. Change a key on purpose to **discard** old `State`:

```dart
// Reset a form (clear controllers, validation) when the edited entity changes.
Form(key: ValueKey(entity.id), child: _EntityFields(entity: entity));
```

When `entity.id` changes, the old `Form` Element is dropped and a fresh one is built —
controllers reinitialize, no stale text. Cheaper and clearer than manually resetting
every field in `didUpdateWidget`.

## GlobalKey: power tool, last resort

A `GlobalKey` gives the same Element a stable identity **across the whole tree** and exposes
its `State`/context imperatively (`_formKey.currentState!.validate()`). Legitimate uses:
form validation, reading a `RenderBox` size, moving a widget between parents without losing
state.

```dart
final _formKey = GlobalKey<FormState>();
// ...
if (_formKey.currentState!.validate()) submit();
```

Costs: a `GlobalKey` must be **unique across the entire app** at any moment, reparenting is
expensive, and reaching into another widget's `State` couples them tightly. Prefer passing
callbacks/values down and events up. If you only need `BuildContext`, a plain
`GlobalKey` for context access is usually a code smell — restructure instead.

## const and rebuild hygiene

- Mark constructors and instances `const` wherever inputs are compile-time constant. A
  `const` widget is canonicalized — Flutter skips rebuilding its subtree entirely.
- Don't allocate closures or new objects in `build` that could be hoisted to fields; each
  new instance can defeat `==`-based skip-rebuild optimizations downstream.
- Pass typed model objects into widgets, not loose maps, so the diff and equality are clear.

## Quick checklist

- [ ] Wrapping/nesting instead of subclassing framework widgets.
- [ ] Non-trivial subtrees are extracted **widgets**, not `_build...` methods.
- [ ] State lives at the lowest common owner; `setState` scope is tight.
- [ ] Same-type stateful siblings in a reorderable list carry a stable `ValueKey`/`ObjectKey`.
- [ ] No keying on list index; no stray `UniqueKey` in lists.
- [ ] Intentional resets use a changing key; not manual field-clearing.
- [ ] `GlobalKey` only for validation/measurement/reparenting — justified, not reflexive.
- [ ] `const` applied everywhere inputs allow.

See [[performance-optimization]] for measuring rebuild cost and [[test-driven-development]]
for widget tests that pin behavior before refactoring. Commit per [[commit-pipeline]].
