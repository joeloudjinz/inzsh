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
make setup     # install the toolchain
make test      # everything runnable locally
make render    # print the prompt as it currently is
make grid COLS=60   # inspect the rendered terminal grid
make demo      # generate a visual render
```

Some checks — older zsh versions and installer tests — run only in CI.

Read [CONVENTIONS.md](CONVENTIONS.md) before your first change. The rules that catch people out
most: internal symbols are prefixed `_inzsh_`, no hardcoded hex outside the token layer, no
subprocesses on the render path, and commits are a single line with no body.

## Scope

Some things are deliberately out of scope: other shells, cloud and language-version segments, and
turning the prayer-times module into a full application. Bare TTY support is planned but not yet
present.

## License

Contributions are accepted under the [MIT License](LICENSE).
