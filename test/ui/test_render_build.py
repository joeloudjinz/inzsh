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


def build(
    side,
    texts=TEXTS,
    mode="alternate",
    preset="sharp",
    depth="truecolor",
    cols=COLS,
    hues=(),
):
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
    declarations = "\n".join(
        f"_inzsh_segment_bg_role[S{index}]={shlex.quote(role)}"
        for index, role in enumerate(hues, start=1)
    )
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
            declarations,
            f"_inzsh_{'right' if side == 'right' else 'left'}=({order})",
            f"_inzsh_render_build {shlex.quote(side)} {order}",
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

    def test_left_prompt_hue(self):
        self.assert_chaining("left", "hue")

    def test_right_prompt_hue(self):
        self.assert_chaining("right", "hue")

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


class HueTest(unittest.TestCase):
    """`hue` — the mode in which a segment names its own fill.

    Everything here is read off the grid rather than off the string, because the claim the mode
    makes is about what a cell ends up holding: that four blocks carry four different colours,
    that the colour follows the SEGMENT rather than its position, and that a run of segments all
    asking for the same fill still comes out with visible boundaries. No colour is named; the
    cells are only ever compared to each other, so a palette change cannot fail this file.
    """

    # Four fills the design system pairs with an on-colour, so each block's ink arrives with its
    # background rather than being declared beside it. `neutral` is included deliberately: it is
    # the muted one, and a mode that only worked for saturated fills would pass without it.
    HUES = ("negative", "neutral", "info", "accent")

    def backgrounds(self, grid, texts=TEXTS):
        columns = text_columns(grid.row_text(0), texts)
        return [grid.cell(0, col).bg for col in columns]

    def test_each_segment_draws_the_fill_it_declared(self):
        """Four declarations, four distinct cells, on whichever side draws them."""
        for side in ("left", "right"):
            grid = build(side, mode="hue", hues=self.HUES)
            self.assertEqual(grid.exit_status, 0, msg=excerpt(grid))
            backgrounds = self.backgrounds(grid)
            self.assertNotIn(DEFAULT_COLOR, backgrounds, msg=excerpt(grid, focus=0))
            self.assertEqual(
                len(set(backgrounds)),
                len(self.HUES),
                msg=f"{side}: declared fills collapsed onto each other\n"
                + excerpt(grid, focus=0),
            )

    def test_the_colour_follows_the_segment_and_not_the_position(self):
        """The whole point of declaring one: reorder the run and each block keeps its colour.

        A positional mode fails this by construction — its second block is the second surface
        whatever is in it. Here the declarations move with the segments, so the set of colours is
        the same and the block that was first is now last still wearing its own.
        """
        forward = build("left", mode="hue", hues=self.HUES)
        first = self.backgrounds(forward)
        reversed_texts = tuple(reversed(TEXTS))
        backward = build(
            "left", texts=reversed_texts, mode="hue", hues=tuple(reversed(self.HUES))
        )
        second = self.backgrounds(backward, texts=reversed_texts)
        self.assertEqual(list(reversed(first)), second, msg=excerpt(backward, focus=0))

    def test_a_segment_that_declared_nothing_keeps_its_position(self):
        """The positional assignment stays underneath, so a partly-declared row still fills."""
        grid = build("left", mode="hue", hues=("accent", "", "", "negative"))
        backgrounds = self.backgrounds(grid)
        self.assertNotIn(DEFAULT_COLOR, backgrounds, msg=excerpt(grid, focus=0))
        for index in range(len(TEXTS) - 1):
            self.assertNotEqual(
                backgrounds[index],
                backgrounds[index + 1],
                msg=excerpt(grid, focus=0),
            )

    def test_every_segment_asking_for_one_colour_still_draws_boundaries(self):
        """The hostile configuration, on a real grid.

        Four segments all naming `accent` is the sequence a positional mode could never produce
        and the one the collision rule exists for. What must survive is not the colour — the
        renderer takes the ask back — but the boundary: no two abutting blocks the same.
        """
        grid = build("left", mode="hue", hues=("accent",) * len(TEXTS))
        backgrounds = self.backgrounds(grid)
        self.assertNotIn(DEFAULT_COLOR, backgrounds, msg=excerpt(grid, focus=0))
        for index in range(len(TEXTS) - 1):
            self.assertNotEqual(
                backgrounds[index],
                backgrounds[index + 1],
                msg=f"blocks {index} and {index + 1} share a background under a map that "
                f"asked for one colour throughout\n" + excerpt(grid, focus=0),
            )

    def test_the_ink_arrives_with_the_fill(self):
        """A declared fill brings the DS's paired on-colour; a positional one does not.

        Read as a relationship rather than as a value: the same segment, same text, drawn once
        with a fill it declared and once without, must not end up with the same foreground —
        otherwise `on-negative` is landing on a surface, which is the failure this pairing was
        built to prevent.
        """
        declared = build("left", mode="hue", hues=("negative", "info", "accent", "neutral"))
        positional = build("left", mode="alternate")
        columns_a = text_columns(declared.row_text(0), TEXTS)
        columns_b = text_columns(positional.row_text(0), TEXTS)
        for index, (col_a, col_b) in enumerate(zip(columns_a, columns_b)):
            self.assertNotEqual(
                declared.cell(0, col_a).fg,
                positional.cell(0, col_b).fg,
                msg=f"block {index} kept its positional ink over a declared fill\n"
                + excerpt(declared, focus=0),
            )

    def test_the_declarations_are_read_in_no_other_mode(self):
        """A positional mode owns every background, which is what makes its invariant free.

        The map is filled identically in all four modes; only `hue` may act on it, so the three
        positional modes must draw exactly what they draw with no map at all.
        """
        for mode in ("alternate", "ramp", "flat"):
            with_map = build("left", mode=mode, hues=self.HUES)
            without = build("left", mode=mode)
            self.assertEqual(
                self.backgrounds(with_map),
                self.backgrounds(without),
                msg=f"{mode} acted on a declared background\n"
                + excerpt(with_map, focus=0),
            )


