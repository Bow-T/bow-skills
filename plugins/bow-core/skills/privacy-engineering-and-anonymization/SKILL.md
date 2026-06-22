---
name: privacy-engineering-and-anonymization
description: Triggers when data must be de-identified for analytics, sharing, or ML — k-anonymity, differential privacy, pseudonymization, tokenization, re-identification risk, and synthetic data generation.
---

# Privacy Engineering and Anonymization

De-identification is a risk-reduction exercise, not a binary switch. "We hashed
the emails" is where re-identification attacks start, not where they end. Pick a
technique by **threat model and downstream use**, then prove the residual risk is
acceptable.

## 1. Classify the data and name the adversary first

Before touching any transform, write down two things:

- **Field roles.** Tag every column:
  - *Direct identifiers* — uniquely point to a person (email, phone, national id,
    device id, Supabase `auth.uid()`).
  - *Quasi-identifiers (QIs)* — innocuous alone, identifying in combination
    (birth date, postal code, gender, job title, first-seen timestamp). The
    classic re-id result: ~87% of a population is unique on `{ZIP, birthdate, sex}`.
  - *Sensitive attributes* — what the adversary wants to learn (diagnosis, salary,
    sexual orientation, location trace).
- **The adversary.** Internal analyst with a join key? A partner you share an
  export with? A public release anyone can download? The release model dictates
  the budget. Public release demands the strongest guarantees; an internal
  pseudonymized warehouse can be weaker because access control carries some load.

If you cannot enumerate the QIs you cannot reason about k-anonymity. Do this on paper.

## 2. Choose the technique to match the use, not the vibe

| Use | Wrong-but-common choice | Better fit |
|---|---|---|
| Reversible link across systems | hashing PII | **tokenization** with a vault |
| Stable analytics join key | raw email | **keyed pseudonym** (HMAC, secret key) |
| Aggregate stats / dashboards | row-level export | **differential privacy** on aggregates |
| Releasing microdata (rows) | drop the name column | **k-anonymity + l-diversity** |
| Sharing for ML / demos | "scrubbed" prod copy | **synthetic data** |

The fatal default is plain hashing of a low-entropy identifier. `sha256(email)` is
trivially reversed by hashing every email in a wordlist or a breached dump — the
output space equals the input space. Hashing is not anonymization.

## 3. Pseudonymization and tokenization — get the key right

Pseudonymization replaces an identifier with a surrogate; the mapping still exists,
so the data is still personal data under most regimes. The security lives in key
management, not the algorithm.

- **Keyed, not bare.** Use `HMAC-SHA256(secret_key, identifier)`, never a bare
  hash. The secret is what makes the surrogate non-invertible by an outsider.
- **Store the key outside the data store.** If the HMAC key sits in the same
  Supabase project as the pseudonyms, a single breach gives both. Put it in a
  secrets manager — see [[secrets-and-config-management]].
- **Salt per dataset to break linkability.** A per-export salt means the same user
  gets different pseudonyms in two releases, so a recipient cannot join them. Use
  a stable per-system key only when cross-time linkage is the actual requirement.
- **Tokenization** keeps a reversible vault: surrogate → real value mapping in an
  isolated, heavily-restricted table. Use it for payment data or when you must
  re-identify later (e.g. fulfil a deletion request). The vault is now your
  crown-jewel asset — RLS it to a service role only, audit every read.

```ts
// Deterministic pseudonym for an analytics join key (TS edge function)
import { createHmac } from "node:crypto";
const KEY = Deno.env.get("PSEUDONYM_KEY")!; // from vault, NOT in the DB
export const pseudonym = (email: string) =>
  createHmac("sha256", KEY).update(email.trim().toLowerCase()).digest("base64url");
```

Do not leave the pseudonym mapping reconstructable through a side channel: an
auto-increment surrogate id leaks insertion order and row count; a created_at
kept to the millisecond is itself a quasi-identifier.

## 4. k-anonymity for microdata releases

When you release rows (not just aggregates), enforce that every record is
indistinguishable from at least *k−1* others on its QIs.

1. **Generalize** QIs until each QI-combination (an *equivalence class*) has ≥ k
   rows. Bucket age into ranges (`30–39`), truncate ZIP to a prefix, round
   timestamps to the day.
2. **Suppress** the rare rows that won't reach k rather than over-generalizing the
   whole column for a handful of outliers.
