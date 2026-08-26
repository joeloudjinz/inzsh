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
   it exits without releasing.
5. Once the version is decided, semantic-release's own `prepare` step builds the
   single-file bundle — `INZSH_BUNDLE_VERSION=vX.Y.Z make bundle` — so the tag exists
   before the bundle does. This is also the one moment `_inzsh_version` (below) is
   ever anything but `source`.
6. It tags `vX.Y.Z` on `main`, generates the release notes from those same commits,
   and publishes a GitHub release with the stamped `dist/inzsh.zsh-theme` attached.

## What lands where

- **Tag** — `vX.Y.Z` on `main`, pushed by the workflow.
- **Changelog** — the generated notes on the GitHub release; the releases page is the
  changelog. No `CHANGELOG.md` is committed back, because that would need a bot
  commit pushed straight to `main`.
- **Bundle** — `dist/inzsh.zsh-theme`, built in the workflow *after* the version is
  decided (step 5) and attached as a release asset. `dist/` is gitignored, so this is
  never committed either.

## The version constant

Issue #244. `_inzsh_version` is declared once, in `inzsh.zsh-theme`, and it is not a
number — it is the literal word `source`, because a checkout has no tag to read
without a subprocess (forbidden here too: a plugin manager may re-source the entry
point every shell). That line never changes; a from-source install always says
`source` and never guesses at a version.

The only place `_inzsh_version` is ever something else is inside `tools/bundle.zsh`'s
own emitted copy of that line, stamped from the `INZSH_BUNDLE_VERSION` environment
variable when it is set — unset (a local `make bundle`), it stamps `source` too. The
release workflow is the only caller that ever sets it, and it sets it to
`v${nextRelease.version}` — the exact tag semantic-release is about to create,
computed in the same `prepare` step that builds the bundle (step 5 above; see
`.releaserc.yml`).
Nothing hand-maintains a version number anywhere in the tree, so there is nothing that
can drift from the tag: the tag and the stamp come from the same `nextRelease.version`,
read once, in the same process.

`inzsh doctor` prints whichever `_inzsh_version` a running shell finds — `source` from
a clone or an unstamped bundle, the released tag from one built by the workflow — and
never invents a third answer (issue #245, not this one).

## Configuration

- `.releaserc.yml` — branches, version rules, release assets.
- `.github/workflows/release.yml` — the trigger, the test gate, the pinned
  semantic-release invocation (npx, no `package.json`).

The token is the workflow's own `GITHUB_TOKEN` with `contents: write` only — there is
no personal token to rotate.
