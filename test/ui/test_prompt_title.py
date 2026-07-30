"""L3 — the terminal title, on a real terminal.

The L2 spec can prove the sequence is `%{…%}`-wrapped and that the bytes leaving
`_inzsh_title_set` are the wrapper's prompt expansion. It cannot prove the thing
that actually matters: that a terminal *swallows* those bytes. Zero columns is a
property of the terminal, not of the string, and this is the layer that has one.

Each case emits a title and then two ordinary characters. If the OSC string cost
anything at all, `XY` would not start in column 0.

The child is a nested shell on purpose. `grid_runner` runs `zsh -f -c`, which is
not interactive, and the title layer is required to write nothing there — so the
snippet spawns `zsh -f -i` on the same pty to get a shell that has a prompt. Its
own prompt is blanked and `nopromptcr`/`nopromptsp` keep zsh from writing a
partial-line marker, so the grid holds nothing but what the theme drew.
"""

from __future__ import annotations

import shlex
import unittest
from pathlib import Path

import grid_runner
from grid_asserts import assert_row_occupancy

REPO_ROOT = Path(__file__).resolve().parents[2]
PROMPTS = REPO_ROOT / "lib" / "core" / "prompts.zsh"

MARKER = "XY"


def interactive(body):
    """Wrap `body` in an interactive, rc-less zsh with a silent prompt."""
    inner = "source %s\n%s" % (shlex.quote(str(PROMPTS)), body)
    return (
        "PROMPT= RPROMPT= PS1= zsh -f -i -o nopromptcr -o nopromptsp -c "
        + shlex.quote(inner)
    )


def render_title(body, **kwargs):
    """Run `body` and then print the marker, on a fresh grid."""
    return grid_runner.render(
        interactive("%s\nprint -rn -- %s" % (body, shlex.quote(MARKER))), **kwargs
    )


class TitleWidthTest(unittest.TestCase):
    def test_the_sequence_occupies_no_columns(self):
        grid = render_title('_inzsh_title_set "a title"')

        self.assertEqual(grid.exit_status, 0, msg=grid.row_text(0))
        self.assertEqual(grid.row_text(0), MARKER)
        self.assertEqual(grid.cell(0, 0).char, "X")
        assert_row_occupancy(grid, 1)

    def test_the_terminal_reads_it_as_a_title_and_not_as_text(self):
        """Consumed is not the same as invisible: the tab has to end up saying it."""
        grid = render_title('_inzsh_title_set "a title"')

        self.assertEqual(grid._screen.title, "a title")
        self.assertEqual(grid._screen.icon_name, "a title")

    def test_a_command_too_long_for_a_tab_still_costs_no_columns(self):
        """The truncation cap is what keeps a long command out of the grid."""
        grid = render_title(
            'cd /\n_inzsh_title_text "${(l:400::x:)}"\n_inzsh_title_set "$REPLY"'
        )

        self.assertEqual(grid.row_text(0), MARKER)
        assert_row_occupancy(grid, 1)
        self.assertLessEqual(len(grid._screen.title), 64)
        self.assertTrue(grid._screen.title.endswith("…"), grid._screen.title)

    def test_a_terminal_that_mishandles_osc_receives_nothing(self):
        """`TERM=dumb` gets the marker and not one byte more."""
        grid = render_title('_inzsh_title_set "a title"', env={"TERM": "dumb"})

        self.assertEqual(grid.row_text(0), MARKER)
        self.assertEqual(grid.raw, MARKER.encode())
        self.assertEqual(grid._screen.title, "")


if __name__ == "__main__":
    unittest.main()
