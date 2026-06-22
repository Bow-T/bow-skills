---
name: accessibility-engineering
description: Triggers when building or remediating UI that must meet WCAG — keyboard navigation, ARIA semantics, focus management, color contrast, or screen-reader support.
---

# Accessibility Engineering

Accessibility is a behavior contract, not a checklist you bolt on at the end. Treat assistive technology (AT) as a first-class user agent that consumes your semantics, not your pixels. Bake it into the component, verify with a real screen reader, then guard it with tests.

## 0. Decide the target before you write code

- Pick the conformance bar explicitly: **WCAG 2.2 AA** is the sane default for most products. AAA only where contractually required.
- Identify the AT matrix you must support, e.g. screen readers (desktop + mobile), keyboard-only, switch control, OS zoom/large-text. Web and Flutter expose different semantic trees — know which you ship.
- Write the bar into the ticket's acceptance criteria. "Accessible" with no target is unbuildable and untestable.

## 1. Lead with semantics, not ARIA

The first rule of ARIA: don't use ARIA when a native element already carries the role.

```html
<!-- Red flag: a div pretending to be a button -->
<div class="btn" onclick="submit()">Save</div>

<!-- Correct: native semantics, free keyboard + focus + role -->
<button type="button" onClick={submit}>Save</button>
```

Decision point:
- Native element exists (button, a[href], input, select, details) → use it.
- No native equivalent (tabs, treeview, combobox) → adopt the matching ARIA pattern *fully*, including its keyboard model. A half-implemented `role="tablist"` is worse than a plain list.

In Flutter, semantics are explicit. Wrap custom gesture widgets so AT sees an action, not a blank box:

```dart
Semantics(
  button: true,
  label: 'Save changes',
  onTap: _save,
  child: GestureDetector(onTap: _save, child: const Icon(Icons.save)),
)
```

## 2. Name everything an AT will announce

Every interactive element needs an accessible name. Verify the *computed* name, not your intent.

- Visible text label → already named.
- Icon-only control → add a label: `aria-label`, `<VisuallyHidden>`, or Flutter `Semantics(label:)`.
- Form field → bind a real `<label for>`. Placeholders are not labels.
- Decorative image → remove it from the tree: `alt=""` / `ExcludeSemantics`.

Red flags: "button", "link", "image", or a filename being read aloud — that is a missing name.

## 3. Keyboard first, mouse second

Every interaction must be reachable and operable without a pointer.

- Tab order follows DOM/widget order. Never use positive `tabindex`; reorder source instead.
- Use `tabindex="0"` to make custom widgets focusable, `-1` for programmatic-only focus.
- Implement the expected keys per pattern: arrows move within a composite (menu, listbox, radiogroup); Tab moves between widgets; Esc closes; Enter/Space activate.
- Never trap focus except inside an intentional modal (see §4).

TypeScript roving-tabindex skeleton for a toolbar:

```ts
function onKeyDown(e: KeyboardEvent, items: HTMLElement[], i: number) {
  const delta = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
  if (!delta) return;
  e.preventDefault();
  const next = (i + delta + items.length) % items.length;
  items[i].tabIndex = -1;
  items[next].tabIndex = 0;
  items[next].focus();
}
```

## 4. Manage focus deliberately

Focus is state. Move it when the UI changes, and never let it vanish.

- **Opening a dialog**: save the trigger element, move focus into the dialog, trap Tab inside it, restore focus to the trigger on close.
- **Route changes** (SPA): move focus to the new page's `<h1>` or a focusable landmark; do not let it sit on the dead old node.
- **Destroying the focused element**: move focus to a logical neighbor before removal, or the page jumps to `<body>`.

```ts
function openDialog(dialog: HTMLElement) {
  const opener = document.activeElement as HTMLElement;
  const first = dialog.querySelector<HTMLElement>('[autofocus], button, [href], input');
  first?.focus();
  return () => opener?.focus(); // call on close
}
```

Red flag: a visible focus ring you "cleaned up" with `outline: none` and no replacement. Always provide a `:focus-visible` style.

## 5. Announce dynamic changes

AT does not re-read the screen when content updates. Tell it.

- Async results, toasts, validation: render into a live region (`aria-live="polite"` for non-urgent, `assertive` for errors).
- The live region must exist in the DOM *before* you write into it — injecting the region and the message together is silent.
- In Flutter, use `SemanticsService.announce(message, direction)` for transient updates.

```ts
liveRegion.textContent = ''; // reset so identical repeats re-announce
requestAnimationFrame(() => { liveRegion.textContent = `${count} results`; });
```

For Supabase realtime feeds, debounce announcements — piping every row event into `assertive` will spam the user into uninstalling. Batch and announce a summary.

## 6. Color and contrast

- Text contrast ≥ 4.5:1 (normal) / 3:1 (large). UI components and focus indicators ≥ 3:1.
- Never encode meaning in color alone — pair status colors with an icon, text, or shape.
- Respect `prefers-reduced-motion`; gate non-essential animation behind it. In Flutter, check `MediaQuery.of(context).disableAnimations`.
- Support OS text scaling. In Flutter never hardcode around `textScaler`; design layouts that reflow.

## 7. Verify like a user, then automate

Order matters: tools catch ~30-40% of issues; the rest needs human verification.

1. **Keyboard pass**: unplug the mouse, complete every flow. If you can't, neither can the user.
2. **Screen-reader pass**: drive the actual platform AT through one core journey. Listen for correct name, role, state, and announced changes.
3. **Automated gate**: run axe-core (web) / `meetsGuideline` semantics tests (Flutter) in CI to catch regressions.

```dart
// Flutter widget test guarding contrast + tap-target size
testWidgets('save button is accessible', (tester) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(const MyApp());
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  handle.dispose();
});
```

Red flag: green automated suite treated as proof of accessibility. It only proves the absence of machine-detectable failures.

## 8. Remediating an audit

- Triage by impact × reach: blockers (can't complete a task with AT) first, then serious, then minor.
- Fix the component, not the instance — one shared button bug usually maps to dozens of audit findings.
- Reproduce each finding with the named AT before and after; attach the before/after to the issue so it doesn't silently regress.
- Land fixes in small reviewable commits. Follow [[commit-pipeline]] for message format.

## Definition of done

- [ ] Conformance target stated and met for the changed surface.
- [ ] Full keyboard operability, visible focus, no traps outside modals.
- [ ] Every interactive element has a correct computed name, role, and state.
- [ ] Dynamic changes announced; live regions present pre-update.
- [ ] Contrast and reduced-motion verified.
- [ ] One real screen-reader pass completed; automated check wired into CI.

See also: [[design-system-and-component-library]] for building the reusable accessible primitives, and [[design-system-and-component-library]] for contrast-safe color tokens.
