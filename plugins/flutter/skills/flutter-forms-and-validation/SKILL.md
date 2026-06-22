---
name: flutter-forms-and-validation
description: Triggers when building Flutter input — Form/FormField/TextEditingController/FocusNode, sync and async validation, submission and error display, controller/focus disposal, and complex multi-field form state.
---

# Flutter Forms and Validation

Forms fail in three predictable ways: leaked controllers, validators that fire at the wrong time, and async checks that race the user. Build them so each of those is structurally impossible.

## Decide the form's shape first

- **One or two fields, no cross-field rules** → skip `Form`. A single `TextField` with a `ValueNotifier<String?>` error is lighter.
- **Several fields validated together on submit** → use one `Form` + `GlobalKey<FormState>` and per-field `validator`s.
- **Wizard / dynamic fields / server-driven errors** → drive state from a `ChangeNotifier`/Bloc/Riverpod model, not from widget state. `FormState.validate()` does not scale to async or conditional rules.

State your choice before coding; the rest of the workflow depends on it.

## Always dispose controllers and focus nodes

Every `TextEditingController` and `FocusNode` you `new` up owns native resources. Leaking them shows up as listener callbacks firing on disposed widgets.

```dart
class _SignInFormState extends State<SignInForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }
  // ...
}
```

Rule: if a `State` field is a controller, focus node, or `AnimationController`, it must appear in `dispose()`. Audit the two lists against each other before you move on. Never recreate a controller inside `build` — it resets cursor and text every frame.

## Synchronous validation: pure functions, composed

Keep validators as plain functions returning `String?` (null = valid). Pure functions are testable without pumping a widget.

```dart
String? notEmpty(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Required' : null;

String? email(String? v) {
  if (v == null || v.isEmpty) return null; // let `notEmpty` own emptiness
  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
  return ok ? null : 'Enter a valid email';
}

/// First non-null wins.
FormFieldValidator<String> all(List<FormFieldValidator<String>> rs) =>
    (v) => rs.map((r) => r(v)).firstWhere((e) => e != null, orElse: () => null);
```

```dart
TextFormField(
  controller: _email,
  keyboardType: TextInputType.emailAddress,
  autovalidateMode: AutovalidateMode.onUserInteraction,
  validator: all([notEmpty, email]),
  textInputAction: TextInputAction.next,
  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
)
```

`AutovalidateMode.onUserInteraction` is the right default: silent until the user touches the field, then live. Avoid `always` (errors scream on a pristine form), and note that the default `AutovalidateMode.disabled` validates only when you call `validate()` (e.g. on submit) — fine if that is genuinely what you want.

## Submission flow

Validate, guard against double-taps, surface a single failure path.

```dart
Future<void> _submit() async {
  FocusScope.of(context).unfocus(); // dismiss keyboard
  if (!_formKey.currentState!.validate()) return;
  if (_submitting) return;
  setState(() => _submitting = true);
  try {
    await widget.onSignIn(_email.text.trim(), _password.text);
  } on AuthException catch (e) { // example: your backend SDK's exception type
    if (mounted) setState(() => _serverError = e.message);
  } finally {
    if (mounted) setState(() => _submitting = false);
  }
}
```

- Always check `mounted` after an `await` before calling `setState` — the user may have popped the route.
- Disable the submit button while `_submitting`, don't just ignore taps: `onPressed: _submitting ? null : _submit`.
- Trim text fields at the boundary; store the canonical value, validate the canonical value.

## Async validation without races

`validator` is synchronous — it cannot `await`. Do not block submit on a network call inside it. Run async checks (username taken, coupon valid) separately, debounce them, and cancel stale results.

```dart
Timer? _debounce;
int _checkSeq = 0;
String? _usernameError;

void _onUsernameChanged(String value) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 400), () async {
    final seq = ++_checkSeq;             // token for this request
    final taken = await api.isTaken(value);
    if (!mounted || seq != _checkSeq) return; // a newer keystroke won
    setState(() => _usernameError = taken ? 'Already taken' : null);
  });
}
```

Show `_usernameError` via the field's `decoration.errorText`, and block submit when it is non-null. Cancel `_debounce` in `dispose()`. The `seq` token is what kills the race — a slow response for an old value never overwrites a fresh one.

## Multi-field and dependent state

Cross-field rules (confirm-password, end-date-after-start) read sibling values, so keep the source of truth in one model rather than scattered field state.

```dart
class CheckoutModel extends ChangeNotifier {
  String password = '', confirm = '';

  String? get confirmError =>
      confirm.isNotEmpty && confirm != password ? 'Passwords differ' : null;

  bool get canSubmit =>
      password.length >= 8 && confirmError == null;

  void setPassword(String v) { password = v; notifyListeners(); }
  void setConfirm(String v) { confirm = v; notifyListeners(); }
}
```

The submit button binds to `canSubmit`; confirm field shows `confirmError`. This also makes server-side field errors trivial: map the API's `{field: message}` into the model and feed each into the right `errorText`. Wire this model into your view-model / state layer rather than into widget state.

## Input shaping and accessibility

- Constrain at entry with `inputFormatters` (`FilteringTextInputFormatter.digitsOnly`, length caps) instead of rejecting after the fact.
- Set `keyboardType`, `autofillHints` (`AutofillHints.email`, `.newPassword`), and `textInputAction` so the keyboard and autofill behave.
- Chain focus with `textInputAction: TextInputAction.next` + `onFieldSubmitted` → `requestFocus()`; last field uses `TextInputAction.done`.
- Errors must be text, not just color, and announced to screen readers — `errorText` already does this; see [[accessibility-engineering]].

## Test the validators and the flow

Validators are pure — unit-test them directly with no widget. For the form, use `WidgetTester`: `enterText`, `tester.tap` submit, then assert `find.text('Required')`. Cover the async race by entering text twice fast and confirming only the latest error renders. Follow [[test-driven-development]]; commit via [[commit-pipeline]].

## Red flags

- Controller created in `build` or missing from `dispose`.
- `setState` after `await` with no `mounted` check.
- Network call inside a `validator`.
- `autovalidateMode: always` on a fresh form.
- Cross-field validation reading another widget's `controller.text` directly instead of shared state.
- Submit handler with no double-tap guard.
