"""The prompt when the window stops being the width it was drawn for.

Nothing on this page could be asserted anywhere else, and that is the point. A render
spec can prove that `_inzsh_render` builds a row of the right width for the `$COLUMNS` it
is given — and it would have passed, unchanged, for every day this bug shipped, because
the bug is not in the arithmetic. It is that nothing re-ran the arithmetic. Proving the
fix therefore needs a terminal that CHANGES SIZE under a prompt that is already on screen,
which means a real pty, a real controlling terminal, and a real SIGWINCH from the kernel:
`Session.resize` moves the window and signals nobody, exactly as dragging an edge does.

The claims, in the order they matter:

* narrowing rebuilds the segment row for the new width, and widening does too — in both
  prompt shapes;
* the same resize WITHOUT the redraw installed leaves a row too wide for its window, so it
  wraps and a two-row prompt becomes four. That is issue #190, reproduced;
* a half-typed command line survives the redraw with its text intact;
* the right side drops rather than relocates when the gap will no longer fit — `v1.3.0 ·
  Prompt rows` removed the old fallback beside the marker, so a resize that narrows the
  window past the gap loses that block rather than moving it;
* the mechanism: a resize fires `TRAPWINCH` and does NOT fire `zle-line-pre-redraw`, which
  is why this is a trap and not a widget;
* a window that changed only its height redraws nothing;
* a foreign `TRAPWINCH` still runs through install, and uninstall gives it back.

Nothing here hardcodes a colour. The two segment texts are the only literals, and they are
words nothing else on the grid contains.
"""

from __future__ import annotations

import os
import re
import tempfile
import unittest
from pathlib import Path

from grid_asserts import excerpt
from pty_session import Session

REPO_ROOT = Path(__file__).resolve().parents[2]
CORE = REPO_ROOT / "lib" / "core"

# One block on each side. Short enough that both fit at 40 columns and neither fits at 20,
# so the same fixture reaches both the padded row and the width where the right one drops.
LEFT = "LEFTBLOCK"
RIGHT = "RIGHT9"

# The library, a two-segment fixture, and two counters the assertions read back.
#
# `_inzsh_resize_winch` is wrapped rather than replaced, so what is counted is the real
# handler running: `winch` is signals seen, and `redraw` is the ones that actually rebuilt
# the prompt — `_inzsh_render_cols` is the width the prompt was built for, so it moves when
# and only when the handler re-rendered. Counting that way needs no arithmetic about how
# many prompts a test's own commands drew.
SETUP = """
unset -m "INZSH_*"
for _f in config detect tokens-256 tokens layout engine render hooks resize; do
  source {core}/$_f.zsh
done
typeset -gA _inzsh_segment_defaults _inzsh_segment_text
_inzsh_segment_defaults=(LEFTA 1 RIGHTB -1)
_inzsh_segment_text=(LEFTA {left} RIGHTB {right})
typeset -gi winch=0 redraw=0 predraw=0 alien=0 prefirst=0 prelast=0
functions[_inzsh_resize_winch_orig]=$functions[_inzsh_resize_winch]
_inzsh_resize_winch() {{
  (( winch++ ))
  (( winch == 1 )) && (( prefirst = predraw ))
  (( prelast = predraw ))
  local was=$_inzsh_render_cols
  _inzsh_resize_winch_orig "$@"
  [[ $_inzsh_render_cols == $was ]] || (( redraw++ ))
}}
_predraw() {{ (( predraw++ )) }}
zle -N zle-line-pre-redraw _predraw
_inzsh_hooks_install
"""

# The foreign handler, bound BEFORE the install — the order a theme loaded from an rc file
# actually meets, a plugin that was already there.
ALIEN = """
TRAPWINCH() {{ (( alien++ )) }}
"""

INSTALL = """
_inzsh_resize_install
"""


