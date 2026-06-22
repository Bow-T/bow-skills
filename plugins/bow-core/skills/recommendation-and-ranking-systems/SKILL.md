---
name: recommendation-and-ranking-systems
description: Triggers when building personalized recommendation or ranking — candidate generation, feature signals, collaborative/content filtering, learning-to-rank, cold-start, diversity/exploration, and offline-vs-online eval.
---

# Recommendation and Ranking Systems

A specialist's process for putting the right items in front of the right user. The job is not "a model" — it is a pipeline: generate candidates, score them, re-rank for the business, and measure whether anyone clicked. Most teams over-invest in the scorer and under-invest in candidates and measurement, which is exactly backwards.

## 0. Pin the objective before touching data

Write down the single thing you are optimizing and how you will read it in production.

- Name the **target event**: a tap, a purchase, a 30-second watch, a save. "Engagement" is not a target.
- Name the **surface and slate size**: a feed of 20, a "you might like" row of 6, a single push. Slate size changes everything downstream.
- Name the **anti-goal**: clickbait, filter bubbles, promoting only your highest-margin item. If you do not name it you will optimize straight into it.

Red flag: the spec says "show better recommendations" with no event and no surface. Stop and run [[interview-me]].

## 1. Split the problem into retrieval then ranking

Never score the whole catalog per request. Two stages, different jobs:

- **Candidate generation (retrieval)** — cheaply narrow millions of items to a few hundred. Optimize for recall; a wrong-order shortlist is fine here.
- **Ranking** — expensively score those few hundred and order them. Optimize for precision at the top.

Use **multiple candidate sources** unioned together, never one. Typical mix: recently-popular, content-similar to the user's last action, collaborative ("users like you"), and freshly-published. Tag each candidate with its source — you will need it to debug why a row looks stale or one-note.

```sql
-- Supabase: a cheap "users who liked X also liked" co-occurrence source
create materialized view item_cooccur as
select a.item_id as seed, b.item_id as rec, count(*) as co
from interactions a
join interactions b on a.user_id = b.user_id and a.item_id <> b.item_id
where a.event = 'like' and b.event = 'like'
group by 1, 2;
create index on item_cooccur (seed, co desc);
```

Refresh it on a schedule; do not compute joins like this per request.

## 2. Pick a filtering approach to match your data, not the trend

- **Content-based** (match item features to user history): works on day one, survives cold-start, but recommends only more-of-the-same. Good default for small catalogs and new products.
- **Collaborative** (learn from co-interaction patterns): finds non-obvious "people like you" picks, but needs interaction volume and dies on new items/users.
- **Hybrid**: content-based for cold items/users, collaborative once a user crosses an interaction threshold. This is what you almost always ship.

For collaborative signal without an ML platform, matrix factorization (ALS) or item-item cosine over an interaction matrix gets you far. Reach for two-tower neural retrieval only when you have millions of interactions and a serving budget for embeddings.

## 3. Engineer features as signals, grouped by type

Features feed the ranker. Keep three families distinct:

- **User features** — long-term taste (preferred categories, average session length) and short-term intent (last 5 items viewed this session). Short-term often beats long-term; weight it.
- **Item features** — content (category, tags, text embedding), and quality/stats (CTR, age, completion rate).
- **Context features** — time of day, device, locale, position in the slate. Position matters: users click the top regardless of relevance.

The most predictive feature is usually **user × item affinity**: has this user interacted with this category/creator before, and how recently? Compute it; do not hope the model infers it.

Beware **leakage**: never feed a feature that is only known after the target event (e.g. "time spent on item" when predicting the click). It will look brilliant offline and useless live.

## 4. Train a learning-to-rank model, not a pointwise classifier (when you can)

Predicting "will this be clicked" per item (pointwise) ignores that ranking is relative. Prefer **pairwise/listwise** objectives that learn order within a slate (LambdaMART / gradient-boosted trees over your features is a strong, debuggable baseline; ranking-loss neural nets when you outgrow it).

