---
name: containerization-and-orchestration
description: Triggers when packaging services into containers and running them — lean Dockerfiles, multi-stage builds, image hardening, Kubernetes/compose manifests, resource limits, and health probes.
---

# Containerization and Orchestration

A container image is a build artifact and an attack surface at once. Treat it like
production code: small, reproducible, least-privilege, and observable. Work in this order.

## 1. Decide what actually needs a container

- Edge functions and managed serverless (Supabase Edge Functions, etc.) ship without you
  authoring a Dockerfile — don't containerize them. Reserve containers for long-running
  services: a TypeScript API, a worker, a job runner.
- A Flutter **app** is not a container. Its build output (APK/IPA/web bundle) is the artifact.
  You may containerize a *build environment* for CI, but never ship a Flutter UI in a runtime pod.
- Red flag: "let's Dockerize everything." Each image is a thing to patch, scan, and pay for.

## 2. Write a lean multi-stage Dockerfile

Separate the **build** stage (full toolchain) from the **runtime** stage (just the artifact).
Pin a digest, not a floating tag, so rebuilds are reproducible.

```dockerfile
# ---- build stage ----
FROM node:20.18-bookworm-slim@sha256:<digest> AS build
WORKDIR /app
# Copy only manifests first so dependency layers cache across code changes
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

# ---- runtime stage ----
FROM node:20.18-bookworm-slim@sha256:<digest> AS runtime
ENV NODE_ENV=production
WORKDIR /app
# Run as an unprivileged, fixed UID — never root
USER 10001:10001
COPY --from=build --chown=10001:10001 /app/node_modules ./node_modules
COPY --from=build --chown=10001:10001 /app/dist ./dist
EXPOSE 8080
# exec form so the process is PID 1 and receives SIGTERM
CMD ["node", "dist/server.js"]
```

Layer-ordering rule: copy dependency manifests and install **before** copying source. Editing
a handler then shouldn't bust the `npm ci` layer.

## 3. Keep the image small and clean

- Prefer `-slim` or `distroless` runtime bases. Alpine is tiny but its musl libc breaks some
  native modules — verify before adopting.
- Add a `.dockerignore` (node_modules, .git, .env, build caches, tests). It shrinks the build
  context and stops secrets from sneaking in.
- One concern per image. A reverse proxy, the API, and a cron worker are three images, not one
  with a shell script juggling them.
- Red flag: image > a few hundred MB for a Node service usually means build tooling leaked into
  the runtime stage.

## 4. Harden the image

- **Non-root, read-only root filesystem.** Mount a writable `emptyDir`/`tmpfs` only where the
  app genuinely writes.
- **No secrets baked in.** Never `ENV API_KEY=...` or `COPY .env`. Inject at runtime via the
  orchestrator's secret store — see [[secrets-and-config-management]].
- **Drop capabilities** and disallow privilege escalation.
- **Scan before push.** Run an image vulnerability scan in CI and fail on fixable HIGH/CRITICAL;
  this is the supply-chain gate, coordinate with [[dependency-and-supply-chain]].
- Verify the user really dropped: `docker run --rm <img> id` should not print `uid=0(root)`.

## 5. Handle signals and startup correctly

- The process must be PID 1 or have an init that reaps zombies and forwards signals. The `exec`
  CMD form gives you this; a bare `CMD npm start` often spawns a shell that swallows SIGTERM.
- On SIGTERM: stop accepting new work, drain in-flight requests, close DB pools, then exit. A
  container that ignores SIGTERM gets SIGKILLed after the grace period, dropping live requests.

```ts
const server = app.listen(8080);
process.on("SIGTERM", () => {
  server.close(() => pool.end().then(() => process.exit(0)));
});
```

## 6. Local composition for dev

Use compose to wire a service to its dependencies. Make dependents wait on **health**, not just
"started".

```yaml
services:
  api:
    build: .
    ports: ["8080:8080"]
    environment:
      DATABASE_URL: postgres://app:app@db:5432/app
    depends_on:
      db: { condition: service_healthy }
  db:
    image: postgres:16-alpine
    environment: { POSTGRES_USER: app, POSTGRES_PASSWORD: app, POSTGRES_DB: app }
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 5s
      timeout: 3s
      retries: 5
```

Keep dev parity honest: the compose Postgres should match the major version your managed
database runs, or migrations and SQL behavior will differ.

## 7. Orchestrate with health probes and limits

Define **two distinct probes** — they answer different questions:

- **Liveness**: is the process wedged and needs a restart? Keep it cheap and dependency-free.
- **Readiness**: can it serve traffic right now? Check DB/cache reachability; failing it pulls
  the pod from the load balancer without killing it.
- A **startup** probe protects slow boots so liveness doesn't kill a still-initializing pod.

```yaml
resources:
  requests: { cpu: "100m", memory: "128Mi" }
  limits:   { cpu: "500m", memory: "256Mi" }
livenessProbe:
  httpGet: { path: /healthz, port: 8080 }
  periodSeconds: 10
readinessProbe:
  httpGet: { path: /readyz, port: 8080 }
  periodSeconds: 5
```

Limits rules:
- Set memory **request == limit** for predictable scheduling; exceeding the memory limit gets the
  container OOM-killed, so size from real measurement, not a guess.
- CPU limits throttle rather than kill — set a request that reflects steady load; be cautious with
  hard CPU limits on latency-sensitive services.
- Pair `/healthz` and `/readyz` separately. A common bug: readiness checks the DB, the DB blips,
  and liveness (also checking the DB) restart-loops the whole fleet.

## 8. Roll out safely

- Use rolling updates with `maxUnavailable: 0` so capacity never dips during deploy.
- Add a PodDisruptionBudget so node drains don't take the last replica down.
- Tag images with an immutable identifier (git SHA), never `:latest` in a manifest — you can't
  roll back to a tag that moved.
- For risky changes, gate behind a flag and shift traffic gradually — see
  [[feature-flags-and-progressive-delivery]] and [[shipping-and-launch]].

## Pre-ship checklist

- [ ] Multi-stage build; runtime stage has no compilers or dev deps
- [ ] Pinned base image digest + `.dockerignore` present
- [ ] Runs as non-root, read-only rootfs, capabilities dropped
- [ ] No secrets in image layers or env defaults
- [ ] Image scanned; no fixable HIGH/CRITICAL
- [ ] PID 1 receives SIGTERM and drains gracefully
- [ ] Liveness, readiness, and (if slow boot) startup probes distinct
- [ ] Memory request == limit, sized from measurement
- [ ] Immutable image tag (git SHA) in the manifest

Commit the Dockerfile, compose, and manifests via [[commit-pipeline]].
