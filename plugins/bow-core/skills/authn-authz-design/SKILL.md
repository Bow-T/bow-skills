---
name: authn-authz-design
description: Designs who-you-are and what-you-can-do correctly — triggers when implementing login, sessions/tokens (JWT/OAuth/OIDC), refresh flows, RBAC/ABAC permission models, multi-tenant isolation, or fixing an authorization gap or privilege-escalation risk.
---

# Authn / Authz Design

Two different problems that get conflated. Keep them separate at every layer.

- **Authentication (authn)** = proving identity. Answers "who is calling?"
- **Authorization (authz)** = enforcing capability. Answers "may this caller do *this* to *that* row?"

Most breaches are authz, not authn. A perfect login screen guarding an endpoint that trusts a client-sent `user_id` is wide open.

## Step 0 — Frame the problem before writing code

Answer these out loud first:

1. Who are the principals? (end user, service account, admin, anonymous)
2. What is the tenancy model? (single tenant, shared DB with tenant column, schema-per-tenant)
3. Where is the trust boundary? Everything *outside* the server is hostile, including your own Flutter app.
4. What is the blast radius if one token leaks?

If you cannot name the principal and the resource owner for an endpoint, you are not ready to write the handler.

## Authentication

### Pick a token strategy deliberately

| Need | Use |
| --- | --- |
| First-party app, you own the backend | Opaque session token or short-lived JWT + refresh |
| Third-party "log in with X" | OIDC (OAuth2 with an `id_token`) — never raw OAuth2 for identity |
| Service-to-service | mTLS or signed JWT with narrow audience |

Red flag: rolling your own password hashing. Use the platform's `argon2`/`bcrypt`; never SHA-256 a password.

### JWT rules that prevent real incidents

- Set and **verify** `iss`, `aud`, `exp`. A token valid for the wrong audience is a confused-deputy bug.
- Pin the algorithm server-side. Reject `alg: none` and reject HS/RS confusion by hardcoding the expected algorithm.
- Keep access tokens short (5–15 min). You cannot revoke a JWT, so make it expire fast.
- Never put secrets or roles you cannot re-verify into a JWT that the client reads. Treat client-readable claims as untrusted hints, not authority.

```ts
// TS — verify, don't just decode
const payload = jwt.verify(raw, publicKey, {
  algorithms: ["RS256"],          // pinned, never from the header
  issuer: "https://auth.example",
  audience: "api.example",
});
```

### Refresh flow

- Access token short-lived; refresh token long-lived, **stored server-side or as a rotating record**.
- Rotate refresh tokens on every use. Detect reuse of an already-rotated token → revoke the whole family (signals theft).
- Refresh tokens live in an `HttpOnly`, `Secure`, `SameSite` cookie for web; in the OS secure storage for Flutter (`flutter_secure_store`-style keychain/keystore), never in `SharedPreferences`.

```dart
// Flutter — secure storage, not prefs
await secureStorage.write(key: 'refresh_token', value: token);
```

## Authorization

### The one rule

**Authorize on the server, against the trusted identity, for every request.** The client may hide a button; that is UX, not security.

### Choose a model

- **RBAC** — role → permissions. Good default. Cheap to reason about.
- **ABAC / relationship-based** — decision is a function of attributes (owner, tenant, status). Reach for it when "can edit if you are the author *and* the doc is in draft" appears.

Start RBAC; add attribute checks per resource. Do not invent a policy engine before you have ten rules.

### Centralize the decision

Put authz in one place that takes `(principal, action, resource)` and returns allow/deny. Scatter the *calls*, centralize the *logic*.

```ts
function can(user: Principal, action: Action, res: Resource): boolean {
  if (res.tenantId !== user.tenantId) return false;      // tenant gate first
  if (user.roles.includes("admin")) return true;
  if (action === "edit:doc") return res.ownerId === user.id && res.status === "draft";
  return false;
}
```

### Multi-tenant isolation with Supabase RLS

The strongest authz is the one the database enforces — the app cannot forget it. Use Row Level Security keyed off the verified JWT, never a client-passed tenant id.

```sql
alter table documents enable row level security;

create policy tenant_read on documents
  for select using (
    tenant_id = (auth.jwt() ->> 'tenant_id')::uuid
  );

create policy owner_write on documents
  for update using (
    tenant_id = (auth.jwt() ->> 'tenant_id')::uuid
    and owner_id = auth.uid()
  );
```

Red flags with RLS:
- A table with `enable row level security` but **no policy** = deny-all (often silently breaks features) — or worse, RLS left *off* = allow-all.
- Using the service-role key from client-reachable code. That key bypasses RLS entirely; keep it on the server.
- Filtering by tenant in application `WHERE` clauses *instead of* RLS. One missed query leaks across tenants.

## Privilege escalation — where it actually happens

Audit these specifically:

- **IDOR**: `GET /invoices/:id` that loads by id and skips the owner check. Always re-fetch with the tenant/owner predicate, not a post-load `if`.
- **Mass assignment**: binding a request body straight onto a model lets a caller set `role: "admin"`. Whitelist writable fields.
- **Vertical climb via stale claims**: roles cached in a long-lived token. Demotions must take effect quickly — keep role checks server-side against current state, or keep tokens short.
- **Function-level gaps**: the `/admin/*` route is unprotected because the *UI* never shows the link. Protect the route, not the link.

## Verification checklist before merge

- [ ] Every mutating endpoint re-derives identity from the verified token, ignores client-sent ids of *self*.
- [ ] Every cross-tenant resource access is denied by default (RLS policy or central `can()`), with a test proving a tenant-B token cannot read tenant-A data.
- [ ] Token algorithm pinned; `exp`/`aud`/`iss` verified.
- [ ] Refresh rotation + reuse detection in place.
- [ ] Negative tests exist: wrong tenant, wrong owner, expired token, missing role each return 403/404 — not 200.
- [ ] Secrets and service-role keys are absent from the client bundle.

## Related

- [[secrets-and-config-management]] for key storage and rotation.
- [[supabase-security-review]] for deeper policy recipes.
- [[api-and-interface-design]] for choosing 401 vs 403 vs 404 (prefer 404 to avoid leaking resource existence).
- Commit any auth change via [[commit-pipeline]] (Conventional Commits + gitmoji).
