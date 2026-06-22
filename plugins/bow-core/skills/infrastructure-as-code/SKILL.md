---
name: infrastructure-as-code
description: Triggers when provisioning cloud resources declaratively — writing/structuring Terraform/Pulumi/CDK, managing state, modules, drift detection, and safe plan/apply workflows.
---

# Infrastructure as Code

Declarative infra means the repo is the source of truth and the cloud is its
projection. Every change goes through code review, a reviewed plan, and an
audited apply. No console clicking, no out-of-band edits.

## Before touching anything

State the assumptions first: which tool, which state backend, which
environments, and who is allowed to apply. Then check the ground truth.

- Confirm the tool already in use — never introduce a second one. Mixing
  Terraform and CDK in one repo doubles the failure surface.
- Locate the **remote state backend** (object storage bucket, managed cloud
  state, or Pulumi service). If state lives on a laptop, stop and fix that
  first — local state is a single point of total loss.
- Verify **state locking** is on (e.g. a lock table or backend-native lock).
  Without it, two concurrent applies corrupt state.
- Read the latest `plan` output, not just the code. Code lies about reality;
  the plan tells you what will actually change.

Red flag: nobody can answer "where is the state and who can apply it?" —
treat all further changes as unsafe until that's resolved.

## Module structure

Keep a flat, predictable layout. Resist deep module nesting until a third
caller needs the abstraction.

```
infra/
  modules/
    storage-bucket/      # reusable, no environment specifics inside
    edge-function/
  envs/
    staging/
      main.tf            # composes modules, sets staging values
      backend.tf         # remote state config for staging
    prod/
      main.tf
      backend.tf
```

Rules that keep this sane:

- **One state file per environment.** Never share state across staging and
  prod. A bad prod apply must be physically incapable of touching staging.
- Modules take inputs and return outputs — no hardcoded env names, regions,
  or secrets inside a module.
- Pin every provider and module version. Floating versions make a clean apply
  today a broken apply next week.

```hcl
# envs/prod/backend.tf — remote state, locked
terraform {
  required_version = "~> 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }
  backend "s3" {
    bucket         = "acme-tfstate-prod"
    key            = "prod/terraform.tfstate"
    dynamodb_table = "tfstate-locks"
    encrypt        = true
  }
}
```

## Secrets and config

Infra code is public to everyone with repo access — treat it that way.

- Never put credentials, tokens, or connection strings in `.tf`/`.ts` files or
  in `*.tfvars` committed to the repo. Reference a secrets manager and inject
  at apply time. See [[secrets-and-config-management]].
- Mark sensitive outputs `sensitive = true` so they don't print in plan logs.
- For a Supabase-backed stack, manage the project's service-role key and DB
  password through the secrets manager — let IaC reference them, not store
  them. The database schema itself belongs in migrations (see
  [[zero-downtime-database-migrations]]), not in IaC resources.

## The plan/apply workflow

This is the load-bearing discipline. The plan is a contract; apply only what
was reviewed.

1. `plan` against the target environment and **save the plan to a file** so
   apply runs exactly what was reviewed:
   ```bash
   terraform plan -out=tfplan.bin
   terraform show -no-color tfplan.bin   # human-readable for the PR
   ```
2. Read the plan line by line. Account for every `+ create`, `~ update`, and
   especially every `- destroy`. A surprise destroy on a database or bucket is
   how data disappears.
3. Get review on the plan, not just the diff — the same code can produce wildly
   different plans depending on current state.
4. `apply tfplan.bin` from CI, never from a laptop against prod. Apply uses the
   saved plan; if state drifted since planning, apply refuses and you re-plan.

Decision point — a resource will be **replaced** (destroy + create):

- Is it stateful (database, volume, bucket)? Stop. Replacement means data loss.
  Find the attribute forcing replacement and migrate around it, or use
  `create_before_destroy` plus a deliberate data move.
- Is it stateless (a function, a load balancer rule)? Confirm the brief
  unavailability is acceptable, or sequence with
  [[feature-flags-and-progressive-delivery]].

## Drift detection

Drift is reality diverging from code — someone edited the console, or an
external process mutated a resource.

- Run a scheduled `plan` (read-only) in CI. A non-empty plan on an unchanged
  branch means drift. Alert on it.
- When you find drift, decide deliberately: either `apply` to reassert the
  code's intent, or update the code to adopt the manual change with a note on
  why. Never silently overwrite a fix someone made during an incident.
- Import existing resources rather than recreating them:
  ```bash
  terraform import aws_s3_bucket.assets acme-prod-assets
  ```

Red flag: recurring drift on the same resource means a human or a script is
fighting your IaC. Fix the process, not just the state.

## State surgery — last resort

Manual state edits are dangerous and occasionally necessary.

- **Always back up state first**: `terraform state pull > state.backup.json`.
- Prefer `moved {}` blocks (or `state mv`) over destroy/recreate when
  refactoring module paths — this preserves the real resource.
- Never hand-edit the state JSON. Use the CLI so the lock and serial are
  respected.

## Verification

"The apply succeeded" is not "it works."

- Confirm the resource exists and is healthy from outside IaC (a real request,
  a health check), not just from green apply output.
- Re-run `plan` immediately after apply — it should report **no changes**. A
  non-empty plan right after apply means non-deterministic config (a perpetual
  diff), and you must fix it before moving on.
- Tear-down test: in staging, prove `destroy` then re-`apply` reproduces the
  environment. If it can't, your IaC isn't actually the source of truth.

## Red flags to halt on

- `-target` used to apply a subset routinely — it hides dependency problems and
  leaves state partially applied.
- `terraform apply` with no saved plan, run by hand against prod.
- A `destroy` line in a plan touching a database, bucket, or volume.
- `prevent_destroy` missing on irreplaceable stateful resources.
- State stored locally, unencrypted, or unlocked.
- Provider/module versions unpinned.

Commit changes — including saved plans referenced in the PR — via the
[[commit-pipeline]] skill (Conventional Commits + gitmoji, no AI-authorship
trailer). For wider release sequencing, see [[shipping-and-launch]].
