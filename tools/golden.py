#!/usr/bin/env python3
"""The golden pipeline — render the whole prompt deterministically, gate on the text.

`test/golden/` holds output gates: the character grid the real theme draws, one file per
case, committed. This tool is both ends of that pipeline. `--update` (via `make
golden-update`) regenerates the files from fixtures; `--check` (via `make golden-check`,
and the CI `golden` job) regenerates to memory, diffs against the committed set, and
fails with a readable diff when they differ. A visual change therefore blocks a merge
until the goldens are updated — deliberately, through the make target — in the same PR.

The render is the real theme: `inzsh.zsh-theme` sourced in `zsh -f -i -c` under the L3
pty harness (`test/ui/grid_runner.py`), `_inzsh_precmd` run once, the expanded PROMPT
and RPROMPT read back off a pyte screen — the same path `tools/grid.py` walks. What the
gate records is TEXT ONLY, the visible cells. Colour never appears in these files: hex
values exist in the token layer and nowhere else — not tests — so colour expectations
live in `test/ui`, where they are asserted against computed values rather than copied.

Every source of nondeterminism is pinned, each through a seam the theme already owns:

  repository   built by `tools/fixture-repo.zsh` in a temp dir — pinned identity, pinned
               dates, never the real checkout. The async git worker runs for real and is
               drained synchronously with `_inzsh_git_async_wait`, its cache directed
               under the fixture by HOME/XDG_CACHE_HOME.
  clock        the injected-epoch argument of `_inzsh_segment_time_build` (and DATE's),
               forwarded by a thin wrapper — the seam the segment documents, with
               TZ=UTC in the environment so the pinned instant renders one civil time.
  user         the injection seam of `_inzsh_segment_user_build`: 'spec', no default,
               no ssh marker. (Env USERNAME does not survive zsh startup — the shell
               resets it from the uid — so the seam is the only honest pin.)
  host         env HOST=spec-host, which zsh adopts, shown via INZSH_HOST_ALWAYS=1.
  directory    HOME is the fixture root, so the path draws as `~/work` whatever mktemp
               named it — and the generator refuses any render that leaks the real path.
  size, TERM   the harness pins TERM=xterm-256color, strips COLORTERM, pins LC_ALL;
               each case states its columns.
  knobs        the snippet starts from `unset -m "INZSH_*"` and clears SSH_*/VIRTUAL_ENV,
               so nothing flows in from the invoking environment.
"""

from __future__ import annotations

import argparse
import difflib
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "test" / "ui"))

THEME = REPO_ROOT / "inzsh.zsh-theme"
PRESETS = REPO_ROOT / "presets"
FIXTURE_TOOL = REPO_ROOT / "tools" / "fixture-repo.zsh"
GOLDEN_DIR = REPO_ROOT / "test" / "golden"
FIXTURES_DIR = REPO_ROOT / "test" / "fixtures"

# 2001-01-01T12:34:00Z — the fixture repository's own pinned date, moved to midday so the
# clock segment draws something a human recognises as a time.
EPOCH = 978352440

USER = "spec"
HOST = "spec-host"

UPDATE_HINT = "run `make golden-update` and commit the result in the same PR"


class Case(NamedTuple):
    """One golden file: a preset, a shape, a width, a repository state.

    `marker` is what every case is named and driven by — `INZSH_MARKER_ROW`, set directly.
    Through `v1.3.0` this field was `lines: int` (`INZSH_PROMPT_LINES`, `1`/`2`), kept that way
    on purpose while the alias still existed: a case that set `rows` also carried a `lines`
    value, harmlessly overridden by the explicit `INZSH_MARKER_ROW` its own `rows` tuple set.
    `v2.0.0` retired the alias (`.claude/docs/DESIGN-prompt-rows.md` §3.1), so there is nothing
    left for a numeric `lines` field to mean; renaming it to the knob's own vocabulary forces the
    whole golden set to regenerate, which is why the rename and the regeneration are one commit.

    `rows` and `variant` are additive — the `v1.3.0 · Prompt rows` cases below are the only
    ones that set them.
    """

    preset: str | None  # None = base tokens; else a file in presets/
    marker: str  # INZSH_MARKER_ROW — "own" or "inline"
    cols: int
    state: str  # a fixture-repo.zsh state name
    rows: tuple[tuple[str, str], ...] = ()  # extra INZSH_ROW*/INZSH_MARKER_ROW assignments
    variant: str = ""  # replaces the marker name component when `rows` is used

    @property
    def name(self):
        preset = self.preset or "default"
        shape = self.variant or self.marker
        return f"{preset}-{shape}-{self.cols}col-{self.state}"