3. **Layer l-diversity / t-closeness.** k-anonymity alone fails if every row in a
   class shares the same sensitive value — the attacker learns it without
   identifying the individual (homogeneity attack). Require ≥ *l* distinct
   sensitive values per class, or that each class's distribution is close to the
   global one (t-closeness).
4. **Pick k from the release model.** Internal: k≈5. External partner: k≈10–20.
   Public: higher, and reconsider whether to release rows at all.

k-anonymity protects against record linkage but **not** against an attacker with
background knowledge or composition across multiple releases. State that limit.

## 5. Differential privacy for aggregates and ML

When you publish counts, averages, histograms, or train a model, DP gives a
mathematical bound: any single person's presence changes the output distribution
by at most a factor tied to **ε** (epsilon).

- **Add calibrated noise.** For a count, Laplace noise scaled to `sensitivity/ε`
  (sensitivity = max change one person can cause, usually 1 for a count). Smaller ε
  = more privacy, more noise.
- **Budget is global and additive.** Every query spends ε. Ten queries at ε=0.1
  cost ε=1 total. Track the cumulative budget per dataset; once spent, stop
  answering. This is the discipline people skip.
- **Clamp unbounded contributions.** One user with 10,000 events dominates a sum;
  cap per-user contribution before aggregating, or sensitivity (and noise) explodes.
- **Suppress small cells.** A bucket with one contributor leaks even with noise —
  enforce a minimum count threshold and round.

DP is the only technique here that composes and resists arbitrary background
knowledge. It is overkill for an internal pseudonymized warehouse and essential
for anything published.

## 6. Synthetic data — useful, not magic

Generated data that mimics real distributions is excellent for dev seeds, demos,
and CI fixtures. Caveats that bite:

- A generator that **overfits memorizes real rows** and can emit them verbatim —
  an outlier record (the only patient with a rare condition) leaks. Test for it:
  search the synthetic set for near-duplicates of training rows.
- Synthetic ≠ private by default. Combine with DP during generation, or treat the
  output as still-sensitive if the model was unconstrained.
- It does not preserve every correlation. Validate the joint distributions your
  downstream task actually needs before trusting it for ML training.

For Flutter/Supabase dev environments, prefer schema-faithful synthetic seeds over
a sanitized prod dump — a "scrubbed" copy almost always leaks via free-text fields,
join keys, or timestamps you forgot were quasi-identifiers.

## 7. Re-identification risk assessment — prove it before release

Treat de-identification output as guilty until tested:

- **Uniqueness check.** Count records that are unique on the QI set. Non-zero
  uniqueness on a public release is a finding, not a footnote.
- **Motivated-intruder test.** Attempt the attack: take a plausible external
  dataset (voter roll, social profile, a prior release) and try to join. If you can
  re-identify anyone, k or generalization is insufficient.
- **Audit free text and derived fields.** Names hide in `notes`, `description`,
  uploaded filenames, EXIF, and stack traces. Geohash precision, last-4 of a card,
  and high-resolution timestamps all re-identify. See [[logging-hygiene]] so the
  same PII doesn't leak through logs after you cleaned the table.
- **Check the pipeline, not just the output.** The de-identification job itself
  reads raw PII — lock down its access, encrypt its working storage, and never
  cache intermediate raw data. Run it through [[threat-modeling]] for the dataflow.

## 8. Operationalize and document

- Make the de-identification a **reproducible, reviewed pipeline**, not a one-off
  SQL script someone runs by hand. Version the QI list, the k/ε/l parameters, and
  the suppression rules.
- **Right-to-erasure interacts with pseudonymization.** If you keep a token vault
  you can honor deletion; if you used a salted per-export pseudonym with the salt
  discarded, you cannot re-identify to delete — decide which you need up front.
- Record the technique, parameters, residual-risk assessment, and release model in
  an ADR — see [[documentation-and-adrs]]. The next person must not have to
  reverse-engineer why k=10 was chosen.
- Validate the transform with tests (uniqueness assertions, budget accounting) and
  show the output before shipping — see [[test-driven-development]].
- Commit the pipeline and config per [[commit-pipeline]].

## Red flags

- "We hashed it, so it's anonymous." Bare hash of low-entropy PII is reversible.
- The HMAC/token key lives in the same database as the data it protects.
- A k-anonymity claim with no documented QI list or uniqueness check.
- DP queries with no global ε budget tracked across the dataset's lifetime.
- A "sanitized" prod export still carrying millisecond timestamps, free-text
  notes, or sequential surrogate ids.
- Synthetic data trusted as private without a memorization / near-duplicate test.
