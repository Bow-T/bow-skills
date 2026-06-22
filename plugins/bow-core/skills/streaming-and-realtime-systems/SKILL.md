---
name: streaming-and-realtime-systems
description: Triggers when delivering live updates — WebSockets/SSE/long-poll choice, presence, backpressure, reconnection, fan-out scaling, and ordering/dedup for realtime channels.
---

# Streaming and realtime systems

Realtime fails in production at the boundaries: the network blips, one slow
consumer stalls a broadcast, a reconnect replays old events, a popular channel
melts a single server. Design for those before the happy path.

## 1. Pick the transport from the data direction

Decide before writing code. Most "we need WebSockets" requests don't.

| Need | Pick | Why |
|---|---|---|
| Server → client, one-way (feeds, notifications, progress) | **SSE** | Auto-reconnect + event IDs built in; plain HTTP, survives proxies |
| Bidirectional, low-latency (chat, collaborative edit, games) | **WebSocket** | Full duplex, lowest per-message overhead |
| Sparse updates, simple infra, legacy proxies | **Long-poll** | No persistent socket; works everywhere, costs a request per update |
| Already on Supabase + Postgres row changes | **Realtime channels** | Postgres CDC + presence + broadcast without running your own socket fleet |

Red flag: choosing WebSockets for a server-push-only feature. SSE is simpler,
reconnects itself, and rides existing HTTP caching/auth.

## 2. Make every message addressable and ordered

A live stream is worthless if the client can't tell *where it is*. Give every
event a monotonic, per-channel sequence and a stable id.

```ts
type Event<T> = {
  id: string;        // stable, for dedup
  seq: number;       // monotonic within (channel)
  ts: number;        // server epoch ms, never trust client clocks
  type: string;
  payload: T;
};
```

- **Ordering** is per-channel, not global. Don't promise total order across
  channels — you can't deliver it at fan-out scale.
- Persist the last N events per channel (or a cursor in Postgres) so a
  reconnecting client can ask "give me everything after seq 4187."
- For SSE, set the `id:` field to `seq`; the browser replays `Last-Event-ID`
  on reconnect for free.

## 3. Reconnection is the feature, not the edge case

Assume the socket dies every few minutes (mobile networks, proxy timeouts,
deploys). The client must reconnect, resume, and reconcile without the user
noticing.

```dart
Future<void> _connectWithBackoff() async {
  var attempt = 0;
  while (!_closed) {
    try {
      _channel = await _open(resumeFrom: _lastSeq);
      attempt = 0;                       // reset on success
      await _listen();                   // returns when the socket drops
    } catch (_) {/* fall through to backoff */}
    if (_closed) break;
    final base = 500 * (1 << attempt.clamp(0, 6));   // cap exponent
    final jitter = Random().nextInt(base ~/ 2);      // avoid thundering herd
    await Future.delayed(Duration(milliseconds: base + jitter));
    attempt++;
  }
}
```

- Always add **jitter** — synchronized reconnects after a deploy can DDoS your
  own gateway.
- On resume, send `_lastSeq`; the server replays the gap or sends a
  `resync` marker if the gap is too large to replay (then the client refetches
  a snapshot).
- Cap retries with a circuit-breaker so a dead backend doesn't spin the battery
  flat. See [[resilience-and-fault-tolerance]].

## 4. Idempotent delivery: assume at-least-once

Any system that retries delivers duplicates. The receiver dedupes; the sender
never promises exactly-once over the wire.

```ts
const seen = new LRU<string, true>({ max: 5000 });
function accept(ev: Event<unknown>) {
  if (seen.has(ev.id)) return;     // duplicate, drop
  seen.set(ev.id, true);
  apply(ev);
}
```

- Dedup by `id` on the client; keep a bounded window (LRU or last-seq
  watermark), not an unbounded set.
- Make the *effect* idempotent too — applying the same "message added" event
  twice must not double-insert. Key local state by event id.
- For server-side exactly-once-ish semantics across a queue, see
  [[idempotency-and-exactly-once]] and [[event-driven-and-messaging]].

## 5. Backpressure: protect the slow consumer and the fast one

A single slow client must never block the broadcast loop, and a flood of events
must never blow client memory.

Server side:
- Use **bounded per-connection send buffers**. When a buffer is full, choose a
  policy explicitly: *drop-oldest* (live metrics), *drop-newest*, or
  *disconnect-and-resync* (chat). Never let it grow unbounded.
- Coalesce: for high-frequency state (cursor position, presence), send the
  latest value on a tick, not every intermediate.

```ts
// Coalesce bursts into one frame per animation/network tick.
let pending: State | null = null;
function push(s: State) {
  pending = s;                       // overwrite — only latest matters
  scheduleFlush();
}
function flush() { if (pending) { send(pending); pending = null; } }
```

Client side:
- If the UI can't keep up, sample or batch on receive; don't `setState` per
  event at 1000/s.
- Apply events to a buffer and drain on a frame timer.

Red flag: an unbounded in-memory queue per connection. One stuck mobile client
and the server OOMs.

## 6. Presence without a stampede

Presence ("who's online / typing") is deceptively expensive: N users each
broadcasting to N-1 others is O(N²) per channel.

- Keep presence state in a shared store (Redis/Postgres), not per-socket memory,
  so it survives reconnects and spans server instances.
- Heartbeat with a **TTL**; treat a missed heartbeat as offline. Don't rely on a
  clean disconnect event — sockets die silently.
- Debounce "typing" to a single boolean with expiry, not a stream of keystrokes.
- For Supabase Realtime, use the built-in `presence` track/untrack; let it
  diff state rather than rebroadcasting the full roster each change.

## 7. Fan-out scaling: the single-node trap

It works on one server because all subscribers share that process's memory. With
two servers, a publish on node A never reaches a subscriber on node B.

- Put a **pub/sub bus** (Redis pub/sub, NATS, or Postgres `LISTEN/NOTIFY` for
  modest scale) between publishers and the socket nodes. Each node subscribes to
  the channels its connected clients care about, then fans out locally.
- Shard channels by a stable hash so hot channels can be isolated/scaled.
- Use **sticky sessions or a session store** so a reconnect can land on any node
  and still resume from `seq`.
- Authorize on the *channel*, server-side, on subscribe — never trust the client
  to scope its own subscription. See [[authn-authz-design]].

## 8. Observe it or you're flying blind

Realtime degrades quietly. Instrument:

- Connection count, connect/disconnect rate, reconnect rate.
- End-to-end **delivery latency** (publish ts → client receive ts) at p50/p99.
- Per-connection send-buffer depth and drop count.
- Replay/resync rate — a spike means clients are falling behind.

Wire these as metrics + structured logs per [[observability-and-instrumentation]]
and set burn alerts via [[slos-and-error-budgets]].

## Definition of done

- [ ] Transport chosen from data direction, not habit.
- [ ] Every event has id + per-channel monotonic seq + server timestamp.
- [ ] Client reconnects with exponential backoff + jitter and resumes from seq.
- [ ] Receiver dedupes by id; effects are idempotent.
- [ ] Bounded send buffers with an explicit overflow policy; bursts coalesced.
- [ ] Presence uses TTL heartbeats in shared state, debounced.
- [ ] Fan-out goes through a pub/sub bus; subscriptions authorized server-side.
- [ ] Latency, drops, and reconnect rate are monitored with alerts.

Load-test the failure modes — kill a node mid-broadcast, throttle a client,
drop the network — before shipping. See [[load-and-stress-testing]] and
[[chaos-and-resilience-testing]]. Commit via [[commit-pipeline]].
