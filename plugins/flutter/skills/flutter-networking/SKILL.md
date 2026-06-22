---
name: flutter-networking
description: Triggers when building an HTTP/data layer in Flutter/Dart — dio/http clients, interceptors (auth/logging), retries, timeouts, cancellation, typed response and error mapping, and serializing API models.
---

# Flutter networking

Build an HTTP layer that is typed end to end, fails predictably, and never leaks
raw `DioException`/`http.Response` into your UI or view models. Pick one client,
centralize it, and wrap every call so callers get a domain result — never a stray
exception or an untyped `Map`.

## Pick one client and configure it once

`dio` for anything non-trivial (interceptors, cancellation, multipart, retry);
`package:http` only for a handful of plain calls. Create a single configured
instance — never `Dio()` scattered per repository.

```dart
Dio buildDio() {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api.example.com/v1/',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 20),
    // Treat only 2xx as success; map everything else yourself.
    validateStatus: (code) => code != null && code >= 200 && code < 300,
    headers: {'Accept': 'application/json'},
  ));
  dio.interceptors.addAll([
    AuthInterceptor(),
    RetryInterceptor(dio),
    if (kDebugMode) LogInterceptor(requestBody: true, responseBody: true),
  ]);
  return dio;
}
```

Set timeouts on the `BaseOptions`, not ad hoc. A request with no `connectTimeout`
hangs forever on a dead network and your loading spinner never resolves.

## Interceptors: auth and token refresh

Inject the token in `onRequest`; refresh on `401` in `onError`. Guard the refresh
with a single in-flight future so ten parallel 401s trigger one refresh, not ten.

```dart
class AuthInterceptor extends QueuedInterceptor {
  final TokenStore _store;
  final Dio _refreshDio; // a bare Dio without this interceptor — avoids recursion
  Future<String>? _refreshing;

  AuthInterceptor(this._store, this._refreshDio);

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    final t = _store.accessToken;
    if (t != null) o.headers['Authorization'] = 'Bearer $t';
    h.next(o);
  }

  @override
  Future<void> onError(DioException e, ErrorInterceptorHandler h) async {
    if (e.response?.statusCode != 401 || o(e).extra['retried'] == true) {
      return h.next(e);
    }
    try {
      final token = await (_refreshing ??= _refresh());
      final req = e.requestOptions..extra['retried'] = true;
      req.headers['Authorization'] = 'Bearer $token';
      h.resolve(await _refreshDio.fetch(req)); // replay with new token
    } catch (_) {
      h.next(e); // refresh failed — surface original 401 so app logs out
    } finally {
      _refreshing = null;
    }
  }

  Future<String> _refresh() async { /* call refresh endpoint, persist, return */ }
}
```

Use `QueuedInterceptor` so requests serialize while the token refreshes. Keep the
refresh call on a separate `Dio` instance without `AuthInterceptor` to avoid an
infinite refresh loop. Never log the `Authorization` header — strip it in your
log interceptor (see [[secrets-and-config-management]]).

## Retries: only on idempotent, transient failures

Retry GETs and network blips with backoff and jitter. Never blind-retry POST/PATCH
unless you send an idempotency key (see [[resilience-and-fault-tolerance]]).

```dart
class RetryInterceptor extends Interceptor {
  final Dio dio;
  static const _max = 3;
  RetryInterceptor(this.dio);

  bool _retryable(DioException e) {
    const transient = {DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout, DioExceptionType.connectionError};
    final code = e.response?.statusCode ?? 0;
    final safe = e.requestOptions.method == 'GET';
    return safe && (transient.contains(e.type) || code == 502 || code == 503);
  }

  @override
  Future<void> onError(DioException e, ErrorInterceptorHandler h) async {
    final attempt = (e.requestOptions.extra['attempt'] as int? ?? 0);
    if (!_retryable(e) || attempt >= _max) return h.next(e);
    final delay = Duration(milliseconds: 200 * (1 << attempt))
        + Duration(milliseconds: Random().nextInt(120)); // jitter
    await Future.delayed(delay);
    final opts = e.requestOptions..extra['attempt'] = attempt + 1;
    try { h.resolve(await dio.fetch(opts)); } catch (err) { h.next(err as DioException); }
  }
}
```

## Cancellation: tie requests to widget lifecycle

Pass a `CancelToken` and cancel it in `dispose`, so a request from an abandoned
screen (or a stale search keystroke) stops mid-flight instead of completing into
a disposed state.

```dart
class _SearchState extends State<Search> {
  final _cancel = CancelToken();

  Future<void> _query(String term) =>
      api.search(term, cancelToken: _cancel); // forwarded into dio.get(...)

  @override
  void dispose() {
    _cancel.cancel('screen disposed');
    super.dispose();
  }
}
```

For typeahead, cancel the previous token on each keystroke. Treat
`DioExceptionType.cancel` as a silent no-op — never surface it as an error toast.

## Type your responses and errors — no raw maps in the app

Serialize with `json_serializable` (`@JsonSerializable`, `part '*.g.dart'`,
`build_runner`). Wrap every call so it returns a sealed `Result`, not a throwing
future. The UI then handles two states, not an open set of exceptions.

```dart
sealed class ApiError {}
class NetworkError extends ApiError {}                    // offline, timeout
class ServerError extends ApiError { final int status; ServerError(this.status); }
class UnauthorizedError extends ApiError {}
class ParseError extends ApiError { final Object cause; ParseError(this.cause); }

sealed class Result<T> {}
class Ok<T> extends Result<T> { final T value; Ok(this.value); }
class Err<T> extends Result<T> { final ApiError error; Err(this.error); }

Future<Result<User>> fetchUser(String id, {CancelToken? cancelToken}) async {
  try {
    final r = await dio.get('users/$id', cancelToken: cancelToken);
    return Ok(User.fromJson(r.data as Map<String, dynamic>));
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) rethrow; // let caller ignore
    return Err(_mapDio(e));
  } on TypeError catch (e) {
    return Err(ParseError(e)); // shape mismatch — fix the model, don't crash
  }
}

ApiError _mapDio(DioException e) => switch (e.response?.statusCode) {
  401 => UnauthorizedError(),
  final int s when s >= 500 => ServerError(s),
  _ => NetworkError(),
};
```

In the view layer, `switch` on the result and render accordingly:

```dart
switch (await fetchUser(id)) {
  Ok(:final value) => show(value),
  Err(error: UnauthorizedError()) => goToLogin(),
  Err(error: NetworkError()) => showRetry('Check your connection'),
  Err() => showRetry('Something went wrong'),
}
```

## Decode off the UI thread

Large JSON payloads block the frame. Move parsing to an isolate with `compute`:

```dart
final list = await compute(_parseProducts, response.data as String);
List<Product> _parseProducts(String body) => (jsonDecode(body) as List)
    .map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
```

## Checklist

- One configured client; timeouts on `BaseOptions`, never per ad-hoc call.
- Token refresh is single-flight and runs on a separate `Dio` to avoid recursion.
- Retries only on idempotent GETs with backoff + jitter; POST needs an idempotency key.
- Every request takes a `CancelToken`; screens cancel on `dispose`; `cancel` is silent.
- Calls return a sealed `Result`/`ApiError`; no `DioException` or raw `Map` escapes the data layer.
- Models use `json_serializable`; large payloads decode via `compute`.
- Auth headers and tokens never hit logs.

Write the data layer test-first against a mocked client; see [[test-driven-development]].
For headers, tokens, and base URLs across environments, see [[secrets-and-config-management]].
When committing, defer to [[commit-pipeline]].
