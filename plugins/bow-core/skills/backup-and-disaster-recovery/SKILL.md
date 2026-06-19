---
name: backup-and-disaster-recovery
description: Triggers when defining backup policy, setting RPO/RTO targets, testing restores, planning failover or replication, or preparing for region loss and data-corruption events.
---

# Backup and Disaster Recovery

A backup you have never restored is a rumor. Design for the restore, not the dump.

## 1. Frame the failure modes first

Do not start with "back up the database." Start with what can go wrong, because each mode needs a different defense:

- **Accidental deletion / bad migration** — needs point-in-time recovery (PITR), short RPO.
- **Data corruption (logical)** — silent bad writes propagate to replicas instantly; replicas DO NOT save you. Needs immutable, time-separated snapshots.
- **Region / provider outage** — needs cross-region copies and a documented failover.
- **Ransomware / credential compromise** — needs offline or write-once (immutable) copies your prod credentials cannot delete.

Red flag: a "backup strategy" that only covers hardware failure. That is the easy 10%.

## 2. Set RPO and RTO as numbers, per data class

- **RPO** (Recovery Point Objective): max acceptable data loss, in time.
- **RTO** (Recovery Time Objective): max acceptable downtime to restore.

Tighter targets cost more — pick per data class, not one number for everything.

| Data class | Example | RPO | RTO | Mechanism |
|---|---|---|---|---|
| Transactional core | orders, auth | <= 5 min | <= 1 h | PITR + warm standby |
| User content | uploads, media | <= 1 h | <= 4 h | Versioned object store, cross-region |
| Derived / cache | search index | n/a | rebuild | Regenerate from source |
| Analytics | event logs | <= 24 h | <= 24 h | Daily snapshot |

Decision point: if a dataset can be **regenerated** from another source, do not back it up — script the rebuild and test that instead. Backing up derived data is wasted RPO.

## 3. Enforce the 3-2-1 rule and time separation

- **3** copies, **2** distinct media/locations, **1** off-site/off-account.
- At least one copy must be **immutable** or in a separate account/region the app credentials cannot reach.

Time separation matters because corruption is fast. Keep a tiered ladder so a bad write discovered late is still recoverable:

```
PITR window:     last 7 days  (catches "oops, ran DELETE without WHERE")
Daily snapshot:  last 30 days (catches corruption found within a month)
Monthly:         last 12 mo   (compliance / slow-burn discovery)
```

## 4. Configure the data store (Supabase / Postgres)

Enable PITR — daily-only dumps give a 24h RPO at best:

```sql
-- verify WAL archiving / PITR is actually on, not just assumed
select name, setting from pg_settings where name in ('archive_mode','wal_level');
```

Take an out-of-platform logical dump on a schedule so a single-vendor failure (account lockout, billing lapse) cannot strand you:

```bash
# nightly, encrypted, off-account. Fails loud on non-zero exit.
set -euo pipefail
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
pg_dump --format=custom --no-owner "$DATABASE_URL" \
  | age -r "$BACKUP_PUBLIC_KEY" \
  | aws s3 cp - "s3://backups-cold/db/${STAMP}.dump.age" \
      --storage-class GLACIER_IR
```

For object storage (user uploads): enable **bucket versioning** and a separate-account replication rule. Versioning is what turns "file overwritten by a bug" from a loss into an undo.

## 5. Protect the application layer

- **Schema/migrations** live in version control — see [[commit-pipeline]]. The DB schema is reproducible code, not a backup artifact.
- **Edge functions / serverless** are redeployable from source; back up the source, not the runtime.
- **Secrets** are NOT in DB backups. Store them in a managed secret manager with its own versioned recovery, or you will restore data you cannot decrypt.

Red flag: backups encrypted with a key that lives only in the same account being backed up. Escrow the recovery key separately.

## 6. Test restores on a schedule (this is the whole point)

A restore drill is the only proof. Automate it; run at least monthly and after any schema change.

```bash
# restore into a throwaway DB, then assert integrity — not just "it ran"
createdb dr_verify
aws s3 cp "s3://backups-cold/db/${TARGET}.dump.age" - \
  | age -d -i "$RECOVERY_KEY" \
  | pg_restore --dbname=dr_verify --no-owner

psql dr_verify -c "select count(*) from orders;" \
  | grep -qE '[1-9]' || { echo "RESTORE EMPTY — FAIL"; exit 1; }
dropdb dr_verify
```

Restore checklist:
- Time the full run; compare to RTO. If it exceeds RTO, the strategy has already failed.
- Verify row counts and a few business invariants, not just that the command exited 0.
- Restore from the **oldest** retained copy too — old backups silently rot or use a format your tooling no longer reads.

For a Flutter client, keep a tested re-sync path: on restore, the server's logical clock or row versions may move backward, so clients must reconcile rather than trust local cache.

```dart
// after a server restore, force clients to reconcile from source of truth
Future<void> reconcileAfterRestore(int serverEpoch) async {
  final localEpoch = await store.readInt('serverEpoch') ?? 0;
  if (serverEpoch != localEpoch) {
    await store.clearMutableCache();      // drop stale optimistic state
    await syncEngine.fullPull();          // re-pull authoritative rows
    await store.writeInt('serverEpoch', serverEpoch);
  }
}
```

## 7. Plan failover and replication deliberately

- **Replication keeps you available; it does not keep you safe.** A logical corruption or `DROP TABLE` replicates in milliseconds. Always pair replicas with time-separated snapshots.
- Decide and write down: **automatic** failover (fast, risks split-brain and flapping) vs **manual promotion** (slower, deliberate). For most teams, manual promotion with a runbook beats fragile automation.
- Document the exact promotion steps, DNS/connection-string cutover, and the rollback. A runbook discovered during the outage is not a runbook.

## 8. Plan for region loss

```
Detect  -> declare incident, freeze writes to dying region
Promote -> bring standby in healthy region to primary (PITR if standby suspect)
Cutover -> repoint connection strings / DNS; rotate any region-pinned secrets
Verify  -> run the restore-integrity assertions before reopening writes
Reopen  -> lift write freeze, monitor error + lag dashboards
```

Test this end-to-end at least quarterly in a staging copy. Record the measured RTO and compare to target.

## 9. Guardrails

- **Monitor backup success and freshness**, and alert on the *absence* of a recent successful backup, not only on failures. A cron that silently stopped looks identical to "no news."
- Track restore-drill recency as a metric; if the last successful drill is older than your test interval, that is a paging-level alert.
- Never let the same credential both write production and delete backups.
- Keep retention and deletion of personal data consistent with your data-handling policy — see [[data-privacy-and-compliance]] before setting long retention windows.

## Quick red-flag scan
- No PITR; only nightly dumps. (RPO is silently 24h.)
- Replicas treated as backups.
- Backups never restored, or only the newest one ever tested.
- Recovery key co-located with the data it protects.
- No measured RTO — only a hoped-for one.
