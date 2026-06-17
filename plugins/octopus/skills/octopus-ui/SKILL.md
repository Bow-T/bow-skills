---
name: octopus-ui
description: Build or edit Flutter UI and pages in apps/mobile using the DUOCT Flutter MVVM architecture — the BaseViewModel + MixinBasePage page+view-model pattern (ChangeState state machine, lifecycle hooks, optimistic updates), reusing existing components, the app theme/spacing/localization, and typed models (never raw maps) in widgets. Use whenever creating or changing a screen, page, view-model (vm), widget, dialog, or any UI/MVVM code under apps/mobile/lib/src/pages or components.
---

# Octopus UI — build screens the project way

Goal: every new screen looks and behaves like the existing ones, reuses what's
already there, and stays type-safe. **Reuse before you build. Match the base
source before you invent.**

## 1. Reuse first — search the component library
Before writing any widget, check `apps/mobile/lib/src/components/` — there is
almost always something to reuse. Catalog:
- **button/** `AppBounceButton`, `AppCircleButton`, `AppGradientButton`, `AppMonoButton`, `AppOutlinedButton`
- **input/** `AppTextField`, `AppPasswordField`, `AppSearchField`  ·  **checkbox/ radio/ switch/** `AppCheckbox`, `AppRadio`, `AppSwitch`
- **dialog/ modal/ popup/ snack_bar/** `AppDialog`, `ModalConfirm`, `AppModal`, `AppPopupMenu`, `AppSnackBar`, `showTopSnackBar`
- **widget/** `AppBarWidget`, `AppRefreshIndicator`, `TabCard`, `AppChoiceChip`, `CachedImage`, `CachedImageCircle`, `ItemNoFound`, `PagedBuilder`, `ServerError`, `PageError`, `AppLoading`, `AppCircularProgress`, `AppRatingBar`, `StatColumn`, `AppCalendar`, `AppReadMore`, `LuxuryCourierBadge`, …
Search first: `grep -ri "class App" apps/mobile/lib/src/components`. If a near-match exists, extend/parameterise it instead of cloning. Only add a new component when nothing fits — and put shared ones in `components/`, screen-local ones in a `widgets/` folder next to the page (e.g. `…/provider_bookings/widgets/provider_booking_card.dart`).

## 2. Page + ViewModel pattern — the MVVM core (always)
A screen = a `StatelessWidget with MixinBasePage<XxxVm>` (the **View**) + an
`XxxVm extends BaseViewModel` (the **ViewModel**, a `ChangeNotifier`). The View is
dumb: it only reads `provider.*` and calls VM methods. All data + actions live in
the VM; mutate there then `notifyListeners()`.
```dart
@RoutePage()
class FooPage extends StatelessWidget with MixinBasePage<FooVm> {
  FooPage({super.key, this.id = 0});
  final int id;
  @override
  FooVm create() => FooVm(id: id);            // construct VM, pass route params
  @override
  void initialise(BuildContext context) {}    // optional: runs once before build
  @override
  Widget build(BuildContext context) => builder(() => Scaffold(
        appBar: AppBarWidget(title: S.of(context).fooTitle),
        body: ListView.builder(
          itemCount: provider.items.length,    // reactive read
          itemBuilder: (_, i) => FooTile(item: provider.items[i]),
        ),
      ));
}
```
- **`builder(() => …)` wraps the whole tree** — it provides the VM via
  `ChangeNotifierProvider`, renders the loading/error overlays driven by VM state,
  wires snackbars, and fires the appear/disappear hooks.

### 2a. ViewModel lifecycle + state (exact BaseViewModel API)
Override these hooks in the VM. **Override the `on…` variants, NOT `appear()/disAppear()`** — those are the framework's internal callers:
- `void onInit()` — once after the provider is created (load initial data).
- `void onAppear()` / `void onDisAppear()` — page became visible / hidden.
- `void dispose()` — free controllers, then `super.dispose()`.

Drive the screen with the state machine, not ad-hoc booleans:
```dart
// enum ChangeState { loading, blank, page, serverError, clone }
changeState(ChangeState.loading);   // base swaps the matching overlay for you
```
Base helpers (already there — don't reinvent): `isLoading`, `showLoading()/hideLoading()`,
`showSuccess/showError/showInfo/showWarning(msg)`, and `runGuarded(() => …)` which
try/catches, routes errors to `showError`, and returns `null` on failure. Query
singletons are on the base via the locator (`driverQueries`, `rideQueries`,
`voucherQueries`, `orderQueries`, `prefs`, `supa`, …).
```dart
class FooVm extends BaseViewModel {
  FooVm({required this.id});
  final int id;
  List<FooModel> items = [];               // typed models, never Map

  @override
  void onInit() => _load();

  Future<void> _load() async {
    changeState(ChangeState.loading);
    final rows = await runGuarded(() => fooQueries.list(id));  // null on error
    if (rows == null) return changeState(ChangeState.serverError);
    items = rows;
    changeState(ChangeState.page);
    notifyListeners();
  }
}
```

### 2b. Optimistic updates (the project idiom for mutations)
Snapshot → update UI now → call server → revert on failure:
```dart
Future<void> increment(FooItem it) async {
  final snapshot = items;
  items = [for (final r in items) r.id == it.id ? r.copyWith(qty: r.qty + 1) : r];
  notifyListeners();
  try {
    await fooQueries.setQty(it.id, it.qty + 1);
  } catch (e) {
    items = snapshot;                       // revert
    notifyListeners();
    SupabaseError.handle(e, showError);
  }
}
```

### 2c. Folder layout + routing
- One page = its own folder: `foo/foo_page.dart` + `foo/foo_vm.dart`. Screen-local
  widgets in `foo/widgets/*.dart`; private helpers in `foo/_helpers.dart`.
- Nested / multi-step flows nest under `foo/pages/<step>/…` (see
  `…/express_delivery/pages/{delivery_destination,delivery_detail,delivery_offers}`).
- New route → `@RoutePage()` on the page class, then codegen
  (`fvm flutter pub run build_runner build`) so `app_router.gr.dart` picks it up.
  Navigate `context.router.push(FooRoute(id: 1))`; pop a result `context.maybePop(value)`.

## 3. Theme, spacing, text — no raw values
- **Colors:** `AppColor.*` (e.g. `AppColor.primaryText`, `AppColor.background`). Never hardcode `Color(0x…)` / `Colors.*`.
- **Text:** `context.appStyle.<token>` (e.g. `context.appStyle.display14Bold`). Never inline a bespoke `TextStyle` when a token exists.
- **Spacing:** the int/num extensions — `12.sizedHeight`, `10.sizedWidth`, paddings via `EdgeInsets` constants. Prefer `N.sizedHeight/sizedWidth` over ad-hoc `SizedBox`.
- **Icons/images:** assets through `AppAsset.icons.*`; remote images through `CachedImage` / `CachedImageCircle` (never a bare `Image.network`).

## 4. Localization — every user-facing string
All copy goes through generated l10n: `S.of(context).key` (or `S.current.key`
off-context). No hardcoded display strings. To add one:
1. Add the key to **both** `apps/mobile/lib/src/l10n/intl_en.arb` and `intl_fr.arb`.
2. Regenerate: `cd apps/mobile && fvm flutter gen-l10n` (arb_dir `lib/src/l10n` → `lib/src/generated`).
3. Use `S.of(context).<key>`.

## 5. Data binding — typed models only
Widgets read **typed model fields**, never `map['key']`. The query layer returns
models (RideModel, OrderModel, CourierOrderModel, DriverWalletModel, …); the VM
holds typed fields/lists; the page binds `provider.someModel.field`. If you find
yourself indexing a `Map<String,dynamic>` in a widget, the model/query is missing
a field — fix it there (see the `supabase-security-review` / model conventions),
don't dig the map in the UI.

## 6. Lists, empty & error states
- Pull-to-refresh: wrap in `AppRefreshIndicator(onRefresh: provider.refresh, …)`.
- Pagination: `PagedBuilder` / `PagedSliverList` with `infinite_scroll_pagination` (see trips/earnings pages).
- Empty: `ItemNoFound`. Error: `ServerError` / `PageError`. Loading: `AppLoading` / `AppCircularProgress`.

## 7. Before you finish
- `cd apps/mobile && fvm flutter analyze` → zero errors AND warnings.
- Re-check: no hardcoded color/text/string, no map-indexing in widgets, reused existing components where possible, page follows the MixinBasePage pattern.
- Then hand off to the `octopus-commit` skill to commit/push.
