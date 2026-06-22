---
name: audit-logging-and-tamper-evidence
description: Triggers when building an audit trail that must survive scrutiny — append-only immutable records, hash chaining or Merkle proofs, who-did-what-when capture, retention and legal hold, and detecting after-the-fact tampering.
---

# Audit Logging and Tamper Evidence

An audit log that an administrator can silently edit is theater. The goal is not
"we write events somewhere" — it is "we can prove to an auditor that no one
altered, deleted, or back-dated an event, including the people who run the
database." Build for the day someone disputes a record, not the happy path.

## First, separate audit logs from everything else

Three different things get conflated; keep them apart:

- **Audit log** — security/compliance evidence: who did what to what, when, from
  where. Legally meaningful. This skill.
- **Application log** — debugging breadcrumbs. Lossy, sampled, short-lived. See
  [[logging-hygiene]].
- **Telemetry/metrics** — operational signals. See [[observability-and-instrumentation]].

Never multiplex them into one stream. Audit events have stricter durability,
immutability, retention, and access rules. If you `console.log` an audit event
and call it done, you have no audit trail.

## Decide what is an audit-worthy event

Capture every action that changes authority, data, or money, plus reads of
sensitive data when regulation demands it. Concretely:

- Authentication and session lifecycle: login, logout, MFA, failed attempts,
  token issue/revoke.
- Authorization changes: role grants, permission edits, ownership transfer —
  pair with [[authn-authz-design]].
- Data mutations on regulated entities: PII, PHI, financial records, consent.
- Sensitive reads/exports when the regime (HIPAA, GDPR access logs) requires it.
- Privileged/admin operations: impersonation, config changes, retention edits,
  log access itself. Auditing the auditors is mandatory.

Do **not** dump every CRUD row blindly — noise hides the event that matters and
inflates retention cost. Define the set deliberately.

## The canonical event shape

Make every event answer who / did-what / to-what / when / from-where / result.
Use a stable, versioned schema:

```ts
interface AuditEvent {
  id: string;            // ULID — monotonic, sortable, no PK guessing
  schemaVersion: number; // bump when shape changes; never reinterpret old rows
  occurredAt: string;    // ISO-8601 UTC, from a trusted clock, not the client
  actor: {               // WHO — resolved identity, not just a display name
    id: string; type: 'user' | 'service' | 'system';
    onBehalfOf?: string; // impersonation: real admin AND target subject
  };
  action: string;        // verb.noun, e.g. 'grant.role', 'export.report'
  target: { type: string; id: string };
  outcome: 'success' | 'failure' | 'denied';
  reason?: string;       // why denied/failed — auditors ask
  context: {             // WHERE — ip, userAgent, requestId, sessionId
    ip?: string; requestId: string; tenantId?: string;
  };
  before?: unknown;      // redacted prior state for mutations
  after?: unknown;       // redacted new state
}
```

Resolve `actor.id` server-side from the authenticated principal — never trust a
client-supplied "user" field. Capture impersonation explicitly: both the
operator and the subject, or you cannot answer "who really did this."

## Make it append-only at the storage layer

Application-level "we only insert" is not enough; enforce it where the data lives.

In Supabase/Postgres:

- Grant the writer role `INSERT` only — revoke `UPDATE` and `DELETE` on the audit
  table. Add a `BEFORE UPDATE OR DELETE` trigger that `RAISE EXCEPTION`s so even
  a superuser script trips on it.
- Turn on RLS: a deny-all policy plus a narrow insert policy. The app reads audit
  data through a separate read-only role or view. See [[supabase-security-review]].
- Prefer storage that supports retention locks / WORM (object-lock buckets,
  ledger databases). Database immutability protects against the app; WORM
  protects against someone with database credentials.

The honest threat model: a DBA with full access can still `DROP TABLE`. You
cannot prevent that with permissions alone — which is why you also need the next
section.

## Chain events so tampering becomes detectable

You cannot stop a determined admin from editing rows, but you can make any edit
**provable after the fact**. Hash-chain each event to its predecessor:

