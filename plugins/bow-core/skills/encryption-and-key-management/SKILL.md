---
name: encryption-and-key-management
description: Triggers when encrypting data at rest or in transit beyond TLS basics — choosing AES-GCM/envelope encryption, integrating a KMS/HSM, key rotation and key hierarchies, deterministic vs randomized encryption, and field-level/application-layer crypto.
---

# Encryption and key management

Application-layer crypto fails quietly. A wrong nonce, a hard-coded key, or a
silent fallback to ECB does not throw — it ships, and the breach surfaces years
later. Your job is to make the secure path the only path and to design so that a
single leaked key does not equal "decrypt everything forever."

## Step 0 — Decide whether you should encrypt at all

Encryption is not free: it breaks indexing, complicates search, and adds a key
you must now guard for the data's whole lifetime. Before writing any crypto:

- **Is the data sensitive enough to need app-layer protection on top of
  transport TLS and disk encryption?** Tokens, PII, health, financial, secrets:
  yes. A public display name: no.
- **Can you avoid storing it instead?** Hashing (passwords → Argon2id), tokenizing
  (store a reference, keep the value in a vault), or simply not collecting it
  beats encrypting it.
- **Who must read it, and where?** If only an edge function decrypts, the key
  never touches the client. If the client must decrypt, you need end-to-end key
  delivery, not server-side keys.

State these answers before you choose an algorithm.

## Step 1 — Pick the primitive; never roll your own

Default to a vetted AEAD (authenticated encryption with associated data). AEAD
gives you confidentiality **and** integrity in one operation — the ciphertext
cannot be tampered with undetected.

- **AES-256-GCM** — hardware-accelerated, ubiquitous. Caveat: a repeated nonce
  with the same key is catastrophic (leaks the auth key). Never reuse a nonce.
- **XChaCha20-Poly1305** — 192-bit random nonces, so random generation is safe
  (no birthday-bound worry). Prefer it when you generate nonces randomly at
  volume, or where AES has no hardware support.

Rules that are not negotiable:

- **Never** use ECB, unauthenticated CBC, or "encrypt then nothing." If you see
  `createCipheriv('aes-256-cbc', ...)` with no MAC, that is a bug.
- **Never** invent a construction (XOR, custom padding, home-grown KDF).
- Bind context with the AAD parameter: pass the row id, tenant id, or column
  name as associated data so a ciphertext copied to another row fails to decrypt.

```ts
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

function seal(key: Buffer, plaintext: Buffer, aad: Buffer) {
  const iv = randomBytes(12);                    // 96-bit GCM nonce
  const c = createCipheriv("aes-256-gcm", key, iv);
  c.setAAD(aad);
  const ct = Buffer.concat([c.update(plaintext), c.final()]);
  return { iv, ct, tag: c.getAuthTag() };        // store all three + key id
}
```

In Dart use `cryptography`'s `AesGcm.with256bits()` or `Xchacha20.poly1305Aead()`;
do not reach for `dart:io` raw ciphers.

## Step 2 — Build a key hierarchy with envelope encryption

Do not encrypt data directly with a key you keep in a KMS — that means a KMS
round-trip per record and a blast radius of "all data" if that key leaks. Use
**envelope encryption**:

1. A **KEK** (key-encryption key) lives in a KMS/HSM and never leaves it. You
   call the KMS to wrap/unwrap, never to encrypt your payload.
2. A **DEK** (data-encryption key) is a fresh random 256-bit key that does the
   actual record/field encryption.
3. Store the DEK **wrapped by the KEK** next to the ciphertext. To read: unwrap
   the DEK via KMS, decrypt locally, discard the plaintext DEK from memory.

This gives cheap rotation (re-wrap DEKs, or rotate the KEK without re-encrypting
data) and a small KMS surface. Grant the wrap/unwrap permission narrowly — the
service identity that decrypts should not be the same one that can disable or
delete the KEK.

## Step 3 — Get keys out of the codebase

The key material itself is the whole game. Where it lives matters more than the
cipher.

