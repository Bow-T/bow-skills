#!/usr/bin/env bash
# store-sweep.sh — read-only sweep for common App Store / Google Play rejection and security leads.
#
# Usage: store-sweep.sh [app-root]      (defaults to the current directory)
#
# Every hit is a LEAD, not a finding: open the file and confirm it is reachable in the release
# build of the production flavor before reporting it. The script never modifies anything.
# Works with Flutter, React Native and native iOS/Android layouts; sections with nothing to look at
# are skipped. Exit code is always 0.

set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "No such directory: $ROOT" >&2; exit 0; }
MAX="${STORE_SWEEP_MAX:-15}"   # hits shown per check

EXCLUDE_DIRS=(--exclude-dir=.git --exclude-dir=build --exclude-dir=.dart_tool --exclude-dir=Pods
  --exclude-dir=node_modules --exclude-dir=.gradle --exclude-dir=DerivedData --exclude-dir=generated
  --exclude-dir=gen --exclude-dir=.symlinks --exclude-dir=ephemeral --exclude-dir=test
  --exclude-dir=tests --exclude-dir=__tests__ --exclude-dir=integration_test --exclude-dir=.fvm)
EXCLUDE_FILES=(--exclude=*.g.dart --exclude=*.gr.dart --exclude=*.freezed.dart --exclude=*.mocks.dart
  --exclude=*.min.js --exclude=*.lock --exclude=*.map)
CODE=(--include=*.dart --include=*.kt --include=*.java --include=*.swift --include=*.m
  --include=*.ts --include=*.tsx --include=*.js --include=*.jsx)
COPY=(--include=*.arb --include=*.json --include=*.strings --include=*.xml --include=*.yaml
  --include=*.yml)

section() { printf '\n== %s\n' "$1"; }
note() { printf '   %s\n' "$1"; }

# grep_leads <description> <regex> <include-set-name> [extra grep flags...]
grep_leads() {
  local title="$1" regex="$2" set="$3"; shift 3
  local -a inc
  if [ "$set" = code ]; then inc=("${CODE[@]}"); elif [ "$set" = copy ]; then inc=("${COPY[@]}");
  else inc=("${CODE[@]}" "${COPY[@]}"); fi
  local out
  # Comment lines are dropped; LEAD_FILTER (a regex) drops known-harmless hits for one check.
  out=$(grep -rnE "$@" "${inc[@]}" "${EXCLUDE_DIRS[@]}" "${EXCLUDE_FILES[@]}" -e "$regex" . 2>/dev/null |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|/\*|\*|#)' |
    { if [ -n "${LEAD_FILTER:-}" ]; then grep -vE "$LEAD_FILTER"; else cat; fi; })
  if [ -n "$out" ]; then
    printf -- '-- %s (%s)\n' "$title" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
    printf '%s\n' "$out" | head -n "$MAX" | cut -c1-220 | sed 's/^/   /'
  else
    printf -- '-- %s: none\n' "$title"
  fi
}

echo "store-sweep: $(pwd)"
[ -f pubspec.yaml ] && note "Flutter: $(grep -m1 -E '^version:' pubspec.yaml)"
[ -f package.json ] && note "Node/RN: $(grep -m1 '"version"' package.json | tr -d ' ,')"

section "Completeness (Apple 2.1, Play broken functionality)"
grep_leads "Placeholder / unfinished copy" \
  'coming soon|lorem ipsum|worem ipsum|bientôt disponible|próximamente|not implemented|under construction|placeholder text' \
  all -i
grep_leads "No-op handlers" \
  'on(Pressed|Tap|LongPress|Changed|Press)[[:space:]]*[:=][[:space:]]*\{?[[:space:]]*\(\)[[:space:]]*(\{[[:space:]]*\}|=>[[:space:]]*(null|\{[[:space:]]*\}))' \
  code
grep_leads "Handlers that only log" \
  'on(Pressed|Tap)[[:space:]]*:[[:space:]]*\(\)[[:space:]]*=>[[:space:]]*(print|debugPrint|log|console\.log)\(' code
grep_leads "Debug / sandbox / internal IDs rendered in UI copy" \
  '"[^"]*(is ?sandbox|app user id|entitlement id|product id|debug mode|environment)[^"]*"[[:space:]]*:' copy -i

section "Payments (Apple 3.1.1 / 3.1.2, Play Payments)"
grep_leads "Codes that may unlock or discount (promo/coupon/referral/voucher/redeem)" \
  'promo ?code|coupon|voucher|redeem|discount ?code|referral (code|discount)|code promo|code de (réduction|parrainage)' \
  all -i