class ResizeSession:
    """An interactive session with the theme sourced from a file rather than typed.

    Typing the setup line by line would leave a dozen prompts on the very grid the
    assertions read. One `source` is one row.
    """

    def __init__(self, *, cols=100, lines=24, prelude="", alien=False, install=True):
        handle, self.path = tempfile.mkstemp(suffix=".zsh", prefix="inzsh-resize-")
        script = SETUP.format(core=CORE, left=LEFT, right=RIGHT)
        if alien:
            script += ALIEN.format()
        if install:
            script += INSTALL
        with os.fdopen(handle, "w") as fh:
            # After the setup, never before it: the setup opens with `unset -m 'INZSH_*'`
            # so a knob in the developer's own environment cannot reach the grid.
            fh.write(script + prelude)
        self.session = Session(cols=cols, lines=lines)
        self.session.send(f"source {self.path}")
        # A clear leaves the live prompt alone on the grid, so `rows_occupied` counts the
        # prompt and nothing that scrolled above it.
        self.session.send("clear")

    def __enter__(self):
        return self.session

    def __exit__(self, *exc):
        try:
            if self.session._proc.poll() is None:  # noqa: SLF001 — teardown, not a read
                self.session.finish()
        finally:
            os.unlink(self.path)


def rows_with(grid, text):
    """Every row index carrying `text`."""
    return [row for row in range(grid.lines) if text in grid.row_text(row)]


def widest(grid):
    """The longest row on the grid, in columns."""
    return max((len(grid.row_text(row)) for row in range(grid.lines)), default=0)


def printed(grid, label):
    """The values a `print A=$a B=$b` line put on the grid, as a dict.

    The row is found by its first field, and a row still carrying a `$` is the ECHO of
    the command rather than its output — the two are otherwise identical, and taking the
    echo would read every value as the name of its own variable.
    """
    for row in range(grid.lines):
        text = grid.row_text(row)
        if text.startswith(f"{label}=") and "$" not in text:
            return dict(field.split("=", 1) for field in text.split())
    raise AssertionError(f"no {label}= row on the grid\n" + excerpt(grid))


def climbs(raw):
    """Every cursor-up amount a resize actually emitted, in the order it was written.

    `_inzsh_resize_winch` prints exactly `\\e[<n>A` immediately followed by `\\r\\e[J` — the
    climb, then the erase — and nothing else in an ordinary session pairs the two, so anchoring
    on both together is what tells this apart from zsh's own cursor movement during ordinary
    line editing, which the plain escape alone cannot. Reading it back from the raw transcript
    is what lets a test compare the SIZE of two climbs directly rather than only their visible
    effect, which is the only way to say anything honest about a terminal that reflows — see
    `ReflowTest` below.
    """
    return [int(n) for n in re.findall(rb"\x1b\[(\d+)A\r\x1b\[J", raw)]


# Four short, distinct fixture segments for `INZSH_ROW<n>_LEFT` / `_RIGHT` (issue #223) — enough
# to spread across three rows with a side to spare. `_inzsh_rows_resolve` claims them by NAME
# (§2.3 of `.claude/docs/DESIGN-prompt-rows.md`), so which row and side each lands on is entirely
# the prelude's own `INZSH_ROW*` assignment, never a rank.
ROW_A = "ALFA"
ROW_B = "BRAVO"
ROW_C = "CHARLIE"
ROW_D = "DELTA"

ROWS_SETUP = """
unset -m "INZSH_*"
for _f in config detect tokens-256 tokens layout engine rows render hooks resize; do
  source {core}/$_f.zsh
done
typeset -gA _inzsh_segment_defaults _inzsh_segment_text
_inzsh_segment_defaults=(ALFA 1 BRAVO 1 CHARLIE 1 DELTA 1)
_inzsh_segment_text=(ALFA {a} BRAVO {b} CHARLIE {c} DELTA {d})
typeset -gi winch=0 redraw=0
functions[_inzsh_resize_winch_orig]=$functions[_inzsh_resize_winch]
_inzsh_resize_winch() {{
  (( winch++ ))
  local was=$_inzsh_render_cols
  _inzsh_resize_winch_orig "$@"
  [[ $_inzsh_render_cols == $was ]] || (( redraw++ ))
}}
_inzsh_hooks_install
_inzsh_resize_install
"""


