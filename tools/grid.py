#!/usr/bin/env python3
"""Print the demonstration prompt as a terminal grid — what the cells actually hold.

A render written to a terminal is judged by eye; a render written to a `pyte` screen
can be read. This is the second one: it drives `tools/render.zsh` through the L3
harness (`test/ui/grid_runner.py`) at a given width and prints, per row, the runs of
cells that share a foreground/background pair, with the columns they occupy.

That is the whole tool. It asserts nothing — `test/ui/` is where expectations live —
and it exists so that "the separator is the wrong colour" can be answered with a
column number instead of a screenshot.

    make grid COLS=60
    python tools/grid.py --cols 60 --depth 256 --preset warm --cells

`--depth`, `--preset` and `--mode` set INZSH_COLOR_DEPTH, INZSH_PRESET and
INZSH_SURFACE_MODE for the child. Unset, the child detects: the harness pins
TERM=xterm-256color and strips COLORTERM, so the detected depth is 256 and a
truecolor grid has to be asked for.
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

DEMO = REPO_ROOT / "tools" / "render.zsh"


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
    parser.add_argument(
        "--prompt-only", action="store_true", help="drop the demo's legend line"
    )
    return parser.parse_args(argv)


def child_env(args):
    env = {}
    if args.depth:
        env["INZSH_COLOR_DEPTH"] = args.depth
    if args.preset:
        env["INZSH_PRESET"] = args.preset
    if args.mode:
        env["INZSH_SURFACE_MODE"] = args.mode
    return env


def render(args):
    snippet = f"source {shlex.quote(str(DEMO))}"
    if args.prompt_only:
        snippet += " --prompt-only"
    return grid_runner.render(
        snippet, cols=args.cols, lines=args.lines, env=child_env(args)
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