grep_leads "Hard-coded trial lengths in copy" \
  '[0-9]+[ -](day|days|jours?|días?|week|semaines?)[ -]*(free )?(trial|essai|prueba)' copy -i
grep_leads "Restore purchases" 'restorePurchases|restoreTransactions|restore_purchases|AppStore\.sync' code
grep_leads "Links to vendor legal pages" 'revenuecat\.com/(terms|privacy)|stripe\.com/(legal|privacy)|adapty\.io/(terms|privacy)' all -i
grep_leads "External purchase links" '(buy|checkout|pricing|subscribe)[^"]*https?://' code -i

section "Sign-in (Apple 4.8)"
deps=$(cat pubspec.yaml package.json ios/Podfile android/app/build.gradle android/app/build.gradle.kts 2>/dev/null)
has() { printf '%s' "$deps" | grep -qiE "$1"; }
if has 'google_sign_in|@react-native-google-signin|GoogleSignIn|facebook|flutter_facebook_auth|twitter_login|linkedin'; then
  if has 'sign_in_with_apple|apple-authentication|AuthenticationServices|apple_sign_in'; then
    note "third-party login + Sign in with Apple: present — check it is offered on every auth screen,"
    note "never followed by a name/email step, and hidden where it cannot work (Android)."
  else
    note "LEAD: third-party login without Sign in with Apple (or another 4.8-compliant option)."
  fi
else
  note "no third-party login dependency found"
fi
grep_leads "Apple sign-in 'not supported' paths" 'apple.*not (supported|available)|appleSignInNotAvailable' all -i

section "Privacy (Apple 5.1.x, Play User Data)"
grep_leads "Account deletion entry points" 'delete[_ ]?(my[_ ]?)?account|deleteAccount|account[_ ]deletion' all -i
grep_leads "Third-party AI / LLM calls, or endpoints that may reach one (5.1.2(i) consent)" \
  'openai|chatgpt|gpt-[0-9]|anthropic|claude-[0-9a-z]|gemini|generativeai|vertexai|bedrock|mistral|@(POST|PUT|Post|Put)\(['"'"'"][^'"'"'"]*(/ai|chat|generat|scan|recogni|vision|completion|recipe|analy[sz])' \
  code -i
grep_leads "Tracking / analytics SDK calls" 'FirebaseAnalytics|logEvent\(|AppsFlyer|Adjust\.|Amplitude|Mixpanel|Segment|AppTrackingTransparency|requestTrackingAuthorization' code

section "iOS configuration"
for plist in $(find ios -name Info.plist -not -path '*/Pods/*' -not -path '*/build/*' -not -path '*/.symlinks/*' -not -path '*Tests*' 2>/dev/null); do
  note "file: $plist"
  awk '/<key>NS[A-Za-z]*UsageDescription<\/key>/{k=$0; getline; gsub(/^[ \t]+|<\/?key>|<\/?string>/,"",k); gsub(/^[ \t]+|<\/?string>/,""); print "   " k ": " $0}' "$plist"
  awk '/<key>UIBackgroundModes<\/key>/{f=1;next} f&&/<\/array>/{f=0} f&&/<string>/{gsub(/[ \t]|<\/?string>/,""); print "   UIBackgroundModes: " $0 "  (each needs code that uses it — 2.5.4)"}' "$plist"
  grep -q ITSAppUsesNonExemptEncryption "$plist" || note "LEAD: ITSAppUsesNonExemptEncryption not set (export compliance asked on every upload)"
  grep -qE 'NSAllowsArbitraryLoads|NSExceptionAllowsInsecureHTTPLoads' "$plist" && note "LEAD: ATS exception allows cleartext HTTP"
  grep -q NSBonjourServices "$plist" && ! grep -q NSLocalNetworkUsageDescription "$plist" && note "LEAD: NSBonjourServices without NSLocalNetworkUsageDescription (debug-only key in release?)"