# The deliberate matrix: a handful, each earning its place. Both presets (token overlays
# may legitimately change glyphs one day, and then the golden pins it), both prompt
# shapes, one narrow width, and one state whose divergence arrows exercise the git text.
#
# The four `rows*` cases are `v1.3.0 · Prompt rows`': two-row and three-row layouts, each in
# both marker modes, over the segments the `dirty` fixture already gives real text — no
# segment here needs a rank set by hand, because naming one in a row array places it and
# shows it regardless of the rank it shipped with (design §2.3).
CASES = (
    Case(None, "own", 80, "dirty"),
    Case(None, "inline", 80, "dirty"),
    Case(None, "own", 60, "dirty"),
    Case(None, "own", 80, "diverged"),
    Case("sharp", "own", 80, "dirty"),
    Case("warm", "own", 80, "dirty"),
    # `ROW2_RIGHT` carries HOST here specifically so the two marker modes are visibly
    # different, not just structurally: under `own` it is a third block padded onto row two
    # exactly like GIT is on row one; under `inline` it is the segment on the LAST drawn row,
    # so it is what actually reaches a real `RPROMPT` rather than a literal pad — the one thing
    # a golden file can show that a render-layer assertion states more precisely but a reader
    # of this file cannot see.
    Case(
        None, "own", 80, "dirty",
        rows=(
            ("INZSH_MARKER_ROW", "own"),
            ("INZSH_ROW1_LEFT", "(TIME DIR)"),
            ("INZSH_ROW1_RIGHT", "(GIT)"),
            ("INZSH_ROW2_LEFT", "(USER)"),
            ("INZSH_ROW2_RIGHT", "(HOST)"),
        ),
        variant="rows2-own",
    ),
    Case(
        None, "inline", 80, "dirty",
        rows=(
            ("INZSH_MARKER_ROW", "inline"),
            ("INZSH_ROW1_LEFT", "(TIME DIR)"),
            ("INZSH_ROW1_RIGHT", "(GIT)"),
            ("INZSH_ROW2_LEFT", "(USER)"),
            ("INZSH_ROW2_RIGHT", "(HOST)"),
        ),
        variant="rows2-inline",
    ),
    Case(
        None, "own", 80, "dirty",
        rows=(
            ("INZSH_MARKER_ROW", "own"),
            ("INZSH_ROW1_LEFT", "(TIME DIR)"),
            ("INZSH_ROW1_RIGHT", "(GIT)"),
            ("INZSH_ROW2_LEFT", "(USER)"),
            ("INZSH_ROW3_LEFT", "(HOST)"),
        ),
        variant="rows3-own",
    ),
    Case(
        None, "inline", 80, "dirty",
        rows=(
            ("INZSH_MARKER_ROW", "inline"),
            ("INZSH_ROW1_LEFT", "(TIME DIR)"),
            ("INZSH_ROW1_RIGHT", "(GIT)"),
            ("INZSH_ROW2_LEFT", "(USER)"),
            ("INZSH_ROW3_LEFT", "(HOST)"),
        ),
        variant="rows3-inline",
    ),
)


# ---------------------------------------------------------------------------------------
# The fast half: pure logic, specified in test/ui/test_golden_tool.py.


def serialize(grid, header):
    """The golden text for one rendered grid: a header, then one line per occupied row."""
    out = [header]
    for row in range(grid.lines):
        text = grid.row_text(row)
        if text:
            out.append(f"row {row} |{text}|")
    return "\n".join(out) + "\n"


