# Accessibility Reference

A scannable checklist for shipping accessible UI. Targets WCAG 2.1 AA. Pair this with the `frontend-ui-engineering` skill. Covers both web (TypeScript/HTML) and Flutter.

## Contents

- [Verify before merge](#verify-before-merge)
- [Operable by keyboard](#operable-by-keyboard)
- [Perceivable by assistive tech](#perceivable-by-assistive-tech)
- [Readable and visible](#readable-and-visible)
- [Forms done right](#forms-done-right)
- [Web semantics cheat sheet](#web-semantics-cheat-sheet)
- [Flutter semantics cheat sheet](#flutter-semantics-cheat-sheet)
- [Announcing dynamic changes](#announcing-dynamic-changes)
- [Mistakes that break a11y](#mistakes-that-break-a11y)

## Verify before merge

Run these before considering a UI change done:

- [ ] Tabbed through the whole flow with no mouse — everything reachable and operable
- [ ] Ran an automated audit (axe / Lighthouse, or Flutter's accessibility guideline tests)
- [ ] Listened to one full task with a screen reader (VoiceOver / TalkBack / NVDA)
- [ ] Confirmed contrast against the design tokens, not by eyeballing

## Operable by keyboard

- [ ] Every control reachable with Tab; the tab order matches reading order
- [ ] The focused element is always visually obvious (never `outline: none` with no replacement)
- [ ] Custom widgets respond to the expected keys (Space/Enter to trigger, Esc to dismiss, arrows for composite widgets)
- [ ] Nothing traps focus — Tab and Shift+Tab always move on
- [ ] A "jump to main content" affordance exists and appears on focus
- [ ] Opening a dialog moves focus inside it; closing it restores focus to the trigger

## Perceivable by assistive tech

- [ ] Informative images carry meaningful `alt`; purely decorative images use `alt=""` (web) or are excluded from the semantics tree (Flutter)
- [ ] Controls expose an accessible name — descriptive button text, or a label on icon-only controls
- [ ] Link/button text makes sense out of context (avoid "here" / "read more" with no target)
- [ ] Exactly one top-level heading; heading levels descend without gaps
- [ ] Data tables use header cells with a defined scope
- [ ] Live updates are announced (see [Announcing dynamic changes](#announcing-dynamic-changes))

## Readable and visible

| Requirement | Threshold |
|---|---|
| Body text contrast | at least 4.5:1 |
| Large text (about 18px+ or 14px bold) | at least 3:1 |
| Icons, borders, focus rings, controls | at least 3:1 vs adjacent color |
| Touch target size | at least 44x44 logical px |

- [ ] Meaning is never carried by color alone — pair it with text, icon, shape, or position
- [ ] Layout survives a 200% zoom / text scale without clipping or overlap
- [ ] No content flashes faster than three times per second
- [ ] Empty and error states render real content, not a blank region

## Forms done right

- [ ] Each field has a persistent, visible label (placeholder text is not a label)
- [ ] Required fields are marked with more than a red asterisk (include text or `required`)
- [ ] Error text is specific, sits next to its field, and is programmatically tied to it
- [ ] Errors are conveyed by icon/text/border, not color alone
- [ ] On submit failure, focus moves to a summary or the first invalid field
- [ ] Inputs use correct `type` and `autocomplete` (e.g. `type="email" autocomplete="email"`)

## Web semantics cheat sheet

Use native elements first; reach for ARIA only when no native element fits.

```html
<!-- Actions are buttons; navigation is links -->
<button type="button">Archive</button>
<a href="/orders/42">Open order 42</a>

<!-- Anti-pattern: clickable div is invisible to keyboard + AT -->
<div onclick="archive()">Archive</div>

<!-- Label tied to input by id -->
<label for="org">Organization</label>
<input id="org" name="org" autocomplete="organization" />

<!-- Icon-only control needs a name -->
<button aria-label="Filter results"><svg ...></svg></button>

<!-- Distinct landmarks -->
<nav aria-label="Primary">…</nav>
<nav aria-label="Breadcrumb">…</nav>

<!-- Native dialog handles focus + Esc -->
<dialog aria-labelledby="confirm-h">
  <h2 id="confirm-h">Remove member?</h2>
</dialog>
```

## Flutter semantics cheat sheet

Flutter exposes a semantics tree to TalkBack / VoiceOver. Most Material widgets are labelled already; wrap custom widgets in `Semantics`.

```dart
// Name an icon-only action
IconButton(
  icon: const Icon(Icons.filter_list),
  tooltip: 'Filter results',        // also surfaces to screen readers
  onPressed: _openFilters,
);

// Decorative widget: hide it from the tree
ExcludeSemantics(child: backgroundIllustration);

// Custom tappable region needs an explicit role + label
Semantics(
  label: 'Mark order complete',
  button: true,
  child: GestureDetector(onTap: _complete, child: customChip),
);

// Group label + value so they are read together
MergeSemantics(
  child: Row(children: [const Text('Status'), Text(order.status)]),
);
```

- [ ] Custom gesture handlers are wrapped so they report a role and label
- [ ] `Image` widgets that convey meaning set `semanticLabel`
- [ ] Tap targets meet the 48dp minimum (the framework warns when they don't)

## Announcing dynamic changes

| Mechanism | When it speaks | Use it for |
|---|---|---|
| `aria-live="polite"` / `role="status"` (web) | after the user pauses | save confirmations, count updates |
| `aria-live="assertive"` / `role="alert"` (web) | immediately, interrupts | validation errors, time-critical warnings |
| `SemanticsService.announce(text, dir)` (Flutter) | immediately | toast-style notifications, async results |

Keep the live region in the DOM/tree from first render — injecting it at the same moment you change its text often skips the announcement.

## Mistakes that break a11y

| Mistake | Why it hurts | Do this instead |
|---|---|---|
| Stripping focus outlines | Keyboard users lose their place | Restyle the ring, don't delete it |
| `tabindex` greater than 0 | Scrambles natural order | Use only `0` or `-1` |
| Placeholder as the only label | Vanishes on input, low contrast | Keep a real visible label |
| Re-implementing `<select>` with no ARIA | Unusable by keyboard and AT | Use native control or a proper listbox pattern |
| Autoplaying audio/video | Disorienting, drowns out AT | Default to paused with controls |
| Color-coded status with no text | Invisible to color-blind users | Add a label or icon |
| Skipped heading levels | Confuses document navigation | Keep the outline contiguous |
| Unlabeled icon buttons | Announced as just "button" | Add `aria-label` / `tooltip` |
