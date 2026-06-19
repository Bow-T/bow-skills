---
name: source-driven-development
description: Backs every framework-specific decision with current official documentation and a citation. Use when correctness depends on a library or framework version, when the user wants verified or up-to-date code, or any time you would otherwise write framework code from memory.
---

# Source-Driven Development

## Overview

Don't code framework specifics from memory — verify them against the official docs for the version in use, then cite the source so the user can check it. Training data ages: APIs get renamed, signatures change, yesterday's best practice becomes today's deprecation. Grounding each framework decision in an authoritative, linkable source is what makes the delivered code trustworthy.

## When to Use

- The user wants code matching current best practice for a framework
- Writing boilerplate or patterns that will be copied across the project
- The user explicitly asks for "correct", "verified", or documented code
- The framework's recommended approach matters: routing, forms, data fetching, state, auth
- Reviewing or upgrading code that leans on framework-specific patterns
- Any moment you're about to write framework code from recall

**Skip it** when correctness doesn't depend on a version (renames, typo fixes, file moves), for plain logic that behaves the same everywhere (loops, math, data structures), or when the user explicitly prioritizes speed over verification.

## The Four Steps

```
identify version → fetch the page → implement to match → cite it
```

### 1. Identify the stack and versions

Read the dependency manifest and pin exact versions:

```
pubspec.yaml      → Flutter / Dart packages
package.json      → Node / TypeScript / Supabase JS
deno.json         → Supabase Edge Functions (Deno)
requirements.txt / pyproject.toml → Python
go.mod, Cargo.toml, Gemfile → Go / Rust / Ruby
```

State what you found, plainly:

```
STACK:
- Flutter 3.24 / Dart 3.5 (pubspec.yaml)
- riverpod 2.5
- @supabase/supabase-js 2.45
→ fetching the docs that match these versions.
```

If a version is missing or ambiguous, **ask** — the version decides which pattern is correct. Don't guess.

### 2. Fetch the exact documentation page

Go to the specific page for the feature, not the homepage and not the whole docs site.

Authority order:

| Rank | Source | Examples |
|---|---|---|
| 1 | Official docs | api.flutter.dev, supabase.com/docs, riverpod.dev |
| 2 | Official blog / changelog / release notes | the project's own release posts |
| 3 | Web/platform standards | MDN, web.dev, the relevant spec |
| 4 | Runtime/compatibility data | caniuse, package changelogs |

Never treat as a primary source: forum answers, third-party tutorials or blog posts (however popular), AI-written summaries, or your own recall — verifying that recall is the entire point.

```
BAD:  open the Supabase homepage
GOOD: open supabase.com/docs/reference/dart/auth-signinwithpassword

BAD:  search "riverpod state management tips"
GOOD: open riverpod.dev/docs/concepts/providers
```

After fetching, pull out the patterns you need and note any deprecation or migration warnings. If two official sources disagree (a migration guide vs. the API reference, say), surface the discrepancy and confirm which one actually works against the installed version.

### 3. Implement to match the docs

Write code that mirrors what the page shows:

- Use the documented signatures, not remembered ones.
- If the docs show a newer approach, use it.
- If the docs mark something deprecated, don't use it.
- If the docs don't cover your case, flag that part as unverified.

When the docs and the existing code disagree, don't silently choose — surface it:

```
CONFLICT:
Existing code calls supabase.auth.signIn (legacy v1).
The v2.45 docs use signInWithPassword.
(source: supabase.com/docs/reference/dart/auth-signinwithpassword)
A) adopt the current API (signInWithPassword)
B) match existing legacy calls
→ which?
```

### 4. Cite the source

Every framework-specific choice gets a citation the user can open.

In code:

```dart
// Riverpod 2.x: AsyncNotifier for async-loaded state
// source: https://riverpod.dev/docs/providers/notifier_provider#async
class BookingsNotifier extends AsyncNotifier<List<Booking>> { /* ... */ }
```

In conversation:

```
Using signInWithPassword rather than the old signIn — v2 renamed it.
source: https://supabase.com/docs/reference/dart/auth-signinwithpassword
```

Citation rules:
- Full URLs, never shortened.
- Prefer deep links with anchors (`/page#section`) — they survive restructuring better than top-level pages.
- Quote the relevant line when the decision isn't obvious.
- Include compatibility data when recommending a platform feature.
- If you can't find documentation, say so outright:

```
UNVERIFIED: no official docs found for this pattern. Based on recall and
possibly stale. Confirm before relying on it in production.
```

Honest "I couldn't verify this" beats confident-but-wrong every time.

## Excuses vs. Reality

| Excuse | Reality |
|---|---|
| "I'm sure about this API" | Certainty isn't evidence. Stale patterns look correct and break on current versions. Verify. |
| "Fetching docs burns tokens" | A hallucinated API burns more — the user debugs for an hour before finding the signature moved. |
| "The docs won't cover it" | If they don't, that's a signal the pattern may not be officially recommended. |
| "I'll just add a 'might be outdated' note" | A hedge helps no one. Verify and cite, or clearly flag unverified. Hedging is the worst option. |
| "It's a trivial task" | Trivial code with a wrong pattern becomes a template copied into ten places before anyone notices. |

## Red Flags

- Writing framework code without checking the docs for that version
- "I believe / I think" about an API instead of a citation
- Implementing a pattern without knowing which version it targets
- Citing forums or blogs as the primary source
- Using a deprecated API because it surfaced from memory
- Not reading the dependency manifest before coding
- Delivering framework code with no citations
- Fetching a whole docs site when one page is relevant

## Done When

- [ ] Versions identified from the dependency manifest
- [ ] Official docs fetched for each framework-specific pattern
- [ ] Sources are official docs, not blogs or recall
- [ ] Code matches the installed version's documented patterns
- [ ] Non-trivial decisions carry full-URL citations
- [ ] No deprecated APIs (checked against migration guides)
- [ ] Doc-vs-code conflicts surfaced to the user
- [ ] Anything unverifiable is explicitly flagged
