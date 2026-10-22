# Apple App Review checklist

Source of truth: <https://developer.apple.com/app-store/review/guidelines/> (guideline text quoted
below was verified 2026-10-22, after the 2026-10-16 revision). Re-read the page if this date is old;
Apple revised the guidelines three times in 2026.

Format: **Check** — how to verify — fix. Guideline numbers in brackets.

## Toolchain and binary

- **Built with the required SDK.** Since 2026-04-28 App Store Connect only accepts iOS/iPadOS apps
  built with Xcode 26 and the iOS 26 SDK or later (verified 2026-10-22,
  <https://developer.apple.com/news/upcoming-requirements/>). — `xcodebuild -version` on the build
  machine / CI image. — Upgrade the CI image; for Flutter, a Flutter version that supports that Xcode.
- **Build number strictly greater** than any build already uploaded for that version. — App Store
  Connect → TestFlight, or the CI's last upload. — Bump it in the single source (`pubspec.yaml`
  `x.y.z+N`, `CURRENT_PROJECT_VERSION`).
- **The release commit contains every fix.** — `git merge-base --is-ancestor <fix> <release-commit>`.
- **Privacy manifest.** `PrivacyInfo.xcprivacy` in the app target declaring the app's own data
  collection and any required-reason APIs the app's code calls (UserDefaults, file timestamps, disk
  space, system boot time, active keyboards); listed third-party SDKs ship their own, signed. Missing
  declarations come back as ITMS-91053 on upload. — `find ios -name PrivacyInfo.xcprivacy`; the upload
  email. — Add the file; update SDKs that lack one.
- **Export compliance.** `ITSAppUsesNonExemptEncryption` set in Info.plist (usually `false` when only
  HTTPS/standard OS crypto is used), so every upload doesn't stop on the question.
- **Device family is what you tested.** `TARGETED_DEVICE_FAMILY` for the app target (not the project
  default). `1,2` means Apple reviews and lists it on iPad as a native app; `1` still runs on iPad in
  compatibility mode, and reviewers *do* use iPads. — Run the release build on an iPad simulator either way.

## 1 Safety

- **[1.2] User-generated content** (posts, chat, comments, profiles — since 2026-02 also random or
  anonymous chat): filter objectionable content, report, block, and a published contact. — Find every
  surface where one user sees another's content. — Add report/block and moderation before launch.
- **[1.2] Nonconsensual intimate imagery**, including AI-generated (added 2026-10-16): apps that
  generate or edit images of people must prevent it.
- **[1.4.1] Medical / physical harm.** Calorie targets, training plans, dosage, diagnosis — claims
  must be backed, and health advice needs a "not medical advice, consult a professional" disclaimer
  where the user enters conditions or receives a plan.
- **[1.3] Kids category / [1.4.x]** only if relevant: no third-party analytics or ads in Kids apps.

## 2 Performance

- **[2.1(a)] Final, complete, testable.** "Placeholder text, empty websites, and other temporary content
  should be scrubbed… include demo account info (and turn on your back-end service!)". —
  - Every tab, button and menu item does something in the production flavor; no dimmed-but-inert
    controls; no "coming soon".
  - Demo account with full (paid) access in App Review Information; if login needs an SMS / OTP, a test
    number with a fixed code.
  - The backend the reviewer hits is production and up during review.
  - Crash-free on a fresh install, on iPad, with permissions denied, offline, and on the oldest
    supported iOS.
- **[2.1(b)] IAP complete and visible.** "If you offer in-app purchases… make sure they are complete,
  up-to-date, visible to the reviewer and functional." — Every product the app can show is in *Ready
  to Submit* or approved, has a review screenshot, and is attached to this version. If a configured
  product cannot be reached in the app, explain why in the notes.
- **[2.3] Accurate metadata.** Screenshots show the current app, on the right devices (iPad screenshots
  required if the app is universal); description matches features; no other platforms' names; no
  pricing in creative assets [2.3.14, added 2026-10-16].
- **[2.3.6] Age rating answered honestly.** The questionnaire (13+/16+/18+ tiers since 2025) asks about
  in-app controls (Parental Controls, Age Assurance), capabilities, medical/wellness topics, violent
  themes. Claiming a control the app doesn't have is a rejection. — Answer "None" unless the app ships it.
- **[2.5.4] Background modes only for their purpose.** — Each `UIBackgroundModes` entry has code that
  uses it (`remote-notification` for silent push, `audio` for playback, `location` for tracking,
  `fetch`/`processing` only with BGTaskScheduler work). — Remove unused modes.
- **[2.5.19] No hidden, dormant or undocumented features** (added 2026-10-16): "Attempting to hide
  undocumented features in your app binary, such as through code obfuscation or other methods, is
  grounds for removal…". — Features behind remote flags that review can't see, dev menus reachable in
  release, kill-switched content that turns on after approval. Symbol obfuscation used for IP
  protection is not named as a violation on its own, but anything it hides must also be visible to
  review. — Remove dev menus from release builds; describe flag-gated features in the review notes.

