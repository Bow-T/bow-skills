---
name: flutter-accessibility
description: Triggers when making a Flutter UI usable by assistive tech — Semantics widgets, labels/hints/merging, focus and traversal order, dynamic text scaling, contrast, and testing with TalkBack/VoiceOver and the semantics debugger.
---

# Flutter Accessibility

Flutter paints to a single canvas, so screen readers see nothing unless you build a
**semantics tree** alongside your widget tree. The job: emit the right semantic nodes,
keep text resizable, ensure focus order makes sense, and verify with a real reader.

## Workflow

1. **Turn on the semantics overlay first.** Wrap a screen and look at what the tree exposes.
   ```dart
   import 'package:flutter/rendering.dart' show debugDumpSemanticsTree;

   // In a debug build, toggle the on-screen overlay:
   MaterialApp(showSemanticsDebugger: true, home: HomePage());
   // Or dump the tree to the console at any point:
   debugDumpSemanticsTree();
   ```
   Anything with no box in the overlay is invisible to TalkBack/VoiceOver. Decorative-only
   visuals should stay invisible; interactive or informative ones must not.

2. **Label what the framework can't infer.** `Text` and most Material widgets are labeled
   automatically. Icon buttons, custom-painted controls, and image-only buttons are not.
   ```dart
   IconButton(
     icon: const Icon(Icons.favorite_border),
     tooltip: 'Save to favorites', // tooltip doubles as the semantic label
     onPressed: _toggleFavorite,
   );

   // Pure decoration — hide it so the reader doesn't announce "image":
   ExcludeSemantics(child: Image.asset('assets/swoosh.png'));

   // Informative image — give it a label instead:
   Semantics(
     label: 'Bar chart: revenue up 12 percent this quarter',
     image: true,
     child: Image.asset('assets/chart.png'),
   );
   ```

3. **Use the right semantic *flags*, not just text.** A reader announces *role* + *state* +
   *label*. Set `button`, `header`, `selected`, `checked`, `toggled`, `enabled` so the user
   hears "Submit, button, dimmed" rather than a bare word.
   ```dart
   Semantics(
     header: true,
     child: Text('Account settings', style: textTheme.headlineSmall),
   );

   Semantics(
     button: true,
     enabled: !_loading,
     label: 'Submit order',
     onTap: _loading ? null : _submit,
     child: _CustomGradientButton(onTap: _loading ? null : _submit),
   );
   ```

4. **Merge fragments that read as one thing.** A row of avatar + name + status should be a
   single swipe stop, not three. `MergeSemantics` collapses descendants into one node.
   ```dart
   MergeSemantics(
     child: Row(children: [
       const CircleAvatar(child: Text('AB')),
       const SizedBox(width: 8),
       Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
         Text('Alex Brand'),
         Text('Online'),
       ]),
     ]),
   ); // announced as "Alex Brand, Online"
   ```
   Inversely, when one widget bundles things that should be separate stops, split with
   `Semantics(explicitChildNodes: true)` or `BlockSemantics`.

5. **Replace meaningless labels with `semanticsLabel`.** Currency, dates, and symbols read
   badly. Keep the visual glyph, override the spoken form.
   ```dart
   Text('\$1,299.00', semanticsLabel: '1299 dollars');
   Text('★ 4.8', semanticsLabel: 'Rated 4.8 out of 5');
   ```

6. **Announce dynamic changes the user can't see happen.** Loading spinners, toasts, and
   live validation need an explicit announcement or a `liveRegion`.
   ```dart
   import 'package:flutter/semantics.dart';

   SemanticsService.announce('Order placed', TextDirection.ltr);

   // Or mark a status node so the reader re-reads it when it changes:
   Semantics(liveRegion: true, child: Text(_statusMessage));
   ```

7. **Respect dynamic text scaling — never hardcode against it.** Read the user's scale via
   `MediaQuery.textScalerOf(context)`; let layouts reflow. Test up to ~2.0x.
   ```dart
   final scaler = MediaQuery.textScalerOf(context);
   final iconSize = scaler.scale(24); // grow icons alongside text

   // Clamp only where overflow is unavoidable, and prefer wrapping over truncating:
   MediaQuery.withClampedTextScaling(
     maxScaleFactor: 1.6,
     child: const _DenseStatusBar(),
   );
   ```
   Avoid fixed-height containers around text; use `minHeight` or let content size itself.

8. **Make targets big enough and contrast strong enough.** Minimum touch target is 48x48
   logical pixels — wrap small hit areas. Body text needs a 4.5:1 contrast ratio (3:1 for
   large text); the debug-build contrast guideline check flags failures.
   ```dart
   SizedBox(
     width: 48, height: 48,
     child: Center(child: GestureDetector(onTap: _close, child: const Icon(Icons.close, size: 20))),
   );
   // Material's IconButton already enforces a 48dp target; prefer it over raw GestureDetector.
   ```

9. **Fix focus and traversal order.** Default order is reading order (top-to-bottom,
   start-to-end). Override only when layout diverges from logical order.
   ```dart
   FocusTraversalGroup(
     policy: OrderedTraversalPolicy(),
     child: Column(children: [
       FocusTraversalOrder(order: const NumericFocusOrder(1), child: _emailField),
       FocusTraversalOrder(order: const NumericFocusOrder(2), child: _passwordField),
     ]),
   );

   // Move the reader to a node after a transition (e.g. open a dialog):
   final node = FocusNode();
   // ...attach to the heading, then:
   node.requestFocus();
   ```
   Sort visual reading order with `Semantics(sortKey: OrdinalSortKey(n))` when needed.

10. **Test on a real screen reader — the debugger is not enough.** Enable TalkBack
    (Android) or VoiceOver (iOS) and swipe through every interactive element. Confirm each
    has a clear label, correct role/state, and reachable focus. Then lock it in with widget
    tests using the semantics matchers.
    ```dart
    testWidgets('save button is an enabled, labeled button', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MyApp());
      expect(
        tester.getSemantics(find.byTooltip('Save to favorites')),
        matchesSemantics(label: 'Save to favorites', isButton: true, isEnabled: true, hasTapAction: true),
      );
      handle.dispose();
    });
    ```
    Add `await expectLater(tester, meetsGuideline(textContrastGuideline));` and
    `meetsGuideline(androidTapTargetGuideline)` to gate regressions in CI.

## Pitfalls

- **Tooltip vs label collision.** Setting both `tooltip` and a `Semantics(label:)` produces
  a doubled announcement. Pick one source of truth per node.
- **Over-merging.** `MergeSemantics` around a tappable list tile that contains its own button
  swallows the inner action. Keep distinct actions as distinct nodes.
- **Invisible focus traps.** Off-screen or `Offstage` content can still hold semantics; wrap
  hidden trees in `ExcludeSemantics` or remove them so focus doesn't land nowhere.
- **Color-only meaning.** Red/green status with no text or icon is invisible to low-vision
  and colorblind users — pair color with a label or shape.
- **`textScaleFactor` is deprecated** — use `TextScaler` / `textScalerOf`. Don't reintroduce
  the old API in new code.

## Related

- Building the UI itself: [[frontend-ui-engineering]] and the Flutter page pattern.
- General WCAG semantics across platforms: [[accessibility-engineering]].
- Locking behavior in with tests: [[test-driven-development]].
- Committing the change: [[commit-pipeline]].
