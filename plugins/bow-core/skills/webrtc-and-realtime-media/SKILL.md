---
name: webrtc-and-realtime-media
description: Triggers when building peer-to-peer audio/video/data — WebRTC signaling, ICE/STUN/TURN/NAT traversal, SFU/MCU topologies, codec/bitrate adaptation, and jitter/packet-loss handling.
---

# WebRTC and Realtime Media

A realtime media bug is rarely where it looks. "No video" can be a signaling race,
a blocked TURN port, an SDP munge, a renegotiation deadlock, or a codec the far end
refused. Work the pipeline in order — signaling → ICE → DTLS → media → adaptation —
and confirm each stage before blaming the next.

## 1. Fix the topology before the code

Pick the media path first; it dictates everything downstream.

- **Mesh (full P2P)** — every peer sends to every other peer. Simple, no media server,
  end-to-end encrypted by default. Upload bandwidth and encode count grow as O(n); dies
  past ~4 participants. Use for 1:1 and tiny calls.
- **SFU (selective forwarding)** — each peer uploads once to a server that fans streams
  out. Linear server bandwidth, client uploads one stream. The default for group calls.
  You get simulcast/SVC layer selection and per-receiver bitrate control.
- **MCU (mixing)** — server decodes, composites, re-encodes one stream per peer. Cheapest
  client, brutal server CPU, adds a transcode hop of latency. Use only for legacy/SIP
  endpoints or recording a single composite.

State the participant ceiling and who pays for bandwidth before writing a line. Do not
build a mesh you will rip out at meeting #3.

## 2. Build signaling as a state machine, not a chat log

Signaling is your transport for SDP and ICE candidates — WebRTC does not define it.
Use whatever bidirectional channel you have (Supabase Realtime broadcast, a WebSocket,
Phoenix channel). The danger is **glare**: both peers send an offer at once.

- Use **Perfect Negotiation**. Assign one peer `polite`, the other `impolite`. On an
  incoming offer during a local offer, the polite peer rolls back; the impolite peer
  ignores. This removes hand-rolled glare logic.
- Trickle ICE: send each candidate as it arrives instead of waiting for gathering to
  finish. Buffer remote candidates that arrive before `setRemoteDescription` and flush
  after.
- Make signaling messages idempotent and ordered per peer. A reconnecting client must
  re-sync state, not replay a half-finished handshake.

```ts
pc.onnegotiationneeded = async () => {
  try {
    makingOffer = true;
    await pc.setLocalDescription();           // implicit createOffer
    signal({ description: pc.localDescription });
  } finally { makingOffer = false; }
};

async function onSignal({ description, candidate }) {
  if (description) {
    const collision = description.type === 'offer'
      && (makingOffer || pc.signalingState !== 'stable');
    ignoreOffer = !polite && collision;
    if (ignoreOffer) return;
    await pc.setRemoteDescription(description);  // rollback handled implicitly
    if (description.type === 'offer') {
      await pc.setLocalDescription();
      signal({ description: pc.localDescription });
    }
  } else if (candidate) {
    try { await pc.addIceCandidate(candidate); }
    catch (e) { if (!ignoreOffer) throw e; }
  }
}
```

## 3. Make connectivity actually work — TURN is not optional

STUN only discovers your public address. It does **not** relay. Symmetric NATs and
many corporate/mobile networks will fail with STUN alone, so:

- Always ship a TURN server (coturn or managed). Budget ~10-20% of calls relaying.
- Offer TURN over **UDP, TCP/443, and TLS/443**. Locked-down networks only let 443 out;
  `turns:` on 443 looks like HTTPS and survives most firewalls.
- Use short-lived TURN credentials (HMAC of an expiry timestamp), never static secrets
  shipped to clients. Mint them server-side per session; treat them like any secret per
  [[secrets-and-config-management]].
- Verify with `iceConnectionState` and a candidate-pair check: in `getStats`, find the
  `succeeded` `candidate-pair` and inspect `relay` vs `srflx`. If everyone relays, your
  STUN/host path is broken.

Diagnose ICE with the actual machine: `new → checking → connected/completed` is healthy;
stuck at `checking` means no working pair (TURN/firewall); `disconnected → failed` after
working means a network drop — trigger an **ICE restart** (`restartIce()`), do not tear
down the whole `RTCPeerConnection`.