class WidthSweepTest(unittest.TestCase):
    """The invariant at the widths a terminal actually gets dragged to.

    `assert_ribbon` proves it at one width in two modes. This proves it across every filled mode
    and a spread of widths, because the assembly measures as it draws and a mode that only holds
    at 100 columns holds by luck.
    """

    WIDTHS = (40, 60, 80, 100, 160)
    FILLED = ("alternate", "ramp", "hue")

    def test_no_two_abutting_blocks_share_a_background_at_any_width(self):
        for preset in ("sharp", "warm"):
            for mode in self.FILLED:
                for cols in self.WIDTHS:
                    hues = HueTest.HUES if mode == "hue" else ()
                    grid = build(
                        "left", mode=mode, preset=preset, cols=cols, hues=hues
                    )
                    self.assertEqual(grid.exit_status, 0, msg=excerpt(grid))
                    row = grid.row_text(0)
                    # A width that cannot hold the run is not what this asserts; the assembly
                    # does not shorten on its own, so every text is there at every width tried.
                    columns = text_columns(row, TEXTS)
                    backgrounds = [grid.cell(0, col).bg for col in columns]
                    self.assertNotIn(
                        DEFAULT_COLOR,
                        backgrounds,
                        msg=f"{preset}/{mode}/{cols}\n" + excerpt(grid, focus=0),
                    )
                    for index in range(len(TEXTS) - 1):
                        self.assertNotEqual(
                            backgrounds[index],
                            backgrounds[index + 1],
                            msg=f"{preset}/{mode} at {cols} columns: blocks "
                            f"{index} and {index + 1} share a background\n"
                            + excerpt(grid, focus=0),
                        )


if __name__ == "__main__":
    unittest.main()
