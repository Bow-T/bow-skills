# Worked Ideation Sessions

These walkthroughs show the skill in motion across three kinds of ideas: a greenfield concept, a feature inside an existing product, and a non-product workflow change. Read for the rhythm — how the restatement shifts the frame, how questions diagnose before prescribing, how Phase 2 stays honest — as much as for the content.

---

## Session 1 — A vague greenfield concept (full three-phase run)

**User:** `/ideate I want to help freelance designers stop losing hours to invoicing and chasing payments`

### Phase 1 — Open up

**Skill:**

> **How might we** let solo designers get paid on time without turning admin into a second job?

That's wide. Three questions to narrow it:

1. **Which part hurts most** — creating invoices, tracking who owes what, or actually collecting late payments?
2. **Who is this for** — the designer, the client, or both sides?
3. **Constraint check** — software you'd build, a service, or something lighter?

**User:** "The designer. The real pain is chasing. Invoices go out fine, then clients ghost for weeks and I hate sending the awkward follow-up. Software, probably."

**Skill:**

So the problem isn't producing invoices — it's the **emotional cost of the follow-up**. The money exists; the designer just won't nag. That's the lever.

Six variations:

1. **Auto-nudge engine.** Once an invoice is sent, the system handles every reminder on a schedule — polite, escalating, in the designer's voice. The designer never sends the awkward message because a system does. Bet: most late payments are forgetfulness, and a neutral automated nudge collects them without friction.

2. **Invert it — make the client want to pay early.** Offer a small "thanks for paying within 5 days" discount, surfaced right in the invoice. Reframe collection as a carrot, not a stick. Bet: a tiny incentive beats any reminder.

3. **Drop the constraint — remove the invoice entirely.** Milestone-based escrow: client funds the project up front, money releases as work is approved. No chasing because the cash is already held. Bet: clients will pre-fund if it feels safe and fair.

4. **Merge — invoicing + a payment page that does the social work.** The follow-up isn't a DM; it's a shared status link the client already has open. "Paid / Pending / Overdue" visible to both. Bet: visibility shames gently without the designer saying a word.

5. **Swap audience — build for the client's accounts payable.** Many late payments are a client-side process problem, not malice. A tool that slots into how the client already pays vendors. Bet: friction is on their end.

6. **Insider lens — what experienced freelancers actually do.** The pros front-load it: deposit before starting, clear net-7 terms in the contract, work paused on overdue. The tool that wins might enforce *terms*, not chase *invoices*.

Variations 1 and 4 together are interesting: automate the nudging and make the status do the nagging. Which directions pull at you?

### Phase 2 — Narrow down

**User:** "1 and 4 feel right. 3 (escrow) is appealing but heavy. Let me look at 1+4 combined."

**Skill:**

Good. The fused thesis: **the designer never has to chase, because automated reminders and a visible shared status do it for them.** Stress-testing it.

**Direction A — "Quiet Collector" (1 + 4 fused).** Invoice goes out, system runs the reminder cadence, and both sides watch a shared Paid/Pending/Overdue link.

- **Value:** high and emotional. You're removing a task people actively dread, not just saving minutes. The pain is described with feeling — a strong painkiller signal.
- **Feasibility:** medium. Payment rails and scheduled reminders are commodity (Stripe handles the money; a Supabase scheduled function plus an email/SMS provider handles cadence). The hard part is tone — reminders that don't read as robotic or hostile.
- **Differentiation:** medium-high. Plenty of tools invoice; few are built specifically around removing the human follow-up. Narrow enough that the big invoicing suites won't bother, which is the wedge.
- **Assumptions:**
  - Automated reminders collect as well as a personal nudge (most likely to be wrong).
  - Designers trust a system to message clients in their name.
  - A visible status link motivates rather than annoys clients.
- **What kills it:** if clients ignore automated reminders the same way they ignore the manual ones, you've automated a thing that didn't work.

**Direction B — "Terms Enforcer" (variation 6).** Deposit up front, net terms in the contract, work auto-paused when overdue.

- **Value:** high ceiling — it prevents the problem instead of managing it.
- **Feasibility:** lower. It changes the designer's *sales process*, not just their tooling. Harder adoption.
- **Differentiation:** high, but it asks the user to behave differently, which is the steepest adoption hill there is.
- **What kills it:** designers won't risk losing a client by demanding deposits, so they never turn the feature on.

