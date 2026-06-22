---
name: flutter-push-notifications-and-deep-linking
description: Triggers when wiring messaging or link entry points — FCM/APNs setup, foreground/background/terminated notification handling, local notifications, and routing universal links / app links / custom schemes into in-app navigation.
---

# Flutter Push Notifications & Deep Linking

Both features share one hard truth: **the app can be cold-started by an external event**, and the data
that triggered it must survive until the navigator is ready. Treat the inbound payload (a notification
tap or a link) as a *pending intent* — capture it, hold it, replay it once routing is alive.

## 1. Model every entry point

There are three notification states and three link sources. Name them so you handle each:

| Trigger | App state | Where you observe it |
|---|---|---|
| Push received | foreground | `FirebaseMessaging.onMessage` |
| Push tapped | background (warm) | `FirebaseMessaging.onMessageOpenedApp` |
| Push tapped | terminated (cold) | `FirebaseMessaging.instance.getInitialMessage()` |
| Push received | background/terminated | top-level `onBackgroundMessage` handler |
| Link opened | warm | `appLinks.uriLinkStream` |
| Link opened | cold | `appLinks.getInitialLink()` |

The cold-start cases are the ones people forget. A `getInitialMessage`/`getInitialLink` call that runs
*before* the router exists silently drops the destination.

## 2. FCM/APNs setup, in order

```dart
Future<void> initMessaging() async {
  // 1. Permission. iOS/web require it; Android 13+ needs POST_NOTIFICATIONS.
  final settings = await FirebaseMessaging.instance.requestPermission(
    alert: true, badge: true, sound: true,
  );
  final status = settings.authorizationStatus;
  // Proceed only when granted; notDetermined/denied must not register a token.
  if (status != AuthorizationStatus.authorized &&
      status != AuthorizationStatus.provisional) {
    return;
  }

  // 2. iOS: ensure the APNs token exists before asking for the FCM token.
  if (Platform.isIOS) {
    final apns = await FirebaseMessaging.instance.getAPNSToken();
    // Simulator or not-yet-provisioned. On a real device it can be null for a
    // short window after the grant — poll getAPNSToken() with backoff, don't drop it.
    if (apns == null) return;
  }

  // 3. Register the device token with your backend, and refresh on rotation.
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) await registerDeviceToken(token);
  FirebaseMessaging.instance.onTokenRefresh.listen(registerDeviceToken);
}
```

Tokens rotate (reinstall, restore, clearing data). **Always** listen to `onTokenRefresh`; never cache a
token as permanent. De-dupe server-side on token value, not user id.

## 3. The background handler must be top-level

It runs in a separate isolate with no access to your widget tree or in-memory singletons.

```dart
@pragma('vm:entry-point') // keep it after tree-shaking / AOT
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(); // the isolate is fresh — initialize again
  // Do only isolate-safe work: badge counts, local DB writes, logging.
}

void main() {
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  runApp(const App());
}
```

Do not navigate here and do not touch a `BuildContext` — there isn't one. Navigation happens only on
*tap*, via `onMessageOpenedApp` / `getInitialMessage`.

## 4. Foreground display with local notifications

FCM does **not** show a system banner while the app is foregrounded — you render it yourself with
`flutter_local_notifications`, which also gives you tap callbacks for notifications you raise locally.

```dart
final _local = FlutterLocalNotificationsPlugin();

Future<void> initLocal() async {
  const channel = AndroidNotificationChannel(
    'high_importance', 'Alerts', importance: Importance.high,
  );
  await _local
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await _local.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (resp) {
      if (resp.payload != null) _routePayload(jsonDecode(resp.payload!));
    },
  );
}

FirebaseMessaging.onMessage.listen((m) {
  final n = m.notification;
  if (n == null) return;
  _local.show(
    n.hashCode, n.title, n.body,
    const NotificationDetails(
      android: AndroidNotificationDetails('high_importance', 'Alerts',
          importance: Importance.high, priority: Priority.high),
    ),
    payload: jsonEncode(m.data), // carry the routing data through the tap
  );
});
```

Put routing info in `message.data` (your own keys), not in the `notification` block — `data` is
delivered intact in every state; the `notification` block is consumed by the OS.

