---
description: Run the full exoplanet release flow with blocking gates and rollback steps.
argument-hint: [patch|minor|major]
---

You are running the exoplanet release process. Follow the phases below in order. **Each gate is blocking — abort the release on any failure and apply the matching rollback.** Do not skip steps, do not bypass `mix precommit`, do not force-push, do not delete tags from the remote.

`$ARGUMENTS` may contain a bump type (`patch` | `minor` | `major`). If absent, infer from conventional commits and confirm with the user before continuing.

---

## Phase 1 — Preflight (gate)

```bash
git status --porcelain                    # must print nothing
git rev-parse --abbrev-ref HEAD           # must be "main"
git pull --ff-only origin main
```

**Abort conditions:** dirty working tree, not on `main`, or remote diverged. **Rollback:** none — the user fixes the working tree and re-runs `/release`. Do not stash or commit changes silently.

---

## Phase 2 — Precommit (gates)

```bash
mix deps.get
mix precommit
```

**Abort conditions:** either command exits non-zero. **Rollback:** none — fix the failure and re-run `/release`. Never edit `mix.exs` aliases or skip steps to make this pass.

---

## Phase 3 — Compute version bump

```bash
LAST_TAG=$(git tag --sort=-v:refname | head -1)   # e.g. v0.4.1
git log "$LAST_TAG"..HEAD --pretty=format:"%h %s"
```

(`git describe --tags --abbrev=0` skips lightweight tags and silently picks an older annotated tag — v0.4.0 / v0.4.1 are lightweight in this repo.)

If `$ARGUMENTS` is `patch` / `minor` / `major`, use it. Otherwise infer from the commit list using conventional commit prefixes:

- `feat!:` or `BREAKING CHANGE:` footer → **major**
- `feat:` → **minor**
- `fix:` / `perf:` → **patch**
- `chore:`, `docs:`, `test:`, `refactor:`, `style:` → no bump on their own; usually excluded from the changelog

Show the proposed bump (and the commit list it was derived from) and confirm with the user via `AskUserQuestion` before continuing. Compute the new version from `@version` in `mix.exs`.

---

## Phase 4 — Update CHANGELOG.md and mix.exs

Read `CHANGELOG.md` entries for v0.4.1, v0.4.0, and v0.3.0 first to mirror their tone and format:

- Keep a Changelog structure: `## [X.Y.Z] - YYYY-MM-DD`, with `### Added` / `### Changed` / `### Fixed` / `### Removed` subsections (omit empty ones).
- Multi-line bullets that explain the _why_, not just the _what_. Reference modules/functions in backticks (e.g. `Exoplanet.Filters.merge/2`). Only backtick **public** modules — `mix docs --warnings-as-errors` fails on backticked references to `@moduledoc false` modules (notably `Exoplanet.Parser`). Use prose like "the feed parser" / "the internal Exoplanet.Parser module" without backticks for hidden modules.
- Call out breaking changes with a leading `**Breaking:**` on the bullet.
- Skip pure-internal commits (test refactors, doc tweaks, dep bumps) unless they affect public behaviour.
- Be brief.

Then:

1. Move the contents of the existing `## [unreleased]` section into a new `## [X.Y.Z] - YYYY-MM-DD` section directly below it. Date is today's UTC date.
2. Leave `## [unreleased]` empty above the new section.
3. Update `@version "X.Y.Z"` in `mix.exs` (line near the top of the module).
4. Re-run `mix precommit` so newly-introduced doc warnings (e.g. backticked references to hidden modules in the CHANGELOG entry) fail locally rather than escaping to CI. Phase 2's run happened before these edits — it does not cover them.

**Rollback if anything goes wrong before commit:**

```bash
git restore CHANGELOG.md mix.exs
```

---

## Phase 5 — Release branch + PR

```bash
git checkout -b "release/vX.Y.Z"
git add CHANGELOG.md mix.exs
git commit -m "chore: prepare vX.Y.Z release"
git push -u origin "release/vX.Y.Z"
```

Open a PR using the changelog entry as the body:

