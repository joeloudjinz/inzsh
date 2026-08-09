"""Dropping by priority, read off a real terminal grid.

`test/unit/layout_spec.sh` proves the arithmetic of `_inzsh_layout_fit`, and it proves it
against widths a spec chose. What it cannot prove is that the engine hands that function the
widths a terminal will actually use, or that what survives is what gets drawn. This file
closes that loop the same way `test/ui/test_resize.py` does: a real pty of a known size, the
real engine, and assertions against the grid it produced.

The fixture is built so that PRIORITY AND POSITION DISAGREE. Ranks run 1..4 left to right;
priorities do not follow them. `BRAVO` sits second in the row and is the first to go, so a
layout that dropped from the right-hand end — the obvious wrong implementation, and the one
`layout.zsh` explicitly argues against — draws a different row at every width below.

Block widths are the text plus a column of padding either side, and a separator is two
columns. The widths below are chosen from that arithmetic rather than discovered by running
it, so a change in the measurement fails here rather than quietly re-pinning itself.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

from grid_asserts import excerpt
from pty_session import Session

REPO_ROOT = Path(__file__).resolve().parents[2]
CORE = REPO_ROOT / "lib" / "core"

#            rank  text          block  priority
# ALFA        1    alfa            6      10   kept longest
# CHARLIE     3    charlie         9      20
# DELTA       4    delta           7      30
# BRAVO       2    bravobravo     12      40   first to go, and it sits in the middle
SETUP = """
unset -m "INZSH_*"
for _f in config detect tokens-256 tokens layout engine render hooks; do
  source {core}/$_f.zsh
done
typeset -gA _inzsh_segment_defaults _inzsh_segment_text _inzsh_segment_priority
_inzsh_segment_defaults=(ALFA 1 BRAVO 2 CHARLIE 3 DELTA 4)
_inzsh_segment_text=(ALFA alfa BRAVO bravobravo CHARLIE charlie DELTA delta)
_inzsh_segment_priority=(ALFA 10 CHARLIE 20 DELTA 30 BRAVO 40)
_inzsh_hooks_install
"""

# Cumulative cost in priority order, which is what the fit walks:
#   ALFA 6 · +CHARLIE 17 · +DELTA 26 · +BRAVO 40
# One column is held back from the budget, so a step needs its cost plus one to survive.
CASES = (
    (60, ["alfa", "bravobravo", "charlie", "delta"]),
    (35, ["alfa", "charlie", "delta"]),
    (22, ["alfa", "charlie"]),
    (12, ["alfa"]),
)


class PrioritySession:
    """The engine and a four-segment fixture, sourced from a file rather than typed."""

    def __init__(self, *, cols, prelude=""):
        handle, self.path = tempfile.mkstemp(suffix=".zsh", prefix="inzsh-priority-")
        with os.fdopen(handle, "w") as fh:
            # The prelude lands AFTER the setup: the setup opens with `unset -m 'INZSH_*'`,
            # so a knob set here is the test speaking and a knob set in the developer's own
            # environment never reaches the grid.
            fh.write(SETUP.format(core=CORE) + prelude)
        self.session = Session(cols=cols, lines=24)
        self.session.send(f"source {self.path}")
        self.session.send("clear")

    def __enter__(self):
        return self.session

    def __exit__(self, *exc):
        try:
            if self.session._proc.poll() is None:  # noqa: SLF001 — teardown, not a read
                self.session.finish()
        finally:
            os.unlink(self.path)


def drawn(grid):
    """Every non-blank row's text, top down."""
    return [
        grid.row_text(row)
        for row in range(grid.lines)
        if grid.row_text(row).strip()
    ]


class PriorityTest(unittest.TestCase):
    def test_what_survives_is_a_prefix_of_the_priority_order(self):
        for cols, expected in CASES:
            with self.subTest(cols=cols):
                with PrioritySession(cols=cols) as session:
                    grid = session.grid()
                    text = " ".join(drawn(grid))
                    for label in ("alfa", "bravobravo", "charlie", "delta"):
                        self.assertEqual(
                            label in expected,
                            label in text,
                            msg=f"{label} at {cols}: {excerpt(grid)}",
                        )

    def test_the_middle_block_goes_before_the_last_one(self):
        """The claim position cannot make.

        `BRAVO` is rank 2 and `DELTA` is rank 4, so dropping from the right-hand end would
        lose DELTA first. Priority says otherwise, and priority is what the engine reads.
        """
        with PrioritySession(cols=35) as session:
            grid = session.grid()
            text = " ".join(drawn(grid))
            self.assertIn("delta", text, msg=excerpt(grid))
            self.assertNotIn("bravobravo", text, msg=excerpt(grid))

    def test_the_prompt_never_wraps_however_narrow_the_window(self):
        """Issue #190's other half.

        The resize handler rebuilds for the new width; this is what it rebuilds INTO. Two
        rows is the shape — the segment row and the marker row — and a third means the
        segment row wrapped, which is the failure the fit exists to prevent.
        """
        for cols in (60, 35, 22, 12, 8):
            with self.subTest(cols=cols):
                with PrioritySession(cols=cols) as session:
                    grid = session.grid()
                    self.assertLessEqual(grid.rows_occupied(), 2, msg=excerpt(grid))
                    for row in range(grid.lines):
                        self.assertLessEqual(
                            len(grid.row_text(row)), cols, msg=excerpt(grid, focus=row)
                        )

    def test_the_order_is_the_users_to_change(self):
        """The whole point of the knob.

        `BRAVO` is the widest block and the first to go by default. Given a priority below
        everything else it becomes the last, and at a width that held two blocks it is one
        of the two — while `CHARLIE`, which outlived it a moment ago, is gone.
        """
        with PrioritySession(cols=22, prelude="\ntypeset -g INZSH_BRAVO_PRIORITY=5\n") as session:
            grid = session.grid()
            text = " ".join(drawn(grid))
            self.assertIn("bravobravo", text, msg=excerpt(grid))
            self.assertIn("alfa", text, msg=excerpt(grid))
            self.assertNotIn("charlie", text, msg=excerpt(grid))


if __name__ == "__main__":
    unittest.main()