class RowsResizeSession:
    """Like `ResizeSession`, but with `lib/core/rows.zsh` sourced too and four fixture
    segments spread over up to three rows rather than the two-segment single-row fixture above.
    `prelude` is where a test assigns `INZSH_ROW<n>_LEFT` / `_RIGHT` and `INZSH_MARKER_ROW`,
    exactly as a `.zshrc` would.
    """

    def __init__(self, *, cols=100, lines=24, prelude=""):
        handle, self.path = tempfile.mkstemp(suffix=".zsh", prefix="inzsh-rows-resize-")
        script = ROWS_SETUP.format(core=CORE, a=ROW_A, b=ROW_B, c=ROW_C, d=ROW_D)
        with os.fdopen(handle, "w") as fh:
            fh.write(script + prelude)
        self.session = Session(cols=cols, lines=lines)
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


class MultiRowShapeTest(unittest.TestCase):
    """The multi-row climb, issue #223. `_inzsh_render` now records the drawn width of every
    row in `_inzsh_render_row_widths` (one entry per row, the assembled row including its gap,
    not one side), and `lib/core/resize.zsh` sums a reflow height over the whole array rather
    than reading `_inzsh_render_width` — a slot the LAST row built happened to leave behind,
    which on a single-row prompt is harmless and on a configured multi-row one is meaningless.
    The default one-row shape is `ShapeTest` above and is untouched by any of this; everything
    here needs at least two configured rows to exist as a claim at all.

    Each case also pins the exact `\\e[<n>A` climb via `climbs()`, and that number is the part
    that actually moved: on the pre-fix code every one of these narrows the SAME way regardless
    of row count — `own` always climbed `1` and `inline` climbed `0` (nothing at all, since a
    climb of 0 is not printed), because `rows` was hardcoded to `1` outside a reflowing
    terminal. zsh's own line editor happens to paper over the resulting gap in the grid these
    tests read back — nothing here is a visible artefact — so without pinning the climb itself
    this class would pass on the old arithmetic too. The number is the fix; see the report for
    the git-stash comparison that proves it.
    """

    def test_two_rows_under_own_climb_past_both_on_narrowing(self):
        prelude = "INZSH_ROW1_LEFT=(ALFA) INZSH_ROW1_RIGHT=(BRAVO) INZSH_ROW2_LEFT=(CHARLIE)\n"
        with RowsResizeSession(prelude=prelude) as session:
            session.resize(44)
            grid = session.grid()

        # Row 1, row 2, the bare marker line below both — three physical rows, and nothing
        # left over from the row built for 100 columns.
        self.assertEqual(grid.rows_occupied(), 3, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_A), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_B), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_C), [1], msg=excerpt(grid))
        self.assertLessEqual(widest(grid), 43, msg=excerpt(grid))
        # `own`: above = rows(2) + lines(2) - 2 = 2 — one row per drawn row.
        self.assertEqual(climbs(grid.raw)[-1], 2, msg=excerpt(grid))

    def test_three_rows_under_own_climb_past_all_three_on_narrowing(self):
        prelude = (
            "INZSH_ROW1_LEFT=(ALFA) INZSH_ROW1_RIGHT=(BRAVO) "
            "INZSH_ROW2_LEFT=(CHARLIE) INZSH_ROW3_LEFT=(DELTA)\n"
        )
        with RowsResizeSession(prelude=prelude) as session:
            session.resize(44)
            grid = session.grid()

        self.assertEqual(grid.rows_occupied(), 4, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_A), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_B), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_C), [1], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_D), [2], msg=excerpt(grid))
        self.assertLessEqual(widest(grid), 43, msg=excerpt(grid))
        self.assertEqual(climbs(grid.raw)[-1], 3, msg=excerpt(grid))

    def test_two_rows_under_inline_climb_past_the_merged_last_row(self):
        prelude = (
            "INZSH_ROW1_LEFT=(ALFA) INZSH_ROW1_RIGHT=(BRAVO) INZSH_ROW2_LEFT=(CHARLIE)\n"
            "INZSH_MARKER_ROW=inline\n"
        )
        with RowsResizeSession(prelude=prelude) as session:
            session.resize(44)
            grid = session.grid()

        # No bare marker line under `inline` — it terminates row 2 instead, so the prompt is
        # one line shorter than the `own` case above over the same rows.
        self.assertEqual(grid.rows_occupied(), 2, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_A), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_C), [1], msg=excerpt(grid))
        self.assertLessEqual(widest(grid), 43, msg=excerpt(grid))
        # `inline`: above = rows(2) + lines(1) - 2 = 1 — one less than `own`, because the
        # cursor already sits on the last drawn row rather than a bare line below it.
        self.assertEqual(climbs(grid.raw)[-1], 1, msg=excerpt(grid))

    def test_three_rows_under_inline_climb_past_the_merged_last_row(self):
        prelude = (
            "INZSH_ROW1_LEFT=(ALFA) INZSH_ROW1_RIGHT=(BRAVO) "
            "INZSH_ROW2_LEFT=(CHARLIE) INZSH_ROW3_LEFT=(DELTA)\n"
            "INZSH_MARKER_ROW=inline\n"
        )
        with RowsResizeSession(prelude=prelude) as session:
            session.resize(44)
            grid = session.grid()

        self.assertEqual(grid.rows_occupied(), 3, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_A), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_C), [1], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_D), [2], msg=excerpt(grid))
        self.assertLessEqual(widest(grid), 43, msg=excerpt(grid))
        # `inline` over three rows: above = rows(3) + lines(1) - 2 = 2.
        self.assertEqual(climbs(grid.raw)[-1], 2, msg=excerpt(grid))

    def test_widening_a_three_row_own_prompt_climbs_every_row_too(self):
        """The climb runs identically on the way back up — nothing here special-cases the
        direction of the resize, only the width it disagrees with `$COLUMNS` about."""
        prelude = (
            "INZSH_ROW1_LEFT=(ALFA) INZSH_ROW1_RIGHT=(BRAVO) "
            "INZSH_ROW2_LEFT=(CHARLIE) INZSH_ROW3_LEFT=(DELTA)\n"
        )
        with RowsResizeSession(cols=44, prelude=prelude) as session:
            session.resize(90)
            grid = session.grid()

        self.assertEqual(grid.rows_occupied(), 4, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_A), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_B), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_C), [1], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, ROW_D), [2], msg=excerpt(grid))
        self.assertEqual(climbs(grid.raw)[-1], 3, msg=excerpt(grid))


