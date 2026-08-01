"""The transient prompt, read off the scrollback of a real terminal.

`test/render/transient_spec.sh` can prove the widget is bound, that it calls whoever was
bound before it, and that collapsing swaps two parameters. It cannot prove any of the
things the feature is FOR, because all of them are properties of a transcript:
`zle-line-finish` only fires inside a line editor, a line editor only exists on a
terminal, and what a collapsed prompt looks like three commands later is a question only
the scrollback can answer.

So this page types into a real one. Every test drives an interactive `zsh -f -i` on a pty,
sources the library, runs commands the way a person would, and reads back the grid the
user would have been left looking at.

The claims, in the order they matter:

* the transcript is commands and output with one marker between them, and the full
  seven-block prompt appears nowhere in it;
* a foreign `zle-line-finish` still runs, through install and after uninstall — this is
  #62, and it is the same class of rule as `add-zsh-hook` for precmd;
* the awkward inputs leave sensible scrollback: a failing command, a quote continued over
  two lines, and Ctrl-C on an empty line.

Nothing here hardcodes a colour. The marker's two states are compared to each other. The
segment text is the only literal, and it is a word nothing else on the grid contains.
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

# The one word that only ever appears inside the full prompt. If it reaches the scrollback,
# a prompt failed to collapse.
BLOCK = "UNIQUEBLOCK"

# Everything the library needs, plus a fixture segment and a foreign `zle-line-finish` that
# counts its own calls. The foreign widget is bound BEFORE the install, which is the order a
# theme loaded from an rc file actually meets — a plugin that was already there.
SETUP = """
unset -m "INZSH_*"
for _f in config detect tokens-256 tokens layout engine render hooks transient; do
  source {core}/$_f.zsh
