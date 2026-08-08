# CLAUDE.md

**InZsh** ("inz-ze-shell") — a calm, configurable zsh prompt theme built from the Joe Inz
design system, with an optional locally-computed prayer-times segment. Pre-release; interfaces
may change until 1.0. Read [CONVENTIONS.md](CONVENTIONS.md) before changing anything.

## Architecture

Dependencies point strictly downward — tokens → config → engine → segments — and `lib/salah/`
imports nothing from the engine (it's pure math over an injected clock). `make bundle`
concatenates everything into one distributable file in dependency order from an explicit
manifest; keep the layout flat enough that this stays trivial.

## Hard rules

**Safety — this theme draws the prompt you're typing into:**
- Never source work-in-progress into the running shell. Development happens in `zsh -f`
  subshells driven by the harness (`make play`, `make test`).
- Installer code never touches the real `$HOME`. Locally it runs against a temp `$HOME` or not
  at all; CI covers the rest.

**Licensing:** the engine is inspired by comfyline, which is GPL-3.0+ — this repo is MIT.
Never copy, adapt, or transcribe comfyline code. Don't work with its source open beside ours.
Reference behaviour and concepts only; write the implementation from understanding.

**Shell:**
- Every internal symbol is prefixed `_inzsh_`; every public config variable `INZSH_`.
- Capture `$?` and `$pipestatus` on the *first line* of `precmd` — anything earlier destroys
  the exit status.
- Register hooks via `add-zsh-hook` only; never assign `precmd`/`preexec` directly.
- No subprocesses on the render path. Render is arithmetic and parameter expansion; anything
  slower runs async and reads from a cache. The **only** async in the repo is
  `lib/segments/git-async.zsh`.
- Never mutate locale or other global state. No-op in non-interactive shells.
- Prompt render must stay **< 30 ms warm** — this is a CI-enforced budget, not a vibe.

**Colour:**
- Hex values exist only in the token layer (`lib/core/tokens.zsh`, `tokens-256.zsh`). Nowhere
  else — not presets, not segments, not tests. One deliberate exception: the token spec's
  transcription spot-checks, which pin palette values and structurally need a second copy.
- Use semantic roles (`positive-text`, `negative`, `on-accent`), never raw ramp names.
- Colour is never the only signal — every state also carries a glyph (`✓ i ✕ ! · —`).
- Separator glyphs live in the token layer, not in segment code.
- Presets set token/role variables **only**; a preset that touches engine vars is a bug.

**Seams (what makes this testable — don't break them):**
- `lib/salah/calc.zsh` takes an injected timestamp; it never reads `EPOCHSECONDS`.
- Segments render from injected state; they never shell out for their own data.

## Testing

Match the layer to the concern:

| Concern | Layer | Where |
|---|---|---|
| Pure functions — maths, sorting, width | unit (ShellSpec) | `test/unit/` |
| Prompt string — order, colours, glyphs | render (`${(%%)PROMPT}`) | `test/render/` |
| What the terminal shows, responsive behaviour | ui (pty + pyte grid) | `test/ui/` |
| Whole-prompt appearance | golden `.txt` + VHS tapes | `test/golden/`, `test/tapes/` |
| Installing and uninstalling | installer suite (throwaway HOME) | `test/install/` |
| The render budget | benchmark | `test/perf/` |

- Golden files are committed; update them only via `make golden-update`, never by hand.
- `test/fixtures/` holds *inputs* (oracle data, expected tables); `test/golden/` holds *output
  gates*. `make golden-update` must never touch fixtures.
- All tests run against fixtures (pinned clock, fixture git repo) — never against the real
  working tree or the real time.

## Dev loop

```zsh
make setup          # install the native toolchain
make test           # unit, render and terminal-grid suites
make play           # a live prompt in a throwaway shell
make grid COLS=60   # the theme as a terminal grid, per-cell colours
make golden-check   # the committed renders — the visual gate
make golden-update  # the only sanctioned way to change test/golden
make perf           # the render budget
make test-install   # the installer, against a throwaway HOME
make bundle         # the single-file build
make shots          # the README stills      (SCALE=2 for high-DPI)
make demo           # the recordings         (SCALE=2 for high-DPI)
make doctor         # the diagnostic
```

The golden gate, the perf benchmark and the installer suite are deliberately outside
`make test` — each has its own CI job so its output is its own.

The zsh 5.8 matrix and full CI parity are CI-only — red CI is the feedback loop for those,
so keep pushes small. macOS runs only when dispatched by hand (`.github/workflows/macos.yml`).

## Commits, branches, PRs

- **Atomic commits** — one coherent change each, build green at every commit. A feature is
  several commits, never one. We never squash.
- **One line, no body.** Conventional Commits, scoped: `engine` · `config` · `tokens` ·
  `segments` · `salah` · `ui` · `install` · `docs`. Breaking changes use `!`
  (`feat(config)!: rename INZSH_SALAH_LAT`).
- `dev` is the development trunk; `main` is for release cycles only. Branch per issue off
  `dev`: `m<n>-<short-slug>` (e.g. `m2-rank-sort`). PR to `dev` with `Closes #N`, milestone
  set (CI-enforced), and labels — `area/*` and `type/test|docs` auto-apply from paths; set
  `type/feat`/`type/fix` by hand (`gh pr create --milestone --label`). Description
  near-empty. Never push to `main` or `dev` directly.
- `docs/configuration.md` updates in the **same PR** as any knob it adds or changes; golden
  files update in the same PR as any visual change.

## Public surface

Everything committed is published permanently. Two rules:

- **Neutral example data only** — docs, tests and defaults never carry real coordinates,
  hostnames or private URLs. Use Mecca (`21.4225, 39.8262`) or an obvious placeholder.
- **Commits, issues and PRs are brief and unremarkable** — they describe what changed and
  never reference untracked or ignored paths.