## 4. Negotiate codecs and let the SFU pick layers

- Prefer **VP8/VP9/AV1** or H.264 by target devices. H.264 has the widest hardware-decode
  coverage on mobile; AV1 saves bandwidth but burns CPU and lacks universal HW support.
  For audio, Opus with in-band FEC and DTX (silence suppression) is the baseline.
- Enable **simulcast** (send 2-3 spatial resolutions) or **SVC** (one scalable stream).
  The SFU forwards the layer each receiver can afford. Without it, one slow viewer drags
  the whole room to the lowest common bitrate.

```ts
pc.addTransceiver(videoTrack, {
  direction: 'sendonly',
  sendEncodings: [
    { rid: 'q', scaleResolutionDownBy: 4, maxBitrate: 150_000 },
    { rid: 'h', scaleResolutionDownBy: 2, maxBitrate: 500_000 },
    { rid: 'f', maxBitrate: 1_700_000 },
  ],
});
```

- Cap bitrate explicitly via `sender.getParameters().encodings[i].maxBitrate`. Browsers
  over-shoot on good networks, then collapse hard on a dip.
- Avoid SDP string munging. If you must reorder codecs or force one, use
  `transceiver.setCodecPreferences()` — typed and survives renegotiation.

## 5. Survive bad networks — jitter, loss, and adaptation

The network is the adversary; instrument it.

- **Jitter buffer** absorbs out-of-order/variable-delay packets. The browser auto-tunes
  it; for media you control (e.g. native, or `playoutDelayHint`), trade latency vs
  smoothness deliberately — conversational audio wants low delay, playback can buffer more.
- **Packet loss** recovery: enable Opus FEC for audio; for video rely on NACK/RTX
  (retransmission) for small loss and PLI/FIR (keyframe requests) for big gaps. A storm of
  PLIs means your keyframes are too rare or loss is too high — drop the layer, do not
  hammer keyframes.
- **Congestion control** (transport-cc / REMB) estimates available bandwidth. Let it lower
  resolution/framerate first; cap `degradationPreference` to `maintain-framerate` for
  motion (sports, screen share with video) or `maintain-resolution` for text/slides.
- Poll `getStats` every 1-2s and watch the receiver-side signals that actually predict a
  bad call: rising `jitter`, growing `packetsLost`/`packetLossRate`, `framesDropped`,
  `freezeCount`, and `nackCount`. Surface these as your QoS metrics per
  [[observability-and-instrumentation]] — log aggregates, never raw media.

## 6. Data channels and lifecycle hygiene

- For non-media (chat, state, file transfer) use `RTCDataChannel`. Pick `ordered:false,
  maxRetransmits:0` for realtime game/cursor state, ordered+reliable for chat. It rides
  the same DTLS/SCTP transport, so it inherits ICE — no second connection to manage.
- Always tear down: stop every track, close senders, `pc.close()`, and free
  `getUserMedia` streams or the camera light stays on. On mobile/Flutter, release native
  renderers explicitly.
- Handle `iceConnectionState`/`connectionState` transitions as first-class events. A
  backgrounded mobile app drops media; reconnect with ICE restart, not a fresh page load.

## 7. Verify with evidence, not vibes

- Confirm each stage independently: signaling delivered both SDPs? ICE reached
  `connected`? DTLS handshake done? RTP flowing (`bytesReceived` climbing)?
- Use `chrome://webrtc-internals` / `about:webrtc` to read the live stats graph and the
  selected candidate pair. This is the single fastest way to locate the broken stage.
- Test the hostile cases on purpose: symmetric-NAT (force TURN), 5% packet loss, a
  mid-call network switch (wifi→cellular). A call that works on your LAN proves nothing.

## Cross-links

- Connectivity under flaky networks: [[resilience-and-fault-tolerance]].
- TURN credentials and signaling auth: [[secrets-and-config-management]],
  [[authn-authz-design]].
- QoS telemetry and dashboards: [[observability-and-instrumentation]].
- Load behavior of an SFU: [[load-and-stress-testing]], [[scalability-and-capacity-planning]].
- Committing changes: [[commit-pipeline]].
