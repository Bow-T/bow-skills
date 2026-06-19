---
name: performance-optimization
description: Finds and fixes real performance problems through measurement. Trigger when a performance budget or SLA exists, when users or monitoring report slowness, when Core Web Vitals or load times fall short, or when profiling has surfaced a bottleneck to fix.
---

# Performance Optimization

## Overview

Measure first or you are guessing — and guesses lead to premature optimization that adds complexity while moving nothing that matters. The loop is fixed: profile, locate the real bottleneck, fix that one thing, measure again. Optimize only what the numbers prove is worth it.

## When to Use

- A budget or SLA exists (load-time targets, response-time limits)
- Users or monitoring report slow behavior
- Core Web Vitals are below threshold
- You suspect a change introduced a regression
- You're building something that handles large data or high traffic

**Skip it when** you have no evidence of a problem. Optimizing on a hunch buys complexity you'll pay for forever and speed you may never need.

## Core Web Vitals Targets

| Metric | Good | Needs work | Poor |
|---|---|---|---|
| LCP (Largest Contentful Paint) | <= 2.5s | <= 4.0s | > 4.0s |
| INP (Interaction to Next Paint) | <= 200ms | <= 500ms | > 500ms |
| CLS (Cumulative Layout Shift) | <= 0.1 | <= 0.25 | > 0.25 |

## The Loop

```
MEASURE   establish a baseline from real data
LOCATE    find the actual bottleneck, not the assumed one
FIX       change only that
CONFIRM   re-measure; prove it improved
GUARD     add a test or monitor so it can't silently regress
```

### Measure with both lenses

- **Lab:** controlled and reproducible (Lighthouse, a browser performance trace, query `EXPLAIN ANALYZE`). Best for CI regression checks and isolating a specific issue.
- **Field:** real users on real devices and networks (a web-vitals reporter, production APM, CrUX). The only way to confirm a fix helped actual people.

```typescript
// field: report real Web Vitals
import { onLCP, onINP, onCLS } from 'web-vitals';
onLCP(send); onINP(send); onCLS(send);
```

```dart
// lab: time a Supabase query directly
final sw = Stopwatch()..start();
final rows = await supabase.from('tasks').select().eq('owner_id', userId);
sw.stop();
log.info({'event': 'query_timed', 'op': 'tasks.byOwner', 'ms': sw.elapsedMilliseconds});
```

### Let the symptom pick what to measure

```
slow first load
  big bundle?            -> measure bundle, check splitting
  slow server response?  -> read TTFB in the network waterfall, then profile the backend
  render-blocking?       -> look for blocking CSS/JS in the waterfall
sluggish interaction
  UI freezes on tap?     -> profile the main/UI thread for long tasks (> 50ms)
  input lag?             -> check rebuilds / controlled-input overhead
  janky animation?       -> check layout thrash and forced reflows
slow after navigation
  data loading?          -> measure API times, hunt request waterfalls
  client rendering?      -> profile build time, look for N+1 fetches
backend / API
  one endpoint slow?     -> profile its queries, check indexes
  every endpoint slow?   -> check connection pool, memory, CPU
  intermittent?          -> check lock contention, GC pauses, external deps
```

### Common bottlenecks

Frontend: oversized images and render-blocking resources hurt LCP; unsized images and late content cause CLS; heavy main-thread work wrecks INP; a fat bundle slows first load. Backend: N+1 queries and missing indexes dominate slow responses; leaked references and unbounded caches grow memory; synchronous heavy compute or pathological regex spike CPU; missing caching and extra network hops raise latency.

## Fixing the Usual Anti-Patterns

### N+1 queries

```dart
// Bad: one extra query per task
final tasks = await supabase.from('tasks').select();
for (final t in tasks) {
  t['owner'] = await supabase.from('users').select().eq('id', t['owner_id']).single();
}

// Good: one query, owner joined in
final tasks = await supabase
    .from('tasks')
    .select('*, owner:users(*)');
```

### Unbounded reads