## 5. One pending-intent queue, replayed after routing is ready

Funnel notification taps and link opens into a single sink so the router has one place to listen.
This solves the cold-start race cleanly.

```dart
class PendingIntents {
  final _controller = StreamController<Uri>.broadcast();
  Stream<Uri> get stream => _controller.stream;
  Uri? _initial; // captured before the router subscribes

  void seedInitial(Uri uri) => _initial ??= uri;
  Uri? takeInitial() { final u = _initial; _initial = null; return u; }
  void push(Uri uri) => _controller.add(uri);
}
```

Normalize a notification payload into the *same* `Uri` shape as a link, so both paths share routing
logic. A push with `{"route": "/orders/42"}` becomes `Uri.parse('myapp:///orders/42')` — the triple
slash leaves the host empty so `uri.path` is `/orders/42`. (`myapp://orders/42` would make
`orders` the host and leave `uri.path` empty, silently breaking the section 7 routing.)

## 6. Capture links with app_links

```dart
final _appLinks = AppLinks();

Future<void> initLinks(PendingIntents pending) async {
  final initial = await _appLinks.getInitialLink(); // cold start
  if (initial != null) pending.seedInitial(initial);
  _appLinks.uriLinkStream.listen(pending.push);     // warm
}
```

Platform config is mandatory and silent when wrong:
- **Android App Links** — `<intent-filter android:autoVerify="true">` plus a hosted
  `/.well-known/assetlinks.json` with your SHA-256 signing fingerprints.
- **iOS Universal Links** — `Associated Domains` capability (`applinks:your.domain`) plus a hosted
  `/.well-known/apple-app-site-association` (JSON, **no** `.json` extension, served as `application/json`).
- **Custom scheme** — declare the scheme in `AndroidManifest.xml` and `Info.plist`. Schemes are
  spoofable; never trust a custom-scheme link for auth or to grant access.

## 7. Drive navigation from the intents, not the call sites

With `go_router`, replay the seeded cold-start intent after the first frame, then stream the rest.

```dart
class _RootState extends State<Root> {
  late final StreamSubscription _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = pending.takeInitial();
      if (initial != null) _go(initial);
      _sub = pending.stream.listen(_go);
    });
  }

  void _go(Uri uri) {
    if (!_isAllowed(uri)) return;            // validate before navigating
    router.go(uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
  }

  @override
  void dispose() { _sub.cancel(); super.dispose(); }
}
```

## 8. Validate, then navigate — links are untrusted input

- **Allow-list paths.** Match against known routes; reject anything else to a safe default. An open
  redirect through a deep link is a real attack vector.
- **Gate auth-required destinations.** If a link targets a protected screen and there's no session,
  route to login and resume afterward — don't crash or flash protected content.
- **Don't `push` blindly on cold start.** There may be no back stack; prefer `go`/replace so Back
  exits cleanly instead of into an empty navigator.
- **Coalesce duplicates.** Both `getInitialMessage` and a queued tap can fire for the same event;
  de-dupe on a message/link id so you navigate once.

## 9. Verify the cases that actually break

Manual tests, per platform:
1. Tap a push while **terminated** — does it deep-link after cold start?
2. Tap a push while **backgrounded** — `onMessageOpenedApp` only.
3. Receive a push in **foreground** — local banner shows, tap routes.
4. Open a universal/app link **cold** and **warm**.
5. Open a link to a protected route while logged out — lands on login, resumes after.

On iOS, test on a real device: APNs tokens and universal links do not work in the Simulator. Use
`adb shell am start -W -a android.intent.action.VIEW -d "https://your.domain/orders/42"` and
`xcrun simctl openurl booted "myapp:///orders/42"` to fire links without a server.

## Related

- [[flutter-navigation-and-routing]] — where the router lives and how your view-model / state layer consumes the navigation event.
- [[authn-authz-design]] — gating deep links to protected routes and resuming after login.
- [[security-and-hardening]] — treating links/payloads as untrusted, avoiding open redirects.
- [[observability-and-instrumentation]] — logging token registration and delivery/tap funnels.
- For committing this work, defer to [[commit-pipeline]].
