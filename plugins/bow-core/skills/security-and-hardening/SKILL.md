---
name: security-and-hardening
description: Harden APP-LAYER code — mobile, web, and third-party/payment integrations — against attack. Covers input validation, auth and sessions, secret handling, untrusted data (including LLM output), and SSRF. Trigger when building anything that takes untrusted input, manages sessions, or talks to external services. For database-layer concerns (RLS, views, triggers, SQL), use [[supabase-security-review]] instead.
---

# Security and Hardening

## Why this exists

Security is not a stage at the end — it is a constraint on every line that touches user data, auth, money, or an external system. The working assumption: every input is hostile, every secret is precious, and every authorization check is required. This skill covers the application layer; backend/database rules live in [[supabase-security-review]].

## Reach for this when

- Accepting any user input
- Building or changing authentication or authorization
- Storing or moving sensitive data
- Integrating an external API or service
- Adding file uploads, webhooks, or callbacks
- Touching payment or PII flows

## Start with a threat model

Controls added without a threat model are guesswork. Spend five minutes as the attacker first.

1. **Find the trust boundaries.** Where does untrusted data enter? HTTP requests, form fields, uploads, webhooks, third-party responses, queues — and **LLM output**. Every boundary is attack surface.
2. **Name the assets.** What is worth stealing or breaking? Credentials, PII, payment data, admin powers, money movement.
3. **Run STRIDE across each boundary** as a quick lens:

| Threat | Question | Typical control |
|---|---|---|
| Spoofing | Can someone pose as a user/service? | Authentication, signature checks |
| Tampering | Can data be altered in flight or at rest? | Integrity checks, parameterized queries, HTTPS |
| Repudiation | Can an action later be denied? | Audit logging of security events |
| Info disclosure | Can data leak? | Encryption, field allowlists, generic errors |
| Denial of service | Can it be flooded? | Rate limits, size caps, timeouts |
| Elevation of privilege | Can a user gain rights they shouldn't? | Authorization checks, least privilege |

4. **Write the abuse case beside the use case.** For each feature ask "how would I misuse this?" and make that your first test.

If you cannot name a feature's trust boundaries, you are not ready to secure it. This is OWASP A04, Insecure Design — most breaches start in the design, not the code.

## Three tiers of boundary

### Always (no exceptions)

- Validate every external input at the boundary (route handlers, form handlers, edge functions)
- Parameterize every query — never splice user input into SQL
- Encode output to stop XSS; rely on framework auto-escaping, don't bypass it
- HTTPS for all external traffic
- Hash passwords with argon2 / scrypt / bcrypt — never plaintext
- Set security headers (CSP, HSTS, X-Frame-Options, X-Content-Type-Options)
- Session cookies are httpOnly, secure, sameSite
- Run a dependency audit before each release

### Ask first (needs a human)

- New or changed auth flows
- Storing a new category of sensitive data (PII, payment)
- A new external integration
- CORS changes
- File upload handlers
- Rate-limit / throttle changes
- Granting elevated roles or permissions

### Never

- Commit secrets (keys, passwords, tokens)
- Log sensitive data (passwords, tokens, full card numbers)
- Treat client-side validation as a security control
- Disable security headers for convenience
- Feed user data into `eval`, `innerHTML`, or a shell
- Keep auth tokens in client-readable storage (e.g. localStorage)
- Return stack traces or internal errors to users

## Prevention patterns

### Injection

```typescript
// WRONG — concatenated SQL
const q = `select * from users where id = '${userId}'`;

// RIGHT — parameterized
const { data } = await supabase.from('users').select().eq('id', userId);
// or, raw: db.query('select * from users where id = $1', [userId]);
```

### Authentication & sessions

```typescript
import { hash, compare } from 'bcrypt';
const ROUNDS = 12;
const stored = await hash(plaintext, ROUNDS);
const ok = await compare(plaintext, stored);

// cookie session
cookie: { httpOnly: true, secure: true, sameSite: 'lax', maxAge: 86_400_000 }
```

Prefer the platform auth (Supabase Auth) over rolling your own; if you must, hash strongly and keep tokens out of client storage.

### Cross-site scripting

```typescript
el.innerHTML = userInput;        // WRONG
return <div>{userInput}</div>;   // RIGHT — auto-escaped
// must render HTML? sanitize first: DOMPurify.sanitize(userInput)
```

### Broken access control

Authentication tells you *who*; authorization tells you *whether they may*. Check ownership, not just login.

```typescript
const task = await repo.findById(id);
if (task.ownerId !== currentUser.id) {
  return forbidden('not your task');   // 403, generic
}
```

In Supabase, enforce this in RLS too — never rely on the client to scope rows.

### Misconfiguration

Lock down headers, CORS to known origins, and a tight CSP. Restrict `connectSrc`/`scriptSrc` to `'self'` plus the few origins you actually call.

### Sensitive data exposure

```typescript
// strip secret fields before returning a record
const { passwordHash, resetToken, ...safe } = user;
return safe;

// secrets come from the environment, and fail loud if absent
const key = process.env.STRIPE_API_KEY;
if (!key) throw new Error('STRIPE_API_KEY missing');
```

### Server-side request forgery (SSRF)

Whenever the server fetches a user-influenced URL — webhooks, "import from URL", image proxies, link previews — an attacker can point it at internal targets (cloud metadata at `169.254.169.254`, `localhost`, private ranges).

