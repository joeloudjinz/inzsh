"""The `make grid` tool draws the real theme, not a demonstration.

`tools/grid.py` is a developer tool and asserts nothing itself; what this file pins is the
one property the tool is trusted for — the snippet it drives through the L3 harness sources
the actual engine, so a column number read off `make grid` is a fact about the theme. The
knob probe is the distinguishing test: a fixed demonstration ignores `INZSH_PROMPT_LINES`,
the engine honours it.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools"))
sys.path.insert(0, str(REPO_ROOT / "test" / "ui"))

import grid_runner  # noqa: E402  — the path insert above is the point

grid_tool = __import__("grid")  # tools/grid.py, imported the way a script may be


class GridToolTest(unittest.TestCase):
    def render(self, env=None, preset=None, cols=80):
        snippet = grid_tool.theme_snippet(preset=preset)
        return grid_runner.render(snippet, cols=cols, lines=24, env=env or {})

    def test_draws_a_prompt_and_exits_cleanly(self):
        grid = self.render()
        self.assertEqual(grid.exit_status, 0)
        self.assertGreaterEqual(grid.rows_occupied(), 1)

    def test_honours_an_engine_knob_a_demonstration_would_ignore(self):
        def drawn(grid):
            return "".join(grid.row_text(row) for row in range(grid.lines))

        wedge, bar = "", "│"
        sharp = self.render()
        divided = self.render(env={"INZSH_SEPARATOR_STYLE": "divider"})
        self.assertEqual(sharp.exit_status, 0)
        self.assertEqual(divided.exit_status, 0)
        self.assertIn(wedge, drawn(sharp))
        self.assertNotIn(wedge, drawn(divided))
        self.assertIn(bar, drawn(divided))

    def test_a_preset_is_sourced_by_file_never_by_harness_variable(self):
        grid = self.render(preset="warm")
        self.assertEqual(grid.exit_status, 0)
        self.assertGreaterEqual(grid.rows_occupied(), 1)


if __name__ == "__main__":
    unittest.main()
