"""The prompt shape, read off a real terminal grid.

`test/render/prompt_shape_spec.sh` can prove PROMPT holds one newline. It cannot prove
that the newline becomes exactly one extra ROW, because that is a property of cells: a
segment row padded one column too far wraps, and a two-row prompt silently becomes a
three-row one on every terminal that wraps eagerly. Only a grid knows.

So the two claims the shape exists to make are asserted here, on the rendered screen:

* two-line occupies exactly 2 rows and one-line exactly 1, at every width;
* the right prompt sits on the SEGMENT row, ending one column in from the edge — which
  is where zsh puts `RPROMPT` itself, and the last test on this page is the measurement
  that says so.

That last one is the reason the two-line shape does not simply use `RPROMPT`. zsh draws
it on the LAST row of a multi-row prompt, which would put the clock and the prayer time
beside the cursor rather than beside the segments. The fact is measured rather than
remembered, so a zsh that ever changed it would fail here rather than in someone's tab.

Nothing here hardcodes a colour. The marker's two states are compared to each other,
never to a value, and the segment texts are the only literals — chosen so that no two are
a substring of another.
"""

from __future__ import annotations

import shlex
import unittest
from pathlib import Path

import grid_runner
from grid_runner import DEFAULT_COLOR
from grid_asserts import assert_row_occupancy, excerpt
from pty_session import Session

REPO_ROOT = Path(__file__).resolve().parents[2]
CORE = REPO_ROOT / "lib" / "core"

# The mark the second row starts with, and its stand-in. Written as escapes rather than as
# bytes because this is Python: the rule against a `\u` literal is a rule about what a zsh
# PARSER does to a file in a single-byte locale, and nothing here is parsed by zsh.
MARKER = "→"
MARKER_ASCII = ">"

WIDTHS = (60, 72, 80, 100, 160)

# The right prompt used by the two measurements at the foot of this file. Never a substring
# of anything else drawn on those grids.
RIGHT_MARK = "RIGHTMARK"


def last_drawn_col(grid, row):
    """The rightmost column of `row` that was written to.

    A cell holding a space still counts when it carries a background — the padded end of
    a filled block is exactly that — so `row_text`, which strips trailing blanks, cannot
    answer this. The padding claim is about where the row ENDS, not about where its last
    letter is.
    """
    for col in range(grid.cols - 1, -1, -1):
        cell = grid.cell(row, col)
        if cell.char.strip() or cell.bg != DEFAULT_COLOR:
            return col
    return -1


def render(*, cols=80, lines=2, status=0, extra=""):
    """Render the real `_inzsh_render` on a `cols`-wide terminal and return the `Grid`.

    The segments are a fixture — three names, fixed ranks, fixed text — so this file
    measures a row it wrote. `zsh -f -i -c` inside the harness because `_inzsh_render`
    returns early in a shell that is not interactive, and that guard is the theme's
    promise to every script on the machine.
    """
    inner = "\n".join(
        [
            'unset -m "INZSH_*"',
            f"INZSH_PROMPT_LINES={lines}",
            extra,
            *(
                f"source {shlex.quote(str(CORE / (name + '.zsh')))}"
                for name in ("config", "detect", "tokens-256", "tokens", "layout",
                             "engine", "render")
            ),
            "typeset -gA _inzsh_segment_defaults _inzsh_segment_text",
            "_inzsh_segment_defaults=(ALFA 1 BRAVO 2 CHARLIE -1)",
            "_inzsh_segment_text=(ALFA alfa BRAVO bravo CHARLIE charlie)",
            f"typeset -g _inzsh_last_status={status}",
            "_inzsh_render",
            'print -rn -- "${(%%)PROMPT}"',
        ]
    )
    snippet = f"exec zsh -f -i -c {shlex.quote(inner)} inzsh-shape"
    return grid_runner.render(snippet, cols=cols, lines=24)


