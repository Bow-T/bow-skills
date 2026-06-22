---
name: flutter-code-generation
description: Triggers when running build_runner codegen — freezed, json_serializable, generated routes/DI — wiring build.yaml, managing part files, and deciding what to commit vs ignore.
---

# Flutter Code Generation

build_runner is a code transformer, not a build system you babysit. Treat generated
files as compiler output: deterministic, reproducible from source, and a hard error
to hand-edit. The recurring failures are stale `.g.dart`/`.freezed.dart` files,
part-directive typos, codegen fighting between packages, and confusion over whether
`*.g.dart` belongs in the repo.

## Decide the commit policy ONCE

Pick one and enforce it repo-wide. Mixing the two is what breaks teammates.

- **Do not commit generated files (recommended).** Add to `.gitignore`:
  ```gitignore
  *.g.dart
  *.freezed.dart
  *.config.dart
  *.gr.dart
  *.mocks.dart
  ```
  Then CI MUST run `dart run build_runner build --delete-conflicting-outputs`
  before analyze/test, or the build fails on a fresh checkout.
- **Commit them** only if CI cannot run codegen (e.g. publishing a `pub` package that
  consumers shouldn't have to generate). Then add a CI check that regenerates and
  fails on a dirty tree — see the drift guard below.

Never do half: ignored locally but committed by one person produces phantom diffs.
For the actual commit step defer to [[commit-pipeline]].

## The four moving parts

Every codegen setup is the same shape:

1. An **annotation** package (`freezed_annotation`, `json_annotation`, `injectable`)
   under `dependencies` — it ships at runtime.
2. A **generator** package (`freezed`, `json_serializable`, `injectable_generator`)
   under `dev_dependencies` — build-time only.
3. `build_runner` under `dev_dependencies`.
4. A `part` directive in your source file pointing at the file to be generated.

```yaml
dependencies:
  freezed_annotation: ^2.4.0
  json_annotation: ^4.9.0
dev_dependencies:
  build_runner: ^2.4.0
  freezed: ^2.5.0
  json_serializable: ^6.8.0
```

Mismatched annotation/generator majors are the silent killer — pin them and bump
together. See [[dependency-and-supply-chain]] for upgrade discipline.

## Part files: get the directives exact

The generator emits a `part of` file; your source declares it with `part`. The names
are mechanical — derive them from the source file, not your imagination.

```dart
// file: user.dart  →  parts MUST be 'user.freezed.dart' and 'user.g.dart'
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user.freezed.dart';
part 'user.g.dart';

@freezed
class User with _$User {
  const factory User({
    required String id,
    @JsonKey(name: 'display_name') required String displayName,
    @Default(false) bool isVerified,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}
```

Rules that prevent 90% of red squiggles:

- One `part 'x.freezed.dart';` per freezed file; add `part 'x.g.dart';` ONLY when the
  class has a `fromJson` (json_serializable) — freezed alone does not need it.
- The `with _$User` mixin and `_$UserFromJson` come from generated code, so they
  error until you run build_runner once. That is expected, not a bug.
- Reference the generated file by the SOURCE file's name. `user.dart` → `user.g.dart`,
  never `users.g.dart`.

## Running it

```bash
# one-shot build, clobbering any stale outputs
dart run build_runner build --delete-conflicting-outputs

# regenerate on every save during active model work
dart run build_runner watch --delete-conflicting-outputs

# nuke generated outputs and the build cache when things get weird
dart run build_runner clean
```

`--delete-conflicting-outputs` is almost always what you want; without it, a renamed
or two-generators-claim-the-same-file situation aborts the whole run. Make it your
default and alias it.

Use `watch` while iterating on many models; use `build` in CI and pre-commit. Don't
leave `watch` running while you switch branches — it regenerates against half-checked-
out source and writes garbage. Stop it, switch, rebuild.

## build.yaml: only when defaults bite

You rarely need it. Reach for `build.yaml` to scope generators, change field naming,
or speed up large repos.

```yaml
targets:
  $default:
    builders:
      json_serializable:
        options:
          # snake_case API → camelCase Dart, without @JsonKey on every field
          field_rename: snake
          # smaller, faster generated code; fail loudly on bad JSON shape
          explicit_to_json: true
          create_to_json: true
          checked: true
```

`field_rename: snake` removes a wall of `@JsonKey(name:)`. `explicit_to_json: true` is
essential once you nest serializable models, or `toJson()` emits the inner object as an
unconverted instance. `checked: true` turns malformed JSON into a `CheckedFromJsonException`
with the offending key instead of a vague type error — worth it for [[debugging-and-error-recovery]].

To stop a generator running on the wrong files, scope its `generate_for`:

```yaml
        generate_for:
          - lib/models/**
```

## Generated routes and DI

Router and DI generators (route tables, dependency graphs) follow the same lifecycle
but emit a single aggregate file (e.g. `*.gr.dart`, `*.config.dart`) from annotations
spread across many sources. Two consequences:

- Adding a new annotated route/injectable requires a rebuild — the aggregate file
  won't pick it up until you regenerate. A "route not found" / "no registered type"
  at runtime is usually a missing rebuild.
- These files import every annotated source, so a compile error anywhere can cascade
  into the generated file. Fix the source error first, then regenerate; don't chase
  errors inside the generated output.

```dart
@module
abstract class AppModule {
  @lazySingleton
  Dio dio() => Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));
}
// after build_runner: getIt.init() is generated in *.config.dart
```

## Failure playbook

- **"Missing concrete implementation" / `_$Foo` undefined** → never run, or output
  deleted. Run `build` with `--delete-conflicting-outputs`.
- **Stale fields after editing the model** → run again; if it persists, `clean` then
  `build`. A leftover `watch` may be overwriting you.
- **"Conflicting outputs"** → two generators target one file, or an orphaned generated
  file from a deleted source. `clean` then `build`.
- **CI passes locally, fails on fresh clone** → you committed generated files but a
  teammate's are ignored, or CI lacks the codegen step. Re-read the commit-policy section.
- **`toJson` emits a nested model as an instance, not a map** → set
  `explicit_to_json: true` in `build.yaml`.

## CI drift guard (when committing generated files)

Prove the committed output matches source:

```bash
dart run build_runner build --delete-conflicting-outputs
git diff --exit-code || {
  echo "Generated files are stale — run build_runner and commit the result."; exit 1;
}
```

Keep generated code out of coverage and lint scope; it's a compiler artifact, not
code you own. Hand-editing it is always wrong — change the source and regenerate.