```ts
// hash = H( prevHash || canonical(event) )
import { createHash } from 'node:crypto';

function chainHash(prevHash: string, event: AuditEvent): string {
  const canonical = JSON.stringify(event, Object.keys(event).sort());
  return createHash('sha256')
    .update(prevHash).update('\n').update(canonical)
    .digest('hex');
}
```

Store `prevHash` and `hash` per row. Verification walks the chain: recompute each
hash; a single altered, inserted, or deleted row breaks every hash downstream.
Pitfalls that silently void the chain:

- **Non-deterministic serialization.** Sort keys, fix number/date formats, pin
  encoding. If canonicalization drifts, honest rows fail verification.
- **Concurrent writers racing on `prevHash`.** Serialize the tail — append inside
  a transaction that locks the chain head (advisory lock or single-writer
  partition per tenant), or hashes will fork.
- **Per-tenant chains** keep one noisy tenant from blocking another; verify each
  independently.

For high volume, batch events into a **Merkle tree** per interval and chain the
roots instead of every row — verification then needs only a logarithmic proof
path, not the whole stream.

## Anchor the chain outside your own control

A chain you compute and store yourself proves nothing if the attacker controls
both. Periodically **anchor** the latest hash where you cannot rewrite it:

- Publish the head hash to append-only external storage (WORM bucket, a different
  account/region, a notary service, or a managed ledger).
- Optionally sign each anchor with a key held off the primary system (KMS/HSM) so
  the timestamp and value are attestable.
- Anchor on a fixed cadence (e.g. hourly) so the tamper-detection window is
  bounded and known.

Now a forger must rewrite history *and* every published anchor since — across
systems they don't fully control.

## Capture without breaking the request path

Auditing must not be skippable, but must not take the app down either.

- **Write in the same transaction as the change it records** when atomicity
  matters: if the business write commits but the audit insert is lost, you have a
  silent gap. Co-committing prevents that.
- For throughput, write to a durable append-only buffer (outbox table, durable
  queue) and chain asynchronously — but the *capture* must be synchronous and
  fail-closed. Dropping an audit event silently is worse than a slow request.
- Never let audit failure be swallowed by a bare `catch`. Decide explicitly:
  block the action, or alert loudly. See [[resilience-and-fault-tolerance]].

## Redact, but keep the evidence intact

Audit logs attract the worst secret leaks because they record `before`/`after`.

- Strip credentials, tokens, full card/SSN — store a stable hash or last-4 so you
  can still prove *which* value without exposing it.
- Redaction must be deterministic and applied **before** hashing, so the chain
  covers exactly what you stored. Coordinate with [[secrets-and-config-management]].
- Right-to-erasure (GDPR) vs immutability: don't delete the row. Tombstone the
  PII payload (replace with a redaction marker), keep the event metadata and
  hash, and record the erasure itself as an audit event.

## Retention, legal hold, and disposal

- Set a retention period per regime (often years for financial/health data) and
  enforce it; over-retention is its own liability.
- **Legal hold overrides retention** — a held record cannot be expired or
  deleted. Model hold as a flag the disposal job must check, and audit every
  hold placement and release.
- Disposal is a privileged, audited, reviewable action — never a silent cron
  `DELETE`. Tie expiry policy into [[backup-and-disaster-recovery]] so backups
  don't quietly resurrect purged data.

## Detect tampering before an auditor does

Run a scheduled verifier that re-walks the chain and confirms each row hashes,
the head matches the latest external anchor, and no ULID gaps exist in a
single-writer partition. Alert on the first mismatch — a broken chain is a
sev-class signal; route it through [[incident-response-and-postmortems]]. A
tamper-evident log nobody verifies is just a slower regular log.

## Before you ship, confirm

- A superuser `UPDATE` / `DELETE` on the audit table raises, and the verifier
  flags any out-of-band change.
- `actor`, `outcome`, `requestId`, and trusted `occurredAt` are present on every
  event; impersonation records both identities.
- The chain verifies end to end and the head matches an external anchor.
- No secrets or full PII sit in `before`/`after`; redaction runs before hashing.
- Legal hold blocks disposal; every hold and purge is itself audited.

When committing this work, follow [[commit-pipeline]].
