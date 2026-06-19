# Performance Reference

A scannable checklist for keeping apps fast — web (TypeScript), Flutter, and the Supabase backend behind them. Pair this with the `performance-optimization` skill.

## Contents

- [Targets to hold the line on](#targets-to-hold-the-line-on)
- [Diagnosing a slow first byte](#diagnosing-a-slow-first-byte)
- [Web frontend](#web-frontend)
- [Flutter frontend](#flutter-frontend)
- [Backend and database](#backend-and-database)
- [How to measure](#how-to-measure)
- [Anti-patterns and their fixes](#anti-patterns-and-their-fixes)

## Targets to hold the line on

Core Web Vitals (the field thresholds that matter for web UX):

| Metric | What it captures | Aim for | Acceptable | Problem |
|---|---|---|---|---|
| LCP | time to render the main content | ≤ 2.5s | ≤ 4.0s | > 4.0s |
| INP | responsiveness to interactions | ≤ 200ms | ≤ 500ms | > 500ms |
| CLS | unexpected layout movement | ≤ 0.1 | ≤ 0.25 | > 0.25 |

For Flutter, the equivalent budget is a steady 16ms frame (60fps) — or 8ms on 120Hz displays — with no jank during scroll or animation.

## Diagnosing a slow first byte

When TTFB exceeds ~800ms, walk the network waterfall segment by segment:

- [ ] DNS is the cost → declare known origins with `dns-prefetch` / `preconnect`
- [ ] TLS/connection setup is the cost → enable HTTP/2 or HTTP/3, keep connections alive, move closer to the edge
- [ ] Server time is the cost → profile the handler, hunt slow queries, add caching

## Web frontend

### Images
- [ ] Served as WebP or AVIF
- [ ] Sized responsively with `srcset` + `sizes`
- [ ] Explicit `width`/`height` (or aspect-ratio) so they reserve space and don't shift layout
- [ ] Off-screen images use `loading="lazy"` + `decoding="async"`
- [ ] The LCP image uses `fetchpriority="high"` and is never lazy-loaded

### JavaScript
- [ ] Initial bundle stays under ~200KB gzipped
- [ ] Routes and heavy features are split out with dynamic `import()`
- [ ] Tree shaking actually works (deps ship ESM and declare `sideEffects: false`)
- [ ] Nothing render-blocking in `<head>` — scripts are `defer` or `async`
- [ ] Long tasks (>50ms) are broken up so the main thread stays free — the primary lever for INP
- [ ] Long loops yield between chunks; prefer `scheduler.yield()`, fall back to `scheduler.postTask()` or a manual yield
- [ ] Non-urgent work (analytics, prefetch, warmup) runs in `requestIdleCallback`
- [ ] Work inside event handlers is trimmed to the minimum needed to respond
- [ ] Heavy third-party scripts are loaded async and fronted by a facade (chat widgets, embeds)
- [ ] In React, memoization (`React.memo`, `useMemo`, `useCallback`) is applied only where a profile proves it helps

### CSS and fonts
- [ ] Critical CSS is inlined or preloaded; the rest is non-blocking
- [ ] No CSS-in-JS runtime cost in prod (use static extraction)
- [ ] Limited to a few families/weights; ship WOFF2 only
- [ ] Self-host fonts to avoid extra DNS/TLS round-trips
- [ ] Preload the LCP-critical font with `crossorigin`
- [ ] `font-display: swap` (or `optional`) to avoid invisible-text blocking
- [ ] Subset with `unicode-range`; consider a variable font; consider the system stack first
- [ ] Tune fallback metrics (`size-adjust`, `ascent-override`) to limit swap-induced CLS

### Network and rendering
- [ ] Hashed static assets get long `max-age`; cacheable API responses set `Cache-Control`
- [ ] HTTP/2 or HTTP/3 is on; known origins are preconnected
- [ ] `fetchpriority` is applied to critical non-image resources too, not just `<img>`
- [ ] No redirect chains
- [ ] Animate only `transform` and `opacity`
- [ ] Long lists are virtualized
- [ ] Read DOM, then write DOM — never interleave (avoids forced sync layout)
- [ ] Off-screen sections use `content-visibility: auto` with `contain-intrinsic-size`
- [ ] No `unload` handlers and no `Cache-Control: no-store` on HTML, so bfcache stays eligible

## Flutter frontend

- [ ] Long/scrollable content uses `ListView.builder` / slivers, never a fully-built `Column` in a scroll view
- [ ] `const` constructors used wherever the widget subtree is static, to skip rebuilds
- [ ] Rebuild scope is kept small (targeted `setState`, `ValueListenableBuilder`, selectors) rather than rebuilding whole screens
- [ ] Expensive work (parsing, image decode, crypto) is moved off the UI isolate via `compute` / `Isolate`
- [ ] Images are cached and right-sized with `cacheWidth`/`cacheHeight`
- [ ] `RepaintBoundary` isolates frequently-repainting subtrees from the rest
- [ ] `Opacity`/`ClipPath` on large or animated subtrees are avoided where a cheaper alternative exists
- [ ] Profiled in profile mode on a real mid-tier device, watching the DevTools frame chart for jank

## Backend and database

Most backends here run on Supabase (Postgres + Edge Functions).

### Database
- [ ] No N+1 access — fetch related rows in one query (join or embedded select)
- [ ] Filtered, sorted, and joined columns are indexed; verified with `EXPLAIN ANALYZE`
- [ ] List queries are paginated (range/keyset) — never an unbounded `select *`
- [ ] Row Level Security predicates are index-backed, not full scans on every request
- [ ] Connection pooling is in place (e.g. the pooler/PgBouncer) for serverless callers
- [ ] Slow query logging / the performance advisor is reviewed

### API / Edge Functions
- [ ] p95 response time stays under ~200ms
- [ ] No heavy synchronous computation inside a request handler
- [ ] Batch operations replace per-item loops of calls
- [ ] Responses are compressed (gzip/brotli)
- [ ] Cacheable reads are cached (in-memory, edge, or CDN)

### Infrastructure
- [ ] Static assets are served from a CDN
- [ ] Compute sits close to users (or at the edge)
- [ ] Horizontal scaling is configured if load requires it
- [ ] A lightweight health endpoint exists for the load balancer

## How to measure

Start with real-user (field) data, then reproduce in the lab:

1. Check field INP/LCP/CLS in your RUM tool or the CrUX report before touching anything
2. Reproduce in DevTools → Performance: record while interacting and look for long tasks tied to input
3. Throttle CPU (4–6x) or test on a real mid-tier Android device — many INP/jank issues only appear on slow hardware

```bash
# Lab audit
npx lighthouse https://localhost:3000 --output=json --output-path=./lh.json

# See what's in the bundle
npx vite-bundle-visualizer            # Vite
npx webpack-bundle-analyzer stats.json # webpack

# Flutter frame profiling
flutter run --profile        # then open DevTools > Performance
```

```ts
// Wire up Web Vitals with per-interaction attribution
import { onINP } from 'web-vitals/attribution';

onINP(({ value, attribution }) => {
  const { interactionTarget, inputDelay, processingDuration, presentationDelay } = attribution;
  console.log({ value, interactionTarget, inputDelay, processingDuration, presentationDelay });
});
```

## Anti-patterns and their fixes

| Anti-pattern | What it costs | Fix |
|---|---|---|
| N+1 queries | DB load grows with row count | Join, embed, or batch |
| Unbounded `select` | OOM and timeouts at scale | Always paginate / `LIMIT` |
| Missing indexes | Reads degrade as data grows | Index filtered/sorted columns |
| Read/write DOM interleaving | Layout thrash, dropped frames | Batch reads, then batch writes |
| Heavy/unsized images | Slow LCP, layout shift | Modern format, responsive, dimensions set |
| Oversized bundles | Slow time-to-interactive | Split, tree-shake, drop dead deps |
| Blocking the main/UI thread | Bad INP / Flutter jank | Chunk and yield, or move off-thread |
| Full `Column` in a scroll view (Flutter) | Builds everything up front | Use `ListView.builder` / slivers |
| Leaked listeners, timers, controllers | Memory climbs until crash | Dispose / unsubscribe on teardown |
