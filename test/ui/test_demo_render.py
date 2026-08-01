"""The M1 demonstration prompt, read off a real terminal grid.

`test/render/` can prove the prompt STRING is right. It cannot prove that the string
becomes a legible ribbon of blocks, because that is a property of cells: a separator
is visible only if the cell it lives in differs from the cell beside it, and only a
grid knows what a cell ended up holding. So the invariant the surface layer exists to
guarantee — no two adjacent segments share a background — is asserted here, on the
rendered screen, in every colour depth the theme claims to support.

Nothing below hardcodes a colour. Backgrounds are compared to each other, never to a
value; the segment labels come from the renderer itself (`--labels`); and the only
literal is the separator glyph, which the test finds in the row rather than assumes
the position of. A palette change must not be able to fail this file.

The depth sweep is the point of the exercise. `INZSH_COLOR_DEPTH` is the only thing
that moves between the three cases, and each one additionally checks the wire: a
256-colour render that quietly emits 24-bit escapes has not degraded, it has just
stopped being tested.
"""

from __future__ import annotations

import shlex
import subprocess
import unittest
from pathlib import Path

import grid_runner
from grid_runner import DEFAULT_COLOR
from grid_asserts import assert_row_occupancy, excerpt, extract_runs

REPO_ROOT = Path(__file__).resolve().parents[2]
DEMO = REPO_ROOT / "tools" / "render.zsh"

SEPARATOR = "\ue0b0"
TRUECOLOR_SGR = b"38;2;"
COLS = 100
DEPTHS = ("truecolor", "256", "8")


def demo_labels():
    """The segment labels, straight from the renderer — never a copy of them."""
    result = subprocess.run(
        ["zsh", "-f", str(DEMO), "--labels"],
        capture_output=True,
        text=True,
        check=True,
    )
    return [line for line in result.stdout.splitlines() if line]


def render_demo(depth="truecolor", mode="alternate", preset="sharp", cols=COLS):
    """One demo render, hermetic.

    The child inherits the developer's environment, so every knob the theme reads is
    wiped and then set explicitly: an `INZSH_SURFACE_MODE` or an `INZSH_DIR_BG` left
    in somebody's zshrc must not be able to change what this file asserts. The
    settings go in the snippet rather than the environment because the renderer is
    sourced into that shell and reads them as parameters either way.
    """
    snippet = "\n".join(
        [
            "unset -m 'INZSH_*'",
            f"INZSH_COLOR_DEPTH={shlex.quote(depth)}",
            f"INZSH_SURFACE_MODE={shlex.quote(mode)}",
            f"INZSH_PRESET={shlex.quote(preset)}",
            f"source {shlex.quote(str(DEMO))} --prompt-only",
        ]
    )
    return grid_runner.render(snippet, cols=cols)


def label_columns(text, labels):
    """Where each label starts in the rendered row, searched left to right."""
    columns = []
    cursor = 0
    for label in labels:
        found = text.find(label, cursor)
        if found < 0:
            raise AssertionError(f"label {label!r} is not in the rendered row {text!r}")
        columns.append(found)
        cursor = found + len(label)
    return columns