```dart
// Bad: fetch the whole table
final all = await supabase.from('tasks').select();

// Good: page it
final page = await supabase
    .from('tasks')
    .select()
    .order('created_at', ascending: false)
    .range(offset, offset + 19);
```

### Images

Give every image explicit `width`/`height` to reserve space and kill layout shift. Serve modern formats (AVIF/WebP) at the right resolution per device, mark the hero/LCP image high priority, and lazy-load anything below the fold.

```html
<!-- LCP image: prioritized, sized -->
<img src="/hero.avif" width="1200" height="600" fetchpriority="high" alt="…" />

<!-- below the fold: deferred -->
<img src="/card.webp" width="800" height="400" loading="lazy" decoding="async" alt="…" />
```

### Wasted UI rebuilds (Flutter)

```dart
// Bad: rebuilds the whole subtree on every tick
Widget build(BuildContext c) => ExpensiveTree(stats: compute(tasks));

// Good: cache the expensive bit, isolate rebuilds with const + a builder
final stats = useMemoized(() => compute(tasks), [tasks]);
return RepaintBoundary(child: StatsView(stats: stats));
```

Use `const` constructors, push state down so only the affected widget rebuilds, and memoize expensive derivations. Wrapping everything in boundaries is as wrong as none — apply where a profile shows churn.

### Bundle size

Modern bundlers tree-shake named imports automatically when the dependency ships ESM and declares `sideEffects: false`, so profile before rewriting imports. The real wins come from splitting and deferring: load heavy, rarely-used features on demand and split by route.

```typescript
const Charts = lazy(() => import('./Charts'));        // heavy, occasional
const Settings = lazy(() => import('./pages/Settings')); // route-level split
```

### Caching what's hot and stable

Cache frequently-read, rarely-changed values behind a TTL; set long-lived, immutable cache headers on content-hashed static assets; and set a short `Cache-Control` max-age on cacheable API responses.

```typescript
const TTL = 5 * 60 * 1000;
let config: AppConfig | null = null, expiry = 0;
async function getConfig(): Promise<AppConfig> {
  if (config && Date.now() < expiry) return config;
  config = await loadConfig();
  expiry = Date.now() + TTL;
  return config;
}
```

## Performance Budget

Set explicit ceilings and enforce them in CI (see `ci-cd-and-automation`):

```
initial JS:    < 200KB gzipped
CSS:           < 50KB gzipped
above-fold img:< 200KB each
fonts:         < 100KB total
API p95:       < 200ms
TTI on 4G:     < 3.5s
Lighthouse perf score: >= 90
```

```bash
npx bundlesize --config bundlesize.config.json
npx lhci autorun
```

## Common Rationalizations

| Excuse | Reality |
|---|---|
| "We'll optimize later" | Perf debt compounds. Fix obvious anti-patterns now; defer micro-tuning. |
| "It's fast on my machine" | Your machine isn't the user's. Profile on representative hardware and networks. |
| "This optimization is obvious" | If you didn't measure, you don't know. Profile first. |
| "Nobody notices 100ms" | They do — 100ms measurably moves engagement and conversion. |
| "The framework handles perf" | Frameworks can't fix your N+1 queries or your oversized bundle. |

## Red Flags

- Optimizing with no profiling data behind it
- N+1 query patterns in data access
- List endpoints without pagination
- Images with no dimensions, lazy loading, or responsive sizes
- Bundle size creeping up unreviewed
- No production performance monitoring
- Memoization sprinkled everywhere "to be safe"

## Verification

- [ ] Before/after numbers exist (concrete, not vibes)
- [ ] The specific bottleneck was identified and addressed
- [ ] Core Web Vitals land in "Good"
- [ ] Bundle size didn't balloon
- [ ] No N+1 queries in new data access
- [ ] Performance budget passes in CI (where configured)
- [ ] Existing tests still pass — the optimization didn't change behavior

For the at-a-glance checklist, optimization commands, and anti-pattern reference, see `references/performance-checklist.md`.

Commit performance changes per the `commit-pipeline` skill.