class ReflowTest(unittest.TestCase):
    """`INZSH_RESIZE_REFLOW` (issue #215, adjacent). `pyte` — this whole harness's terminal —
    does not itself re-wrap rows already on screen when it is resized (`Screen.resize` clips or
    extends columns in place; nothing in it moves text between rows), so no assertion here can
    honestly claim to show a reflowed SCREEN. What it can show, and what actually changed with
    this fix, is the ARITHMETIC: `lib/core/resize.zsh` now sums `ceil(width / columns)` over
    every row in `_inzsh_render_row_widths` when `_inzsh_resize_reflows` says yes, instead of
    computing it from `_inzsh_render_width` — a single slot a multi-row prompt made meaningless.
    Reading the actual `\\e[<n>A` escape back from the transcript is what lets the climb's SIZE
    be compared directly, which is more than the visible grid alone could ever prove.
    """

    def test_a_reflowing_terminal_climbs_further_than_a_flat_one(self):
        # Row 1 (ALFA/BRAVO, both sides) pads out to nearly the full 100 columns it was built
        # for — `_inzsh_render_gap` always proposes filling the row up to `cols - 1` when there
        # is room, regardless of how short the segments themselves are — so narrowing hard, to
        # 20, makes it wrap several times over on a terminal that reflows and not at all on one
        # that does not, however the fixture's own text is spelled.
        prelude = "INZSH_ROW1_LEFT=(ALFA) INZSH_ROW1_RIGHT=(BRAVO) INZSH_ROW2_LEFT=(CHARLIE)\n"

        with RowsResizeSession(prelude=prelude + "INZSH_RESIZE_REFLOW=0\n") as session:
            session.resize(20)
            flat = climbs(session.grid().raw)

        with RowsResizeSession(prelude=prelude + "INZSH_RESIZE_REFLOW=1\n") as session:
            session.resize(20)
            reflowed = climbs(session.grid().raw)

        self.assertTrue(flat, msg="no climb escape seen on the non-reflowing run")
        self.assertTrue(reflowed, msg="no climb escape seen on the reflowing run")
        # Two rows, neither reflowing: the climb is exactly the row count, `2`.
        self.assertEqual(flat[-1], 2)
        # The same two rows, `ROW1` alone now assumed to have wrapped `ceil(99 / 20) = 5`
        # times: climbing past it costs strictly more than climbing past one physical row.
        self.assertGreater(reflowed[-1], flat[-1])