class DemoRenderTest(unittest.TestCase):
    """One row, alternating surfaces, at every depth.

    WHAT DEGRADING COSTS, and what it may not. The two surfaces `alternate` swings between are
    both raised ends of one narrow family, and at eight colours that family has ONE index per
    register: every dark surface is 0 and every light one is 7. So below 256 the alternation
    collapses and the ribbon draws as one filled run — the engine's assignment is still valid,
    because the invariant is over ROLES and the roles still differ, and the terminal simply
    cannot express the difference.

    That is a boundary lost, and it is the right half to lose. The other half is `assert_legible`
    below: every block's ink must differ from its own fill at every depth, because a boundary you
    cannot see costs you where one block ends and a text colour you cannot see costs you the
    block. Eight colours can keep exactly one of the two.
    """

    #: Depths at which the palette can still tell the two alternating surfaces apart.
    ALTERNATING = ("truecolor", "256")

    @classmethod
    def setUpClass(cls):
        cls.labels = demo_labels()

    def assert_legible(self, grid, depth):
        """Every run of TEXT on the row is drawn in something other than its own background.

        Asserted over the RUNS rather than over the labels, so the state glyphs — three
        foregrounds inside one block — are covered as well as the plain ones.

        Separator cells are excluded, and that exclusion is the whole point of the split: a
        separator whose ink IS its fill is a boundary the palette could not draw, which is what
        the class note calls the right half to lose. A LABEL whose ink is its fill is a block
        nobody can read, which is not.
        """
        for run in extract_runs(grid, 0):
            body = run.text.replace(SEPARATOR, "").strip()
            if not body:
                continue
            self.assertNotEqual(
                run.fg,
                run.bg,
                msg=f"{run.text!r} is drawn in its own background at depth {depth}\n"
                + excerpt(grid, focus=0),
            )

    def assert_ribbon(self, depth):
        """Every structural claim the demo makes, checked on one rendered grid."""
        grid = render_demo(depth=depth)
        self.assertEqual(grid.exit_status, 0, msg=excerpt(grid))

        # (a) one prompt, one row. Wrapping at 100 columns would mean the demo outgrew
        # the width every later assertion assumes.
        assert_row_occupancy(grid, 1)

        text = grid.row_text(0)
        columns = label_columns(text, self.labels)
        backgrounds = [grid.cell(0, col).bg for col in columns]

        # (b) the surfaces are actually distinguishable on screen. Two alternating
        # surfaces, the reserved accent fill and the terminal's own background behind
        # the closing separator — four different backgrounds in one row. At eight colours
        # the two alternating surfaces are one index, so the accent and the terminal's own
        # are all that is left to tell apart, and that is the claim made instead.
        distinct = {run.bg for run in extract_runs(grid, 0)}
        wanted = 4 if depth in self.ALTERNATING else 3
        self.assertGreaterEqual(
            len(distinct), wanted, msg=f"{sorted(map(str, distinct))}\n{excerpt(grid, focus=0)}"
        )
        self.assertGreaterEqual(
            len({bg for bg in distinct if bg != DEFAULT_COLOR}), wanted - 1
        )

        # (c) every block IS filled, at every depth: whatever the palette can express, no
        # segment falls through to the terminal's own background.
        self.assertNotIn(DEFAULT_COLOR, backgrounds, msg=excerpt(grid, focus=0))

        # (d) the ink is never the fill — the half of legibility eight colours keeps.
        self.assert_legible(grid, depth)

        # (e) the invariant, observed rather than argued: no segment shares a background
        # with the segment beside it, so every boundary is a boundary you can see. Only
        # asked where the palette can draw the difference; see the note on the class.
        if depth in self.ALTERNATING:
            for i, (left, right) in enumerate(zip(self.labels, self.labels[1:])):
                self.assertNotEqual(
                    backgrounds[i],
                    backgrounds[i + 1],
                    msg=f"{left!r} and {right!r} share a background at depth {depth}\n"
                    + excerpt(grid, focus=0),
                )

        # …and the chaining that makes it read as one ribbon: each separator is drawn in
        # the previous segment's background over the next one's, and the last one over
        # the terminal's.
        separators = [col for col, char in enumerate(text) if char == SEPARATOR]
        self.assertEqual(len(separators), len(self.labels), msg=excerpt(grid, focus=0))
        if depth not in self.ALTERNATING:
            # A separator between two blocks the palette collapsed is drawn in its own fill,
            # which is exactly what "the boundary is lost" means; only the accent's boundary
            # and the closing cap carry a colour change, and those are (b)'s business.
            return grid
        for index, col in enumerate(separators):
            cell = grid.cell(0, col)
            following = (
                backgrounds[index + 1] if index + 1 < len(backgrounds) else DEFAULT_COLOR
            )
            self.assertEqual(cell.fg, backgrounds[index], msg=excerpt(grid, focus=0))
            self.assertEqual(cell.bg, following, msg=excerpt(grid, focus=0))

        return grid

    def test_truecolor_render_is_one_legible_ribbon(self):
        grid = self.assert_ribbon("truecolor")
        self.assertIn(TRUECOLOR_SGR, grid.raw)

    def test_256_render_is_the_same_ribbon_without_24_bit_escapes(self):
        grid = self.assert_ribbon("256")
        self.assertNotIn(TRUECOLOR_SGR, grid.raw)

    def test_8_render_is_the_same_ribbon_without_24_bit_escapes(self):
        grid = self.assert_ribbon("8")
        self.assertNotIn(TRUECOLOR_SGR, grid.raw)

    def test_8_colours_lose_the_boundary_and_keep_the_block(self):
        """The degradation, stated both ways round so it cannot rot into an accident.

        Eight colours have one background per register, so the two alternating surfaces really
        do collapse — asserting that they differ would be asserting something the palette cannot
        do. What may not collapse is the ink: every block is still drawn in a colour that is not
        its own fill, which is the half that carries the words.
        """
        grid = render_demo(depth="8")
        columns = label_columns(grid.row_text(0), self.labels)
        backgrounds = [grid.cell(0, col).bg for col in columns]
        # The surfaces: one value across every positional block, the accent apart from them.
        positional = set(backgrounds[:-1])
        self.assertEqual(len(positional), 1, msg=excerpt(grid, focus=0))
        self.assertNotIn(backgrounds[-1], positional, msg=excerpt(grid, focus=0))
        self.assert_legible(grid, "8")

    def test_every_depth_draws_the_same_text(self):
        """Degrading changes the colours and nothing else — same glyphs, same width."""
        rendered = {depth: render_demo(depth=depth).row_text(0) for depth in DEPTHS}
        self.assertEqual(len(set(rendered.values())), 1, msg=str(rendered))


if __name__ == "__main__":
    unittest.main()
