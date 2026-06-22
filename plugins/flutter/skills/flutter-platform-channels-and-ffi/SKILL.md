---
name: flutter-platform-channels-and-ffi
description: Triggers when bridging Flutter to native — MethodChannel/EventChannel, Pigeon type-safe channels, dart:ffi for C/C++, and threading platform-side code on iOS/Android correctly.
---

# Flutter platform channels and FFI

Native bridging is where Flutter apps crash in production: silent type
mismatches, wrong-thread UI calls, leaked memory, and channels that hang
forever. Pick the right bridge, type it, and respect the platform thread rules.

## Choose the bridge first

- **One-shot request/response** (read battery, open a file picker): `MethodChannel`.
- **Native pushes a stream** (sensor ticks, connectivity changes, location):
  `EventChannel`.
- **Many methods + structured data, you control both sides**: **Pigeon**. It
  generates type-safe Dart + Kotlin/Swift glue so you stop hand-marshalling maps.
- **Calling an existing C/C++/Rust library** (no platform code, sync, hot path):
  `dart:ffi`.

Rule of thumb: if you find yourself writing `as Map<String, dynamic>` after a
channel call, you should have used Pigeon.

## MethodChannel: the request/response baseline

Channel names must be globally unique — namespace them. Always handle
`PlatformException` and `MissingPluginException` (thrown when the platform side
isn't registered, e.g. on an unsupported OS or during hot restart).

```dart
class BatteryService {
  static const _channel = MethodChannel('dev.app/battery');

  Future<int?> level() async {
    try {
      // invokeMethod returns dynamic; use the typed variant.
      return await _channel.invokeMethod<int>('getLevel');
    } on MissingPluginException {
      return null; // platform doesn't implement it
    } on PlatformException catch (e) {
      throw BatteryError(e.code, e.message);
    }
  }
}
```

Standard codec supports null, bool, num, String, Uint8List, List and Map only.
Anything else must be serialized — which is exactly the trap Pigeon removes.

Kotlin side — handle on the main thread, reply exactly once:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.app/battery")
  .setMethodCallHandler { call, result ->
    when (call.method) {
      "getLevel" -> result.success(readBatteryLevel())
      else -> result.notImplemented()
    }
  }
```

If `getLevel` does real work, jump off the main thread, then post the reply back
on the main thread — `result.success` must be called on the platform main thread.

```kotlin
"getLevel" -> scope.launch(Dispatchers.IO) {
  val v = readBatteryLevel()
  withContext(Dispatchers.Main) { result.success(v) }
}
```

## EventChannel: native-driven streams

Use it when native emits over time. Expose it as a broadcast `Stream` and let
callers `listen`. The native side gets `onListen`/`onCancel` — register and
tear down resources there, or you leak sensors and battery.

```dart
class ConnectivityWatcher {
  static const _events = EventChannel('dev.app/connectivity');

  Stream<bool> get online => _events
      .receiveBroadcastStream()
      .map((e) => e as bool);
}
```

```kotlin
EventChannel(messenger, "dev.app/connectivity").setStreamHandler(
  object : EventChannel.StreamHandler {
    private var receiver: BroadcastReceiver? = null
    override fun onListen(args: Any?, sink: EventChannel.EventSink) {
      receiver = registerNetworkReceiver { online ->
        Handler(Looper.getMainLooper()).post { sink.success(online) }
      }
    }
    override fun onCancel(args: Any?) { unregister(receiver); receiver = null }
  })
```

Always cancel the Dart subscription in `dispose()` — that fires `onCancel`.

## Pigeon: stop hand-marshalling

Define one schema file; generate both sides. No string method names, no manual
map casts, compile-time errors when shapes drift.

```dart
// pigeons/messages.dart  (run: dart run pigeon --input pigeons/messages.dart)
import 'package:pigeon/pigeon.dart';

class Device { String? id; int? batteryLevel; }

@HostApi() // Dart calls native
abstract class DeviceApi {
  @async
  Device current();
}

@FlutterApi() // native calls Dart (callbacks)
abstract class DeviceEvents {
  void onUnplugged(Device device);
}
```

Generated `DeviceApi().current()` returns a real `Device` — no codec guessing.
Prefer Pigeon for any plugin with more than two methods or nested data.

## dart:ffi: calling C directly

For CPU-bound native code with no platform-thread needs. Load the library,
look up symbols with typed signatures, and **manage memory yourself**.

```dart
import 'dart:ffi';
import 'package:ffi/ffi.dart'; // malloc, toNativeUtf8

typedef _HashC = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _HashDart = Pointer<Utf8> Function(Pointer<Utf8>);

final _lib = DynamicLibrary.open(
  Platform.isAndroid ? 'libhasher.so' : 'hasher.framework/hasher',
);
final _hash = _lib.lookupFunction<_HashC, _HashDart>('hash');

String hash(String input) {
  final inPtr = input.toNativeUtf8();
  final outPtr = _hash(inPtr);
  try {
    return outPtr.toDartString();
  } finally {
    malloc.free(inPtr);       // free what Dart allocated
    _freeNative(outPtr);      // free what C returned, via its own free fn
  }
}
```

FFI hazards, every one a real bug:
- **Leaks**: every `malloc`/`toNativeUtf8` needs a matching `free`. Wrap in
  `try/finally`. For owned-by-Dart structs, attach a `NativeFinalizer`.
- **Blocking the UI isolate**: FFI calls are synchronous. A long call freezes
  frames. Move it to a worker `Isolate` (or `Isolate.run`).
- **Callbacks from native threads**: a C callback firing off the main thread
  cannot touch Dart objects directly. Use `NativeCallable.listener` to marshal
  back to the owning isolate.

```dart
final result = await Isolate.run(() => hash(payload)); // off the UI isolate
```

For generating FFI bindings from C headers, use `package:ffigen` instead of
typing `typedef`s by hand once you have more than a few functions.

## Threading rules that bite

- Dart side: every channel call is async and runs on the root isolate. Don't
  `await` a channel in a tight `build()`.
- Android: `MethodChannel` handlers run on the platform main thread. Offload
  heavy work, then reply on main.
- iOS: same — Swift handlers run on the main queue; dispatch work to a
  background queue and call `result()` back on `DispatchQueue.main`.
- Replying twice (or never) to a `result` is a crash/hang. Reply exactly once.

## Verify before you ship

- Unit-test Dart logic by setting a mock handler:
  `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
  .setMockMethodCallHandler(channel, (call) async => 42);`
- Force the `MissingPluginException` path (it happens on hot restart and on the
  platform you didn't implement) and confirm graceful degradation.
- Run a leak/profile pass on FFI paths before merging.

See [[flutter-mvvm]] for keeping channel calls out of widgets, [[performance-optimization]]
for measuring FFI cost, [[debugging-and-error-recovery]] for tracing native crashes,
and [[concurrency-and-async-correctness]] for isolate and threading correctness.
For commits, follow [[commit-pipeline]].
