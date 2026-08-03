#!/usr/bin/env python3
"""Print the theme's prompt as a terminal grid — what the cells actually hold.

A render written to a terminal is judged by eye; a render written to a `pyte` screen
can be read. This is the second one: it sources `inzsh.zsh-theme` — the real engine,
real segments, the shell this repo is checked out in — through the L3 harness
(`test/ui/grid_runner.py`) at a given width and prints, per row, the runs of cells
that share a foreground/background pair, with the columns they occupy.

That is the whole tool. It asserts nothing — `test/ui/` is where expectations live —
and it exists so that "the separator is the wrong colour" can be answered with a
column number instead of a screenshot.

    make grid COLS=60
    python tools/grid.py --cols 60 --depth 256 --preset warm --cells

`--depth` and `--mode` set INZSH_COLOR_DEPTH and INZSH_SURFACE_MODE for the child;
any other `INZSH_*` knob flows in from your environment — `INZSH_PRESET=warm` among them,
which is the theme's own way to pick a preset. `--preset` is the other way: it sources the
named preset file over the theme, as a plugin manager might. Unset, the child detects: the
harness pins TERM=xterm-256color and strips COLORTERM, so the detected depth is 256
and a truecolor grid has to be asked for.
"""

from __future__ import annotations

import argparse
import shlex
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "test" / "ui"))

import grid_runner  # noqa: E402  — the path insert above is the point
from grid_asserts import extract_runs  # noqa: E402

THEME = REPO_ROOT / "inzsh.zsh-theme"
PRESETS = REPO_ROOT / "presets"


def theme_snippet(preset=None):
    """The zsh command the harness runs: the whole theme, one prompt, printed.

    `zsh -f -i -c` because the theme no-ops in a non-interactive shell, and `-f` so the
    machine's own zshrc never loads under the harness. `_inzsh_precmd` is what the shell
    would run before drawing — same code path, called once — and the expanded PROMPT (and
    RPROMPT, when there is one) is what the terminal would receive.
    """
    lines = [f"source {shlex.quote(str(THEME))}"]
    if preset:
        lines.append(f"source {shlex.quote(str(PRESETS / f'inzsh-{preset}.zsh'))}")
    lines += [
        "_inzsh_precmd",
        'print -rn -- "${(%%)PROMPT}"',
        '[[ -n $RPROMPT ]] && { print; print -rn -- "${(%%)RPROMPT}" }',
        "true",
    ]
    inner = "\n".join(lines)
    return f"exec zsh -f -i -c {shlex.quote(inner)} inzsh-grid"


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cols", type=int, default=80, help="terminal width (default 80)")
    parser.add_argument("--lines", type=int, default=24, help="terminal height (default 24)")
    parser.add_argument("--depth", choices=("truecolor", "256", "8"))
    parser.add_argument("--preset", choices=("sharp", "warm"))
    parser.add_argument("--mode", choices=("alternate", "ramp", "flat"))
    parser.add_argument(
        "--cells", action="store_true", help="also dump every cell, one line each"
    )
    return parser.parse_args(argv)


def child_env(args):
    env = {}
    if args.depth:
        env["INZSH_COLOR_DEPTH"] = args.depth
    if args.mode:
        env["INZSH_SURFACE_MODE"] = args.mode
    return env


def render(args):
    return grid_runner.render(
        theme_snippet(preset=args.preset),
        cols=args.cols,
        lines=args.lines,
        env=child_env(args),
    )


def run_columns(grid, row):
    """Pair every run on `row` with the column span it covers."""
    spans = []
    col = 0
    for run in extract_runs(grid, row):
        spans.append((col, col + len(run.text) - 1, run))
        col += len(run.text)
    return spans


def print_grid(grid, args):
    print(
        f"grid {grid.cols}x{grid.lines} — {grid.rows_occupied()} row(s) occupied, "
        f"child exit {grid.exit_status}"
    )
    for row in range(grid.lines):
        text = grid.row_text(row)
        if not text:
            continue
        print(f"\nrow {row} |{text}|")
        for first, last, run in run_columns(grid, row):
            where = f"{first:>3}" if first == last else f"{first:>3}..{last:<3}"
            print(f"  {where:<9} fg={run.fg!s:<10} bg={run.bg!s:<10} {run.text!r}")
        if args.cells:
            for col in range(grid.cols):
                cell = grid.cell(row, col)
                print(
                    f"  cell {col:>3} {cell.char!r:<6} "
                    f"fg={cell.fg!s:<10} bg={cell.bg!s}"
                )


def main(argv=None):
    args = parse_args(argv)
    grid = render(args)
    print_grid(grid, args)
    return 0 if grid.exit_status == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