class ShapeTest(unittest.TestCase):
    """What the terminal shows after the window has changed size."""

    def test_narrowing_rebuilds_the_segment_row_for_the_new_width(self):
        with ResizeSession() as session:
            session.resize(44)
            grid = session.grid()

        self.assertEqual(grid.rows_occupied(), 2, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, LEFT), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, RIGHT), [0], msg=excerpt(grid))
        self.assertLessEqual(widest(grid), 43, msg=excerpt(grid))

    def test_without_the_redraw_the_row_stays_too_wide_and_wraps(self):
        """Issue #190, reproduced. The only difference from the example above is the
        trap: the prompt built for 100 columns is still 99 wide at 44, so the segment row
        spills over two more grid rows and the two-row prompt is four rows tall."""
        with ResizeSession(install=False) as session:
            session.resize(44)
            grid = session.grid()

        # The two ends of ONE segment row, landing on two grid rows: that is the wrap.
        # The example above is the mirror of this one — both on row 0, prompt two rows
        # tall — and the only difference between them is the trap.
        self.assertGreater(grid.rows_occupied(), 2, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, LEFT), [0], msg=excerpt(grid))
        self.assertNotEqual(rows_with(grid, RIGHT), [0], msg=excerpt(grid))

    def test_switching_it_off_leaves_the_prompt_exactly_as_stale(self):
        """`INZSH_RESIZE=0` is the escape hatch, and it has to be the whole of it: the
        trap is still installed and still runs, and the prompt is still not redrawn."""
        with ResizeSession(prelude="INZSH_RESIZE=0\n") as session:
            session.resize(44)
            session.send("print WINCH=$winch REDRAW=$redraw")
            grid = session.finish()

        seen = printed(grid, "WINCH")
        self.assertEqual(seen["WINCH"], "1", msg=excerpt(grid))
        self.assertEqual(seen["REDRAW"], "0", msg=excerpt(grid))

    def test_widening_puts_the_right_side_back_at_the_new_edge(self):
        with ResizeSession() as session:
            session.resize(44)
            narrow = widest(session.grid())
            session.resize(88)
            grid = session.grid()

        self.assertEqual(grid.rows_occupied(), 2, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, RIGHT), [0], msg=excerpt(grid))
        self.assertLessEqual(widest(grid), 87, msg=excerpt(grid))
        self.assertGreater(widest(grid), narrow, msg=excerpt(grid))

    def test_the_one_line_shape_redraws_too(self):
        """At `INZSH_PROMPT_LINES=1` the right side is a real `RPROMPT`, which zsh places
        itself — so this is the shape the bug was mildest in, and it still has to be
        rebuilt: the LEFT side is measured against `$COLUMNS` like everything else."""
        with ResizeSession(prelude="INZSH_PROMPT_LINES=1\n") as session:
            session.resize(50)
            grid = session.grid()

        self.assertEqual(grid.rows_occupied(), 1, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, LEFT), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, RIGHT), [0], msg=excerpt(grid))
        self.assertLessEqual(widest(grid), 49, msg=excerpt(grid))

    def test_the_right_side_drops_rather_than_relocates_when_the_gap_will_not_fit(self):
        """`v1.3.0 · Prompt rows` removed the old fallback beside the marker: nothing
        relocates between rows any more, so a block that will not fit its row drops by
        priority instead. The marker row stays bare — RIGHT9 is nowhere on the grid."""
        with ResizeSession() as session:
            session.resize(20)
            grid = session.grid()

        self.assertEqual(grid.rows_occupied(), 2, msg=excerpt(grid))
        self.assertEqual(rows_with(grid, LEFT), [0], msg=excerpt(grid))
        self.assertEqual(rows_with(grid, RIGHT), [], msg=excerpt(grid))
        self.assertLessEqual(widest(grid), 19, msg=excerpt(grid))

    def test_a_half_typed_command_line_survives_the_resize(self):
        """Not fighting the line editor. `zle .reset-prompt` redraws around the buffer, so
        what was typed is still there, still editable, and still runs when Enter lands."""
        with ResizeSession() as session:
            session.send_raw("print HALFTYPED")
            session.resize(56)
            mid = session.grid()
            self.assertEqual(rows_with(mid, "print HALFTYPED"), [1], msg=excerpt(mid))
            self.assertEqual(mid.rows_occupied(), 2, msg=excerpt(mid))
            session.send_raw("\r")
            grid = session.finish()

        self.assertIn(
            "HALFTYPED",
            "".join(grid.row_text(row) for row in range(grid.lines)),
            msg=excerpt(grid),
        )


