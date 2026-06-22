---
name: flutter-app-size-optimization
description: Triggers when a Flutter binary is too large — measuring with --analyze-size, tree-shaking, deferred components, asset/font/image trimming, split-per-abi/app bundles, and cutting dependency weight.
---

# Flutter App Size Optimization

Shrink the shipped artifact without breaking features. **Measure first, cut second, re-measure third.** Never optimize a number you haven't seen.

## 1. Measure before touching anything

Build a release artifact with the size analyzer enabled. The flag emits a JSON breakdown of every package, asset, and native library.

```bash
# Android App Bundle (what Play Store actually ships)
# --target-platform pins ONE ABI so you measure a single device slice;
# drop it to build (and ship) the full multi-ABI bundle.
flutter build appbundle --release --analyze-size --target-platform android-arm64

# iOS
flutter build ipa --release --analyze-size

# Open the breakdown in DevTools (the JSON path is printed at the end of the build;
# the filename matches the build target, e.g. app-code-size-analysis_NN.json)
dart devtools --appSizeBase=~/.flutter-devtools/app-code-size-analysis_01.json
```

Read the artifact, **not** the APK on disk. A universal APK lies — users download a per-ABI split. For Android, the Play Console "Download size" under App bundle explorer is the truth. For iOS, App Store Connect's App Thinning report gives the per-device size.

Record a baseline number (e.g. `arm64 download = 18.4 MB`) and re-run after each change. If a change doesn't move the number, revert it.

## 2. Split by ABI / ship app bundles

Shipping one fat APK with arm, arm64, and x86 native code triples the native payload. Let the store thin it.

```bash
# Preferred: App Bundle — Play Store generates per-device splits automatically
flutter build appbundle --release

# Sideloaded / non-Play distribution: split APKs per ABI
flutter build apk --release --split-per-abi
# -> app-armeabi-v7a-release.apk, app-arm64-v8a-release.apk, app-x86_64-release.apk
```

If you must distribute a single APK, drop 32-bit unless you genuinely support old devices: `--target-platform android-arm64`. (For an *app bundle*, never pin a single ABI for a shipping build — ship the full multi-ABI bundle and let Play thin per device; pin an ABI only when measuring one slice.) iOS only ships thinned slices via TestFlight/App Store — local `.app` size is meaningless.

## 3. Tree-shake icons and dead Dart

Release builds already tree-shake unused Dart and icon-font glyphs automatically. Watch for the build log line:

```
Font asset "MaterialIcons-Regular.otf" was tree-shaken, reducing it from 1645184 to 9532 bytes (99.4% reduction).
```

If tree-shaking is **disabled**, something forced it off — usually a non-const `IconData` built at runtime:

```dart
// BAD: dynamic codepoint defeats icon tree-shaking for the WHOLE font
Icon(IconData(0xe800 + offset, fontFamily: 'MaterialIcons'))

// GOOD: const tokens stay shakeable
Icon(Icons.favorite)
```

Never pass `--no-tree-shake-icons` to "fix" a missing glyph; instead reference the icon as a const so the shaker keeps it. Audit `grep -rn "IconData(" lib/` for runtime-constructed icons.

## 4. Defer rarely-used features

Deferred components (Android, Play Feature Delivery) move a slice of Dart + assets out of the base download and fetch it on demand. Use it for onboarding flows, admin panels, heavy editors — anything not on the cold-start path.

```dart
import 'rarely_used.dart' deferred as rare;

Future<void> openEditor() async {
  await rare.loadLibrary(); // downloads + links the component
  rare.launchHeavyEditor();
}
```

Declare the component in `pubspec.yaml` and `android/app/src/main/AndroidManifest.xml`, then validate with:

```bash
flutter build appbundle --release
# Verify split:
bundletool build-apks --bundle=build/app/outputs/bundle/release/app-release.aab --output=app.apks
```

Deferred loading is async and can fail (no network) — always wrap `loadLibrary()` in try/catch and show a retry. See [[resilience-and-fault-tolerance]] for the retry/timeout shape.

## 5. Crush assets, fonts, and images

Assets are usually the biggest *removable* chunk.

- **Resolution variants:** don't ship a 4x PNG to every device. Provide `2.0x/` and `3.0x/` folders so Flutter picks the right density and skips the rest.
- **Vectors over raster:** replace multi-resolution PNG icon sets with a single tree-shakeable icon font or `flutter_svg`. One SVG beats four PNGs.
- **WebP for photos:** convert JPEG/PNG to WebP (`cwebp -q 80`). Often 30–50% smaller at equal quality.
- **Subset fonts:** a full variable font can be 1–2 MB. Subset to the glyphs you ship.

```bash
# Subset a font to Latin + the punctuation you actually render
pyftsubset NotoSans.ttf --unicodes=U+0000-00FF,U+2018-201F --output-file=NotoSans-subset.ttf
```

List only what you use in `pubspec.yaml` — a bare directory ships every file in it:

```yaml
flutter:
  assets:
    - assets/images/logo.webp        # explicit > directory
  fonts:
    - family: AppSans
      fonts:
        - asset: assets/fonts/NotoSans-subset.ttf
```

Audit large assets: `find assets -type f -size +100k -exec ls -lh {} \; | sort -k5 -h`.

## 6. Trim dependency weight

Each package drags in its Dart, transitive deps, and sometimes native libs. The `--analyze-size` breakdown ranks packages by bytes — start at the top.

- A package pulled in for one helper? Inline the helper, drop the dep.
- Prefer a focused package over a kitchen-sink one (e.g. a single date formatter vs a full i18n megalib you barely touch).
- Watch native bloat: ML, video, and crypto plugins ship multi-MB `.so` files per ABI. Confirm you need them on every platform.
- Check transitive duplication: `dart pub deps --style=compact` reveals two packages bundling the same heavy dependency.

Before adding any dependency, weigh its size cost — coordinate with [[dependency-and-supply-chain]] on whether it earns its place.

## 7. Obfuscation reclaims symbol bytes

Obfuscation shrinks the Dart symbol table and protects identifiers. Always emit and archive the debug symbols, or you can't symbolicate crashes.

```bash
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols
```

Store `build/symbols` as a build artifact (the store, your crash backend). Without it, every stack trace is unreadable garbage.

## 8. Re-measure and lock it in

Run the same `--analyze-size` command from step 1 and diff against the baseline. Add a CI guard so the binary can't silently regrow — fail the pipeline if `arm64` download size exceeds a threshold. Wire this into [[ci-cd-and-automation]].

```bash
# Crude regression gate: fail if the AAB grows past the budget.
# `wc -c` is portable (BSD `stat -f%z` and GNU `stat -c%s` differ across OSes).
SIZE=$(wc -c < build/app/outputs/bundle/release/app-release.aab)
[ "$SIZE" -lt 26214400 ] || { echo "AAB over 25MB budget"; exit 1; }
```

## Checklist

- [ ] Baseline captured with `--analyze-size`; numbers are from store thinning, not on-disk APK.
- [ ] Shipping App Bundle or `--split-per-abi`; 32-bit dropped if unsupported.
- [ ] Icon tree-shaking confirmed in build log; no runtime `IconData`.
- [ ] Rare/heavy features behind deferred components with retry handling.
- [ ] Assets explicit in pubspec, WebP/SVG used, fonts subset, density variants present.
- [ ] Top packages in the size report justified; native `.so` weight checked.
- [ ] `--obfuscate --split-debug-info` set; symbols archived.
- [ ] Re-measured, diffed against baseline, CI size budget in place.

When committing the result, follow [[commit-pipeline]].
