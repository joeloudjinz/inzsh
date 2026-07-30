"""The assembled prompt, read off a real terminal grid.

`test/render/render_build_spec.sh` can prove the STRING is right. It cannot prove that
the string becomes a legible ribbon of blocks, because that is a property of cells: a
separator is visible only if the cell it lives in differs from the cell beside it, and
only a grid knows what a cell ended up holding. So the two claims the assembly exists
to make are asserted here, on the rendered screen:

* adjacent segments do not share a background, on either side of the prompt;
* the chaining is oriented — the left prompt's separators carry the colour of the block
  BEFORE them and the right prompt's the colour of the block AFTER them.

The mirror is the reason this file exists at all. A left-oriented right prompt still
passes a naive "the backgrounds differ" check and still looks like a ribbon in a
screenshot; on the grid the ink lands in the wrong cell and the assertion fails.

Nothing here hardcodes a colour. Backgrounds are compared to each other, never to a
value, and the segment texts are the only literals — chosen so that no two are a
substring of another. A palette change must not be able to fail this file.
"""

from __future__ import annotations

import shlex
import unittest
from pathlib import Path

import grid_runner
from grid_runner import DEFAULT_COLOR
from grid_asserts import assert_row_occupancy, excerpt, extract_runs

REPO_ROOT = Path(__file__).resolve().parents[2]
CORE = REPO_ROOT / "lib" / "core"

SEP_LEFT = ""
SEP_RIGHT = ""
COLS = 100
TEXTS = ("alpha", "bravo", "charlie", "delta")


def build(side, texts=TEXTS, mode="alternate", preset="sharp", depth="truecolor", cols=COLS):
    """Render one assembled side on its own row and hand back the `Grid`.

    Hermetic on purpose: `unset -m 'INZSH_*'` first, so an `INZSH_SURFACE_MODE` or an
    `INZSH_DIR_BG` in the developer's zshrc cannot change what this file asserts. The
    library is sourced in the entry point's dependency order plus the two files the
    assembly calls at draw time; the theme file itself is not sourced, because it no-ops
    in a non-interactive shell and this is one.

    `print -r -- "${(%%)REPLY}"` is the only drawing: the builder returns a string and
    something has to expand it. Nothing assigns PROMPT — the dispatch in
    `lib/core/hooks.zsh` fires on a function named `_inzsh_render`, and neither this
    harness nor the library defines one.
    """
    assignments = "\n".join(
        f"_inzsh_segment_text[S{index}]={shlex.quote(text)}"
        for index, text in enumerate(texts, start=1)
    )
    order = " ".join(f"S{index}" for index in range(1, len(texts) + 1))
    snippet = "\n".join(
        [
            "unset -m 'INZSH_*'",
            f"INZSH_COLOR_DEPTH={shlex.quote(depth)}",
            f"INZSH_SURFACE_MODE={shlex.quote(mode)}",
            f"source {shlex.quote(str(CORE / 'detect.zsh'))}",
            f"source {shlex.quote(str(CORE / 'tokens-256.zsh'))}",
            f"source {shlex.quote(str(CORE / 'tokens.zsh'))}",
            f"source {shlex.quote(str(CORE / 'layout.zsh'))}",
            f"source {shlex.quote(str(CORE / 'engine.zsh'))}",
            f"source {shlex.quote(str(CORE / 'render.zsh'))}",
            f"source {shlex.quote(str(REPO_ROOT / 'presets' / f'inzsh-{preset}.zsh'))}",
            assignments,
            f"_inzsh_{'right' if side == 'right' else 'left'}=({order})",
            f"_inzsh_render_build {shlex.quote(side)}",
            'print -r -- "${(%%)REPLY}"',
            'print -r -- "width=$_inzsh_render_width"',
        ]
    )
    return grid_runner.render(snippet, cols=cols)


def text_columns(row, texts):
    """Where each text starts in the rendered row, searched left to right."""
    columns = []
    cursor = 0
    for text in texts:
        found = row.find(text, cursor)
        if found < 0:
            raise AssertionError(f"{text!r} is not in the rendered row {row!r}")
        columns.append(found)
        cursor = found + len(text)
    return columns