- Build training rows as `(features, label)` grouped by the slate that was actually shown.
- Label from logged outcomes: clicked = positive, shown-but-not-clicked = negative. Impressions are your negatives — log them.
- Correct for **position bias**: an item at slot 1 gets clicks it did not earn. Train on inverse-propensity weights or include position as a feature you zero out at serving time.

A boosted-tree ranker over 30 good features will beat a deep model over raw IDs until you have serious scale.

## 5. Solve cold-start explicitly — it is not an edge case

- **New user**: no history. Fall back to popularity within their declared segment (locale, signup source), and lean on a quick onboarding ("pick 3 topics"). Exploit context features you do have.
- **New item**: no interactions, so collaborative sources skip it. Inject it via content similarity and a deliberate exploration slot (see §6) so it can earn data.
- **New everything** (fresh marketplace): you have no collaborative signal at all. Run content-based + popularity and instrument hard; collaborative comes later.

Red flag: a brilliant model that never surfaces anything published this week. Check whether new items can physically reach the slate.

## 6. Build in diversity and exploration deliberately

A pure relevance ranker collapses into a monotone feed (five posts from one creator) and never learns about items it never shows.

- **Diversity / de-duplication**: after scoring, re-rank with a penalty for repeated category/creator (e.g. MMR — trade relevance against similarity to already-picked items). Cap per-entity counts in a slate.
- **Exploration**: reserve a small fraction of slots (or use epsilon-greedy / a bandit) for items the model is unsure about. Without exploration your training data only ever reflects what you already showed — a feedback loop that ossifies.
- Make both **tunable knobs**, not hardcoded constants, so product can dial them per surface.

## 7. Evaluate offline, then confirm online — they disagree

Offline metrics gate experiments cheaply; only an online test proves impact.

- **Offline** (replay logged data): ranking metrics over held-out slates — NDCG@k, MAP, recall@k for retrieval. Split by **time** (train on past, test on future), never randomly — random splits leak the future and lie.
- **Online** (A/B test): the target event rate from §0, plus guardrails (diversity, latency, and the anti-goal). An offline win that does not move the live metric is common and expected; trust the A/B.
- Watch for **delayed feedback** (a purchase lands hours after the impression) — do not call an experiment early.

Red flag: shipping on offline NDCG alone. It correlates with, but does not equal, the metric you actually care about.

## 8. Serve, log, and close the loop

- **Latency budget**: retrieval + ranking + re-rank within the slate's deadline (often <150ms). Precompute user/item embeddings offline; rank online.
- **Log everything you served**: the slate, each item's source, feature values at serve time, and position — keyed to outcomes. This log is your next training set; if you do not log impressions you cannot train an unbiased ranker, ever.
- **Monitor for decay**: CTR drift, candidate-source share, and stale models. Recommenders rot as catalog and taste shift; schedule retraining.

```ts
// Log the served slate so it becomes training data later.
await supabase.from('rec_impressions').insert(
  slate.map((item, position) => ({
    user_id: userId, request_id: reqId, item_id: item.id,
    candidate_source: item.source, score: item.score,
    position, served_at: new Date().toISOString(),
  })),
);
```

## Pitfalls

- Optimizing a proxy (clicks) that diverges from value (satisfaction, returns) — clickbait wins the proxy.
- One candidate source, so the feed is narrow and fragile.
- Training/serving skew: a feature computed differently in the pipeline vs. live request.
- Popularity feedback loop: popular gets shown, gets clicked, gets more popular. Counter with exploration.
- No impression logging, so you can only learn from clicks and never from what users ignored.

When persisting interaction tables, materialized views, or new ranking schemas, follow [[data-modeling-and-schema-design]] and [[database-query-optimization]]; for scoring under a latency budget see [[performance-optimization]]; commit per [[commit-pipeline]].
