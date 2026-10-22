---
name: store-review-readiness
description: Audit a mobile app for App Store and Google Play rejection risks and security gaps before it is submitted. Covers Apple's App Review Guidelines, Google Play policy, privacy (purpose strings, privacy manifest, Data safety, third-party AI consent), in-app purchase and subscription rules, account deletion, release-build hygiene and OWASP MASVS, and ends in one report that separates what to fix in code from what to change in App Store Connect / Play Console. Trigger when the user is about to release, submit or resubmit an app ("sắp release", "review store", "đưa app lên store", "submit app", "check trước khi release"), when a store rejection or policy email arrives, or before a first store launch.
---

# Store Review Readiness

A store rejection costs days, not minutes: every round trip is a new binary, a new build number and
another wait in the queue. The reviewer also tests things you did not: an iPad, a fresh sandbox
account, a declined permission, a tab you thought was harmless. This skill finds those before they do.

It complements, not replaces:

- [[mobile-release-and-app-store]] — rollout, force-update gates and crash monitoring *after* approval.
- [[security-and-hardening]] — fixing the security findings this audit raises.
- [[data-privacy-and-compliance]] — the legal side of what the privacy findings touch.

## When to use

- "We're about to release / submit / resubmit", or the build is going to TestFlight / a Play test track
  for the last time before review.
- A rejection message from App Review or a Play policy email arrived (go to Step 6 first).
- First launch of an app on a store, or a new store account.

Not for: a routine internal build, or a backend-only release.

## Ground rules

- **Evidence or it did not happen.** Every ✅ needs a file:line, a command output, a test, or a
  screenshot. "I read the code and it looks fine" is ⚠, not ✅.
- **Read before you report.** A grep hit is a lead, not a finding. Open the file, follow the call,
  confirm it is reachable in the *release* build of the *production* flavor.
- **Store rules move.** Facts with a date (SDK floors, target API levels, new guidelines) are marked
  "verified YYYY-MM-DD" in the references. If that date is older than ~3 months, re-check the official
  page before quoting it — see [[source-driven-development]].
- **Split by who can fix it.** Code (you), store console (whoever owns the account), backend, or a
  product/legal decision. A report that mixes them leaves half of it undone.
- **Decisions are the user's.** If a fix changes what users see or pay (hide a feature, drop a
  discount, add a consent screen), present options and let them choose.

## Workflow

### Step 1 — Scope the release

Write these down before checking anything:

- Platforms (iOS, Android, both) and the stores (App Store, Google Play, others).
- The exact version and build number going up, and the **commit** it will be built from. A fix merged
  after the release commit is not in the binary.
- What changed since the last approved build (`git log <last-release-tag>..HEAD`), and anything that
  touches sign-in, payments, permissions, data collection, or account management.
- Past rejections: ask for the last rejection messages and any audit doc in the repo. Old rejections
  are the best predictor of new ones.
- Does the app have: login? subscriptions or IAP? user-generated content? health, finance or kids
  content? AI features that send user data out? Each "yes" switches on a block in the references.

### Step 2 — Run the automated sweep

```bash
# the script ships in this skill's folder (the plugin cache when installed as a plugin)
bash <this-skill-dir>/scripts/store-sweep.sh <app-root>
```

The script greps for the usual suspects: placeholder / "coming soon" copy, no-op handlers, debug output
in release, TLS bypasses, cleartext / ATS exceptions, Info.plist purpose strings and background modes,
Android permissions and SDK levels, secrets and keystores in git, and the presence of a privacy
manifest. It never edits anything. Each hit is a lead for Step 3.

