"""Assertions over a rendered `Grid`.

Every failure carries an excerpt of the grid it failed on — the whole point of the
L3 layer is that "the colour is wrong somewhere" becomes "row 0, columns 5..12 are
ab12cd on default". Expected colours are normalised the same way the runner
normalises what pyte reports, so '#AB12CD', 'AB12CD' and 'ab12cd' all compare
equal, and an int compares against a 256-index.
"""

from __future__ import annotations

from typing import NamedTuple

from grid_runner import DEFAULT_COLOR, normalize_color

_EXCERPT_CONTEXT = 1


class Run(NamedTuple):
    """A stretch of consecutive cells sharing one fg/bg pair."""

    text: str
    fg: object
    bg: object


def extract_runs(grid, row):
    """Collapse a row into `Run`s of consecutive same-colour cells.

    Covers columns 0 through the last drawn one — the last cell holding a visible
    character or a non-default background — so the untouched tail of the row is not
    a run. A blank cell between two coloured ones is its own run: a space still
    carries a background.
    """
    runs = []
    for col in range(_last_occupied_col(grid, row) + 1):
        cell = grid.cell(row, col)
        if runs and runs[-1].fg == cell.fg and runs[-1].bg == cell.bg:
            runs[-1] = runs[-1]._replace(text=runs[-1].text + cell.char)
        else:
            runs.append(Run(cell.char, cell.fg, cell.bg))
    return runs


def assert_cell_colors(grid, row, col, fg=None, bg=None):
    """Assert the cell's colours. A channel left as None is not checked."""
    cell = grid.cell(row, col)
    problems = []
    for channel, expected, actual in (
        ("fg", fg, cell.fg),
        ("bg", bg, cell.bg),
    ):
        if expected is None:
            continue
        wanted = normalize_color(expected)
        if actual != wanted:
            problems.append(f"{channel}: expected {wanted!r}, got {actual!r}")
    if problems:
        raise AssertionError(
            f"cell ({row}, {col}) = {cell.char!r} — "
            + "; ".join(problems)
            + "\n"
            + excerpt(grid, focus=row)
        )


def assert_row_occupancy(grid, expected_rows):
    """Assert how many rows carry visible text (wrapping, blank lines, overflow)."""
    actual = grid.rows_occupied()
    if actual != expected_rows:
        raise AssertionError(
            f"expected {expected_rows} occupied row(s), got {actual}\n"
            + excerpt(grid)
        )


def excerpt(grid, focus=None, context=_EXCERPT_CONTEXT):
    """Render the grid (or a window around `focus`) as text, for failure messages.

    Without a focus row the excerpt stops just past the last written row: a 24-row
    screen holding one line of prompt should not print 23 blanks into the failure.
    """
    if focus is None:
        first = 0
        last = min(_last_occupied_row(grid) + context, grid.lines - 1)
    else:
        first = max(focus - context, 0)
        last = min(focus + context, grid.lines - 1)

    header = f"grid {grid.cols}x{grid.lines}, child exit status {grid.exit_status}"
    body = [header]
    for row in range(first, last + 1):
        marker = ">" if row == focus else " "
        body.append(f"{marker} {row:>3} |{grid.row_text(row)}")
    hidden = grid.lines - 1 - last
    if hidden > 0:
        body.append(f"      ... {hidden} further row(s) not shown")
    if focus is not None:
        body.append(f"      runs on row {focus}: {_describe_runs(grid, focus)}")
    return "\n".join(body)


def _last_occupied_row(grid):
    for row in range(grid.lines - 1, -1, -1):
        if grid.row_text(row):
            return row
    return 0


def _describe_runs(grid, row):
    runs = extract_runs(grid, row)
    if not runs:
        return "(row is blank)"
    return ", ".join(
        f"{run.text!r} fg={run.fg!r} bg={run.bg!r}" for run in runs
    )


def _last_occupied_col(grid, row):
    for col in range(grid.cols - 1, -1, -1):
        cell = grid.cell(row, col)
        if cell.char.strip() or cell.bg != DEFAULT_COLOR:
            return col
    return -1