## 3 Business

- **[3.1.1] All digital unlocks through IAP.** — Look for anything that unlocks or discounts digital
  content without the App Store: promo/coupon/referral/partner codes typed in the app, "enter code"
  fields, web checkout links, server flags the user can trigger. Apple's own wording in rejections:
  "the app uses discount codes to unlock or enable features… create offer codes for In-App Purchases."
  — iOS: App Store offer codes / promotional offers; in-app codes only for attribution.
- **[3.1.1] Restore Purchases** reachable where purchases are offered, and it reports the three
  outcomes correctly (restored / nothing to restore / failed).
- **[3.1.2] Subscriptions.** Before purchase the app shows: the subscription's title, its length, the
  price per period (from StoreKit, not hard-coded), what the user gets, the free-trial length and what
  is charged after, that it renews automatically and how to cancel, and functional links to the
  Terms of Use (EULA) and Privacy Policy — the app's own, not the payment vendor's. The App Store
  Connect description or EULA field also links the Terms.
- **Trial claims match the store.** Length from the product's intro offer, shown only when the intro
  price is free and the user is eligible (StoreKit / RevenueCat eligibility check). A reviewer's sandbox
  account often has used the trial already.
- **Hard paywall.** Allowed, but it must not hide account deletion, sign-out, or the legal links.

## 4 Design

- **[4.2] Minimum functionality.** Not a thin web wrapper; works without the developer's hardware.
- **[4.3] Spam / duplicates.** Since 2026-06, apps "indistinguishable" from existing ones can be rejected
  or removed; white-label builds need real differentiation.
- **[4.8] Login services.** With any third-party/social login for the primary account, also offer an
  equivalent option that limits data to name and email, lets the user hide the email, and doesn't track
  for ads without consent (Sign in with Apple qualifies). Offer it on *every* screen that offers the
  others (sign in and sign up).
- **Sign in with Apple experience** (cited under 4): never ask for name or email after it; Apple gives
  the name on the first authorization only — save it to the account then; handle the private relay email.

## 5 Legal / privacy

- **[5.1.1(i)] Privacy policy** linked in App Store Connect *and* inside the app, describing what is
  collected, third parties, retention and deletion.
- **[5.1.1(ii)] Consent and purpose strings.** Every `NS*UsageDescription` says what the data is for,
  with an example ("…to recognize the gym machine you point it at, e.g. a leg press"). Strings for
  permissions the app never requests: remove the permission code path, or at least make the string true.
  Localized `InfoPlist.strings` override Info.plist — check each `*.lproj`.
- **[5.1.1(iv)] No forced consent.** The app works (minus that feature) when a permission is denied; a
  denied state has a way back (close button) and a link to Settings, no loop of prompts.
- **[5.1.1(v)] Account deletion in the app** if the app creates accounts — deletes the account and its
  data (not just deactivation), reachable from settings *and* from any screen that covers the app
  (hard paywall, error screen). Subscribers are told to cancel in the store, not blocked.
- **[5.1.1(v)] No login wall** for an app without significant account features.
- **[5.1.2(i)] Data sharing and third-party AI.** "You must clearly disclose where personal data will be
  shared with third parties, including with third-party AI, and obtain explicit permission before doing
  so." — List every request that sends photos, text, health or profile data to a backend that calls an
  external AI provider. — One-time consent screen naming the provider, privacy policy and App Privacy
  label updated.
- **[5.1.2] Tracking.** Any tracking across apps/websites needs App Tracking Transparency.
- **[5.1.3] Health data** not used for advertising or data mining; HealthKit data never in iCloud.
- **App Privacy label** in App Store Connect matches what the app and its SDKs collect (Crashlytics,
  analytics, RevenueCat, Firebase Messaging all collect identifiers).

## App Store Connect checklist (console owner)

- [ ] App Review Information: demo account (with paid access), contact, notes explaining non-obvious
      flows, partner/ambassador accounts, codes that only credit referrers, hardware-dependent features.
- [ ] Every IAP / subscription: metadata complete, review screenshot, *Ready to Submit*, attached.
- [ ] Paid Apps Agreement signed, tax and banking complete (IAP fails in review otherwise).
- [ ] Age rating questionnaire re-answered honestly (in-app controls = None unless shipped).
- [ ] App Privacy answers match the binary.
- [ ] Privacy Policy URL public; Terms of Use linked in the description or the custom EULA field.
- [ ] Screenshots for every required device size, current UI, no pricing in creative assets.
- [ ] Sign in with Apple capability on the App ID; push key (APNs) uploaded to the push provider.
- [ ] Export compliance answered.
