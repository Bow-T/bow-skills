---
name: networking-and-tls-fundamentals
description: Triggers when debugging or designing connectivity — DNS, TLS/mTLS, certificates and rotation, proxies/load balancers, timeouts, keep-alive, and diagnosing latency or connection-reset failures.
---

# Networking and TLS fundamentals

A connection touches at least five layers before your code sees a byte: DNS, TCP,
TLS, the HTTP proxy/LB chain, and the application. When something breaks, the
symptom (a hang, a reset, a cert error) rarely names the layer. Work the layers
in order from the wire up; do not guess.

## Triage: name the failure mode first

Match the symptom before forming a theory.

| Symptom | Most likely layer | First probe |
|---|---|---|
| Hangs, then times out with no response | TCP connect or upstream stall | `nc -vz host 443`, then measure connect time |
| `ECONNRESET` / "connection reset by peer" | Peer closed mid-flight (LB idle, crash, keep-alive race) | Check idle timeout vs your keep-alive |
| `ENOTFOUND` / `getaddrinfo` failure | DNS | `dig`, `nslookup`, check resolver |
| `CERT_HAS_EXPIRED`, `UNABLE_TO_VERIFY_LEAF`, hostname mismatch | TLS | `openssl s_client` |
| Fast 502/503/504 from a gateway | Proxy/LB, not your app | Inspect LB logs, not app logs |
| Works locally, fails in CI/prod | DNS, egress firewall, or missing CA bundle | Compare resolver + cert store across envs |

Red flag: jumping to "it's a TLS bug" before confirming the TCP handshake even
completes. A reset during the TLS `ClientHello` is a network/firewall problem,
not a certificate problem.

## Layer 1 — DNS

```bash
dig +short api.example.com           # what does the authoritative answer say
dig api.example.com @1.1.1.1         # bypass local resolver to isolate caching
dig +trace api.example.com           # follow the delegation when answers conflict
```

Decision points:
- Multiple A records → the client picks one; a single bad backend looks like
  *intermittent* failure. Round-robin DNS is not load balancing.
- Low TTL + slow resolver = latency on every cold connection. Cache or pool.
- In containers, the resolver is `/etc/resolv.conf` injected by the orchestrator,
  not your laptop's. "Works on my machine" often dies here.

## Layer 2 — TCP reachability

```bash
nc -vz api.example.com 443           # can we even open the socket
curl -w 'dns=%{time_namelookup} conn=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}\n' -o /dev/null -s https://api.example.com
```

The `curl -w` timing breakdown is the single most useful latency tool: it splits
DNS vs TCP connect vs TLS handshake vs time-to-first-byte. If `conn` is fast but
`ttfb` is huge, the network is fine and the server (or a downstream query) is
slow — pivot to [[database-query-optimization]] or [[performance-optimization]].

## Layer 3 — TLS and certificates

```bash
# Full handshake, see the presented chain and verify result
openssl s_client -connect api.example.com:443 -servername api.example.com </dev/null

# Just the expiry dates of the leaf
echo | openssl s_client -connect api.example.com:443 -servername api.example.com 2>/dev/null \
  | openssl x509 -noout -dates -subject -issuer
```

The four certificate failures and what each means:
- **Expired / not-yet-valid** → rotation lapsed or clock skew. Check both ends'
  system time before blaming the cert.
- **Hostname mismatch** → the SAN list doesn't include the name you dialed.
  `-servername` (SNI) must match; wildcard `*.example.com` does not cover the
  apex or a second label deep.
- **Unable to verify leaf / self-signed in chain** → the server sent an
  incomplete chain (missing intermediate) *or* the client lacks the root CA.
  Distinguish: if a browser trusts it but your service doesn't, it's a missing
  CA bundle in the runtime, not a server problem.
- **Protocol/cipher** → one side pinned TLS 1.2-only against a 1.3-only peer.

Never reach for `rejectUnauthorized: false`, `--insecure`, or a custom
`badCertificateCallback` that returns `true`. That disables the entire point of
TLS and is a finding in any [[security-and-hardening]] review. Fix the chain or
trust the right CA instead.