def guard_golden_dir(golden_dir, fixtures_dir):
    """Refuse a golden directory that is, or sits inside, the fixtures directory.

    `test/fixtures/` holds inputs and `make golden-update` must never touch it. The rule
    is enforced rather than remembered.
    """
    golden_dir = Path(golden_dir).resolve()
    fixtures_dir = Path(fixtures_dir).resolve()
    if golden_dir == fixtures_dir or fixtures_dir in golden_dir.parents:
        raise ValueError(
            f"golden dir {golden_dir} is inside fixtures dir {fixtures_dir}; "
            "golden-update never writes under test/fixtures"
        )


def write_goldens(rendered, golden_dir):
    """Write `<case>.txt` per rendered case into `golden_dir`; prune stale case files.

    Only `.txt` files are pruned, and only ones shaped like a case this run no longer
    produced — anything else in the directory is somebody's and is left alone.
    """
    golden_dir = Path(golden_dir)
    golden_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for name in sorted(rendered):
        path = golden_dir / f"{name}.txt"
        path.write_text(rendered[name])
        paths.append(path)
    for path in sorted(golden_dir.glob("*.txt")):
        if path.stem not in rendered:
            path.unlink()
    return paths


def check_goldens(rendered, golden_dir):
    """Diff a freshly rendered set against the committed one. Returns (ok, report).

    Three ways to fail, each named: a golden that differs (with a unified diff), a
    golden that is missing, and a stale golden whose case no longer exists — a renamed
    case must not leave a dead gate behind."""
    golden_dir = Path(golden_dir)
    problems = 0
    out = []

    for name in sorted(rendered):
        path = golden_dir / f"{name}.txt"
        if not path.is_file():
            problems += 1
            out.append(f"missing: {path.name} — no committed golden for case '{name}'")
            continue
        expected = path.read_text()
        if expected == rendered[name]:
            continue
        problems += 1
        out.append(f"differs: {path.name}")
        out.extend(
            line.rstrip("\n")
            for line in difflib.unified_diff(
                expected.splitlines(keepends=True),
                rendered[name].splitlines(keepends=True),
                fromfile=f"committed/{path.name}",
                tofile=f"rendered/{path.name}",
            )
        )

    for path in sorted(golden_dir.glob("*.txt")):
        if path.stem not in rendered:
            problems += 1
            out.append(f"stale: {path.name} — no case renders this golden any more")

    ok = problems == 0
    summary = f"golden: {len(rendered)} case(s), " + (
        "all match" if ok else f"{problems} problem(s)"
    )
    if not ok:
        out.append("")
        out.append(f"the prompt no longer matches its committed golden; {UPDATE_HINT}")
    out.append(summary)
    return ok, "\n".join(out) + "\n"


# ---------------------------------------------------------------------------------------
# The slow half: the render itself.


def snippet(case, work):
    """The zsh the harness runs: the whole theme, pinned, one prompt, printed.

    The wrappers around the TIME/DATE and USER builders are not a parallel seam — they
    forward pinned values into the injection arguments those builders document, which
    `_inzsh_render` (calling builders bare) otherwise leaves to the live shell.
    """
    lines = [
        f"cd -- {shlex.quote(str(work))} || exit 9",
        'unset -m "INZSH_*"',
        "unset SSH_CONNECTION SSH_TTY SSH_CLIENT VIRTUAL_ENV",
        f"INZSH_MARKER_ROW={case.marker}",
        "INZSH_HOST_ALWAYS=1",
    ]
    # `case.rows` — the row arrays and (for the row cases) another, identical `INZSH_MARKER_ROW`
    # assignment — are set BEFORE the theme is sourced, same as every other knob above: the
    # registry reads whatever is already in the shell the moment `_inzsh_precmd` first runs, not
    # what was true at `source` time. Setting the same knob twice for those cases is harmless —
    # both lines agree — and keeps `case.marker` meaning the same thing for every case rather
    # than only the ones with no `rows`.
    for knob, value in case.rows:
        lines.append(f"{knob}={value}")
    lines.append(f"source {shlex.quote(str(THEME))}")
    if case.preset:
        preset = PRESETS / f"inzsh-{case.preset}.zsh"
        lines.append(f"source {shlex.quote(str(preset))}")
    lines += [
        "functions[_inzsh_golden_time_build]=$functions[_inzsh_segment_time_build]",
        f"_inzsh_segment_time_build() {{ _inzsh_golden_time_build {EPOCH} }}",
        "functions[_inzsh_golden_date_build]=$functions[_inzsh_segment_date_build]",
        f"_inzsh_segment_date_build() {{ _inzsh_golden_date_build {EPOCH} }}",
        "functions[_inzsh_golden_user_build]=$functions[_inzsh_segment_user_build]",
        f"_inzsh_segment_user_build() {{ _inzsh_golden_user_build {shlex.quote(USER)} '' '' }}",
        # The real async worker, drained synchronously — the door git-async.zsh keeps
        # for specs and demos. The cache lands under the fixture's HOME, nowhere real.
        '_inzsh_git_async_start "$PWD"',
        "_inzsh_git_async_wait 10",
        "_inzsh_precmd",
        'print -rn -- "${(%%)PROMPT}"',
        '[[ -n $RPROMPT ]] && { print; print -rn -- "${(%%)RPROMPT}" }',
        "true",
    ]
    inner = "\n".join(lines)
    return f"exec zsh -f -i -c {shlex.quote(inner)} inzsh-golden"