class RibbonTest(unittest.TestCase):
    """Both sides, on the grid, in the two modes that draw filled blocks."""

    def assert_ribbon(self, side, mode):
        grid = build(side, mode=mode)
        self.assertEqual(grid.exit_status, 0, msg=excerpt(grid))

        # The prompt is one row and the reported width is on the next; anything more
        # means the assembly outgrew the width every later assertion assumes.
        assert_row_occupancy(grid, 2)

        row = grid.row_text(0)
        columns = text_columns(row, TEXTS)
        backgrounds = [grid.cell(0, col).bg for col in columns]

        # (a) every block is actually filled, and filled with something the terminal
        # distinguishes from its own background.
        self.assertNotIn(DEFAULT_COLOR, backgrounds, msg=excerpt(grid, focus=0))

        # (b) the invariant, observed rather than argued: no segment shares a background
        # with the segment beside it, so every boundary is one you can see.
        for index in range(len(TEXTS) - 1):
            self.assertNotEqual(
                backgrounds[index],
                backgrounds[index + 1],
                msg=f"{TEXTS[index]!r} and {TEXTS[index + 1]!r} share a background "
                f"({side}, {mode})\n" + excerpt(grid, focus=0),
            )

        # (c) the width the builder tracked is the width the terminal ended up holding.
        # Two independent measurements of the same row, one arithmetic and one observed.
        reported = grid.row_text(1)
        self.assertTrue(reported.startswith("width="), msg=excerpt(grid))
        tracked = int(reported.split("=", 1)[1])
        drawn = sum(1 for run in extract_runs(grid, 0) for _ in run.text)
        self.assertEqual(tracked, drawn, msg=excerpt(grid, focus=0))

        return grid, row, backgrounds

    def assert_chaining(self, side, mode):
        """The orientation, cell by cell.

        Left: the separator after block i is inked with bg[i] and filled with bg[i+1],
        the last one over the terminal's own background. Right: mirrored — the separator
        before block i is inked with bg[i] and filled with bg[i-1], the FIRST one over
        the terminal's own. A side drawn with the other side's orientation fails here
        even though it passes every assertion in `assert_ribbon`.
        """
        grid, row, backgrounds = self.assert_ribbon(side, mode)
        glyph = SEP_RIGHT if side == "right" else SEP_LEFT
        separators = [col for col, char in enumerate(row) if char == glyph]
        self.assertEqual(len(separators), len(TEXTS), msg=excerpt(grid, focus=0))

        # The other side's glyph must not appear at all: the wedge points one way per side.
        self.assertNotIn(
            SEP_LEFT if side == "right" else SEP_RIGHT, row, msg=excerpt(grid, focus=0)
        )

        for index, col in enumerate(separators):
            cell = grid.cell(0, col)
            if side == "right":
                ink = backgrounds[index]
                behind = backgrounds[index - 1] if index else DEFAULT_COLOR
            else:
                ink = backgrounds[index]
                behind = (
                    backgrounds[index + 1]
                    if index + 1 < len(backgrounds)
                    else DEFAULT_COLOR
                )
            self.assertEqual(
                cell.fg,
                ink,
                msg=f"separator {index} on the {side} prompt carries the wrong ink\n"
                + excerpt(grid, focus=0),
            )
            self.assertEqual(
                cell.bg,
                behind,
                msg=f"separator {index} on the {side} prompt sits on the wrong fill\n"
                + excerpt(grid, focus=0),
            )

    def test_left_prompt_alternate(self):
        self.assert_chaining("left", "alternate")

    def test_left_prompt_ramp(self):
        self.assert_chaining("left", "ramp")

    def test_right_prompt_alternate(self):
        self.assert_chaining("right", "alternate")

    def test_right_prompt_ramp(self):
        self.assert_chaining("right", "ramp")

    def test_flat_mode_draws_one_surface_and_still_caps_the_ribbon(self):
        """`flat` is the exemption: equal neighbours are the design, not a defect."""
        grid = build("left", mode="flat")
        row = grid.row_text(0)
        columns = text_columns(row, TEXTS)
        backgrounds = {grid.cell(0, col).bg for col in columns}
        self.assertEqual(len(backgrounds), 1, msg=excerpt(grid, focus=0))
        self.assertNotIn(DEFAULT_COLOR, backgrounds, msg=excerpt(grid, focus=0))
        # The cap is still drawn over the terminal's own background, so the ribbon ends
        # rather than running to the edge of the row.
        last = max(col for col, char in enumerate(row) if char == SEP_LEFT)
        self.assertEqual(grid.cell(0, last).bg, DEFAULT_COLOR, msg=excerpt(grid, focus=0))

    def test_a_segment_with_no_text_leaves_no_separator_behind(self):
        """The classic artefact, checked on the grid: three ranked, two drawn."""
        grid = build("left", texts=("alpha", "", "charlie"))
        row = grid.row_text(0)
        self.assertEqual(row.count(SEP_LEFT), 2, msg=excerpt(grid, focus=0))
        self.assertNotIn("bravo", row, msg=excerpt(grid, focus=0))
        columns = text_columns(row, ("alpha", "charlie"))
        first, second = (grid.cell(0, col).bg for col in columns)
        self.assertNotEqual(first, second, msg=excerpt(grid, focus=0))

    def test_an_empty_side_writes_nothing_to_the_terminal(self):
        """No blocks, no separators, no escapes — the row the prompt did not draw on.

        The row is blank because the harness printed an empty string, and blank means
        blank: an "empty" prompt that still emitted `%f%k` would leave the cell carrying
        a reset rather than never having been written to, and would still read as
        `default` here — so the raw bytes are checked as well.
        """
        grid = build("left", texts=())
        self.assertEqual(grid.row_text(0), "", msg=excerpt(grid))
        self.assertEqual(grid.row_text(1), "width=0", msg=excerpt(grid))
        self.assertEqual(grid.cell(0, 0).bg, DEFAULT_COLOR, msg=excerpt(grid, focus=0))
        self.assertEqual(grid.cell(0, 0).fg, DEFAULT_COLOR, msg=excerpt(grid, focus=0))
        self.assertNotIn(b"\x1b[", grid.raw.split(b"width=")[0], msg=repr(grid.raw))

    def test_degrading_the_depth_changes_the_colours_and_nothing_else(self):
        """Same glyphs, same width, same structure — a different lookup, not a path."""
        rows = {
            depth: build("left", depth=depth).row_text(0)
            for depth in ("truecolor", "256", "8")
        }
        self.assertEqual(len(set(rows.values())), 1, msg=str(rows))

    def test_both_registers_draw_a_legible_ribbon(self):
        """The warm preset is the other register, and the invariant is not register-bound."""
        for preset in ("sharp", "warm"):
            grid = build("left", preset=preset)
            columns = text_columns(grid.row_text(0), TEXTS)
            backgrounds = [grid.cell(0, col).bg for col in columns]
            self.assertNotIn(DEFAULT_COLOR, backgrounds, msg=excerpt(grid, focus=0))
            for index in range(len(TEXTS) - 1):
                self.assertNotEqual(
                    backgrounds[index],
                    backgrounds[index + 1],
                    msg=f"{preset}: adjacent blocks share a background\n"
                    + excerpt(grid, focus=0),
                )


if __name__ == "__main__":
    unittest.main()