**Honest read:** Direction A is the sharper first bet — it fits existing behavior and just removes the dread. The riskiest assumption is whether automated nudges actually collect; test that before building the rest. I want to push back on one thing: don't bundle escrow in "to be safe." If A works, escrow is a later upsell. If you build escrow first, you're a heavy product nobody finishes onboarding into.

### Phase 3 — Commit

```markdown
# Quiet Collector: Get Paid Without the Chase

## Problem Statement
How might we get freelance designers paid on time without making them send the follow-up messages they dread?

## Chosen Direction
Build a reminder-and-status layer on top of invoicing, not a full accounting suite. One job: the designer never personally chases a payment again. Automated, voice-matched reminders run on a cadence, and a shared Paid/Pending/Overdue link does the social nudging.

The insight is that the money usually exists — the blocker is the designer's reluctance to nag. Removing the human from the loop is the whole product. Stripe handles funds; a scheduled Supabase function plus an email/SMS provider runs the cadence; a TypeScript edge function exposes the shared status page.

## Assumptions to Validate
- [ ] Automated reminders collect as well as a manual nudge — run 10 designers, ~50 invoices, compare collection time against their prior baseline over 6 weeks.
- [ ] Designers will let a system message clients in their name — interview 10, show a sample cadence, ask if they'd switch it on.
- [ ] A shared status link motivates payment without souring the relationship — A/B reminder-only vs. reminder + status link.

## MVP Scope
- Connect Stripe, send an invoice, attach a shared status link.
- Configurable reminder cadence (default: day 3, day 7, day 14), editable copy.
- Reminders sent via email; SMS later.
- Paid/Pending/Overdue status page (TypeScript edge function + Supabase row).
- No accounting, no expense tracking, no escrow in v1.

## Not Doing (and Why)
- **Escrow / milestone funding** — heavy, changes the sales process; revisit only if reminders prove insufficient.
- **Full accounting / expenses** — commodity, and not the dreaded part. Stay narrow.
- **Multi-currency, tax handling** — premature; validate the core loop in one currency first.
- **A client-facing mobile app** — a link in an email is lower friction than an install.

## Open Questions
- What's the compliance landscape for automated payment-reminder messaging?
- Default cadence tone — how firm before it backfires?
- Pricing: per-invoice fee, flat monthly, or a cut of collected late payments?
```

---

## Session 2 — A feature inside an existing product (codebase-aware)

**User:** `/ideate add offline support to our Flutter field-inspection app`

### Phase 1 — Open up

**Skill:**

> **How might we** let inspectors keep working with no signal, and have everything sync cleanly once they're back online?

I scanned the repo: it's Flutter on the client, talking to Supabase over the REST/PostgREST client, with no local persistence layer today — every read hits the network (`lib/data/inspection_repository.dart`). That matters. Three questions:

1. **What must work offline** — viewing assigned inspections, or also creating/editing them in the field?
2. **How long offline** — minutes between cell towers, or whole days in a basement?
3. **What's driving this now** — inspectors complaining, lost data, or a sales requirement?

**User:** "Creating and editing in the field, often for a full day underground. Inspectors are losing reports when the app can't save."

**Skill:**

"Losing reports" is the real signal — this is data-integrity, not convenience. The bar is higher: anything entered offline must be durable locally before sync, or you've just moved where data gets lost.

Your repository pattern helps: writes already funnel through `InspectionRepository`, so a local store can sit behind that interface without touching the UI (`lib/ui/inspection/`). Five variations:

1. **Local-first queue (simplest durable path).** Every write lands in a local store (Drift/SQLite) first, then a background sync pushes to Supabase when online. The repository decides source-of-truth. Last-write-wins on conflict, since one inspector owns a report. Smallest change that actually stops data loss.

2. **Invert it — offline as the default mode.** Treat the network as the exception. The app always reads/writes local; sync is a separate, observable background concern. Bet: for all-day-underground use, an online-first app retrofitted with offline always feels bolted on.

3. **Halve it — drafts only.** Don't make the whole app offline. Just make in-progress reports survive locally and auto-resume. No offline reads of *other* data. Maybe 80% of the value (stop losing the report being written) at a fraction of the cost.

4. **Merge — offline + audit trail.** Since this is inspection data, every offline edit is timestamped and synced as an append-only log, not a destructive update. Plays to a compliance need and sidesteps conflict resolution.

5. **Scale it — full bidirectional sync.** Real-time merge, multi-device, server-authoritative conflict resolution. Powerful, and far more than "stop losing reports" requires right now.

