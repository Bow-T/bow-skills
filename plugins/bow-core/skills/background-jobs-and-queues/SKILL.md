---
name: background-jobs-and-queues
description: Trigger when offloading work to async jobs — designing a queue/worker, scheduling, retries, dead-letter handling, visibility timeouts, or preventing job pileups.
---

# Background Jobs & Queues

A process for moving work off the request path without losing, duplicating, or piling up jobs.

## 0. First decide: do you even need a queue?

Reach for async only when one is true:

- The work is slow (> ~1s) and the caller should not wait (emails, image transforms, exports).
- The work may fail transiently and you want retries decoupled from the user.
- You need to smooth bursts so a downstream system is not flooded.

If none hold, run it inline. A queue you do not need is a second database to operate.

## 1. Pick the substrate

| Need | Use |
|------|-----|
| Already on Supabase/Postgres, modest throughput | Postgres table as queue (`SKIP LOCKED`) or `pgmq` extension |
| Time-based triggers | `pg_cron` / scheduled edge functions |
| High throughput, multiple consumers, fan-out | Dedicated broker (SQS, Redis streams, etc.) |
| Just defer one thing after a write | A trigger that enqueues a row |

Default for this stack: **Postgres-backed queue**. One less system, transactional enqueue with the data change, easy to inspect.

## 2. Design the job record before the worker

Every job row carries its own state machine. Minimum columns:

```sql
create table jobs (
  id            bigint generated always as identity primary key,
  kind          text not null,              -- 'send_email', 'resize_image'
  payload       jsonb not null,
  status        text not null default 'queued', -- queued|running|done|failed|dead
  attempts      int  not null default 0,
  max_attempts  int  not null default 5,
  run_at        timestamptz not null default now(), -- for delay/backoff
  locked_at     timestamptz,               -- visibility timeout marker
  last_error    text,
  created_at    timestamptz not null default now()
);
create index on jobs (status, run_at);
```

Decision points:

- **Idempotency key** — add a unique column (e.g. `dedupe_key`) when the same logical job must not enqueue twice. Enqueue with `on conflict do nothing`.
- **Payload is data, not pointers** — store enough to run the job; do not assume related rows still exist at run time. But keep it small; reference large blobs by id.

## 3. Claim work atomically (no double-processing)

The whole correctness story is one query. Use `FOR UPDATE SKIP LOCKED` so concurrent workers never grab the same row:

```sql
update jobs
set status = 'running', locked_at = now(), attempts = attempts + 1
where id = (
  select id from jobs
  where status = 'queued' and run_at <= now()
  order by run_at
  for update skip locked
  limit 1
)
returning *;
```

Red flag: a "pick next job" query without `SKIP LOCKED` or without atomic status flip. Two workers will run the same job.

## 4. Build the worker loop with the right guarantee

Choose **at-least-once** (default) — jobs may run more than once, so **handlers must be idempotent**. At-most-once loses work on crash; rarely what you want.

```ts
async function runOnce() {
  const job = await claimJob();          // the SKIP LOCKED update above
  if (!job) return false;
  try {
    await handlers[job.kind](job.payload);
    await markDone(job.id);
  } catch (err) {
    await handleFailure(job, err);
  }
  return true;
}
```

Make every handler idempotent: upsert instead of insert, check "already sent?" before sending, use the external provider's idempotency key.

## 5. Visibility timeout — reclaim stuck jobs

A worker that crashes mid-job leaves a row stuck in `running`. A reaper returns timed-out jobs to `queued`:

```sql
update jobs
set status = 'queued', last_error = 'reclaimed: visibility timeout'
where status = 'running'
  and locked_at < now() - interval '5 minutes';
```

Set the timeout to comfortably exceed the slowest legitimate run. Too short → you reprocess in-flight jobs (relies on idempotency); too long → failures sit invisible.

## 6. Retries with backoff + jitter

Never retry instantly in a tight loop — you hammer a struggling dependency.

```ts
async function handleFailure(job, err) {
  if (job.attempts >= job.max_attempts) return moveToDead(job, err);
  const base = Math.min(2 ** job.attempts, 300);      // exponential, capped
  const delay = base * (0.5 + Math.random());          // jitter
  await reschedule(job.id, delay, String(err));        // status=queued, run_at=now()+delay
}
```

Decision: distinguish **retryable** (timeout, 429, 5xx) from **permanent** (validation error, 4xx, missing record) failures. Send permanent failures straight to dead — retrying them just burns attempts.

## 7. Dead-letter handling

`status = 'dead'` is not the end — it is a queue you must watch.

- Alert when `dead` count crosses a threshold; a silent DLQ is a silent outage.
- Keep `last_error` and full payload so a human can diagnose and replay.
- Provide a requeue path: reset `status='queued', attempts=0, run_at=now()`.

## 8. Prevent pileups

The failure mode that pages you at 3am: producers outrun consumers.

- **Watch queue depth and oldest `run_at`**, not just throughput. Rising lag = losing.
- **Cap concurrency** per job kind so one slow kind cannot starve others (separate worker pools or a per-kind in-flight limit).
- **Shed or coalesce** when flooded: collapse duplicate jobs via `dedupe_key`; drop stale jobs whose result no longer matters (e.g. an outdated cache-warm).
- **Backpressure the producer** if the queue is the bottleneck — return 429 rather than enqueue infinitely.

## 9. Scheduling recurring work

Use `pg_cron` or a scheduled function to **enqueue** jobs, not to do the work:

```sql
select cron.schedule('nightly-digest', '0 3 * * *', $$
  insert into jobs (kind, payload)
  select 'send_digest', jsonb_build_object('user_id', id) from users where digest_opt_in;
$$);
```

The scheduler fans out rows; the normal worker drains them. This keeps scheduled work retryable and observable like everything else. Guard against overlap: if a run can exceed its interval, skip when the prior batch is unfinished.

## Flutter / client note

The client never runs the job — it enqueues and observes. Insert via the Supabase client (or call an edge function), then subscribe to the job row's `status` for progress. Do not poll the client into a busy loop; use realtime or a single status check on resume.

## Red flags checklist

- Claiming jobs without `SKIP LOCKED` + atomic status flip.
- Handlers that are not idempotent under at-least-once delivery.
- Retries with no cap, no backoff, or no jitter.
- No visibility timeout → crashed workers strand jobs forever.
- A dead-letter state nobody monitors or can replay.
- Alerting on throughput but not on **lag / queue depth**.
- The scheduler doing the work instead of enqueueing it.

## Related

- [[octopus-model]] for shaping the job/payload data layer.
- Defer all commit and branching conventions to [[commit-pipeline]].
