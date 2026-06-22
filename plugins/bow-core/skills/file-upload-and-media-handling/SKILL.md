---
name: file-upload-and-media-handling
description: Triggers when accepting user file/image/video uploads — validation, size/type limits, virus scanning, presigned URLs, storage layout, transcoding, and serving via CDN.
---

# File Upload and Media Handling

User-supplied files are hostile input that also costs money to store and serve. Treat every byte as
untrusted until proven otherwise, and never let bytes flow through your app server when the storage
layer can take them directly.

## 1. Decide the upload path first

Two patterns; pick before writing code.

- **Direct-to-storage (default).** Client uploads straight to object storage via a presigned URL or
  storage SDK. Your server never touches the bytes — it only signs and records metadata. Use for
  anything over a few hundred KB, and for images/video always.
- **Proxy-through-server.** Bytes pass through your API. Only justified when you must transform or
  inspect synchronously and the file is tiny. It burns request memory and ties up workers — avoid.

Red flag: an endpoint reading `req.body` as a multipart blob for a 50 MB video. That worker is dead
for the duration of the upload.

## 2. Constrain before you accept

Set limits at the boundary, not after the file lands.

- **Size cap per type.** Avatars 2 MB, documents 25 MB, video 500 MB — different rules per bucket.
  Enforce in the presign request, not just client-side.
- **Allowed MIME + extension allowlist.** Allowlist, never blocklist. `image/jpeg`, `image/png`,
  `image/webp`, `application/pdf` — name what you accept and reject the rest.
- **Content-type is a claim, not a fact.** Validate the real bytes server-side after upload by
  sniffing the magic number. A file named `cat.png` with `MZ` header is a Windows executable.

```ts
// edge function: verify magic bytes after upload, reject mislabeled files
const SIGNATURES: Record<string, number[]> = {
  "image/png": [0x89, 0x50, 0x4e, 0x47],
  "image/jpeg": [0xff, 0xd8, 0xff],
  "application/pdf": [0x25, 0x50, 0x44, 0x46],
};

function sniff(head: Uint8Array, claimed: string): boolean {
  const sig = SIGNATURES[claimed];
  return !!sig && sig.every((b, i) => head[i] === b);
}
```

## 3. Issue a scoped presigned URL

Sign narrowly: one object key, one method, short TTL, enforced content-length and content-type.

```ts
// Supabase: signed upload URL, server-side, after auth + quota check
const objectKey = `u/${userId}/${crypto.randomUUID()}`; // never trust client filename
const { data, error } = await supabase.storage
  .from("uploads")
  .createSignedUploadUrl(objectKey, { upsert: false });
// TTL is short by default; pair with a row that records intent
```

Rules:
- **Generate the key server-side.** Client-chosen paths invite traversal and overwrite of other
  users' objects.
- **Bind the URL to the authenticated user** and check quota before signing — see
  [[rate-limiting-and-quota-design]].
- **TTL in minutes, not hours.** A leaked long-lived URL is an open write endpoint.

## 4. Storage layout

Design keys so access control and lifecycle are mechanical, not case-by-case.

```
uploads/u/{userId}/{uuid}              # tenant-isolated, opaque key
uploads/u/{userId}/{uuid}/orig.jpg     # original, never served directly
uploads/u/{userId}/{uuid}/720.mp4      # derived rendition
```

- **Prefix by tenant/user** so storage RLS / IAM policies match on a path segment.
- **Keep originals private; derive everything served.** Originals may contain EXIF GPS, full
  resolution, or unsanitized payloads.
- **Set lifecycle rules**: expire orphaned uploads (rows that never confirmed), tier cold media to
  cheaper storage. Tie cleanup cost back to [[cost-and-finops-optimization]].

## 5. Two-phase commit the metadata

The DB row is the source of truth, not the bucket. Never mark a file "ready" before bytes land.

1. **Pending:** insert a row (`status = 'pending'`) and return the presigned URL.
2. **Client uploads** to storage.
3. **Confirm:** client calls back; a storage webhook or your confirm endpoint sniffs bytes, then
   flips `status = 'ready'` and records size/dimensions/checksum.

A `pending` row with no object after its TTL is garbage — sweep it. An object with no row is an
orphan — sweep it too. This reconciliation is non-negotiable; without it storage leaks forever.

## 6. Scan and sanitize untrusted files

Do this asynchronously after upload, before the file is reachable by other users.

- **Virus/malware scan** every file that other users can download. Quarantine bucket → scanner →
  promote to served bucket on clean. Never serve straight from the upload bucket.
- **Strip metadata** from images (EXIF GPS, camera serial) — a privacy leak by default.
- **Re-encode images** through a trusted library rather than serving raw bytes; this neutralizes
  polyglot files and malformed-decoder exploits.
- **Never** pass user filenames or paths into a shell, `eval`, or SQL. See [[security-and-hardening]].

```ts
// quarantine flow, triggered by storage webhook
await scanner.check(objectKey);            // throws on detection → leave quarantined
await stripExifAndReencode(objectKey);     // produce clean derivative
await promoteToServingBucket(objectKey);   // only clean files become reachable
```

## 7. Transcode media off the request path

Image resizing and video transcoding are slow and bursty. Queue them.

- **Enqueue a job** on confirm; do not transcode inline. See [[background-jobs-and-queues]].
- **Generate renditions** the client actually needs: a few image widths, an HLS/DASH ladder for
  video, a poster frame. Don't pre-generate sizes nobody requests.
- **Make jobs idempotent** — keyed on object + rendition — so retries don't double-bill or corrupt
  output. See [[idempotency-and-exactly-once]].
- **Record progress** in the row (`processing` → `ready` / `failed`) so the UI can poll or subscribe.

In Flutter, show optimistic state immediately and reconcile when the rendition is ready:

```dart
// upload, then watch the row for the ready transition
final key = await api.requestUpload(file.lengthSync(), mime);
await storage.uploadBinary(key, bytes); // direct to bucket
state = state.copyWith(status: UploadStatus.processing);
// stream the row; flip to ready when the rendition lands
```

## 8. Serve through a CDN, signed when private

- **Public media:** serve from CDN with long cache headers and immutable, content-hashed keys so a
  new version is a new URL — never invalidate by editing in place.
- **Private media:** short-lived signed download URLs scoped to the authenticated user; let the CDN
  validate the signature at the edge so origin stays out of the hot path.
- **Set correct `Content-Type` and `Content-Disposition`.** Force `attachment` for anything
  user-uploaded that a browser might render inline (HTML, SVG) to kill stored-XSS.
- **Range requests** must work for video, or seeking breaks.

## Red flags

- Bytes flowing through your app server for files over ~1 MB.
- Trusting the client-supplied filename, path, or `Content-Type`.
- Serving from the upload/quarantine bucket before scanning.
- No reconciliation between DB rows and stored objects (guaranteed leak).
- Synchronous transcoding inside the request handler.
- Long-lived or unscoped presigned URLs.
- Serving user SVG/HTML inline from your own origin domain.
- Originals served to end users with EXIF and full resolution intact.

## Definition of done

Limits enforced at the boundary; keys server-generated and tenant-isolated; presigned URLs short and
scoped; magic-byte validation and malware scan before anything is reachable; metadata two-phase
committed with orphan sweep; transcoding queued and idempotent; served via CDN with correct headers
and signing. Commit per [[commit-pipeline]].