done
loc=$(find ios -name 'InfoPlist.strings' -not -path '*/Pods/*' 2>/dev/null)
[ -n "$loc" ] && note "Localized InfoPlist.strings (override Info.plist purpose strings): $(echo $loc)"
if [ -d ios ]; then
  pm=$(find ios -name PrivacyInfo.xcprivacy -not -path '*/Pods/*' -not -path '*/.symlinks/*' 2>/dev/null)
  [ -n "$pm" ] && note "PrivacyInfo.xcprivacy: $pm" || note "LEAD: no PrivacyInfo.xcprivacy in the app target"
  fam=$(grep -hE 'TARGETED_DEVICE_FAMILY' ios/*.xcodeproj/project.pbxproj 2>/dev/null | tr -d ' \t;' | sort | uniq -c | tr '\n' ' ')
  [ -n "$fam" ] && note "TARGETED_DEVICE_FAMILY values (project + targets): $fam — Apple reviews on iPad either way"
  ent=$(find ios -name '*.entitlements' -not -path '*/Pods/*' 2>/dev/null)
  [ -n "$ent" ] && note "Entitlements: $(echo $ent)"
fi

section "Android configuration"
for g in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$g" ] || continue
  note "file: $g"
  grep -nE 'targetSdk|compileSdk|minSdk|versionCode|minifyEnabled|isMinifyEnabled|shrinkResources|debuggable' "$g" | sed 's/^/   /'
done
for m in $(find android/app/src -name AndroidManifest.xml 2>/dev/null); do
  note "file: $m"
  grep -oE 'uses-permission[^>]*android:name="[^"]+"[^>]*' "$m" |
    sed -E 's/.*android:name="([^"]+)"(.*tools:node="remove".*)?.*/\1 \2/; s/ .*tools:node="remove".*/ (removed with tools:node="remove")/; s/ +$//; s/^/   permission: /'
  grep -q 'allowBackup="false"' "$m" || { grep -q '<application' "$m" && note "LEAD: android:allowBackup not false (tokens in prefs go to backup)"; }
  grep -q 'usesCleartextTraffic="true"' "$m" && note "LEAD: usesCleartextTraffic=true"
  grep -n 'exported="true"' "$m" | sed 's/^/   exported: /'
  grep -nE -A2 'API_KEY"' "$m" | grep -E 'android:value="(\$\{[^}]*\})?"' |
    sed 's/^/   LEAD: API key meta-data with an empty or placeholder value: /'
done
note "Merged manifest (what Play sees): ./gradlew :app:processReleaseManifest, then build/intermediates/merged_manifests/"

section "Security (MASVS)"
grep_leads "TLS validation bypass" \
  'badCertificateCallback|onBadCertificate|allowBadCertificates|TrustAllCerts|ALLOW_ALL_HOSTNAME_VERIFIER|setHostnameVerifier|checkServerTrusted\([^)]*\)[[:space:]]*\{[[:space:]]*\}' code
LEAD_FILTER='schemas\.android\.com|www\.w3\.org|apple\.com/DTDs|http://(localhost|127\.0\.0\.1|10\.0\.2\.2)|xmlns' \
  grep_leads "Cleartext http:// URLs" 'http://[^"'"'"' ]+' all
grep_leads "Logging that may leak secrets" \
  '(print|debugPrint|log|console\.log|Log\.[dviwe]|NSLog)\(.*(token|password|authorization|bearer|secret|otp)' code -i
grep_leads "HTTP loggers with headers/bodies" 'PrettyDioLogger|LogInterceptor|HttpLoggingInterceptor|requestHeader:[[:space:]]*true' code
grep_leads "Credentials in plain preferences" \
  '(setString|putString|setItem|UserDefaults[^)]*set)[^;]*(token|password|secret)' code -i
grep_leads "Hard-coded secrets" \
  '(api[_-]?key|secret|password|private[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_\-]{12,}' code -i
grep_leads "WebView JS bridges" 'addJavascriptInterface|JavascriptChannel|javascriptChannels|setJavaScriptEnabled\(true\)' code

section "Repository secrets (tracked files)"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked=$(git ls-files | grep -iE '\.(jks|keystore|p8|p12|pem|mobileprovision|cer)$|(^|/)key\.properties$|(^|/)\.env($|\.)' | grep -viE '\.example$|\.sample$|\.template$')
  [ -n "$tracked" ] && printf '%s\n' "$tracked" | sed 's/^/   LEAD (rotate if ever pushed): /' || note "no keystores / key.properties / .env tracked"
  git ls-files | grep -E 'google-services\.json|GoogleService-Info\.plist' | sed 's/^/   info (normal to commit, check the project id matches): /'
else
  note "not a git repository — skipped"
fi

printf '\nDone. Confirm each lead in code before reporting; see references/ for what each check means.\n'
exit 0
