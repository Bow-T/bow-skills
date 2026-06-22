---
name: content-moderation-and-trust-safety
description: Triggers when handling user-generated content at scale — classifier and human-review pipelines, CSAM/illegal-content handling and reporting, appeals, reviewer tooling, and policy enforcement workflows.
---

# Content Moderation and Trust & Safety

User-generated content (UGC) is a liability surface, not just a feature. The job is to
catch policy-violating and illegal content fast, without burying reviewers, blocking
legitimate users, or mishandling evidence. Build the pipeline around **graded confidence**,
**reversibility**, and **auditability**.

## Step 0 — Decide what you are even moderating

Before code, write the policy taxonomy. Moderation without a written policy is just vibes.

- **Tier the categories by legal exposure.** Separate *illegal* (CSAM, terrorism content,
  non-consensual intimate imagery, credible threats) from *policy-violating but legal*
  (spam, harassment, nudity, self-harm) from *quality* (off-topic, low effort). Each tier
  has a different latency budget, escalation path, and retention rule.
- **Define the action ladder per category**: allow → label/warn → reduce reach → quarantine
  (hide pending review) → remove → ban actor → legal report. Pick the *least* irreversible
  action that contains the harm.
- **Never auto-delete the illegal tier.** It must be preserved as evidence and reported, not
  wiped. Deletion destroys what authorities need.

## Step 1 — Ingest with a graded verdict, never a boolean

A classifier returning `is_bad: true` is a trap. Capture a **score per category** plus the
deciding signal so humans and appeals have something to reason about.

```ts
type ModerationVerdict = {
  contentId: string;
  scores: Record<PolicyCategory, number>; // 0..1 per category
  decidedAction: 'allow' | 'label' | 'limit' | 'quarantine' | 'remove' | 'escalate';
  decidedBy: 'auto' | 'human' | 'rule';
  signals: string[];        // e.g. ['hash_match:known_csam', 'model:nsfw=0.93']
  modelVersion: string;     // pin so you can re-evaluate after a model change
  decidedAt: string;        // ISO timestamp
};
```

Persist every verdict immutably. When the policy or model changes you must be able to
answer "why was this removed in March" with the model version and thresholds *as they were
then*, not as they are now.

## Step 2 — Run the cheap, certain checks first

Order detectors by cost and certainty. Stop early on a hard match.

1. **Hash matching against known-bad lists** (perceptual hashes for images/video, exact
   hashes for files). A hash hit on the illegal tier is high-certainty — quarantine
   immediately, do not wait for a model.
2. **Deterministic rules** — banned-link domains, repeated-poster spam patterns, leaked-key
   regexes. Fast and explainable.
3. **ML classifiers** — text, image, audio. These produce *scores*, never final removals on
   the illegal tier by themselves; they route to humans.

Run untrusted media in an isolated worker (a Supabase Edge Function or a sandboxed job), not
inline in the request path. Decoding attacker-supplied media in your main process is a
remote-code-execution vector — see [[security-and-hardening]].

## Step 3 — Threshold into three bands, not two

Single-threshold systems either over-remove or leak. Use two thresholds per category:

- **score ≥ high** → auto-action (quarantine/limit) and queue for *audit* (sampled human check).
- **low ≤ score < high** → route to human review queue; content stays in its current state
  (or soft-limited) until a human rules.
- **score < low** → allow, but log for drift analysis.

Set thresholds from a labelled validation set, optimising for the cost asymmetry of your
domain: a missed CSAM image is catastrophic; a wrongly hidden meme is annoying. Bias the
illegal tier hard toward recall and route the borderline to humans.

## Step 4 — Build the review queue as a real system

The queue is where throughput and reviewer wellbeing are won or lost.

- **Prioritise by harm × reach × age.** A threat on a viral post outranks borderline nudity
  on a post with two views. Compute a priority score; don't serve FIFO.
