---
name: secrets-and-config-management
description: Use when handling API keys or credentials, separating config from code, managing per-environment values, rotating or revoking secrets, preventing secret leakage into logs/repos, or wiring a secrets manager.
---

# Secrets and Config Management

Config is anything that changes per environment. A secret is config that grants access and must never appear in version control, logs, or a client bundle. Treat them differently from the first commit.

## Step 1: Classify before you store

For each value, decide its tier. The tier dictates where it lives.

| Tier | Examples | Storage |
|------|----------|---------|
| Public config | API base URL, feature flags, region | committed `*.env.example`, build-time constants |
| Client-safe key | Supabase anon key, public publishable key | env injected at build, fine in shipped bundle |
| Server secret | Supabase service-role key, DB password, signing keys, third-party API secrets | secrets manager only, server-side only |

Decision point: "Can a hostile user read the shipped artifact?" Flutter app binaries and TS frontend bundles are readable. If a value is server-only, it must never reach a Flutter `--dart-define` for a client build or a `NEXT_PUBLIC_`/`VITE_` variable.

Red flag: a service-role key used inside a Flutter widget or browser code. That key bypasses row-level security; it belongs only in an edge function or backend.

## Step 2: Establish the layout

```
.env.example        # committed: every key, NO real values
.env                # local dev, gitignored
.env.<environment>  # never committed; loaded from the manager in CI/CD
```

Confirm ignores before the first secret exists:

```bash
git check-ignore .env .env.local .env.production || echo "ADD THESE TO .gitignore NOW"
```

Commit `.env.example` so onboarding is self-documenting. Defer the commit itself to [[commit-pipeline]].

## Step 3: Load config through a single typed accessor

Never read raw env vars scattered across the code. One module validates at startup and fails loud on a missing value.

TypeScript:

```ts
function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

export const config = {
  supabaseUrl: required("SUPABASE_URL"),
  serviceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"), // server only
  environment: process.env.APP_ENV ?? "development",
} as const;
```

Dart/Flutter — inject at build, never hardcode:

```dart
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  // build: flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
}
```

Decision point: fail-fast at boot vs. lazy. Always fail-fast for required secrets — a server that starts with a missing key only to 500 on first request is worse than one that refuses to boot.

## Step 4: Keep secrets out of logs

Leakage happens at the edges: error dumps, request logging, crash reporters.

- Never log whole config objects or request headers.
- Redact known-sensitive keys before any structured log.

```ts
const SENSITIVE = /key|token|secret|password|authorization|cookie/i;
function redact(obj: Record<string, unknown>) {
  return Object.fromEntries(
    Object.entries(obj).map(([k, v]) => [k, SENSITIVE.test(k) ? "[REDACTED]" : v]),
  );
}
```

Red flags:
- `console.log(error)` on an object that carries the failed request body.
- Echoing `--dart-define` values into CI build logs.
- A stack trace that interpolates a connection string.

## Step 5: Wire the secrets manager (the real source of truth)

Local `.env` is a convenience; the deployed source of truth is a manager (cloud secrets store, platform env settings, or the Supabase project secrets for edge functions).

For a Supabase edge function:

```bash
supabase secrets set STRIPE_API_SECRET=sk_live_xxx --project-ref <ref>
supabase functions deploy charge --project-ref <ref>
```

Inside the function read it from the environment — it is never bundled into the client:

```ts
const stripeSecret = Deno.env.get("STRIPE_API_SECRET");
```

CI/CD pulls secrets from the manager into the build environment at deploy time. The pipeline must not print them; mask them in the runner.

## Step 6: Rotation and revocation

Rotate on a schedule and immediately on any suspected exposure. Design for rotation up front: code reads a key by name, never assumes a value is permanent.

Rotation procedure (zero-downtime):
1. Generate the new secret in the provider; keep the old one valid.
2. Update the manager value for each environment.
3. Redeploy / restart so processes pick up the new value.
4. Verify the new secret works in production.
5. Revoke the old secret at the provider.

Decision point: prefer providers that allow two active keys during overlap. If only one key can exist, accept a brief cutover and schedule it in a low-traffic window.

## Incident: a secret got committed

Rotating beats scrubbing. The value is compromised the moment it is pushed.

1. Revoke the leaked secret at its provider immediately. Removing the commit does NOT make it safe.
2. Issue a replacement and roll it out via Step 6.
3. Purge from history only after rotation (history rewrite, force-push, notify collaborators).
4. Add a pre-commit secret scan so it cannot recur.

```bash
git diff --cached --name-only | xargs -r grep -nE \
  '(service_role|sk_live_|-----BEGIN|AKIA[0-9A-Z]{16})' && \
  { echo "Potential secret staged — aborting"; exit 1; }
```

## Final checklist

- [ ] Every value classified; server secrets never in client artifacts.
- [ ] `.env*` ignored; only `.env.example` committed.
- [ ] Single typed accessor; boot fails on missing required keys.
- [ ] Logs redact sensitive keys; CI masks secrets.
- [ ] Deployed secrets live in the manager, not the repo.
- [ ] Rotation runbook exists; pre-commit scan installed.
