---
description: Audit a mobile app for App Store / Google Play rejection risks and security gaps before release
argument-hint: [app root, platform, or the rejection message to answer]
---

Apply the **store-review-readiness** skill to: $ARGUMENTS

Scope the release first (version, build number, release commit, past rejections), run the skill's
`scripts/store-sweep.sh` on the app root, walk the Apple, Google Play and mobile-security references,
and finish with the report template: verdict first, one line per finding with severity, owner
(code / console / backend / decision) and evidence. If $ARGUMENTS contains a rejection message,
answer it item by item before anything else.
