"""Smoke tests for the L3 grid harness — does the pty round-trip actually work?

These test the harness, not the theme. The one case that touches the theme sources
the token layer and asserts only that a role *resolves to some colour*: palette
values live in `lib/core/tokens.zsh` and are never copied into a test. The colour
values asserted below are invented here and injected by these tests, so the
expectations are derived from what the test set, not from the design system.
"""

import shlex
import unittest
from pathlib import Path

import grid_runner
from grid_asserts import assert_cell_colors, assert_row_occupancy, extract_runs

REPO_ROOT = Path(__file__).resolve().parents[2]
TOKENS = REPO_ROOT / "lib" / "core" / "tokens.zsh"

# Arbitrary colours owned by this test — not palette values. Every expectation
# below is computed from these tuples.
INJECTED_FG = (12, 210, 87)
INJECTED_BG = (40, 20, 90)

RESET = "\033[0m"


def truecolor(channel, rgb):
    """An SGR truecolor escape. `channel` is 38 for foreground, 48 for background."""
    return "\033[%d;2;%d;%d;%dm" % (channel, *rgb)


def as_hex(rgb):
    """The same triple in the runner's normalised form: lowercase hex, no hash."""
    return "%02x%02x%02x" % rgb


class PlainTextTest(unittest.TestCase):
    def test_one_line_of_text_occupies_one_row(self):
        grid = grid_runner.render("print -r -- 'hello grid'")

        self.assertEqual(grid.exit_status, 0)
        self.assertEqual(grid.row_text(0), "hello grid")
        self.assertEqual(grid.cell(0, 0).char, "h")
        assert_row_occupancy(grid, 1)

    def test_untouched_cells_report_default_colours(self):
        grid = grid_runner.render("print -rn -- 'plain'")

        assert_cell_colors(grid, 0, 0, fg="default", bg="default")


class TruecolorTest(unittest.TestCase):
    """Colours the test itself injects come back cell-for-cell."""

    HEAD = "PLAIN"
    MIDDLE = "COLOURED"
    TAIL = "TAIL"

    def render_three_runs(self):
        payload = "".join(
            [
                self.HEAD,
                truecolor(38, INJECTED_FG),
                truecolor(48, INJECTED_BG),
                self.MIDDLE,
                RESET,
                self.TAIL,
            ]
        )
        return grid_runner.render(f"print -rn -- {shlex.quote(payload)}")

    def test_coloured_cells_carry_the_injected_values(self):
        grid = self.render_three_runs()
        self.assertEqual(grid.row_text(0), self.HEAD + self.MIDDLE + self.TAIL)

        first = len(self.HEAD)
        last = first + len(self.MIDDLE) - 1
        for col in (first, last):
            assert_cell_colors(
                grid, 0, col, fg=as_hex(INJECTED_FG), bg=as_hex(INJECTED_BG)
            )
        assert_cell_colors(grid, 0, first - 1, fg="default", bg="default")
        assert_cell_colors(grid, 0, last + 1, fg="default", bg="default")

    def test_extract_runs_isolates_the_coloured_run(self):
        grid = self.render_three_runs()

        runs = extract_runs(grid, 0)

        self.assertEqual(
            runs,
            [
                (self.HEAD, "default", "default"),
                (self.MIDDLE, as_hex(INJECTED_FG), as_hex(INJECTED_BG)),
                (self.TAIL, "default", "default"),
            ],
        )


class TokenLayerTest(unittest.TestCase):
    """The real token layer renders *a* colour. Presence, never the value."""

    def test_accent_role_reaches_the_cell_as_a_non_default_colour(self):
        snippet = "\n".join(
            [
                f"source {shlex.quote(str(TOKENS))}",
                'prompt="%F{$_inzsh_role[accent]}X%f"',
                'print -rn -- "${(%%)prompt}"',
            ]
        )

        grid = grid_runner.render(snippet)

        self.assertEqual(grid.exit_status, 0, msg=grid.row_text(0))
        self.assertEqual(grid.cell(0, 0).char, "X")
        self.assertNotEqual(grid.cell(0, 0).fg, "default")
        self.assertEqual(len(extract_runs(grid, 0)), 1)


class OverflowTest(unittest.TestCase):
    def test_forty_chars_in_twenty_columns_wrap_onto_two_rows(self):
        cols = 20
        line = "x" * (cols * 2)

        grid = grid_runner.render(f"print -rn -- {shlex.quote(line)}", cols=cols)

        self.assertEqual(grid.cols, cols)
        self.assertEqual(grid.row_text(0), "x" * cols)
        self.assertEqual(grid.row_text(1), "x" * cols)
        assert_row_occupancy(grid, 2)


if __name__ == "__main__":
    unittest.main()
