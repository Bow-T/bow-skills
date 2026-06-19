# Testing Patterns Reference

A scannable catalog of testing patterns across the stack. Pair this with the `test-driven-development` skill. Examples cover TypeScript/web and Flutter/Dart.

## Contents

- [Shape of a test](#shape-of-a-test)
- [Naming tests](#naming-tests)
- [Assertions cheat sheet](#assertions-cheat-sheet)
- [Mocking and test doubles](#mocking-and-test-doubles)
- [Where to draw the mock line](#where-to-draw-the-mock-line)
- [UI / widget tests](#ui--widget-tests)
- [API and integration tests](#api-and-integration-tests)
- [End-to-end tests](#end-to-end-tests)
- [Anti-patterns](#anti-patterns)

## Shape of a test

Three phases, in order: set up the world, do the thing, check the result. (Given/When/Then is the same idea.)

```typescript
it('assigns a pending status to a newly created task', () => {
  // Given: the inputs
  const draft = { title: 'Ship release notes', priority: 'high' };

  // When: the behavior under test
  const task = createTask(draft);

  // Then: the observable outcome
  expect(task.title).toBe('Ship release notes');
  expect(task.priority).toBe('high');
  expect(task.status).toBe('pending');
});
```

```dart
test('assigns a pending status to a newly created task', () {
  final draft = TaskDraft(title: 'Ship release notes', priority: Priority.high);

  final task = createTask(draft);

  expect(task.title, 'Ship release notes');
  expect(task.priority, Priority.high);
  expect(task.status, TaskStatus.pending);
});
```

## Naming tests

Name the behavior and the condition, not the method mechanics. A reader should learn the spec from the test list alone.

```typescript
describe('createTask', () => {
  it('defaults new tasks to pending status', () => {});
  it('rejects an empty title with a ValidationError', () => {});
  it('strips leading and trailing whitespace from the title', () => {});
  it('assigns a unique id per task', () => {});
});
```

## Assertions cheat sheet

```typescript
// equality
expect(value).toBe(expected);          // identity / primitives
expect(value).toEqual(expected);       // structural, ignores undefined props
expect(value).toStrictEqual(expected); // structural + type-strict

// presence / truthiness
expect(value).toBeDefined();
expect(value).toBeNull();
expect(value).toBeTruthy();

// numbers
expect(n).toBeGreaterThan(5);
expect(n).toBeCloseTo(0.3, 5);         // floats

// strings & collections
expect(text).toMatch(/pattern/);
expect(list).toContain(item);
expect(list).toHaveLength(3);
expect(obj).toHaveProperty('key', 'value');

// throwing
expect(() => parse('')).toThrow(ValidationError);

// async
await expect(load()).resolves.toEqual(record);
await expect(load()).rejects.toThrow();
```

Dart/`flutter_test` matcher equivalents: `equals`, `isNull`, `isNotNull`, `greaterThan`, `closeTo`, `contains`, `hasLength`, `throwsA(isA<ValidationError>())`, and `completion(...)` / `throwsA(...)` for futures.

## Mocking and test doubles

```typescript
// a standalone stub
const send = jest.fn();
send.mockResolvedValue({ id: 'msg_1' });
send.mockImplementation((to) => `queued:${to}`);

expect(send).toHaveBeenCalledWith('a@example.com');
expect(send).toHaveBeenCalledTimes(1);

// swap a whole module
jest.mock('./mailer', () => ({
  send: jest.fn().mockResolvedValue({ id: 'msg_1' }),
}));

// keep the real module, override one export
jest.mock('./ids', () => ({
  ...jest.requireActual('./ids'),
  newId: jest.fn().mockReturnValue('fixed-id'),
}));
```

In Dart, generate mocks with `mockito`/`mocktail` and stub with `when(() => repo.fetch()).thenAnswer((_) async => rows)`.

## Where to draw the mock line

Mock at the edges of your system; exercise the real thing inside it.

| Worth mocking (slow / external / nondeterministic) | Leave real (it's what you're testing) |
|---|---|
| Database and Supabase client calls | Business logic and rules |
| Outbound HTTP / third-party APIs | Pure functions and data transforms |
| File system access | Validation and parsing |
| Clock, randomness, UUIDs | Internal helpers |

If you find yourself mocking your own logic to make a test pass, the test is probably asserting the wrong layer.

## UI / widget tests

Web — query by accessible role/label rather than test IDs, so the test mirrors how users (and AT) reach controls:

```tsx
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

it('calls onSubmit with the entered title', async () => {
  const onSubmit = jest.fn();
  render(<TaskForm onSubmit={onSubmit} />);

  fireEvent.change(screen.getByRole('textbox', { name: /title/i }), {
    target: { value: 'New task' },
  });
  fireEvent.click(screen.getByRole('button', { name: /create/i }));

  await waitFor(() => expect(onSubmit).toHaveBeenCalledWith({ title: 'New task' }));
});

it('surfaces a validation message for an empty title', async () => {
  render(<TaskForm onSubmit={jest.fn()} />);
  fireEvent.click(screen.getByRole('button', { name: /create/i }));
  expect(await screen.findByText(/title is required/i)).toBeInTheDocument();
});
```

Flutter — pump the widget, drive it with the `WidgetTester`, and assert with finders:

```dart
testWidgets('calls onSubmit with the entered title', (tester) async {
  String? submitted;
  await tester.pumpWidget(MaterialApp(
    home: TaskForm(onSubmit: (t) => submitted = t),
  ));

  await tester.enterText(find.byKey(const Key('title')), 'New task');
  await tester.tap(find.text('Create'));
  await tester.pumpAndSettle();

  expect(submitted, 'New task');
});

testWidgets('surfaces a validation message for an empty title', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: TaskForm()));
  await tester.tap(find.text('Create'));
  await tester.pump();
  expect(find.text('Title is required'), findsOneWidget);
});
```

## API and integration tests

Exercise the route through the real stack, asserting status and shape together:

```typescript
import request from 'supertest';
import { app } from '../src/app';

describe('POST /api/tasks', () => {
  it('creates a task and returns 201', async () => {
    const res = await request(app)
      .post('/api/tasks')
      .set('Authorization', `Bearer ${token}`)
      .send({ title: 'Test task' })
      .expect(201);

    expect(res.body).toMatchObject({
      id: expect.any(String),
      title: 'Test task',
      status: 'pending',
    });
  });

  it('rejects a blank title with 422', async () => {
    const res = await request(app)
      .post('/api/tasks')
      .set('Authorization', `Bearer ${token}`)
      .send({ title: '' })
      .expect(422);

    expect(res.body.error.code).toBe('VALIDATION_ERROR');
  });

  it('refuses an unauthenticated request with 401', async () => {
    await request(app).post('/api/tasks').send({ title: 'x' }).expect(401);
  });
});
```

For Supabase-backed code, run integration tests against a local stack (`supabase start`) so RLS policies and SQL run for real, then reset state between tests.

## End-to-end tests

Drive the deployed UI as a user would. Keep these few and high-value — they're the slowest, flakiest layer.

```typescript
import { test, expect } from '@playwright/test';

test('a user can create then complete a task', async ({ page }) => {
  await page.goto('/');
  await page.getByLabel('Email').fill('user@example.com');
  await page.getByLabel('Password').fill('correct-horse');
  await page.getByRole('button', { name: 'Log in' }).click();

  await page.getByRole('button', { name: 'New task' }).click();
  await page.getByLabel('Title').fill('Water the plants');
  await page.getByRole('button', { name: 'Create' }).click();

  await expect(page.getByText('Water the plants')).toBeVisible();

  await page.getByRole('button', { name: 'Complete Water the plants' }).click();
  await expect(page.getByText('Water the plants'))
    .toHaveCSS('text-decoration-line', 'line-through');
});
```

(Flutter equivalent: `integration_test` package driven by `flutter test integration_test`.)

## Anti-patterns

| Anti-pattern | Why it bites | Do instead |
|---|---|---|
| Asserting on internals | Breaks on every refactor | Assert observable inputs → outputs |
| Snapshotting everything | Diffs get rubber-stamped | Assert the specific values that matter |
| Shared mutable fixtures | Tests leak into each other | Fresh setup/teardown per test |
| Testing library/framework code | Not your bug to find | Mock at that boundary |
| `skip`-ing tests to green CI | Hides real failures | Fix it or delete it |
| Permanent `it.skip` / `test.skip` | Dead, misleading code | Remove or repair |
| Vague catch-all assertions | Misses regressions | Pin down exact expectations |
| Forgetting to `await` | Errors get swallowed, false pass | Always await async work |