Given the architecture and that the pain is lost reports, I'd push toward 1 or 3. Variation 3 is the cheapest thing that kills the actual bug; variation 1 is the right foundation if offline is going to grow.

---

*Phase 2 would cluster into "stop the data loss now (3)" vs. "build the offline foundation (1)", weighing the cost of a proper local store against the urgency of the bug, and naming the assumption that last-write-wins is acceptable because reports are single-owner.*

*Phase 3 would recommend variation 1 scoped to writes only, with a "Not Doing" list covering real-time multi-device merge (overkill for single-owner reports), offline reads of unrelated data (not the pain), and CRDTs (unjustified complexity), plus an open question on how synced rows surface in existing Supabase RLS policies.*

---

## Session 3 — A workflow change (non-product)

**User:** `/ideate our pull-request reviews take days and everyone's blocked — fix it`

### Phase 1 — Open up

**Skill:**

> **How might we** get changes reviewed quickly enough that nobody sits blocked, without dropping review quality?

Before expanding:

1. **Where's the delay** — reviews not picked up, picked up but slow, or stuck in back-and-forth rounds?
2. **Team shape** — how many people review, and is it the same two carrying it?
3. **What does a good review turnaround look like to you** — hours? same day?

**User:** "PRs sit a day before anyone looks. Two senior devs do almost all reviews and they're swamped. We want same-day."

**Skill:**

The signal is the **bottleneck on two people**, not review speed itself. Even instant reviews won't help if everything funnels through two overloaded humans. Six variations:

1. **Fix the assignment, not the review.** Auto-assign a reviewer by round-robin (excluding the author) the moment a PR opens, with a same-day SLA. The constraint forces the load off the two seniors.

2. **Invert it — shrink the PRs.** The reviews are slow because the PRs are big. Cap diffs (say ~400 lines); anything larger must be split. Smaller PRs review in minutes and spread naturally across people.

3. **Swap audience — grow more reviewers.** The two seniors pair-review with juniors for two weeks, then juniors review solo. Trades short-term senior time for a wider review pool. Fixes the cause, not the symptom.

4. **Halve it — tiered review.** Trivial changes (copy, config, dependency bumps) get a lightweight one-approval path or auto-merge with CI green. Reserve deep review for logic changes. Stop spending senior attention on changes that don't need it.

5. **Merge — review + CI gates.** Push more correctness into automation (lints, types, tests, Supabase advisor checks) so humans review design, not mechanics. Less to review per PR means faster reviews.

6. **Insider lens — what unblocks teams.** The usual killer isn't review speed; it's that authors don't make reviews easy. A short PR description, a self-review pass, and a "what to look at" note can halve review time at zero process cost.

The tension: 1, 3, and 4 redistribute *who/what* gets reviewed; 2, 5, and 6 reduce *how much* there is to review. Where's your real bottleneck — too few reviewers, or too much per review?

---

*Phase 2 would weigh effort-to-try (most cost nothing — just change the next PR), risk (variation 3 spends scarce senior time up front), and whether the bottleneck is reviewer supply or review size.*

*Phase 3 would recommend starting with variation 1 (auto round-robin assignment + same-day SLA) combined with variation 2 (a soft diff-size cap), as a zero-budget experiment, with a "Not Doing" list ruling out new tooling, mandatory pair-review, and any process that needs a meeting to run.*

---

## What to take from these

1. **The restatement re-frames the work.** "Stop losing hours to invoicing" became "remove the dreaded follow-up." "Add offline support" became "stop losing reports." "Reviews are slow" became "two people are the bottleneck."

2. **Questions diagnose first.** Each one decides which *kind* of problem this is. The review example surfaced a people-bottleneck, not a speed problem — and that changed every variation.

3. **Variations carry a reason.** Each names the lens that produced it and the bet it's making, which teaches the user to think this way too.

4. **The skill takes a position.** "I'd push toward 1 or 3." "Don't bundle escrow in to be safe." It says what it thinks matters, not a flat menu.

5. **Phase 2 is candid.** Ideas get flagged for weak differentiation or steep adoption. The skill pushes back on bundling "necessary" extras.

6. **The output is doable.** The brief ends in actions — validate this, build that, run the experiment — not things to mull over.

7. **The "Not Doing" list does work.** Each entry is something tempting that should wait, with the reason it waits.

8. **Context shapes the output.** The codebase example cites real files and the Supabase/Flutter stack; the workflow example produces zero-cost experiments. Same frame, output fitted to the domain.