- KEKs live in a managed KMS/HSM (cloud KMS, HashiCorp Vault transit, a hardware
  module). The application holds only the *ability to call* wrap/unwrap.
- For a Supabase backend, the KEK or a master secret lives in edge-function
  secrets / Vault, **never** in client-shipped config and never in a row a
  client-readable RLS policy can reach. Decrypt only inside the edge function.
- Never log keys, plaintext DEKs, IVs paired with their key, or plaintext. Scrub
  them from error objects. See [[secrets-and-config-management]] and
  [[logging-hygiene]].
- Zero key buffers after use where the language allows; treat any key in a debug
  dump as compromised.

## Step 4 — Choose deterministic vs randomized deliberately

Randomized (a fresh nonce every time) is the default and is what AEAD wants:
encrypting the same value twice yields different ciphertext, so an attacker
learns nothing from equality.

Choose **deterministic** encryption *only* when you must query by exact value
(e.g. look up a user by encrypted email). Understand the cost: equal plaintexts
produce equal ciphertexts, which leaks duplicates and frequency.

- Derive deterministic ciphertext with a synthetic IV (SIV mode) or a keyed
  hash of the plaintext as the nonce — never a constant nonce on GCM.
- Prefer a **blind index** instead: store randomized ciphertext for the value
  *plus* a separate HMAC-of-plaintext column to query on. The HMAC key is its
  own secret. This keeps the stored value strongly hidden while enabling exact
  lookups, and you can truncate the index to trade precision for less leakage.
- Never use deterministic encryption for low-entropy fields (booleans, status,
  small enums) — frequency analysis recovers them trivially.

## Step 5 — Plan rotation before you ship, not after

Every ciphertext must record **which key encrypted it**. Without a key id you
can never rotate.

- Prepend a small header to every ciphertext: a version byte, a key id, the
  algorithm id, then the IV and tag. This is your crypto-agility envelope —
  it lets you change cipher or key without a flag day.
- **KEK rotation:** create a new KEK version, re-wrap DEKs lazily on next read or
  via a background pass. Old data stays readable because its key id still
  resolves.
- **DEK rotation / re-keying:** decrypt with the old DEK, re-encrypt with a new
  one, update the key id. Do this in batches; make it idempotent and resumable.
- **On suspected key compromise**, rotation is not enough — you must re-encrypt
  everything that key could touch and revoke the old key. Design so that scope is
  bounded (per-tenant DEKs limit it to one tenant).
- Test the rotation path in CI with a fixture encrypted under an old key id; a
  rotation you have never run is a rotation that does not work.

## Step 6 — Verify the implementation adversarially

Crypto bugs pass happy-path tests. Prove these explicitly:

- **Tampering is rejected:** flip one ciphertext byte, one tag byte, and one AAD
  byte — each must fail to decrypt, not return garbage.
- **Nonce uniqueness:** assert IVs are random per-encryption; add a test that
  encrypting the same value twice yields different ciphertext (unless
  deterministic mode is the explicit intent).
- **Wrong-context rejection:** a ciphertext from row A must not decrypt when
  presented with row B's AAD.
- **No silent fallback:** confirm an unknown key id or algorithm id raises, never
  defaults to plaintext or a legacy weak path.
- Use known-answer test vectors for the primitive so a library swap can't change
  behavior unnoticed.

Treat unproven crypto as broken; see [[debugging-and-error-recovery]] and
[[threat-modeling]] for surfacing where keys and plaintext flow.

## Anti-patterns

- A single global key for all data, all tenants, forever.
- Storing the key in the same table/row as the ciphertext, or in client config.
- Reusing a GCM nonce; using a counter that resets; using time as a nonce.
- Encrypting without authentication (no tag / no AAD), then trusting the result.
- Deterministic encryption chosen for indexing convenience without weighing leakage.
- No key id in the ciphertext, so rotation is impossible.

When committing crypto changes, defer to [[commit-pipeline]]; never weaken a
construction to make a test green.
