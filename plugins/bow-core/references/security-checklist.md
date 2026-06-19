# Security Reference

A scannable checklist for shipping secure features. Pair this with the `security-and-hardening` skill. Examples lean on the team's stack: TypeScript/web, Supabase (Postgres + Auth + RLS), and Flutter clients.

## Contents

- [Think like an attacker first](#think-like-an-attacker-first)
- [Before you commit](#before-you-commit)
- [Authentication](#authentication)
- [Authorization and access control](#authorization-and-access-control)
- [Validating input](#validating-input)
- [HTTP security headers](#http-security-headers)
- [CORS](#cors)
- [Protecting data](#protecting-data)
- [Dependencies and supply chain](#dependencies-and-supply-chain)
- [LLM-backed features](#llm-backed-features)
- [Error responses](#error-responses)
- [OWASP Top 10 at a glance](#owasp-top-10-at-a-glance)
- [OWASP Top 10 for LLMs at a glance](#owasp-top-10-for-llms-at-a-glance)

## Think like an attacker first

Spend a few minutes modelling threats before picking controls:

- [ ] Drew the trust boundaries — anywhere untrusted data enters (form posts, uploads, webhooks, third-party APIs, LLM output)
- [ ] Listed what's worth stealing — credentials, PII, payment data, admin powers, anything that moves money
- [ ] Walked STRIDE per boundary (Spoofing, Tampering, Repudiation, Information disclosure, Denial of service, Elevation of privilege)
- [ ] For each feature, wrote the abuse case beside the use case ("how would I misuse this?")

## Before you commit

- [ ] No secrets staged — scan with `git diff --cached | grep -iE 'password|secret|api[_-]?key|token'`
- [ ] `.gitignore` excludes `.env`, `.env.local`, `*.pem`, `*.key`
- [ ] `.env.example` holds placeholders only, never live values
- [ ] On mobile, no API secrets baked into the Flutter binary (anything in the app ships to the user — keep privileged calls server-side)

## Authentication

- [ ] Passwords hashed with a memory-hard algorithm (argon2 preferred; bcrypt at ≥12 rounds or scrypt acceptable). If using Supabase Auth, this is handled for you — don't roll your own.
- [ ] Session cookies set `HttpOnly`, `Secure`, and `SameSite=Lax`
- [ ] Sessions expire on a sane schedule; refresh tokens rotate
- [ ] Login is rate-limited (e.g. ≤10 tries / 15 min per identifier+IP)
- [ ] Password-reset tokens are single-use and short-lived (≤1 hour)
- [ ] Repeated failures trigger lockout or step-up (with user notification)
- [ ] MFA available for high-value actions

## Authorization and access control

- [ ] Every protected route confirms the caller is authenticated
- [ ] Every resource fetch confirms the caller owns it or has the role (stops IDOR)
- [ ] In Supabase, RLS is **enabled on every table** and policies are tested — never rely on the client to scope queries
- [ ] The anon/publishable key is treated as public; privileged work uses the service-role key server-side only
- [ ] Admin-only routes verify the admin role explicitly
- [ ] API keys and tokens are scoped to the least privilege they need
- [ ] JWTs are validated for signature, expiry, and issuer before trust

## Validating input

- [ ] All boundary input is validated (API routes, form handlers, Edge Functions)
- [ ] Validation is allowlist-based, not denylist-based
- [ ] String lengths and numeric ranges are bounded
- [ ] Emails, URLs, and dates are checked with a real parser, not a hand-rolled regex
- [ ] Uploads are restricted by type and size, and the actual content is verified
- [ ] SQL is parameterized — no string concatenation (the Supabase client and prepared statements do this for you)
- [ ] Output rendered into HTML is escaped (lean on the framework's auto-escaping)
- [ ] Redirect targets are validated against an allowlist (stops open redirect)
- [ ] Server-side fetches are allowlisted and block private/reserved IP ranges (stops SSRF)

## HTTP security headers

```
Content-Security-Policy: default-src 'self'; script-src 'self'
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

Leave the legacy `X-XSS-Protection` off (`0`) and rely on CSP instead.

## CORS

```typescript
// Allow only the origins you actually serve
const corsOptions = {
  origin: ['https://app.example.com', 'https://admin.example.com'],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
};

// Do not ship this — a wildcard origin defeats the point
// { origin: '*' }
```

## Protecting data

- [ ] Sensitive columns (password hashes, reset tokens, internal flags) are stripped from API responses
- [ ] Secrets, tokens, and full card numbers never reach logs
- [ ] Regulated PII is encrypted at rest where required
- [ ] All external traffic is HTTPS
- [ ] Backups are encrypted
- [ ] On the client, sensitive values use secure storage (Keychain/Keystore via `flutter_secure_storage`), not plain shared prefs

## Dependencies and supply chain

```bash
npm audit                      # known vulnerabilities
npm audit fix                  # auto-remediate what it can
npm audit --audit-level=critical
npx npm-check-updates          # surface upgrades
```

`npm audit` won't catch a deliberately malicious package, so also:

- [ ] Lockfile is committed; CI installs with `npm ci`, never `npm install`
- [ ] New deps are vetted (maintenance, download counts, any `postinstall` script)
- [ ] No typosquats slipped in (e.g. `crossenv` vs `cross-env`)

## LLM-backed features

For anything that calls a model — chat, summarization, agents, RAG:

- [ ] Model output is untrusted input — never feed it straight into `eval`, SQL, a shell, `innerHTML`, or a file path
- [ ] Assume prompt injection will happen; enforce permissions in code, not in the system prompt
- [ ] Keep secrets, other tenants' data, and the full system prompt out of the context window
- [ ] Scope every tool the model can call; require explicit confirmation for destructive or irreversible actions
- [ ] Cap tokens, request rate, and loop/recursion depth so a run can't balloon

## Error responses

```typescript
// Production: opaque to the caller, logged in full server-side
res.status(500).json({
  error: { code: 'INTERNAL_ERROR', message: 'Something went wrong' },
});

// Never return internals to the client
// res.status(500).json({ message: err.message, stack: err.stack, sql: err.query });
```

## OWASP Top 10 at a glance

| Risk | First-line defense |
|---|---|
| Broken access control | Auth + ownership/role check on every request; RLS on every table |
| Cryptographic failures | HTTPS everywhere, strong hashing, secrets out of code |
| Injection | Parameterized queries, validated/escaped input |
| Insecure design | Threat model up front, spec-driven work |
| Security misconfiguration | Security headers, least privilege, audited config |
| Vulnerable components | `npm audit`, prompt upgrades, minimal dependency surface |
| Identification & auth failures | Strong hashing, rate limits, sound session handling |
| Software/data integrity failures | Verify updates and artifacts, signed builds |
| Logging & monitoring failures | Log security events; never log secrets |
| SSRF | Allowlist outbound targets, block internal IP ranges |

## OWASP Top 10 for LLMs at a glance

For features with model integrations. Reference: the OWASP GenAI Security Project LLM Top 10.

| ID | Risk | First-line defense |
|---|---|---|
| LLM01 | Prompt injection | The prompt isn't a security boundary; enforce in code |
| LLM02 | Sensitive info disclosure | Keep secrets/PII out of prompts; filter outputs |
| LLM03 | Supply chain | Vet models, datasets, and plugins like any dependency |
| LLM04 | Data/model poisoning | Trusted sources, integrity checks, vet fine-tune and RAG data |
| LLM05 | Improper output handling | Treat output as untrusted; validate, parameterize, encode |
| LLM06 | Excessive agency | Scope tools; confirm destructive actions |
| LLM07 | System-prompt leakage | Assume it leaks; store no secrets in it |
| LLM08 | Vector/embedding weaknesses | Partition embeddings per tenant; validate before indexing |
| LLM09 | Misinformation | Ground with citations, verify critical claims, keep a human in the loop |
| LLM10 | Unbounded consumption | Cap tokens, request rate, and recursion depth |
