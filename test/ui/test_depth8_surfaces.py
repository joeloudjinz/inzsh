"""Eight colours, read off a real terminal grid.

`test/unit/tokens256_spec.sh` can prove that a foreground token and a background token
resolve to different ANSI indices. It cannot prove that the prompt the engine assembles
from them has no cell drawing its ink in its own fill, because that is a property of the
finished ribbon: which surface a block lands on is the renderer's decision, the mode's
and the position's, and the roles it picks are all distinct — the collision only exists
in colour space, after the eight-colour table has resolved them. The role-space guard in
`lib/core/render.zsh` passes either way.

So the claim is made where it can be observed. Every mode, both presets, depth 8: no cell
draws a character in its own background colour. A separator whose ink is its fill is a
boundary that is not there; a block whose text is its fill is a segment that is not there.
One assertion covers both, because on the grid they are the same defect.

`flat` is the exemption, and only for the separator: one surface throughout is the design,
so the boundary between two flat blocks is meant to be absent. Its TEXT still has to be
legible, and that half is asserted.

Nothing here hardcodes a colour. The roles are named — roles are not hex — and every
assertion compares a cell to itself.
"""

from __future__ import annotations

import shlex
import unittest
from pathlib import Path

import grid_runner
from grid_asserts import excerpt

REPO_ROOT = Path(__file__).resolve().parents[2]
CORE = REPO_ROOT / "lib" / "core"

# The two separator glyphs, written as escapes rather than as bytes: the rule against a `\u`
# literal is a rule about what a zsh PARSER does to a file in a single-byte locale, and
# nothing here is parsed by zsh.
SEP_LEFT = ""
SEP_RIGHT = ""
SEPARATORS = (SEP_LEFT, SEP_RIGHT)
COLS = 160
PRESETS = ("sharp", "warm")

# Every role a segment registers as its foreground, plus the two the engine paints with
# outside the segment maps. Each one can land on any surface the renderer hands out, so
# each one is put on each one below.
INKS = (
    "text-body",
    "text-muted",
    "text-strong",
    "positive-text",
    "info-text",
    "negative-text",
    "caution-text",
    "neutral-text",
    "negative",
    "accent",
)

# The backgrounds the shipped segments declare, in the order they are drawn — the left
# prompt, then the right, then the three that ship switched off. `hue` is the only mode
# that reads them, and adjacency there is a property of the sequence, so the sequences
# asserted are the ones the theme actually produces. An empty entry declares nothing and
# takes the positional surface, which is what an undeclared segment does.
HUE_SEQUENCES = (
    ("negative", "neutral", "surface-deep", "info", "surface-deep", "info-wash", "negative"),
    ("accent", "surface-deep"),
    ("caution", "", "info-wash", "", "neutral-wash", ""),
)


def build(*, preset, mode, fgs, side="left", importances=(), hues=(), cols=COLS):
    """Render one assembled side at depth 8 and hand back the `Grid`.

    Hermetic, like `test_render_build.py`: `unset -m 'INZSH_*'` first so nothing in the
    developer's environment can change what is asserted, the library sourced in the entry
    point's dependency order, and the preset sourced by file the way a zshrc would.
    """
    count = len(fgs)
    names = [f"S{index}" for index in range(1, count + 1)]
    lines = [
        "unset -m 'INZSH_*'",
        "INZSH_COLOR_DEPTH=8",
        f"INZSH_SURFACE_MODE={shlex.quote(mode)}",
        *(
            f"source {shlex.quote(str(CORE / (name + '.zsh')))}"
            for name in ("detect", "tokens-256", "tokens", "layout", "engine", "render")
        ),
        f"source {shlex.quote(str(REPO_ROOT / 'presets' / f'inzsh-{preset}.zsh'))}",
    ]
    for index, name in enumerate(names):
        lines.append(f"_inzsh_segment_text[{name}]={shlex.quote(name.lower())}")
        lines.append(f"_inzsh_segment_fg_role[{name}]={shlex.quote(fgs[index])}")
        if index < len(importances):
            lines.append(f"_inzsh_segment_importance[{name}]={importances[index]}")
        if index < len(hues) and hues[index]:
            lines.append(f"_inzsh_segment_bg_role[{name}]={shlex.quote(hues[index])}")
    lines += [
        f"_inzsh_{'right' if side == 'right' else 'left'}=({' '.join(names)})",
        f"_inzsh_render_build {shlex.quote(side)} {' '.join(names)}",
        'print -r -- "${(%%)REPLY}"',
    ]
    return grid_runner.render("\n".join(lines), cols=cols)


def invisible_cells(grid, *, separators=True):
    """Every drawn cell whose foreground is its own background.

    Blanks are skipped — a padding column carries a fill and no ink, and there is nothing
    for it to hide. `separators=False` skips the wedge glyphs as well, which is the `flat`
    exemption and nothing else.
    """
    found = []
    for row in range(grid.lines):
        if not grid.row_text(row):
            continue
        for col in range(grid.cols):
            cell = grid.cell(row, col)
            if not cell.char.strip():
                continue
            if not separators and cell.char in SEPARATORS:
                continue
            if cell.fg == cell.bg:
                found.append((row, col, cell.char, cell.fg))
    return found


class DepthEightTest(unittest.TestCase):
    """No cell draws its ink in its own fill, at eight colours."""

    def assert_all_visible(self, grid, label, *, separators=True):
        self.assertEqual(grid.exit_status, 0, msg=excerpt(grid))
        hidden = invisible_cells(grid, separators=separators)
        self.assertEqual(
            hidden,
            [],
            msg=f"{label}: {len(hidden)} cell(s) drawn in their own background — "
            f"{hidden}\n" + excerpt(grid, focus=0),
        )

    def test_alternate_draws_nothing_in_its_own_background(self):
        """The default mode, with every ink over both surfaces it swings between."""
        for preset in PRESETS:
            for shift in range(2):
                fgs = INKS[shift:] + INKS[:shift]
                with self.subTest(preset=preset, shift=shift):
                    grid = build(preset=preset, mode="alternate", fgs=fgs)
                    self.assert_all_visible(grid, f"alternate/{preset}/{shift}")

    def test_ramp_draws_nothing_in_its_own_background(self):
        """Importance drives the surface, so all three of the cycle are in play."""
        for preset in PRESETS:
            for shift in range(3):
                fgs = INKS[shift:] + INKS[:shift]
                importances = [(index + shift) % 3 + 1 for index in range(len(fgs))]
                with self.subTest(preset=preset, shift=shift):
                    grid = build(
                        preset=preset, mode="ramp", fgs=fgs, importances=importances
                    )
                    self.assert_all_visible(grid, f"ramp/{preset}/{shift}")

    def test_hue_draws_nothing_in_its_own_background(self):
        """The declared fills, in the sequences the shipped segments produce."""
        for preset in PRESETS:
            for index, hues in enumerate(HUE_SEQUENCES):
                side = "right" if index == 1 else "left"
                fgs = [INKS[position % len(INKS)] for position in range(len(hues))]
                with self.subTest(preset=preset, sequence=index):
                    grid = build(
                        preset=preset, mode="hue", fgs=fgs, side=side, hues=hues
                    )
                    self.assert_all_visible(grid, f"hue/{preset}/{index}")

    def test_flat_keeps_its_text_legible(self):
        """One surface throughout: the boundary is meant to be absent, the text is not."""
        for preset in PRESETS:
            with self.subTest(preset=preset):
                grid = build(preset=preset, mode="flat", fgs=INKS)
                self.assert_all_visible(
                    grid, f"flat/{preset}", separators=False
                )


if __name__ == "__main__":
    unittest.main()