done
typeset -gA _inzsh_segment_defaults _inzsh_segment_text
_inzsh_segment_defaults=(ALFA 1)
_inzsh_segment_text=(ALFA {block})
typeset -gi alien=0
alienfn() {{ (( alien++ )) }}
zle -N zle-line-finish alienfn
_inzsh_hooks_install
_inzsh_transient_install
"""


class TransientSession:
    """An interactive session with the theme sourced from a file rather than typed.

    Typing the setup line by line would put a dozen prompts into the very transcript the
    assertions read. One `source` is one row, and it is the only row this class leaves
    behind.
    """

    def __init__(self, *, cols=72, lines=20, prelude=""):
        handle, self.path = tempfile.mkstemp(suffix=".zsh", prefix="inzsh-transient-")
        with os.fdopen(handle, "w") as script:
            # After the setup, never before it: the setup opens with `unset -m 'INZSH_*'`
            # so that a knob in the developer's own environment cannot reach the grid, and
            # a prelude written above that line would be unset by it.
            script.write(SETUP.format(core=CORE, block=BLOCK) + prelude)
        self.session = Session(cols=cols, lines=lines)
        self.session.send(f"source {self.path}")

    def __enter__(self):
        return self.session

    def __exit__(self, *exc):
        try:
            if self.session._proc.poll() is None:  # noqa: SLF001 — teardown, not a read
                self.session.finish()
        finally:
            os.unlink(self.path)


def rows_of(grid):
    return [grid.row_text(row) for row in range(grid.lines) if grid.row_text(row)]


def row_index(grid, text):
    """The row the given text was drawn on. An error rather than a -1: a test that went
    looking for a row and did not find one has already failed, and the grid says why."""
    for row in range(grid.lines):
        if text in grid.row_text(row):
            return row
    raise AssertionError(f"{text!r} is nowhere on the grid\n" + excerpt(grid))


class TranscriptTest(unittest.TestCase):
    """What the user is left looking at."""

    def test_the_prompt_collapses_to_the_marker_in_the_scrollback(self):
        with TransientSession() as session:
            session.send("print ONE")
            session.send("print TWO")
            grid = session.finish()

        rows = rows_of(grid)
        self.assertIn("print ONE", " ".join(rows), msg=excerpt(grid))
        for command in ("print ONE", "print TWO"):
            row = grid.row_text(row_index(grid, command))
            self.assertTrue(
                row.endswith(command) and len(row) - len(command) <= 2,
                msg=f"{row!r} is not a collapsed prompt\n" + excerpt(grid),
            )
        self.assertNotIn(
            BLOCK,
            "".join(rows),
            msg="a full prompt survived into the scrollback\n" + excerpt(grid),
        )

    def test_switching_it_off_keeps_the_full_prompt_in_the_scrollback(self):
        with TransientSession(prelude="INZSH_TRANSIENT=0\n") as session:
            session.send("print ONE")
            session.send("print TWO")
            grid = session.finish()

        rows = rows_of(grid)
        kept = [row for row in rows if BLOCK in row]
        self.assertGreaterEqual(len(kept), 2, msg=excerpt(grid))

    def test_the_directory_format_puts_the_path_in_front_of_the_marker(self):
        with TransientSession(prelude="cd /tmp\n") as session:
            session.send("INZSH_TRANSIENT_FORMAT=dir")
            session.send("print ONE")
            grid = session.finish()

        row = grid.row_text(row_index(grid, "print ONE"))
        self.assertTrue(row.startswith("/tmp "), msg=excerpt(grid))
        self.assertTrue(row.endswith("print ONE"), msg=excerpt(grid))

    def test_a_failing_command_leaves_a_marker_that_says_so(self):
        """The collapsed prompt carries the status colour the live one carried.

        Compared to itself: the marker in front of the command AFTER `false` must differ
        from the marker in front of `false` itself, which followed a command that worked.
        """
        with TransientSession() as session:
            session.send("print ONE")
            session.send("false")
            session.send("print TWO")
            grid = session.finish()

        clean = grid.cell(row_index(grid, "false"), 0)
        failed = grid.cell(row_index(grid, "print TWO"), 0)
        self.assertEqual(clean.char, failed.char, msg=excerpt(grid))
        self.assertNotEqual(
            clean.fg,
            failed.fg,
            msg="the collapsed marker reads the same after a failure as after a success\n"
            + excerpt(grid),
        )

    def test_a_quote_continued_over_two_lines_keeps_both_of_them(self):
        with TransientSession() as session:
            session.send("print 'one")
            session.send("two'")
            session.send("print AFTER")
            grid = session.finish()

        rows = rows_of(grid)
        joined = "\n".join(rows)
        for expected in ("print 'one", "two'", "one", "two", "AFTER"):
            self.assertIn(expected, joined, msg=excerpt(grid))
        # The continuation row is zsh's own PS2, not a collapsed prompt: a transient that
        # redrew the whole buffer would have eaten the first half of the command.
        self.assertTrue(
            any(row.endswith("two'") and "print" not in row for row in rows),
            msg=excerpt(grid),
        )


class ForeignWidgetTest(unittest.TestCase):
    """#62 — the binding is not ours, and installing over it is the bug."""

    def test_a_foreign_zle_line_finish_still_runs_after_install(self):
        with TransientSession() as session:
            session.send("print ONE")
            session.send("print TWO")
            session.send("print alien=$alien")
            grid = session.finish()

        row = grid.row_text(row_index(grid, "alien=") + 1)
        self.assertEqual(row, "alien=3", msg=excerpt(grid))

    def test_uninstalling_gives_the_foreign_widget_back_and_stops_collapsing(self):
        with TransientSession() as session:
            session.send("_inzsh_transient_uninstall")
            session.send("print ONE")
            session.send("print alien=$alien")
            grid = session.finish()

        # Still firing: the widget we handed back is the one that was there before us.
        row = grid.row_text(row_index(grid, "alien=") + 1)
        self.assertEqual(row, "alien=3", msg=excerpt(grid))
        # And the full prompt is back in the transcript, which is the other half of
        # "uninstall put everything where it found it".
        self.assertIn(BLOCK, "".join(rows_of(grid)), msg=excerpt(grid))

    def test_ctrl_c_on_an_empty_line_collapses_nothing(self):
        """An interrupt is not a command. Nothing ran, so nothing may be collapsed — and
        the foreign widget must not be told a line finished either."""
        with TransientSession() as session:
            session.send("print ONE")
            session.interrupt()
            session.send("print alien=$alien")
            grid = session.finish()

        row = grid.row_text(row_index(grid, "alien=") + 1)
        self.assertEqual(row, "alien=2", msg=excerpt(grid))
        self.assertIn("ONE", "".join(rows_of(grid)), msg=excerpt(grid))


if __name__ == "__main__":
    unittest.main()