```bash
gh pr create --title "chore: prepare vX.Y.Z release" --body "$(cat <<'EOF'
## Summary

<paste the new ## [X.Y.Z] CHANGELOG section here, without the date header>

## Test plan

- [ ] CI green on the release branch
- [ ] `mix precommit` passes locally
- [ ] CHANGELOG entry mirrors v0.4.x tone (concise prose, backticked code, why-not-what)
EOF
)"
```

**Rollback if branch creation, commit, push, or PR creation fails:**

```bash
git checkout main
git branch -D "release/vX.Y.Z"
git push origin --delete "release/vX.Y.Z"   # only if push succeeded earlier
```

Report the failure to the user and stop. Do not retry blindly.

---

## Phase 6 — Tag + Hex publish (after PR merges)

The user merges the PR manually. Wait for confirmation, then:

```bash
git checkout main
git pull --ff-only origin main

# Sanity: HEAD's commit subject should be "chore: prepare vX.Y.Z release"
git log -1 --pretty=%s

git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
git push origin "vX.Y.Z"
```

Verify the tag propagated to GitHub. Annotated tags have two layers — the tag object and the commit it points at — so verify both:

```bash
TAG_SHA=$(gh api "repos/milmazz/exoplanet/git/refs/tags/vX.Y.Z" --jq '.object.sha')
[ "$TAG_SHA" = "$(git rev-parse vX.Y.Z)" ] || { echo "tag-object SHA mismatch"; exit 1; }

# Dereference the tag to its commit and confirm it matches local
gh api "repos/milmazz/exoplanet/git/tags/$TAG_SHA" --jq '.object.sha'
# must equal `git rev-parse vX.Y.Z^{}`
```

If either comparison differs, stop and investigate before publishing to Hex. (Comparing `.object.sha` directly to `git rev-parse vX.Y.Z^{}` is wrong — for annotated tags those are always different: one is the tag-object SHA, the other is the commit SHA.)

Publish to Hex. **The user must run this in their own terminal** — `mix hex.publish` blocks on `Proceed? [Yn]` *and* prompts for a 2FA code, neither of which can be supplied through Claude Code's Bash tool. Ask the user to run it via `! mix hex.publish` (or in another shell) and report back when it prints `Package published to https://hex.pm/packages/exoplanet/X.Y.Z`:

```bash
mix hex.publish
```

Verify Hex propagation:

```bash
mix hex.info exoplanet | head -5     # latest version should now be X.Y.Z
```

**Rollback matrix for Phase 6:**

| Failure point                                                      | Action                                                                                                                                           |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `git tag` / `git push origin <tag>` fails                          | Delete local tag (`git tag -d vX.Y.Z`); fix and retry. Do **not** delete a tag that already reached the remote without confirming with the user. |
| Tag pushed but `gh api` shows mismatch                             | Stop. Investigate (force-push? wrong commit?). Do not publish to Hex.                                                                            |
| Tag pushed, Hex publish fails                                      | Tag stays. Fix the Hex issue (auth, package config) and rerun `mix hex.publish`. Do **not** retag.                                               |
| Hex publish succeeded, `mix hex.info` doesn't show new version yet | Wait 1–2 min; Hex CDN propagation. Re-check before continuing.                                                                                   |

---

## Phase 7 — GitHub release notes

Draft release notes from the new CHANGELOG section. Tone reference: v0.4.0's release notes (multi-paragraph for `### Added`, terse for `### Fixed`).

```bash
gh release create "vX.Y.Z" \
  --title "vX.Y.Z" \
  --verify-tag \
  --notes "$(awk '/^## \[X.Y.Z\]/{flag=1;next} /^## \[/{flag=0} flag' CHANGELOG.md)"
```

(Substitute the literal version into both the `--title` and the `awk` pattern.)

**Rollback:** `gh release delete vX.Y.Z --cleanup-tag=false` removes the release without touching the tag. Keep the tag — it's the source of truth that the package is published to Hex.

---

## Final report to the user

Summarise:

- Version released (`vX.Y.Z`) and bump type
- PR URL (Phase 5) and merge commit SHA
- Hex package URL: `https://hex.pm/packages/exoplanet/X.Y.Z`
- GitHub release URL (Phase 7)
- Anything skipped, deferred, or that needed manual intervention
