# Contributing

Thanks for looking. This is a personal project built in the open.

**Issues are welcome** — bugs, terminal quirks, prayer-time discrepancies, all useful.

**Pull requests are considered case-by-case.** The theme follows a specific design system and a
deliberately narrow scope, so please open an issue before writing anything substantial. Small,
obvious fixes are fine to send directly.

## Reporting a bug

Run the diagnostic and include its output:

```zsh
inzsh doctor
```

That covers zsh version, terminal, colour depth, Nerd Font, tmux and locale — which is most of
what's needed. Add what you expected and what you saw instead. A screenshot helps for anything
visual.

## Prayer-time reports

Include your calculation method, Asr school, and the times you expected against the times shown.
Please don't include your exact coordinates — a city name is enough.

## Working on the code

```zsh
make setup           # install the toolchain
make test            # unit, render and terminal-grid suites
make play            # a live prompt in a throwaway shell
make grid COLS=60    # inspect the rendered terminal grid, per cell
```

Gates that run on their own, because each wants its own output:

```zsh
make golden-check    # the committed prompt renders — fails on a visual change
make golden-update   # the only sanctioned way to change test/golden
make perf            # the render budget
make test-install    # the installer, against a throwaway HOME
make bundle          # the single-file build
```

And the things that make pictures and answers:

```zsh
make shots           # the README stills   (SCALE=2 for high-DPI)
make demo            # the recordings      (SCALE=2 for high-DPI)
make doctor          # the diagnostic, same code path as the shipped command
```

`make test` deliberately leaves out the installer suite, the perf benchmark and the golden
gate — each is its own CI job, and a failure in one should not be buried in another's noise.
They all run locally by the commands above; CI is where they are authoritative. Older zsh
versions are CI-only.

Read [CONVENTIONS.md](CONVENTIONS.md) before your first change. The rules that catch people out
most: internal symbols are prefixed `_inzsh_`, no hardcoded hex outside the token layer, no
subprocesses on the render path, and commits are a single line with no body.

Releases are automated from those commits — maintainers, see
[docs/releasing.md](docs/releasing.md).

## Scope

Some things are deliberately out of scope: other shells, cloud and language-version segments, and
turning the prayer-times module into a full application. Bare TTY support is planned but not yet
present.

## License

Contributions are accepted under the [MIT License](LICENSE).
