---
name: api-versioning-and-evolution
description: Trigger when evolving a published API — adding fields, choosing a versioning strategy, deprecating endpoints, or keeping old clients alive through a breaking change.
---

# API Versioning and Evolution

A published API has clients you cannot redeploy. Your job is to ship change without breaking them, and to make breaking change rare, loud, and slow when it must happen.

## Step 0 — Classify the change first

Before touching code, decide which bucket the change falls in. This decision drives everything else.

| Change | Breaking? | Action |
|--------|-----------|--------|
| Add an optional response field | No | Ship it, no version bump |
| Add a new endpoint | No | Ship it |
| Add an optional request param with a safe default | No | Ship it |
| Add a new enum value | **Maybe** | Breaking if clients exhaustively match |
| Make an optional field required | Yes | New version or migration window |
| Rename / remove a field | Yes | Deprecate, don't delete |
| Change a field's type or units | Yes | New field, never mutate in place |
| Tighten validation on existing input | Yes | Old payloads must still pass |

Red flag: "it's just a small rename." Renames are always breaking on the wire. Add the new name, keep the old.

## Step 1 — Default to additive evolution

Most evolution needs no version at all. Follow the expand/contract pattern:

1. **Expand** — add the new field/endpoint alongside the old.
2. **Migrate** — move clients over (you control some, not all).
3. **Contract** — remove the old, but only after the deprecation window closes.

Hold expand and contract in *separate releases*. Never expand-and-contract in one deploy — that is a breaking change wearing a costume.

## Step 2 — Pick a versioning strategy only when forced

Reach for explicit versions only for genuinely breaking change you cannot avoid. Pick one axis and stay consistent:

- **URL path** (`/v1/orders`, `/v2/orders`) — most visible, easiest to route and cache, coarse-grained. Default choice for public REST.
- **Header** (`Accept: application/vnd.app.v2+json`) — clean URLs, harder to test by hand, easy to forget.
- **Query param** (`?version=2`) — avoid; pollutes caches and gets dropped by proxies.

Version the *contract*, not the implementation. `/v2` should mean a new shape, not "we rewrote the service."

Red flag: a new version per sprint. If you mint `/v3` casually, you now maintain three surfaces forever. Versions are expensive; additive change is cheap.

## Step 3 — Make new fields safe for old clients

The wire contract is the law. Design every change so an old client that ignores the new bits keeps working.

TypeScript (Supabase Edge Function response):

```ts
// SAFE: additive. Old clients read `total`; new ones also get `total_with_tax`.
type OrderResponseV1 = {
  id: string;
  total: number;          // existing — never change meaning/units
  total_with_tax?: number; // NEW, optional — old clients ignore it
};

// UNSAFE: changed units of an existing field. Old clients now read cents as dollars.
// total: number; // was dollars, now cents  ← DO NOT DO THIS
```

Rules for additive change:
- New fields are always optional with a sensible absent-state.
- Never repurpose an existing field's name, type, or units.
- Treat enums as open: clients must tolerate unknown values, servers must keep emitting known ones.

## Step 4 — Keep client parsers forward-compatible

Old-client survival is half server discipline, half client discipline. In Dart/Flutter, parse defensively so a server that adds fields never crashes the app:

```dart
factory Order.fromJson(Map<String, dynamic> json) => Order(
      id: json['id'] as String,
      total: (json['total'] as num).toDouble(),
      // Unknown future fields are simply ignored — no strict schema rejection.
      // New optional field tolerated whether present or null:
      totalWithTax: (json['total_with_tax'] as num?)?.toDouble(),
    );
```

Never ship a client that throws on unknown JSON keys. Forward compatibility is the contract you give your *future* server.

## Step 5 — Deprecate loudly, delete slowly

Removal is a process, not a commit. For each thing you retire:

1. **Announce** in a machine-readable way. On HTTP, send headers:
   ```
   Deprecation: true
   Sunset: Wed, 31 Dec 2026 23:59:59 GMT
   Link: <https://docs.example/migrate>; rel="deprecation"
   ```
2. **Measure** real usage before you set the sunset date. Log calls to the deprecated path with client id/version.
   ```sql
   select client_version, count(*) as hits, max(called_at) as last_seen
   from api_access_log
   where endpoint = '/v1/orders'
   group by client_version
   order by hits desc;
   ```
3. **Wait** through the published window. The clock starts when usage data says clients have a path off.
4. **Remove** only after traffic to the old surface drops to a known, accepted floor.

Decision point: do not pick a sunset date from a calendar. Pick it from the usage curve.

## Step 6 — Treat the database as its own versioned API

In a Supabase stack the schema is an API too. Apply the same expand/contract discipline to migrations:

- Add nullable columns; backfill; then enforce `NOT NULL` in a later migration — never in the same one.
- Add a new column rather than altering a column's type in place.
- Keep a compatibility view if a rename is unavoidable, so old queries still resolve.

```sql
-- Migration 1 (expand): add, allow null, backfill.
alter table orders add column total_cents bigint;
update orders set total_cents = round(total * 100);

-- Migration 2 (contract, separate release, after readers updated):
alter table orders alter column total_cents set not null;
-- drop old column only once nothing reads `total`
```

See [[octopus-model]] for data-layer modeling conventions that keep these migrations clean.

## Step 7 — Lock the contract with tests

A version you cannot prove is a version you will break by accident.

- **Contract/snapshot tests** on serialized response shapes — diffing the JSON catches accidental breaking changes in review.
- **Old-client fixtures**: keep a saved v1 request/response pair and assert it still round-trips after every change.
- **Regenerate types** from the source of truth (e.g. `generate_typescript_types` from Supabase) so client and server cannot drift silently.

CI red flag: a schema snapshot diff in a PR with no version bump and no deprecation note. Block it.

## Quick red-flag scan

- Field renamed or removed with no deprecation window.
- Existing field's type or units changed in place.
- New version cut for a change that was actually additive.
- `NOT NULL` / required added in the same release that introduced the field.
- Client that hard-fails on unknown JSON keys.
- Sunset date chosen before measuring real client usage.
- Three live major versions with no plan to retire any.

## Shipping

Stage evolution across releases (expand, then contract) and write the migration note in the deprecation comment so reviewers see the timeline. Follow [[commit-pipeline]] for the commit message format.
