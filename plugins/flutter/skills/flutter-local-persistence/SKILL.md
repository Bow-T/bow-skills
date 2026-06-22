---
name: flutter-local-persistence
description: Triggers when choosing or implementing on-device storage in Flutter — picking among Drift/Isar/Hive/sqflite/shared_preferences/secure storage, schema migrations, and matching the store to the shape of the data.
---

# Flutter Local Persistence

Pick the store by the *shape and lifetime* of the data, not by familiarity. The
wrong store leaks across every screen that reads it; migrating later is painful.

## 1. Match the store to the data

Answer these before adding a dependency:

- **Is it a handful of scalar settings?** (theme, last tab, onboarding-done) →
  `shared_preferences`. No schema, no queries, just typed keys.
- **Is it a secret?** (auth token, refresh token, API key, PIN) → `flutter_secure_storage`.
  Backed by Keychain (iOS) and EncryptedSharedPreferences/Keystore (Android). Never
  put credentials in SharedPreferences or a plain DB file.
- **Is it a typed object graph you query and watch?** (offline cache, lists you
  filter/sort, relations) → a real database. Pick by query style:
  - **Relational, SQL-first, type-safe, reactive streams** → **Drift** (codegen, compiles
    SQL at build time, runs on a background isolate).
  - **NoSQL, fast, links between objects, full-text search** → **Isar** (note:
    `isar` 3.x is effectively unmaintained and 4.0 is still preview — prefer the
    actively maintained Drift/sqflite unless you specifically need Isar's model).
  - **Simple boxes of objects, minimal ceremony, no complex queries** → **Hive**.
  - **Raw SQL, you control everything, tiny footprint** → **sqflite**.

Rule of thumb: reach for `shared_preferences` for preferences and a database for
**data**. Anything you would model with a class and a list belongs in a database.

## 2. Key-value: do it safely

`shared_preferences` is async and cheap — but it is not a cache and not a database.

```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('onboarding_done', true);
final done = prefs.getBool('onboarding_done') ?? false; // always default
```

Wrap it so the rest of the app never touches raw string keys:

```dart
class AppSettings {
  AppSettings(this._prefs);
  final SharedPreferences _prefs;

  static const _kThemeMode = 'theme_mode';

  ThemeMode get themeMode =>
      ThemeMode.values[_prefs.getInt(_kThemeMode) ?? ThemeMode.system.index];

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setInt(_kThemeMode, mode.index);
}
```

For secrets, swap in secure storage — the API is async string-only:

```dart
const storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);
await storage.write(key: 'refresh_token', value: token);
final token = await storage.read(key: 'refresh_token'); // String? — may be null
```

## 3. Relational + reactive: Drift

Drift gives compile-checked SQL, typed rows, and `Stream`s that rebuild the UI when
the underlying rows change. Define tables, let codegen build the dao.

```dart
class Todos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Todos])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  @override
  int get schemaVersion => 1;

  // Reactive: emits a new list whenever any matching row changes.
  Stream<List<Todo>> watchOpen() =>
      (select(todos)..where((t) => t.done.equals(false))).watch();
}
```

Run `dart run build_runner build` to generate `*.g.dart`. Then bind the stream:

```dart
StreamBuilder<List<Todo>>(
  stream: db.watchOpen(),
  builder: (context, snap) {
    final items = snap.data ?? const [];
    return ListView(children: [for (final t in items) Text(t.title)]);
  },
);
```

Open the file on a background isolate so large queries never jank the UI thread —
use `driftDatabase(name: ...)` (the `drift_flutter` convenience opener, which defaults
to a background isolate) or the lower-level `NativeDatabase.createInBackground`.

## 4. Migrations are the hard part — plan them up front

Bumping `schemaVersion` without a migration **wipes or corrupts** user data. Every
schema change needs a tested step.

```dart
@override
MigrationStrategy get migration => MigrationStrategy(
      onCreate: (m) => m.createAll(),
      onUpgrade: (m, from, to) async {
        if (from < 2) {
          await m.addColumn(todos, todos.createdAt); // additive: safe
        }
        if (from < 3) {
          // Destructive change → migrate data explicitly, don't drop blindly.
          // Pass columnTransformer/newColumns so existing rows are remapped,
          // not silently re-created with identity transforms.
          await m.alterTable(TableMigration(
            todos,
            columnTransformer: {
              todos.title: todos.title.trim(),
            },
          ));
        }
      },
    );
```

Migration discipline (applies to every store, not just Drift):

- **Additive changes are cheap; renames and type changes are not.** Add a new column,
  backfill, then stop reading the old one — across two releases, not one.
- **Never reorder or repurpose an existing field.** Hive type adapters and Isar
  schemas key on declared order/ids; reuse breaks old data on device.
- **Test migrations against a real old database file**, not an empty one. Ship a fixture
  DB at each version and assert the upgrade path. Drift's `schema dump` + generated
  test helpers make this verifiable.
- A migration that "ran once on my machine" proves nothing — see [[test-driven-development]].

## 5. Isar / Hive quick shape

Isar — annotate, query with a typed builder, watch changes:

```dart
@collection
class Note {
  Id id = Isar.autoIncrement;
  @Index(type: IndexType.value) late String title;
  late DateTime updatedAt;
}

final notes = await isar.notes.filter().titleContains('todo').findAll();
Stream<void> changes = isar.notes.watchLazy();
```

Hive — boxes of values; register adapters and version your model carefully:

```dart
await Hive.initFlutter();
final box = await Hive.openBox<String>('drafts');
await box.put('current', text);
final draft = box.get('current');
```

## 6. Lifecycle, threading, and correctness

- **Open once, close late.** Initialize the DB in `main()` (after
  `WidgetsFlutterBinding.ensureInitialized()`), inject the instance, and close it on
  app teardown — not per-screen.
- **Everything is async.** Disk I/O off the UI isolate; never call blocking storage in
  `build()`. Drift/Isar already run native work off the main isolate — prefer their
  reactive `watch` APIs over polling in a `Timer`.
- **Default every read.** SharedPreferences and secure storage return null when a key
  is absent; a missing key on first launch is normal, not an error.
- **Treat the cache as disposable.** Local data is a performance/offline copy of a
  source of truth — design so a wiped DB degrades to "refetch," never to "data loss."
  See [[caching-strategy]] for invalidation, and [[secrets-and-config-management]] for
  what must live in secure storage instead.
- **Test write→read→migrate paths**, not just reads ([[test-driven-development]]). Commit
  generated `*.g.dart` and migration fixtures together via [[commit-pipeline]].

Tie the chosen store back to your model / data layer so the same typed objects
serialize to disk and to the network.