```typescript
import { lookup } from 'node:dns/promises';
import ipaddr from 'ipaddr.js';

const ALLOWED = new Set(['hooks.example.com']);

async function safeUrl(raw: string): Promise<URL> {
  const u = new URL(raw);
  if (u.protocol !== 'https:') throw new Error('https only');
  if (!ALLOWED.has(u.hostname)) throw new Error('host not allowed');
  const addrs = await lookup(u.hostname, { all: true });
  // any non-unicast (loopback, link-local, private, ULA) fails
  if (addrs.some((a) => ipaddr.parse(a.address).range() !== 'unicast')) {
    throw new Error('resolves to a private address');
  }
  return u;
}

await fetch(await safeUrl(input), { redirect: 'error' });
```

This still has a TOCTOU gap: `fetch` re-resolves DNS, so a short-TTL record can rebind to an internal IP after the check. For high-risk surfaces, resolve once and connect to the pinned IP, or front it with a filtering agent.

## Validate at the boundary

```typescript
import { z } from 'zod';

const CreateTask = z.object({
  title: z.string().min(1).max(200).trim(),
  description: z.string().max(2000).optional(),
  priority: z.enum(['low', 'medium', 'high']).default('medium'),
});

const parsed = CreateTask.safeParse(body);
if (!parsed.success) return unprocessable(parsed.error.flatten());
// parsed.data is now typed and trusted
```

File uploads: allowlist MIME types, cap the size, and don't trust the extension — check magic bytes when it matters.

## Secrets

```
.env.example   committed   placeholders only
.env           ignored     real secrets
.env.*.local   ignored     local overrides

.gitignore: .env, .env.local, .env.*.local, *.pem, *.key
```

Scan staged changes before committing:

```bash
git diff --cached | grep -iE 'password|secret|api[_-]?key|token'
```

If a secret ever reaches a remote, treat it as burned: rotate and reissue the key first, then purge it from history. Deleting the line is not enough. The team [[commit-pipeline]] runs a staged safety scan — use it.

## Dependency and supply-chain hygiene

An audit finds known CVEs; it won't catch a malicious or typosquatted package. Triage a finding by reachability and severity:

```
critical/high → reachable in prod? fix now. dev-only/unreachable? fix soon.
moderate      → reachable? next release. dev-only? backlog.
low           → batch with routine updates.
```

Also:

- Commit the lockfile; install with the frozen/`ci` mode in CI for reproducible builds.
- Review a new dependency before adding it — maintenance, downloads, whether it earns its place. Every dep is attack surface.
- Be wary of `postinstall` scripts in unfamiliar packages.
- Watch for typosquats (`crossenv` vs `cross-env`).

When you defer a fix, record why and a review date.

## Rate limiting

Cap request rate per window, and apply a much tighter cap to auth endpoints (login, reset, OTP) than to general API traffic.

## Securing LLM features

If the app calls a model — chatbot, summarizer, agent, RAG — it inherits the OWASP Top 10 for LLM Applications:

- **Model output is untrusted input (LLM05).** Never pass it straight into `eval`, SQL, a shell, `innerHTML`, or a file path. Validate and encode it exactly like raw user input.
- **Prompts can be hijacked (LLM01).** Untrusted text in context — a user message, fetched page, or PDF — may carry instructions. The system prompt is not a security boundary; enforce permissions in code.
- **Keep secrets and other tenants' data out of the context (LLM02/07).** Anything in context can be echoed back.
- **Constrain agency (LLM06).** Minimal tool scope; confirmation for destructive actions; validate every tool argument.
- **Bound consumption (LLM10).** Cap tokens, rate, and loop depth so a crafted input can't run up cost or hang.
- **Isolate retrieval (LLM08).** Partition embeddings per tenant; validate documents before indexing.

```typescript
// WRONG — model output executed or injected as markup
await db.query(await llm.generate(`SQL for: ${q}`));
el.innerHTML = await llm.reply(msg);

// RIGHT — output is data: parse, validate, encode
let intent;
try { intent = CommandSchema.parse(JSON.parse(await llm.replyJson(msg))); }
catch { throw new ValidationError('unexpected model output'); }
await runAllowlisted(intent.action, intent.params);
el.textContent = await llm.reply(msg);
```

## Reference checklist

A fuller audit checklist plus pre-commit verification steps live in `references/security-checklist.md` — work through it before shipping security-relevant changes.

## Excuses and rebuttals

| Excuse | Reality |
|---|---|
| "Internal tool, doesn't matter" | Internal tools get breached; attackers go for the weakest link. |
| "We'll secure it later" | Retrofitting security costs far more than building it in. |
| "Nobody would attack this" | Automated scanners attack everything. Obscurity is not security. |
| "The framework handles it" | Frameworks give tools, not guarantees. You still have to use them right. |
| "It's only a prototype" | Prototypes ship. Build the habits now. |
| "Threat modeling is overkill" | Five minutes of "how would I attack this?" prevents flaws no control can patch later. |
| "It's just LLM text" | That text can be SQL, a script tag, or a shell command. Treat it as untrusted input. |

## Red flags

- User input flowing straight into queries, shells, or HTML
- Secrets in source or git history
- Endpoints with no auth or ownership check
- Missing CORS config, or `*` origins
- No rate limit on auth endpoints
- Stack traces leaking to users
- Dependencies with known critical CVEs
- Server fetching user URLs without an allowlist (SSRF)
- LLM output reaching a query, the DOM, a shell, or `eval`
- Secrets/PII/system prompt placed inside an LLM context

## Before you ship

- [ ] Dependency audit shows no critical/high issues
- [ ] No secrets in source or history
- [ ] All input validated at the boundary
- [ ] Auth and ownership checked on every protected path
- [ ] Security headers present
- [ ] Errors hide internal details
- [ ] Rate limiting active on auth endpoints
- [ ] Server-side URL fetches allowlisted (no SSRF)
- [ ] LLM output validated and encoded before use (if AI features exist)
