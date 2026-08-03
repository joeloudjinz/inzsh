"""The golden gate's own logic — compare, update, and the fixture guard.

`tools/golden.py` has two halves. The slow half renders the real theme through the L3
harness inside a git fixture; it is exercised by `make golden-check` and by CI, and its
output gates are the committed files in `test/golden/`. The fast half — serialising a
grid, writing a golden set, diffing a rendered set against a committed one — is plain
logic, and plain logic gets a spec. Everything here is hermetic: no zsh, no pty, no
fixture repository, no file outside a `TemporaryDirectory`.

The one rule with teeth: `make golden-update` must never touch `test/fixtures/`.
`write_goldens` only ever writes `<case>.txt` inside the directory it is given, and
`guard_golden_dir` refuses a golden directory that is, or sits inside, the fixtures
directory — both facts are asserted here rather than trusted.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import golden  # noqa: E402  — the path insert above is the point


class FakeGrid:
    """The two attributes `serialize` reads, and nothing else."""

    def __init__(self, rows):
        self._rows = rows
        self.lines = len(rows)

    def row_text(self, row):
        return self._rows[row]


class SerializeTest(unittest.TestCase):
    def test_header_then_one_line_per_occupied_row(self):
        grid = FakeGrid(["spec  ~/work", "→"])
        text = golden.serialize(grid, "case one")
        self.assertEqual(text, "case one\nrow 0 |spec  ~/work|\nrow 1 |→|\n")

    def test_blank_rows_are_skipped_but_numbering_is_kept(self):
        grid = FakeGrid(["top", "", "", "bottom"])
        text = golden.serialize(grid, "h")
        self.assertEqual(text, "h\nrow 0 |top|\nrow 3 |bottom|\n")

    def test_ends_with_exactly_one_newline(self):
        text = golden.serialize(FakeGrid(["x"]), "h")
        self.assertTrue(text.endswith("|x|\n"))
        self.assertFalse(text.endswith("\n\n"))


class WriteGoldensTest(unittest.TestCase):
    def test_writes_one_txt_per_case_and_nothing_else(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "golden"
            golden.write_goldens({"b": "B\n", "a": "A\n"}, target)
            self.assertEqual(
                sorted(p.name for p in target.iterdir()), ["a.txt", "b.txt"]
            )
            self.assertEqual((target / "a.txt").read_text(), "A\n")
            # Nothing appeared beside the golden directory.
            self.assertEqual([p.name for p in root.iterdir()], ["golden"])

    def test_prunes_a_stale_golden_for_a_case_that_no_longer_exists(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            (target / "gone.txt").write_text("old\n")
            (target / "notes.md").write_text("kept\n")
            golden.write_goldens({"kept": "K\n"}, target)
            names = sorted(p.name for p in target.iterdir())
            self.assertEqual(names, ["kept.txt", "notes.md"])


class CheckGoldensTest(unittest.TestCase):
    def test_a_matching_set_passes_with_a_countable_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            golden.write_goldens({"a": "A\n", "b": "B\n"}, target)
            ok, report = golden.check_goldens({"a": "A\n", "b": "B\n"}, target)
            self.assertTrue(ok)
            self.assertIn("golden: 2 case(s)", report)
            self.assertNotIn(golden.UPDATE_HINT, report)

    def test_a_difference_fails_with_a_readable_diff_and_the_update_hint(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            golden.write_goldens({"a": "h\nrow 0 |old glyph|\n"}, target)
            ok, report = golden.check_goldens({"a": "h\nrow 0 |new glyph|\n"}, target)
            self.assertFalse(ok)
            self.assertIn("-row 0 |old glyph|", report)
            self.assertIn("+row 0 |new glyph|", report)
            self.assertIn("a.txt", report)
            self.assertIn(golden.UPDATE_HINT, report)

    def test_a_missing_golden_fails_and_names_the_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            ok, report = golden.check_goldens({"a": "A\n"}, Path(tmp))
            self.assertFalse(ok)
            self.assertIn("missing", report)
            self.assertIn("a.txt", report)
            self.assertIn(golden.UPDATE_HINT, report)

    def test_a_stale_golden_fails_so_a_renamed_case_cannot_leave_a_dead_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            golden.write_goldens({"a": "A\n", "old": "O\n"}, target)
            ok, report = golden.check_goldens({"a": "A\n"}, target)
            self.assertFalse(ok)
            self.assertIn("stale", report)
            self.assertIn("old.txt", report)


class GuardTest(unittest.TestCase):
    def test_refuses_the_fixtures_directory_itself(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixtures = Path(tmp) / "fixtures"
            fixtures.mkdir()
            with self.assertRaises(ValueError):
                golden.guard_golden_dir(fixtures, fixtures)

    def test_refuses_a_directory_inside_fixtures(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixtures = Path(tmp) / "fixtures"
            (fixtures / "golden").mkdir(parents=True)
            with self.assertRaises(ValueError):
                golden.guard_golden_dir(fixtures / "golden", fixtures)

    def test_accepts_a_sibling_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixtures = Path(tmp) / "fixtures"
            target = Path(tmp) / "golden"
            fixtures.mkdir()
            target.mkdir()
            golden.guard_golden_dir(target, fixtures)  # must not raise


if __name__ == "__main__":
    unittest.main()