class ShapeTest(unittest.TestCase):
    """How many rows the prompt takes, and what is on them."""

    def test_two_line_prompt_occupies_exactly_two_rows(self):
        for cols in WIDTHS:
            with self.subTest(cols=cols):
                grid = render(cols=cols, lines=2)
                self.assertEqual(grid.exit_status, 0, msg=excerpt(grid))
                assert_row_occupancy(grid, 2)

    def test_one_line_prompt_occupies_exactly_one_row(self):
        for cols in WIDTHS:
            with self.subTest(cols=cols):
                grid = render(cols=cols, lines=1)
                self.assertEqual(grid.exit_status, 0, msg=excerpt(grid))
                assert_row_occupancy(grid, 1)

    def test_the_second_row_is_the_marker_and_nothing_else(self):
        grid = render()
        row = grid.row_text(1)
        self.assertIn(row, (MARKER, MARKER_ASCII), msg=excerpt(grid, focus=1))

    def test_the_segment_row_carries_both_sides(self):
        """Left and right on row 0, and the marker row carries neither."""
        grid = render()
        first, second = grid.row_text(0), grid.row_text(1)
        for text in ("alfa", "bravo", "charlie"):
            self.assertIn(text, first, msg=excerpt(grid, focus=0))
            self.assertNotIn(text, second, msg=excerpt(grid, focus=1))

    def test_the_segment_row_stops_one_column_short_of_the_edge(self):
        """The off-by-one that turns two rows into three, asserted at every width."""
        for cols in WIDTHS:
            with self.subTest(cols=cols):
                grid = render(cols=cols)
                self.assertEqual(
                    last_drawn_col(grid, 0), cols - 2, msg=excerpt(grid, focus=0)
                )
                self.assertTrue(
                    grid.row_text(0).endswith("charlie"), msg=excerpt(grid, focus=0)
                )

    def test_the_marker_changes_colour_with_the_last_command(self):
        """Compared to itself, never to a palette value: a repaint may not fail this."""
        clean = render(status=0)
        failed = render(status=1)
        self.assertEqual(clean.row_text(1), failed.row_text(1))
        self.assertNotEqual(
            clean.cell(1, 0).fg,
            failed.cell(1, 0).fg,
            msg="the marker is the same colour after a failure as after a success\n"
            + excerpt(failed, focus=1),
        )

    def test_a_narrow_terminal_keeps_the_shape(self):
        """Too narrow for both sides is still two rows — the right side moves, not the row."""
        grid = render(cols=24)
        assert_row_occupancy(grid, 2)
        self.assertNotIn("charlie", grid.row_text(0), msg=excerpt(grid, focus=0))


class RpromptPlacementTest(unittest.TestCase):
    """The measurement the two-line shape is built on.

    zsh draws `RPROMPT` on the LAST row of a multi-row prompt and one column in from the
    right edge. Both halves matter: the first is why the right prompt is padded into the
    segment row instead of being left to `RPROMPT`, and the second is the column the
    padding aims at.
    """

    @staticmethod
    def _rprompt_rows(grid):
        """Rows where zsh DREW the right prompt.

        The value is assigned through a variable so that the mark itself is never typed,
        and the one row that still mentions it — the assignment being echoed back — is
        dropped by name. Without that, the echo of `RPROMPT=RIGHTMARK` looks exactly like
        a row zsh right-aligned a prompt onto.
        """
        rows = [grid.row_text(row) for row in range(grid.lines)]
        return [row for row in rows if RIGHT_MARK in row and "rp=" not in row]

    def test_zsh_draws_rprompt_on_the_last_row_of_a_multi_row_prompt(self):
        session = Session(cols=40, lines=12)
        session.send(f"rp={RIGHT_MARK}")
        session.send("PROMPT=$'AAAA\\nBB '")
        session.send("RPROMPT=$rp")
        session.send("print done")
        grid = session.finish()

        drawn = self._rprompt_rows(grid)
        self.assertTrue(drawn, msg=excerpt(grid))
        for row in drawn:
            self.assertTrue(
                row.startswith("BB "),
                msg="zsh no longer puts RPROMPT on the LAST row of a multi-row prompt\n"
                + excerpt(grid),
            )

    def test_zsh_leaves_one_column_spare_to_the_right_of_rprompt(self):
        session = Session(cols=40, lines=12)
        session.send(f"rp={RIGHT_MARK}")
        session.send("PROMPT='LL '")
        session.send("RPROMPT=$rp")
        session.send("print done")
        grid = session.finish()

        drawn = self._rprompt_rows(grid)
        self.assertTrue(drawn, msg=excerpt(grid))
        for row in drawn:
            self.assertEqual(len(row), grid.cols - 1, msg=excerpt(grid))


if __name__ == "__main__":
    unittest.main()
