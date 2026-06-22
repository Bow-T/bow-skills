---
name: data-privacy-and-compliance
description: Trigger when handling PII/PHI, implementing GDPR/CCPA rights (deletion, export, consent), data retention, or building any system subject to regulatory data rules.
---

# Data Privacy and Compliance

A working process for shipping features that touch regulated personal data. Privacy is an architecture decision, not a checkbox at the end. Decide where data lives and how it leaves *before* you write the write path.

## Step 0 — Classify before you store

Tag every new column the moment you add it. If you cannot label it, you cannot govern it.

- **PII**: name, email, phone, IP, device id, precise location, government id.
- **PHI**: anything PII + health context (diagnosis, medication, appointment).
- **Sensitive**: race, religion, sexual orientation, biometrics, union membership — extra consent rules.
- **Derived**: an inference is regulated too (e.g. "likely pregnant" from purchases).

Encode the class in the schema so it is queryable, not tribal knowledge:

```sql
comment on column profiles.phone is 'pii:contact;retention:account_life;export:yes';
```

Red flag: a free-text `notes` / `metadata jsonb` column. Users paste their medical history there and it silently becomes PHI you cannot find.

## Step 1 — Data map (the single source of truth)

Maintain a machine-readable inventory. Every right you must honor reads from this.

```typescript
type DataAsset = {
  table: string;
  column: string;
  class: "pii" | "phi" | "sensitive" | "derived";
  lawfulBasis: "consent" | "contract" | "legitimate_interest";
  retention: string;       // ISO 8601 duration, e.g. "P30D"
  onErasure: "delete" | "anonymize" | "retain_legal";
  exportable: boolean;
};
```

Decision point — **delete vs anonymize vs retain**:
- Order rows tied to tax/financial law → `retain_legal` (you are *required* to keep them).
- Analytics events → `anonymize` (strip the user id, keep the aggregate).
- Everything else → `delete`.

## Step 2 — Consent before collection

Capture consent as an append-only event, never a mutable boolean. You must prove *what* was agreed and *when*.

```sql
create table consent_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id),
  purpose     text not null,          -- 'marketing_email', 'analytics'
  granted     boolean not null,
  policy_version text not null,        -- which notice they saw
  created_at  timestamptz not null default now()
);
```

Current state is a query (`distinct on (purpose) ... order by created_at desc`), not a column you overwrite. Withdrawal must be as easy as granting.

Red flags: pre-ticked boxes; bundling consent into the ToS; collecting first and asking later.

## Step 3 — Minimize and enforce at the boundary

- Collect the minimum field set the feature actually needs. Every extra field is future liability.
- Never log PII. Scrub at the logger, not the call site.

```dart
String redact(String raw) => raw
    .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '[email]')
    .replaceAll(RegExp(r'\b\d{10,}\b'), '[number]');
```

- Use Supabase **Row Level Security** as the default deny. A user reads only their own rows; cross-user access is an explicit, audited policy.

```sql
alter table profiles enable row level security;
create policy "own_profile" on profiles
  for select using (auth.uid() = id);
```

Red flag: the `service_role` key reachable from client code or an unauthenticated edge function. It bypasses RLS entirely.

## Step 4 — Right to access / export (data portability)

Build export off the data map so new tables are included automatically. Run it server-side with elevated privileges, verify identity first, and deliver via a short-lived signed URL — never email the payload.

```typescript
async function exportUserData(userId: string) {
  const bundle: Record<string, unknown[]> = {};
  for (const a of dataMap.filter(d => d.exportable)) {
    bundle[a.table] = await db.from(a.table)
      .select(a.column).eq("user_id", userId);
  }
  return bundle; // machine-readable JSON, structured, complete
}
```

Decision point: re-authenticate the requester (recent login or email-link confirm) before producing the bundle. Export is a data breach if it goes to the wrong person.

## Step 5 — Right to erasure (this is the hard one)

A `DELETE` from one table is almost never enough. Walk the full data map and apply each asset's `onErasure` policy in a single transaction.

```sql
create or replace function erase_user(target uuid)
returns void language plpgsql security definer as $$
begin
  -- delete: remove entirely
  delete from messages   where user_id = target;
  delete from profiles   where id      = target;
  -- anonymize: keep the row, sever the identity
  update analytics_events set user_id = null, ip = null where user_id = target;
  -- retain_legal: leave invoices untouched, log the exception
  insert into erasure_log(user_id, retained_tables, created_at)
    values (target, array['invoices'], now());
end; $$;
```

Then chase data **outside** Postgres — this is where erasure quietly fails:
- Storage buckets (avatars, uploads).
- Search indexes, caches, queues.
- Third-party processors (email, analytics, payments) — call their delete API; track each as a sub-task.
- Backups: you usually cannot surgically delete; document the rolling backup window and that restored data is re-erased.

Soft-delete first (`deleted_at`) for a grace window, then a scheduled hard-purge. Always emit an audit record proving the erasure ran.

## Step 6 — Retention as a scheduled job, not a promise

Retention only counts if something enforces it. Schedule purges from the data map durations.

```sql
delete from sessions where created_at < now() - interval '90 days';
```

Run via `pg_cron` or a scheduled edge function. Test it actually fires — an unenforced retention policy is worse than none because you stated it publicly.

## Step 7 — Cross-border and processors

- Know where rows physically sit (region of your Supabase project / storage).
- Every third party touching personal data is a sub-processor; keep the list current and ensure a transfer mechanism exists for cross-region flows.
- Vet new SDKs before adding them — an analytics tag can exfiltrate PII without a backend change.

## Breach reflex

Suspected breach → contain, assess scope from the data map (whose data, which classes), then notify within the legal window (often ~72h). You cannot scope a breach you cannot map — which is why Step 1 exists.

## Pre-merge checklist

- [ ] New columns classified + commented.
- [ ] Data map updated; export and erasure cover the new asset.
- [ ] RLS enabled; no `service_role` on the client path.
- [ ] No PII in logs or error payloads.
- [ ] Consent captured for any new purpose.
- [ ] Retention job covers new data.

See [[octopus-model]] for shaping the data layer these rules sit on. Commit per [[commit-pipeline]].