Also run the project's own gates (`flutter analyze` / `flutter test`, `./gradlew lint`, `xcodebuild
test`, …) so a broken build does not hide behind a compliance report.

### Step 3 — Walk the checklists

Go through the references that apply. They are written as *check → how → fix*:

| Reference | Covers |
| :-- | :-- |
| [references/apple-app-review.md](references/apple-app-review.md) | App Review Guidelines by number, App Store Connect metadata, IAP, privacy manifest, toolchain floor |
| [references/google-play-policy.md](references/google-play-policy.md) | Target API, 16 KB pages, AAB / signing, Data safety, permissions, Payments, account deletion, declarations |
| [references/mobile-security.md](references/mobile-security.md) | OWASP MASVS v2 categories with concrete checks for the release build |

Large apps: split the walk across parallel subagents by reference (Apple / Google / security), each
returning findings with file:line, then verify the high-severity ones yourself before reporting.

The patterns that cause the most rejections, all seen in real reviews, are in
[Common rejection patterns](#common-rejection-patterns) below — check every one.

### Step 4 — Rate each finding

| Severity | Meaning |
| :-- | :-- |
| **Blocker** | Certain rejection or policy violation (missing account deletion, non-IAP unlock, missing purpose string, target API too low, IAP not submitted). |
| **High** | Likely rejection, depends on the reviewer (dead control, hard paywall with no way out, vague trial copy). |
| **Medium** | Rejection possible, or a real user or security harm (silent failures, tokens in plaintext). |
| **Low** | Hygiene (leftover keys, unused permissions with no prompt). |

Tag each with **Owner**: `code` · `console` · `backend` · `decision`.

### Step 5 — Fix and verify

- Fix the `code` items on a branch, with a test per behavior change (see
  [[test-driven-development]]); show the test fails on the old code where you can.
- Re-run the sweep and the project's gates after the fixes.
- Things only a device can prove (StoreKit sandbox, real purchase sheet, permission prompts, iPad
  layout) stay ⚠ until someone runs them — say so.
- Bump the build number for the new binary, and make sure the release commit is *after* every fix.

### Step 6 — When answering a rejection

1. Copy the rejection text verbatim. One row per guideline cited, in the order Apple/Google listed them.
2. For each row: is it code, console, or a reply? Find the evidence that it is fixed — commit, file:line,
   test — and **check that commit is in the build you will upload**.
3. Read each item literally *and* as a class. "The Community button was unresponsive" means every
   dimmed or inert control; "discount codes" means every code that changes a price, not just the field
   that was removed.
4. Note the review device. Apple reviews iPhone-only apps on iPad too; the bug must be reproduced there.
5. Draft the Resolution Center reply and the App Review notes (demo account, how to reach each feature,
   anything that looks odd but is intended).

### Step 7 — Report

Use [report-template.md](report-template.md). It must contain: the release scope (version, build,
commit), one line per finding with severity, owner, evidence and fix, a separate checklist of console
actions, a draft of review notes, and a QA handoff. Lead with whether the release is ready; if it is
not, say what blocks it in the first sentence.

## Common rejection patterns

Each line: what reviewers hit → what to look for → the usual fix.

**Completeness (Apple 2.1, Play "broken functionality")**
- A dimmed or "disabled" control that does nothing on tap, including tabs for unreleased features →
  `onTap: () {}`, `onPressed: null` on a visible button, opacity-only "disabled" states → hide it, or make
  it work. A dimmed tab is read as a broken tab.
- "Coming soon", lorem ipsum, sample data, or a toast instead of a feature → user-visible strings and
  their call sites → remove the entry point until the feature ships.
- Debug info on screen in release (sandbox flags, user IDs, product IDs, env names) → dialogs after
  purchase, about screens, error screens → guard with the release-mode flag.
- The reviewer cannot get in: login needs an SMS to a number they don't have, a region-locked phone
  picker, an invite code, real hardware or a real place → demo account with full access in the review
  notes, a fixed test OTP, or a demo mode.
- IAP products referenced by the app but not submitted with the binary (Apple 2.1(b)) → every product
  the paywall can show must be submitted, with a review screenshot.
- A feature that needs something the reviewer lacks (a gym machine, a barcode, a paired device) →
  attach a demo video or test images in the notes.

**Payments (Apple 3.1.1 / 3.1.2, Play Payments)**
- A code typed in the app that unlocks or discounts digital content — promo, referral, partner,
  coupon — even if the purchase still goes through IAP → on iOS use App Store offer codes; keep in-app
  codes for attribution only.
- Free access granted server-side (ambassadors, staff, partners) → explain in review notes; never let a
  user grant it to themselves in the app.
- Trial copy that the store does not back: hard-coded length, shown to users no longer eligible, "free"
  on a paid intro offer → read the length from the product, check eligibility, show only when free.
- Missing subscription disclosure: title, length, price per period, auto-renewal and how to cancel,
  functional links to Terms of Use (EULA) and Privacy Policy, Restore Purchases on the paywall.
- Legal links that point to a vendor's page (the payment SDK's terms) instead of the app's own.
- A paywall that cannot be closed and hides Settings → keep log out and account deletion reachable from
  it (Apple 5.1.1(v)).

**Sign-in (Apple 4.8 / 5.1.1)**
- Asking for name or email after Sign in with Apple → use what Apple gives on the first authorization,
  save it to the account immediately (it is given once), skip the step.
- A third-party social login offered without an equivalent privacy-preserving option on iOS (4.8).
- A social login button on a platform where it cannot work (Sign in with Apple on Android showing an
  error) → hide it there.
- Login forced before any content when the app has no significant account features (5.1.1(v)).

**Privacy (Apple 5.1.x, Play User Data)**
- Purpose strings that don't say *what for* with an example, leftovers from another app, a language
  mismatch, or strings for permissions the app never asks for → rewrite or drop the permission.
- Personal data sent to a third-party AI without disclosure and explicit permission (Apple 5.1.2(i)).
- No in-app account deletion; on Play also no public web page to request it.
- Data safety / App Privacy labels that disagree with what the SDKs in the binary collect.
- Health or fitness data used beyond the feature, or medical-sounding advice without a disclaimer.

**Metadata (Apple 2.3, Play Store listing)**
- Age rating answers that claim features the app lacks (e.g. "In-App Controls: Parental Controls"
  with no parental controls) → answer "None".
- Screenshots or creative assets that show pricing, other platforms, or features not in the build.

**Platform hygiene**
- Background modes declared but unused (Apple 2.5.4); Android permissions declared but unused, broad
  photo/storage access where the picker would do (Play).
- Toolchain floors: App Store Connect requires a minimum Xcode/SDK, Google Play a minimum target API —
  check the references for the current values.

## Red flags

- "Fixed" with no commit, test or screenshot behind it.
- A fix merged after the release commit, or a build number that did not move.
- Checking only the screen in the rejection screenshot, not the same pattern elsewhere.
- Testing on the phone you develop on, never on a fresh install, an iPad, or a declined permission.
- Answering a policy question (age rating, data safety) from memory instead of from the binary.
- A paywall, login or permission flow changed in the last week with no device test.

## Done when

- Every finding is ✅ with evidence, or ⚠ with the reason and who will check it, or ❌ with an owner.
- The console checklist has an owner for each line.
- The build number is bumped and the release commit contains every code fix.
- Review notes are drafted (demo account, feature walkthrough, explanations).
- The report says plainly whether the release is ready.
