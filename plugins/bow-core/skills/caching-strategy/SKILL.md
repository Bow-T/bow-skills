---
name: caching-strategy
description: Triggers when adding a cache layer, choosing TTL vs event-based invalidation, debugging stale data, designing cache keys, or hardening against stampede/thundering-herd under load.
---

# Caching Strategy

A cache trades freshness for speed. Before adding one, prove the read is hot, slow, or expensive — otherwise you are buying a class of bugs for nothing.

## 1. Decide whether to cache at all

Ask three questions in order. Stop the moment one says "don't".

- **Is the read actually hot?** Pull request counts. A query hit 12 times an hour does not need a cache; it needs an index.
- **Can the caller tolerate stale data?** Quote a number. "Up to 60s stale is fine" is a spec. "Should be fresh-ish" is not.
- **Is recomputation expensive or just annoying?** Cache a 400ms aggregate or a paid API call. Do not cache a 3ms primary-key lookup.

Red flag: "let's cache it to be safe." Caching is the opposite of safe.

## 2. Pick the layer (cache closest to the cost, not the user)

| Layer | Use for | Lifetime |
|---|---|---|
| In-memory (process) | Per-request memoization, hot config | Process / seconds |
| Local device (Flutter) | Last-known UI state, offline reads | App session / persisted |
| Edge / CDN | Public, identical-for-everyone responses | Minutes–hours |
| Shared store (Redis-like) | Cross-instance, expensive aggregates | Seconds–minutes |
| DB materialized view | Heavy joins refreshed on schedule | Refresh interval |

Personalized or authz-scoped data must never land in a shared/edge cache without the principal in the key. A leaked `Authorization`-scoped response is a security incident, not a stale read.

## 3. Design the key before the value

A cache key is a contract. Get it wrong and you serve one user's data to another.

- Include **every input that changes the output**: entity id, version, locale, and the principal if the response is scoped.
- Namespace and version the key so you can mass-invalidate by bumping a prefix.
- Never put unbounded/free-text input directly in a key — hash it to bound cardinality.

```ts
// TS — explicit, ordered, versioned key
function userFeedKey(userId: string, page: number, filtersHash: string) {
  return `feed:v3:${userId}:${page}:${filtersHash}`;
}
```

Red flag: a key built from `JSON.stringify(params)` where key order or undefined fields vary — same logical input, two physical keys, half your hit rate gone.

## 4. Choose an invalidation model

Default to **TTL** for read-heavy data with a tolerable staleness window. Reach for **event-based** invalidation only when staleness is unacceptable and writes are observable.

- **TTL**: simplest, self-healing, no write-path coupling. Cost: bounded staleness.
- **Event-based (write-through / delete-on-write)**: fresh, but every writer must know every key it affects. Miss one path and you get permanent staleness.
- **Hybrid**: short TTL as a safety net + delete-on-write for the common path. Best of both for most real systems.

With Supabase, drive event invalidation from the write itself — a database trigger or an Edge Function reacting to a row change publishes the bust:

```ts
// Edge Function on row update -> bust the shared cache
await redis.del(userFeedKey(row.user_id, 0, "default"));
// Safety net: the key also carries a 60s TTL so a missed event self-heals.
```

Rule: **invalidate on write, never trust write-path completeness alone.** Always pair it with a TTL backstop.

## 5. Defend against stampede and thundering herd

These hit at expiry, on cold start, and during deploys — exactly when traffic is high.

- **Single-flight (request coalescing):** when a key is missing, let one caller recompute while the rest await the same in-flight result.
- **Jittered TTL:** never expire 10k keys at the same instant. Add randomness so expiries spread out.
- **Stale-while-revalidate:** serve the expired value and refresh in the background, so users never block on recompute.
- **Early/probabilistic refresh:** refresh slightly before expiry, weighted so only one caller usually triggers it.

```dart
// Dart — single-flight: collapse concurrent misses into one computation
final _inflight = <String, Future<T>>{};

Future<T> getOrCompute<T>(String key, Future<T> Function() compute) {
  final existing = _inflight[key] as Future<T>?;
  if (existing != null) return existing; // ride the in-flight call
  final future = compute().whenComplete(() => _inflight.remove(key));
  _inflight[key] = future;
  return future;
}
```

```ts
// TS — jittered TTL so a batch of writes doesn't expire in lockstep
const ttl = baseTtlSeconds + Math.floor(Math.random() * 30);
await redis.set(key, value, { EX: ttl });
```

Red flag: a hot key with no coalescing and a fixed TTL. On expiry, every concurrent request stampedes the origin at once.

## 6. Handle the failure modes explicitly

- **Cache down ≠ app down.** On a cache error, fall through to the source. Wrap cache calls so a timeout degrades to a slow path, not a 500.
- **Negative caching:** cache "not found" too (with a short TTL) or a missing row becomes a stampede magnet.
- **Never cache errors as success.** A 500 from the origin must not be stored as the value.
- **Bound memory:** set max size + eviction (LRU/LFU). An unbounded in-process map is a slow leak.

## 7. Make it observable before you trust it

Ship these from day one:

- **Hit ratio** per key namespace. A namespace below ~70% usually has a key-design bug, not a sizing problem.
- **Staleness budget alert:** measure actual age served vs the promised window.
- **Eviction + miss-rate** trend after deploys (cold-cache cost).

If you cannot answer "what's the hit ratio for this key family?" you do not have a caching strategy — you have a guess.

## 8. Flutter client cache checklist

- Separate **memory cache** (instant, volatile) from **persisted cache** (survives restart) and decide per data type.
- Show cached data immediately, then revalidate and reconcile — never block first paint on the network.
- Key persisted entries by entity id + a server-provided version/etag so a stale write is detectable on read.
- Clear user-scoped caches on logout. A leftover cache after account switch is a data-leak bug.

## Quick decision flow

1. Hot + slow/expensive + staleness-tolerant? If not, stop — index or paginate instead.
2. Cache at the layer closest to the cost; keep scoped data out of shared/edge caches.
3. Design a versioned, complete, bounded key.
4. TTL by default; add delete-on-write when staleness is unacceptable — always keep the TTL backstop.
5. Add single-flight + jitter + stale-while-revalidate for any hot key.
6. Degrade gracefully when the cache is unavailable; cache misses negatively.
7. Instrument hit ratio and staleness before declaring victory.

---

When persisting cache shape in Postgres (materialized views, trigger-driven busts), follow [[data-modeling-and-schema-design]] for the data layer. When committing the change, defer to [[commit-pipeline]] for the message format.
