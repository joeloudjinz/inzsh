# Releasing

Releases are automated. Nobody tags, writes notes, or uploads anything by hand.

## How a release happens

1. Open a pull request from `dev` to `main` — the usual hygiene gate applies, so link
   the driving issue and set the milestone.
2. Merge it. The push to `main` triggers the `release` workflow (the full `ci`
   workflow runs on the same push).
3. The workflow re-runs the unit and render suites, then builds the single-file
   bundle with `make bundle`.
4. semantic-release reads every commit since the last tag and picks the version from
   Conventional Commits: `feat` → minor, `fix` → patch, `!` → major. Other types
   (`docs`, `test`, `chore`) never bump on their own; if nothing releasable landed,
   it exits without releasing.
5. It tags `vX.Y.Z` on `main`, generates the release notes from those same commits,
   and publishes a GitHub release with `dist/inzsh.zsh-theme` attached.

## What lands where

- **Tag** — `vX.Y.Z` on `main`, pushed by the workflow.
- **Changelog** — the generated notes on the GitHub release; the releases page is the
  changelog. No `CHANGELOG.md` is committed back, because that would need a bot
  commit pushed straight to `main`.
- **Bundle** — `dist/inzsh.zsh-theme`, built in the workflow and attached as a
  release asset.

## Configuration

- `.releaserc.yml` — branches, version rules, release assets.
- `.github/workflows/release.yml` — the trigger, the test gate, the pinned
  semantic-release invocation (npx, no `package.json`).

The token is the workflow's own `GITHUB_TOKEN` with `contents: write` only — there is
no personal token to rotate.