- **Deduplicate.** Cluster near-identical reports/items so one decision applies to the whole
  cluster. One reviewer action on a hash-cluster should resolve every copy.
- **Lease items, don't assign permanently.** A reviewer claims an item with a short TTL lease;
  if they go idle it returns to the queue. Prevents work vanishing into a closed tab.
- **Hide reviewer identity from the actor and vice versa** in the data model, so a decision
  can never leak who reviewed it.

```sql
-- Lease the next item atomically so two reviewers never grab the same one
update review_items
set leased_by = $reviewer, leased_until = now() + interval '10 minutes'
where id = (
  select id from review_items
  where status = 'pending' and (leased_until is null or leased_until < now())
  order by priority desc, created_at asc
  limit 1
  for update skip locked
)
returning *;
```

Enforce row-level access so a reviewer only sees items in queues their role permits, and so
raw illegal-tier media is gated behind a separate, more restricted role.

## Step 5 — Protect reviewers handling the worst content

This is a moderation-specific duty, not a nicety.

- **Blur/grayscale by default**, click-to-reveal, audio muted. Reduces unavoidable exposure.
- **Cap exposure** — limit consecutive illegal-tier items per session; rotate reviewers off it.
- For the illegal tier, prefer routing to **hash-and-report flows** that minimise human eyes:
  if a hash already confirms it, a reviewer confirms metadata rather than re-viewing.

## Step 6 — Handle the illegal tier as a legal evidence pipeline

Get this wrong and you create criminal liability.

- **Preserve, don't delete.** Move the content and its full context to a sealed,
  access-logged store. Record who accessed it and when.
- **Report to the relevant authority/clearinghouse** within the required window. Encode the
  obligation as a tracked task with a deadline, not tribal knowledge.
- **Minimise propagation.** Never copy the media into logs, analytics events, chat tools, or
  ticket attachments. Reference it by id; access it only through the gated store.
- **Suspend the actor and freeze associated content** pending the report, but keep that frozen
  data intact.

## Step 7 — Make every action appealable and reversible

Enforcement without appeal generates false-positive damage you can't undo.

- Record the **reason code** and the human-readable explanation sent to the user. "Removed
  for violating X" beats a silent disappearance.
- Build an **appeal queue** routed to a *different* reviewer than the original decision, with
  the original verdict and signals visible.
- Make actions reversible: prefer `status = quarantined` over a hard delete for the
  legal-but-policy tiers, so an overturned appeal restores instantly.
- On overturn, **feed the case back as a labelled example** to recalibrate thresholds.

## Step 8 — Measure the system, not just the model

Track, per category and over time:

- **Precision/recall on a human-labelled audit sample** — not on the model's own scores.
- **Appeal overturn rate** — high overturns mean your thresholds or policy are wrong.
- **Time-to-action** for the illegal tier (must meet your legal SLA) vs other tiers.
- **Reviewer agreement rate** — low agreement means the policy is ambiguous; fix the policy,
  not the reviewers.
- **Prevalence** — fraction of *all* content that is violating, sampled blindly. This catches
  what your classifiers never flagged.

Watch for **model drift**: when a new model version ships, re-score a frozen benchmark set and
compare action distributions before rolling out. Roll out behind a flag so you can revert —
see [[feature-flags-and-progressive-delivery]].

## Anti-patterns

- Storing a single `is_flagged` boolean with no score, category, or model version.
- Auto-deleting illegal-tier content instead of preserving and reporting it.
- One shared review queue with no prioritisation, so urgent threats sit behind spam.
- Copying flagged media into logs, analytics, or support tickets.
- No appeals path, or appeals reviewed by the same person who made the call.
- Tuning thresholds against the classifier's own output instead of human labels.
- Decoding untrusted media in the request path instead of an isolated sandbox.

When committing changes to this pipeline, follow [[commit-pipeline]]. Treat the data model
and access rules as security-sensitive — review with [[threat-modeling]] and
[[authn-authz-design]] before shipping.
