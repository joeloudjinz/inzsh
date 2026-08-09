# Conventions

Rules for working in this repo. Short by design.

## Layout

```
inzsh.zsh-theme       entry point
install.zsh           idempotent installer / uninstaller
docs/                 configuration.md — the config reference — plus assets/
lib/core/             tokens, detect, config, engine, layout, render, prompts,
                      transient, resize, hooks, doctor
lib/segments/         one file per segment; git-async.zsh is the only async in the repo
lib/salah/            calc, methods, cache, location
presets/              inzsh-sharp.zsh, inzsh-warm.zsh — token overlays only
test/                 unit, render, ui, install, perf, tapes, golden, fixtures
tools/                dev harness, bundle, colour audit
```

Dependencies point strictly downward — tokens → config → engine → segments — and `lib/salah/`
imports nothing from the engine. `make bundle` concatenates the tree into a single
distributable file in dependency order, from an explicit manifest in `tools/bundle.zsh`. Keep
the layout flat enough that this stays trivial.

`docs/configuration.md` updates in the same PR as any knob it adds or changes.

## Shell

- **Prefix every internal symbol `_inzsh_`** and every public config variable `INZSH_`. Nothing
  the theme defines may collide with a user's commands, variables or another plugin's functions.
- **Capture `$?` and `$pipestatus` on the first line of `precmd`.** Anything running before that
  destroys the exit status.
- **Register hooks with `add-zsh-hook`.** Never assign `precmd` or `preexec` directly.
- **No subprocesses on the render path.** Prompt rendering is arithmetic and parameter expansion.
  Anything slower runs async and reads from a cache.
- **Never set locale or other global state.** The user's environment is theirs.
- **No-op when non-interactive.** Scripts and `ssh host command` must not receive escapes.

## Colour

- Use **semantic roles** — `--positive-text`, `--negative`, `--on-accent` — never raw ramp names.
  Roles survive a palette change; ramps may not.
- **No hardcoded hex outside the token layer.** One transcription point, and only one.
- **Colour is never the only signal.** Every state carries a glyph as well.
- Separator glyphs live in the token layer, not in segment code.

## Tests

Match the layer to the concern:

| Concern | Layer |
|---|---|
| Pure functions — maths, sorting, width | unit |
| Prompt string — order, colours, glyphs | render |
| What the terminal actually shows, responsive behaviour | ui |
| Whole-prompt appearance | golden files + tapes |
| Installing and uninstalling, against a throwaway HOME | install |
| The render budget | perf |

Golden files are committed. Update them with `make golden-update`, never by hand.

## Commits

**One line. No body.** Conventional Commits, scoped to the layout:

```
feat(engine): sort non-contiguous ranks
fix(salah): handle midnight rollover
test(ui): assert token colours at 60 columns
docs: document tmux setup
```

Scopes: `engine` · `config` · `tokens` · `segments` · `salah` · `ui` · `install` · `docs`

Breaking changes use `!` — `feat(config)!: rename INZSH_SALAH_LAT` — since there is no body for a
footer.

Each commit is one coherent change and leaves the build green. A branch is several commits, never
one. We do not squash.

## Branches

`dev` is the development trunk; `main` carries release cycles only and moves when a release
cuts from `dev`.

`m<n>-<short-slug>` — one branch per issue, e.g. `m2-rank-sort`, cut from and PR'd back to
`dev`.

## Issues and pull requests

- **Issues**: describe the work briefly. Link the milestone and any related issue. Nothing else.
- **Pull requests**: a good title does the work. Link the issue with `Closes #N`, set the
  milestone, and label it — `area/*` and `type/test`/`type/docs` auto-apply from changed
  paths; set `type/feat` or `type/fix` by hand. Milestone and issue link are CI-enforced.
  The description stays near-empty.

Both should stand on their own. If an issue needs paragraphs of background, it is under-specified
— tighten the scope rather than adding prose.