## mTLS (mutual TLS)

When the server also demands a client certificate, the handshake fails *after*
`ClientHello` with a vague reset if your client sends none. Verify both halves:

```ts
import { Agent } from 'undici';

const agent = new Agent({
  connect: {
    cert: clientCertPem,   // presented to the server
    key:  clientKeyPem,
    ca:   serverRootCa,    // used to verify the server
  },
});
```

Common mTLS traps: the client key and cert don't pair; the server's CA doesn't
recognize the client cert's issuer; the cert is valid but the CN/SAN isn't on
the server's allow-list.

## Layer 4 — proxies, load balancers, keep-alive

Most production "random `ECONNRESET`" bugs are an **idle-timeout race**: the LB
closes an idle keep-alive connection at, say, 60s; your client pool holds the
same socket and sends a request into the closing connection. Fix by making the
client's keep-alive timeout *shorter* than the LB's idle timeout, and retry
idempotent requests once on reset.

```ts
import { Agent, setGlobalDispatcher } from 'undici';
setGlobalDispatcher(new Agent({
  keepAliveTimeout: 30_000,        // below the LB's idle timeout
  keepAliveMaxTimeout: 30_000,
  connections: 64,                 // bound the pool; unbounded pools exhaust ports
}));
```

Other proxy-layer checks:
- A fast `502` means the LB reached a dead/unhealthy backend; a `504` means the
  backend accepted but didn't answer in time — different fixes.
- `X-Forwarded-For` / `Forwarded` rewrite the client IP; trust them only from
  known proxies or you enable spoofing.
- TLS termination at the LB means traffic past it is plaintext on the internal
  hop — confirm that's intended, not an accident.

## Timeouts: set all four, explicitly

A request without timeouts is a latent hang. Defaults are usually "infinite."

- **Connect timeout** — give up opening the socket (2–5s).
- **TLS handshake timeout** — usually folded into connect.
- **Read/idle timeout** — no bytes for N seconds (5–30s by call type).
- **Overall deadline** — wall-clock cap on the whole call, the backstop.

```dart
final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
// Cap the whole operation independently of socket idle behaviour.
final res = await client
    .getUrl(Uri.parse('https://api.example.com/v1/ping'))
    .then((r) => r.close())
    .timeout(const Duration(seconds: 15));
```

For Supabase edge functions and TypeScript clients, wrap `fetch` with an
`AbortController` so a stalled upstream can't pin a worker:

```ts
const ac = new AbortController();
const t = setTimeout(() => ac.abort(), 10_000);
try {
  return await fetch(url, { signal: ac.signal });
} finally {
  clearTimeout(t);
}
```

Pair timeouts with bounded retries and backoff — see [[resilience-and-fault-tolerance]].
Retrying on a timeout without idempotency duplicates side effects; see
[[idempotency-and-exactly-once]].

## Certificate rotation

Expiry is a scheduled outage you chose to ignore. Treat rotation as routine.
- Alert on **days remaining**, not on expiry. Page at 14 days, hard-fail builds
  at 7. Track this as an SLI if it gates traffic — see [[slos-and-error-budgets]].
- Automate issuance/renewal; manual rotation is a 3am incident waiting to happen.
- Roll the **new CA into the trust store before** the leaf switches, so clients
  trust both old and new during the overlap window.
- Pinning (cert or public-key) breaks silently on rotation — pin to a long-lived
  CA, keep a backup pin, and never ship a pin with no rotation plan.

Store keys and CA material as secrets, never in the repo or image — defer to
[[secrets-and-config-management]].

## Verify before you call it fixed

- Reproduce the original failure, apply one change, confirm it's gone — don't
  stack fixes blindly. See [[debugging-and-error-recovery]].
- Re-run the `curl -w` timing breakdown; the slow phase should have moved.
- Confirm certificate validity from the *runtime* environment, not your laptop —
  CA stores differ.
- Soak it: idle-timeout races and pool exhaustion only show under sustained
  concurrency, so verify with [[load-and-stress-testing]] before trusting it.

When committing the fix, follow [[commit-pipeline]].
