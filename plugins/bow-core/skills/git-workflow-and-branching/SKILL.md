---
name: git-workflow-and-branching
description: Triggers when establishing or untangling version-control practice — branching model, rebase vs merge, conflict resolution, recovering lost work, bisecting, and history hygiene.
---

# Git workflow and branching

Git is a content-addressable graph plus a few pointers (branches, `HEAD`). Almost every "scary" situation is just a pointer in the wrong place — and pointers are cheap to move. Work from that model, not from memorized incantations.

## Pick a branching model (decide once, write it down)

- **Trunk-based** — short-lived branches off `main`, merged within a day or two, releases cut from tags or release branches. Default for app teams shipping continuously (a Flutter app + Supabase backend usually wants this).
- **Release-branch flow** — long-lived `release/x.y` branches when you must support multiple shipped versions in parallel (e.g. a mobile app stuck on an old store version). Cherry-pick fixes back; don't merge release into `main`.
- Avoid heavyweight develop/release/hotfix layer cakes unless you genuinely ship on a slow, gated cadence. Branches that live for weeks rot and conflict.

**Red flag:** a branch older than ~3 days that isn't an intentional release line. Rebase it now or it becomes a merge swamp.

## Branch naming and scope

- One branch = one reviewable unit of work. If you can't describe it in a Conventional-Commit subject, it's two branches.
- Name by intent: `feat/offline-sync`, `fix/null-jwt-refresh`, `chore/bump-supabase-cli`.
- Branch from up-to-date `main`:

```bash
git switch main && git pull --ff-only
git switch -c feat/offline-sync
```

`--ff-only` on pulls is the single best habit here: it refuses to silently create a merge commit when your local `main` has drifted, forcing you to notice.

## Rebase vs merge — the actual rule

| Situation | Use | Why |
|---|---|---|
| Updating *your own* feature branch to latest `main` | `rebase` | Linear history, your commits stay on top, clean review diff |
| Integrating a finished feature into `main` | `merge --no-ff` (or squash) | Preserves the integration point; one revertable unit |
| A branch *anyone else has pulled* | `merge` | Never rebase shared history — you rewrite commits others hold |

The line that matters: **rebase private history, merge public history.** If in doubt about whether someone else has your commits, you don't rebase.

```bash
# refresh your feature branch
git switch feat/offline-sync
git fetch origin
git rebase origin/main
# ... resolve any conflicts ...
git push --force-with-lease   # never plain --force
```

`--force-with-lease` refuses the push if the remote moved since you last fetched — it catches the case where a teammate pushed to your branch. Plain `--force` silently clobbers them.

For merging the finished branch, defer to [[commit-pipeline]] for the final commit/push step. Prefer squash-merge when the branch's intermediate commits are noise; prefer `--no-ff` when each commit is independently meaningful and bisectable.

## Resolving conflicts without panic

1. Read the markers. `<<<<<<< HEAD` is *what's on the branch you're applying onto* (during rebase, that's `main`); `>>>>>>>` is your incoming commit. During a rebase the sides feel reversed — check `git status` if unsure.
2. Resolve by *intent*, not by picking a side. Often the correct result contains pieces of both.
3. For generated files, never hand-merge — regenerate:
   - Dart: `dart run build_runner build --delete-conflicting-outputs` for `*.g.dart`.
   - Supabase types: regenerate the typed client output rather than merging it.
   - Lockfiles (`pubspec.lock`, `package-lock.json`): take one side, then re-run the install/resolve and commit the result.
4. Continue: `git add <files> && git rebase --continue`. Bail anytime with `git rebase --abort` — it's free.

```bash
# enable reusable conflict resolution; replays your past resolutions automatically
git config rerere.enabled true
```

`rerere` is the highest-leverage setting for anyone who rebases long branches — it remembers how you resolved a conflict and reapplies it next time.

**Red flag:** resolving the same conflict on every rebase. Turn on `rerere`, or your branch is too stale — merge `main` more often.

## Recovering lost work (the reflog is your undo)

Commits are nearly never gone. Branches and resets only move pointers; the commit objects survive ~30 days. Find them in the reflog:

```bash
git reflog                       # every position HEAD has held, newest first
git switch -c recovery <sha>     # resurrect a "lost" state onto a new branch
```

Common rescues:

- **Bad reset / wrong rebase:** `git reflog`, find the SHA from *before* the mistake, `git reset --hard <sha>`.
- **Deleted branch:** its tip is still in the reflog or via `git fsck --lost-found`; re-point a new branch at the SHA.
- **Committed to the wrong branch:** `git switch right-branch && git cherry-pick <sha>`, then drop it from the wrong branch.
- **Uncommitted changes blown away by checkout:** if you ever `git stash`ed them, `git stash list` / `git fsck` may surface them; un-stashed un-committed edits are genuinely unrecoverable — which is why you commit early.

**Mantra:** before any `reset --hard`, `rebase`, or force-push, note the current SHA (`git rev-parse HEAD`). That's your seatbelt.

## Bisecting to find the commit that broke it

When something regressed and you don't know which commit, binary-search instead of guessing:

```bash
git bisect start
git bisect bad                    # current commit is broken
git bisect good <known-good-sha>  # last commit you trust
# git checks out a midpoint; test it, then:
git bisect good   # or: git bisect bad
# repeat until it names the culprit
git bisect reset
```

Automate it when the test is scriptable — exit 0 = good, non-zero = bad:

```bash
git bisect run flutter test test/sync_test.dart
git bisect run npm test -- --runTestsByPath src/auth.spec.ts
```

This turns "somewhere in 200 commits" into ~8 test runs. Keep the script's exit code honest (skip with exit 125 for un-buildable commits).

## History hygiene

- Commit small and often locally; clean up *before* you publish. A private branch with messy WIP commits is fine — tidy it before review.
- Squash fixup noise interactively or with autosquash:

```bash
git commit --fixup <sha>          # mark a fix for an earlier commit
git rebase --autosquash origin/main
```

- Each commit on `main` should build and pass tests (bisect depends on this).
- Use `.gitignore` to keep build artifacts, `.env`, and generated noise out. Generated code (`*.g.dart`) is a team call — commit it only if everyone regenerates identically.
- Never rewrite published history on `main` or any shared branch.
- Never commit secrets. If one lands, rotate the credential first (rewriting history does NOT un-leak it — clones and forks still have it), then scrub. See [[secrets-and-config-management]].

## Pre-flight before pushing or merging

- [ ] Rebased (or merged) onto current `main`; branch is short-lived.
- [ ] Conflicts resolved by intent; generated files regenerated, not hand-merged.
- [ ] Each commit builds; subjects follow the convention in [[commit-pipeline]].
- [ ] No secrets, no stray debug artifacts, no unrelated changes (see [[code-review-and-quality]]).
- [ ] Pushing a rebased branch uses `--force-with-lease`, never `--force`.
- [ ] Noted the current SHA before any history-rewriting operation.