class MechanismTest(unittest.TestCase):
    """Why it is a trap, and what it costs."""

    def test_a_resize_fires_the_winch_trap_and_not_the_line_editor(self):
        """The measurement `lib/core/resize.zsh` is built on. `zle-line-pre-redraw` is the
        widget that would have been the nicer seam — it wraps and restores exactly the way
        `zle-line-finish` does — and zsh does not call it when the window changes. Ten
        resizes, ten signals, no widget calls."""
        with ResizeSession() as session:
            for cols in (60, 90, 70, 100, 65, 95, 75, 85, 55, 45):
                session.resize(cols)
            session.send("print WINCH=$winch REDRAW=$redraw A=$prefirst B=$prelast")
            grid = session.finish()

        seen = printed(grid, "WINCH")
        self.assertEqual(seen["WINCH"], "10", msg=excerpt(grid))
        self.assertEqual(seen["REDRAW"], "10", msg=excerpt(grid))
        # `prefirst` and `prelast` are the widget's own counter, sampled by the trap at
        # the first signal and again at the last. Nothing was typed between them, so any
        # movement would be the resizes calling the widget. There is none.
        self.assertEqual(seen["A"], seen["B"], msg=excerpt(grid))
        # And the counter is live: the widget did fire, for the keystrokes that set the
        # session up. An assertion that a dead counter did not move proves nothing.
        self.assertGreater(int(seen["A"]), 0, msg=excerpt(grid))

    def test_a_change_of_height_alone_redraws_nothing(self):
        """The coalescing, and the whole of it. Dragging the bottom edge of a window
        signals every frame and moves nothing the prompt draws."""
        with ResizeSession() as session:
            session.resize(70)
            session.resize(70, 30)
            session.resize(70, 18)
            session.send("print WINCH=$winch REDRAW=$redraw")
            grid = session.finish()

        seen = printed(grid, "WINCH")
        self.assertEqual(seen["WINCH"], "3", msg=excerpt(grid))
        self.assertEqual(seen["REDRAW"], "1", msg=excerpt(grid))


class ForeignTrapTest(unittest.TestCase):
    """zsh has ONE WINCH handler. Taking somebody else's is the bug this refuses to ship."""

    def test_a_foreign_trapwinch_still_runs_after_install(self):
        with ResizeSession(alien=True) as session:
            session.resize(60)
            session.resize(80)
            session.send("print ALIEN=$alien REDRAW=$redraw")
            grid = session.finish()

        seen = printed(grid, "ALIEN")
        self.assertEqual(seen["ALIEN"], "2", msg=excerpt(grid))
        self.assertEqual(seen["REDRAW"], "2", msg=excerpt(grid))

    def test_uninstalling_gives_the_foreign_trap_back_and_stops_redrawing(self):
        with ResizeSession(alien=True) as session:
            session.send("_inzsh_resize_uninstall")
            session.send("clear")
            session.resize(60)
            grid = session.grid()
            session.send("print ALIEN=$alien REDRAW=$redraw")
            final = session.finish()

        # Still firing: the handler we handed back is the one that was there before us.
        seen = printed(final, "ALIEN")
        self.assertEqual(seen["ALIEN"], "1", msg=excerpt(final))
        self.assertEqual(seen["REDRAW"], "0", msg=excerpt(final))
        # And the stale row is back, which is the other half of "uninstall put everything
        # where it found it".
        self.assertGreater(grid.rows_occupied(), 2, msg=excerpt(grid))


if __name__ == "__main__":
    unittest.main()
