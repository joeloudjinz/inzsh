# Releasing

Releases are automated. Nobody tags, writes notes, or uploads anything by hand.

## How a release happens

1. Open a pull request from `dev` to `main` — the usual hygiene gate applies, so link
   the driving issue and set the milestone.
2. Merge it. The push to `main` triggers the `release` workflow (the full `ci`
   workflow runs on the same push).
3. The workflow re-runs the unit and render suites.
4. semantic-release reads every commit since the last tag and picks the version from
   Conventional Commits: `feat` → minor, `fix` → patch, `!` → major. Other types
   (`docs`, `test`, `chore`) never bump on their own; if nothing releasable landed,
   it exits without releasing. It also generates the release notes from those same
   commits, still without having changed anything on disk or in git.
5. Only now, with the version known but nothing yet tagged, does its own `prepare`
   step run. It checks the notes from step 4 first (below), then builds the single-file
   bundle — `INZSH_BUNDLE_VERSION=<tag> make bundle` — so the bundle can be stamped with
   the version rather than left to guess at one. This is the one moment `_inzsh_version`
   (below) is ever anything but `source`. The git tag is not created until `prepare`
   returns, so a failed check or a failed `make bundle` aborts the release without
   leaving a tag behind.
6. Once the bundle builds, it tags `vX.Y.Z` on `main` and publishes a GitHub release
   with the notes from step 4 and the stamped `dist/inzsh.zsh-theme` attached.

## What lands where

- **Tag** — `vX.Y.Z` on `main`, pushed by the workflow, and not created until after
  the bundle in the next row has already built successfully (step 5 above).
- **Changelog** — the generated notes on the GitHub release; the releases page is the
  changelog. No `CHANGELOG.md` is committed back, because that would need a bot
  commit pushed straight to `main`.

## The notes, and why they are checked

Issue #289. Because the releases page *is* the changelog, empty notes mean this project
has no changelog — and that is exactly what happened for five releases. The preset that
renders the notes is pinned in `.github/workflows/release.yml`, and an incompatible
major of it emits a body consisting of the compare-link header and nothing else, without
failing. `@semantic-release/commit-analyzer` is unaffected by the same mismatch, so every
version was correct while every set of notes was empty and nothing reported a problem.

Two things follow, and neither is optional:

- **The preset is held at `conventional-changelog-conventionalcommits@9`.** Bumping it to
  10 silently reintroduces the bug. The default `angular` preset is not a fallback either:
  its header pattern does not match the `!` breaking marker, so `feat(config)!: …` would
  vanish from the notes — and `!` on a one-line commit is our whole breaking-change
  convention (CONVENTIONS.md).
- **`prepare` refuses to build a release whose notes have no sections.** `###` is the
  heading conventional-changelog writes above every group it renders, so its absence means
  no commit was rendered at all. The check runs before the tag exists, so a release that
  would have shipped an empty changelog aborts instead.
- **Bundle** — `dist/inzsh.zsh-theme`, built in the workflow once the version is
  known but before the tag exists (step 5) and attached as a release asset. `dist/`
  is gitignored, so this is never committed either.

## The version constant

Issue #244. `_inzsh_version` is declared once, in `inzsh.zsh-theme`, and it is not a
number — it is the literal word `source`, because a checkout has no tag to read
without a subprocess (forbidden here too: a plugin manager may re-source the entry
point every shell). That line never changes; a from-source install always says
`source` and never guesses at a version.

The only place `_inzsh_version` is ever something else is inside `tools/bundle.zsh`'s
own emitted copy of that line, stamped from the `INZSH_BUNDLE_VERSION` environment
variable when it is set — unset (a local `make bundle`), it stamps `source` too. In
CI, the release workflow is the only caller that ever sets it, and it sets it to
`${nextRelease.gitTag}` — the exact tag `tagFormat` (`.releaserc.yml`) just computed,
reused rather than re-derived, in the same `prepare` step that builds the bundle
(step 5 above).
Nothing hand-maintains a version number anywhere in the tree, so there is nothing that
can drift from the tag: the tag and the stamp are the same `nextRelease.gitTag`, read
once, in the same process.

`inzsh doctor` prints whichever `_inzsh_version` a running shell finds — `source`
from a clone or an unstamped bundle, the released tag from one built by the workflow
— and never invents a third answer (issue #245's `version` row, beside `install` and
`theme root`, in `lib/core/doctor.zsh`).

## Configuration

- `.releaserc.yml` — branches, version rules, release assets.
- `.github/workflows/release.yml` — the trigger, the test gate, the pinned
  semantic-release invocation (npx, no `package.json`).

The token is the workflow's own `GITHUB_TOKEN` with `contents: write` only — there is
no personal token to rotate.
