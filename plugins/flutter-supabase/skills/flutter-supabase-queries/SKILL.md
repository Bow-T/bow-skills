---
name: flutter-supabase-queries
description: Build the Supabase data-access layer the project way — query/repository singletons resolved via the locator, runGuarded error handling, typed models in and out (never raw maps), and optimistic mutations that revert on failure. Use when adding a query, repository method, RPC call, or wiring a view-model to Supabase data in apps/mobile.
---

# Supabase Queries — the data-access layer

Goal: every screen reads and writes Supabase through the same typed, guarded query layer the
existing repositories use — never raw `supa` calls from a widget, never `Map` indexing in a VM.

> Paths/names below (`apps/mobile`, `package:app/`, the query singletons) follow the project
> defaults; read real values from `.conventions.json`. Pairs with [[flutter-mvvm]] and [[flutter-data-model]].

## 1. Where data access lives
- Queries are **singletons** grouped by domain (`driverQueries`, `rideQueries`, `orderQueries`,
  `voucherQueries`, …), resolved from the service locator and exposed on `BaseViewModel`.
- **View-models call queries; widgets never do.** A widget reading `supa` directly is a bug.
- A query method takes/returns **typed models** ([[flutter-data-model]]), never `Map<String, dynamic>`.

```dart
class RideQueries {
  final SupabaseClient _db;
  RideQueries(this._db);

  Future<List<RideModel>> listForDriver(int driverId, {int from = 0, int to = 19}) async {
    final rows = await _db
        .from('rides')
        .select('id, status, price, startedAt, driver:drivers(id, name)')
        .eq('driverId', driverId)
        .order('startedAt', ascending: false)
        .range(from, to);                       // bounded — feeds PagedBuilder
    return rows.map(RideModel.fromJson).toList();
  }
}
```

## 2. Reads
- **Select explicit columns**, not `*`; pull nested relations with the `foreign:table(cols)` form so the generated model parses them.
- **Always bound list reads** with `.range(from, to)` for pagination; never fetch an unbounded table.
- Single row: `.maybeSingle()` (nullable) or `.single()` (must exist) — pick deliberately.

## 3. Writes & mutations
- `insert` / `update` / `upsert` return the affected row(s); map straight back to a model.
- **Never trust client-supplied money/discount/role values** — enforce server-side and via RLS ([[supabase-security-review]]).
- Multi-step or atomic operations go through an **RPC** (`_db.rpc('claim_ride', params: {...})`), not several client round-trips.

## 4. Error handling — always guarded
Wrap every call from a VM in `runGuarded` (from `BaseViewModel`): it try/catches, routes to
`showError`, and returns `null` on failure. For explicit mutation handling use `SupabaseError.handle`.

```dart
Future<void> load() async {
  changeState(ChangeState.loading);
  final rows = await runGuarded(() => rideQueries.listForDriver(driverId));
  if (rows == null) return changeState(ChangeState.serverError);
  rides = rows;
  changeState(ChangeState.page);
  notifyListeners();
}
```

## 5. Optimistic mutations (the project idiom)
Snapshot → update UI now → call server → revert on failure.

```dart
Future<void> cancel(RideModel ride) async {
  final snapshot = rides;
  rides = rides.where((r) => r.id != ride.id).toList();
  notifyListeners();
  try {
    await rideQueries.cancel(ride.id);
  } catch (e) {
    rides = snapshot;                 // revert
    notifyListeners();
    SupabaseError.handle(e, showError);
  }
}
```

## 6. Realtime (only when needed)
Subscribe through a query method that exposes a typed `Stream<List<XxxModel>>`; cancel the
subscription in the VM's `dispose()`. Don't open raw channels from widgets.

## Red flags — stop and fix
- ✗ `supa.from(...)` or `_db` called from a widget/page. → move it into a query, call via the VM.
- ✗ `map['key']` / `row['price']` in a VM or widget. → return a typed model field instead.
- ✗ `.select('*')` or a list read with no `.range(...)`. → select columns, bound the range.
- ✗ a query call not wrapped in `runGuarded` / `try` with `SupabaseError.handle`. → guard it.
- ✗ trusting a client-sent amount/role on write. → validate server-side + RLS.
- ✗ a mutation that updates the UI but can't revert on error. → snapshot first.

For framework-level networking patterns (interceptors, retries, generic error mapping) see the
generic [[flutter-networking]] skill; this skill is the app's Supabase-specific convention.