def build_fixture(state, parent):
    """A fixture repository in `state`, built by the shared generator. Returns the
    checkout path. Never the real tree: the generator works under `parent`, a temp dir."""
    result = subprocess.run(
        ["zsh", str(FIXTURE_TOOL), state, str(parent)],
        capture_output=True,
        text=True,
        check=True,
    )
    work = Path(result.stdout.strip())
    if not work.is_dir():
        raise RuntimeError(f"fixture generator returned no checkout for '{state}'")
    return work


def render_case(case, work, grid_runner):
    """One case rendered to golden text, or a raised error — never a quiet blank."""
    root = work.parent
    header = (
        f"inzsh golden — preset={case.preset or 'default'} marker={case.marker} "
        f"cols={case.cols} state={case.state} epoch={EPOCH} user={USER} host={HOST}"
    )
    grid = grid_runner.render(
        snippet(case, work),
        cols=case.cols,
        lines=24,
        env={
            "HOME": str(root),
            "XDG_CACHE_HOME": str(root / ".cache"),
            "HOST": HOST,
            "TZ": "UTC",
        },
        timeout=20.0,
    )
    if grid.exit_status != 0:
        raise RuntimeError(
            f"case {case.name}: zsh exited {grid.exit_status}\n{grid.raw.decode(errors='replace')}"
        )
    if grid.rows_occupied() == 0:
        raise RuntimeError(f"case {case.name}: rendered an empty grid")
    text = serialize(grid, header)
    if str(root) in text:
        raise RuntimeError(
            f"case {case.name}: the fixture path leaked into the render — "
            "HOME collapsing failed, the golden would not be reproducible"
        )
    return text


def render_all():
    """Every case, each state's fixture built once, all of it in one temp dir."""
    import grid_runner  # deferred: needs the venv, and only this half does

    rendered = {}
    with tempfile.TemporaryDirectory(prefix="inzsh-golden-") as tmp:
        fixtures = {}
        for case in CASES:
            if case.state not in fixtures:
                fixtures[case.state] = build_fixture(case.state, tmp)
            rendered[case.name] = render_case(case, fixtures[case.state], grid_runner)
    return rendered


# ---------------------------------------------------------------------------------------


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument(
        "--update", action="store_true", help="regenerate the committed golden files"
    )
    action.add_argument(
        "--check", action="store_true", help="render fresh and diff against committed"
    )
    parser.add_argument(
        "--golden-dir", type=Path, default=GOLDEN_DIR, help="(tests only) target dir"
    )
    args = parser.parse_args(argv)

    guard_golden_dir(args.golden_dir, FIXTURES_DIR)
    rendered = render_all()

    if args.update:
        paths = write_goldens(rendered, args.golden_dir)
        for path in paths:
            print(f"wrote {path.relative_to(REPO_ROOT) if path.is_relative_to(REPO_ROOT) else path}")
        print(f"golden: {len(rendered)} case(s), updated")
        return 0

    ok, report = check_goldens(rendered, args.golden_dir)
    print(report, end="")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
