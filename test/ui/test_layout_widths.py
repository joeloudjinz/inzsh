"""The one-row invariant, read off a real terminal grid.

`test/unit/layout_spec.sh` proves the arithmetic: the segments that survive at a
width, plus their separators, add up to no more than that width. It cannot prove
that the arithmetic was about the right thing, because the widths it works from
are numbers a spec chose. This file closes that loop — a line is BUILT out of
colour escapes and glyphs, measured by `_inzsh_width` alone, and then drawn on a
pty of a known size. If the measurement counted an escape as a column, or missed
a glyph, the line wraps and the row count says so.

There are no segments yet (they land at M3), so the line here is a model: fixed
labels, a powerline separator between blocks, and a MINCOLS per block derived from
what that block and everything more important than it cost together. Rank order and
priority order deliberately disagree, so a layout that dropped from the right-hand
end rather than by MINCOLS would draw a different row.

Nothing below hardcodes a colour value or a width. The widths come out of the
library, the survivors come out of the library, and the assertions compare the grid
to what the library said it was going to draw.
"""

from __future__ import annotations

import shlex
import unittest
from pathlib import Path

import grid_runner
from grid_asserts import assert_row_occupancy, excerpt

REPO_ROOT = Path(__file__).resolve().parents[2]
LAYOUT = REPO_ROOT / "lib" / "core" / "layout.zsh"

# Wide enough for every block, then down through each rung of the ladder to a pane
# nothing much fits in.
WIDTHS = (140, 120, 100, 80, 70, 60, 40, 24)

# The model, as one zsh program with two modes. `plan` reports what the library
# decided; `prompt` draws it. Both read `$COLUMNS`, which on a pty is the real
# terminal width — the point of running this at L3 rather than at L2.
SNIPPET = """
unset -m 'INZSH_*'
source {layout}

names=(DIR STATUS GIT CLOCK VENV SALAH)
labels=('~/dev/inzsh' '{tick}' 'main' '12:04' 'venv' 'Maghrib {dot} 19:59')
fills=(blue magenta blue magenta blue magenta)
# 1 is kept longest. DIR outranks everything and sits first; VENV goes first and
# sits fifth; nothing here can be inferred from position.
ranks=(1 4 2 3 6 5)

sep='{sep}'
_inzsh_width "$sep"
sep_width=$REPLY

# A drawn block is the label with one column of padding either side.
typeset -a blocks widths
integer i j
for (( i = 1; i <= $#names; i++ )); do
  blocks[i]="%K{{${{fills[i]}}}}%F{{white}} ${{labels[i]}} %f%k"
  _inzsh_width "${{blocks[i]}}"
  widths[i]=$REPLY
done

# MINCOLS: what this block and everything more important than it cost together.
typeset -a cost
for (( i = 1; i <= $#names; i++ )); do
  cost=()
  for (( j = 1; j <= $#names; j++ )); do
    (( ranks[j] <= ranks[i] )) && cost+=${{widths[j]}}
  done
  _inzsh_layout_total $sep_width "${{cost[@]}}"
  typeset -g INZSH_${{names[i]}}_MINCOLS=$REPLY
done

_inzsh_layout_filter $COLUMNS "${{names[@]}}"
typeset -a survivors=("${{reply[@]}}")

cost=()
for name in "${{survivors[@]}}"; do
  i=${{names[(Ie)$name]}}
  cost+=${{widths[i]}}
done
_inzsh_layout_total $sep_width "${{cost[@]}}"
integer total=$REPLY
if [[ ${{SPEC_MODE:-prompt}} == plan ]]; then
  print -rn -- "$COLUMNS $total ${{survivors[*]}}"
  return 0
fi

line=''
for (( i = 1; i <= $#survivors; i++ )); do
  j=${{names[(Ie)${{survivors[i]}}]}}
  line+=${{blocks[j]}}
  (( i < $#survivors )) && line+="%F{{white}}$sep%f"
done
print -rn -- "${{(%%)line}}"
"""


def snippet():
    return SNIPPET.format(
        layout=shlex.quote(str(LAYOUT)),
        sep="",
        tick="✓",
        dot="·",
    )


class Plan:
    """What the library said it would draw at one width."""

    def __init__(self, text):
        fields = text.split()
        self.cols = int(fields[0])
        self.total = int(fields[1])
        self.survivors = fields[2:]


def plan_at(cols):
    grid = grid_runner.render(snippet(), cols=cols, env={"SPEC_MODE": "plan"})
    if grid.exit_status != 0:
        raise AssertionError(excerpt(grid))
    return Plan(grid.row_text(0))


def prompt_at(cols):
    return grid_runner.render(snippet(), cols=cols)


class LayoutWidthTest(unittest.TestCase):
    """One row at every width, and a row that actually changes with the width."""

    def test_every_width_draws_exactly_one_row(self):
        for cols in WIDTHS:
            with self.subTest(cols=cols):
                grid = prompt_at(cols)
                self.assertEqual(grid.exit_status, 0, msg=excerpt(grid))
                assert_row_occupancy(grid, 1)

    def test_the_drawn_row_is_no_wider_than_the_terminal(self):
        """What the library measured is what the terminal ended up holding.

        The trailing padding column of the last block is blank, so the drawn text
        can come back one column short of the total; anything else is a
        measurement that did not match the render.
        """
        for cols in WIDTHS:
            with self.subTest(cols=cols):
                plan = plan_at(cols)
                grid = prompt_at(cols)
                drawn = len(grid.row_text(0))
                self.assertLessEqual(plan.total, cols, msg=str(vars(plan)))
                self.assertLessEqual(drawn, cols, msg=excerpt(grid, focus=0))
                self.assertIn(drawn, (plan.total, plan.total - 1), msg=excerpt(grid, focus=0))

    def test_what_survives_is_what_is_drawn(self):
        for cols in WIDTHS:
            with self.subTest(cols=cols):
                plan = plan_at(cols)
                grid = prompt_at(cols)
                text = grid.row_text(0)
                for name in plan.survivors:
                    self.assertIn(name, ("DIR", "STATUS", "GIT", "CLOCK", "VENV", "SALAH"))
                self.assertEqual("VENV" in plan.survivors, "venv" in text, msg=text)
                self.assertEqual("SALAH" in plan.survivors, "Maghrib" in text, msg=text)
                self.assertEqual("GIT" in plan.survivors, "main" in text, msg=text)

    def test_the_row_degrades_as_the_terminal_narrows(self):
        """Fewer segments at every step down the widths."""
        plans = [plan_at(cols) for cols in WIDTHS]
        counts = [len(plan.survivors) for plan in plans]
        self.assertEqual(counts, sorted(counts, reverse=True), msg=str(counts))
        self.assertEqual(counts[0], 6, msg=str(counts))
        self.assertLess(counts[-1], counts[0], msg=str(counts))

    def test_a_terminal_too_narrow_for_anything_draws_nothing_rather_than_wrapping(self):
        grid = prompt_at(8)
        self.assertEqual(grid.exit_status, 0, msg=excerpt(grid))
        self.assertLessEqual(grid.rows_occupied(), 1, msg=excerpt(grid))
        self.assertLessEqual(len(grid.row_text(0)), 8, msg=excerpt(grid, focus=0))


if __name__ == "__main__":
    unittest.main()
