"""L3 harness — run a zsh snippet inside a pty and read back the terminal grid.

This is a library, not a test: it imports no test framework. `render()` spawns
`zsh -f` on a pty of the requested size, feeds every byte the child writes through
a `pyte` screen, and hands back a `Grid` that answers per-cell questions.

Colour normalisation
--------------------
pyte reports a cell's colour as a string in one of three vocabularies. We keep the
distinction but make the values predictable:

* truecolor (`ESC[38;2;R;G;B m`) -> lowercase 6-digit hex, no leading '#'
  ('AB12CD' -> 'ab12cd'). Compare against hex you computed, never a palette copy.
* 256-index (`ESC[38;5;N m`) -> `int(N)`. Note that pyte 0.8.2 resolves indices
  through its own xterm table before we ever see them, so in practice they arrive
  as 6-digit hex and normalise as truecolor. The int branch exists for pyte builds
  that pass the index through; a caller that wants index-independence should assert
  on presence, not value.
* named (`ESC[31m`) -> the name pyte used, lowercased ('red', 'brightblue').
* absent / unset -> the string 'default' for both channels.

A 6-hex-digit string is always read as a colour value, never as a decimal index —
'123456' is hex. That is the only ambiguity in the mapping and truecolor wins it,
because pyte only emits bare decimals for indices it declined to resolve.

Environment
-----------
TERM defaults to 'xterm-256color'. COLORTERM is passed only when the caller asks
for it (and is stripped from the inherited environment otherwise) so a truecolor
terminal on the dev machine cannot quietly change a render. LC_ALL is pinned to
C.UTF-8 always: `${(m)#...}` counts bytes rather than cells outside a UTF-8 locale,
which is the same trap the CI workflow pins against.
"""

from __future__ import annotations

import errno
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import termios
import time
from typing import NamedTuple

import pyte

DEFAULT_TERM = "xterm-256color"
LOCALE = "C.UTF-8"
DEFAULT_COLOR = "default"

_READ_CHUNK = 65536
_POLL_INTERVAL = 0.05


class RenderTimeout(TimeoutError):
    """The child outlived its timeout and was killed.

    Carries whatever had been rendered when the clock ran out, so the failing test
    reports a grid instead of just a stopwatch.
    """

    def __init__(self, message, partial=None):
        super().__init__(message)
        self.partial = partial


class Cell(NamedTuple):
    """One character cell: what is drawn and in what colours."""

    char: str
    fg: object
    bg: object


class Grid:
    """A rendered screen. Read-only view over a `pyte.Screen`."""

    def __init__(self, screen, *, exit_status=None, raw=b""):
        self._screen = screen
        self.lines = screen.lines
        self.cols = screen.columns
        self.exit_status = exit_status
        self.raw = raw

    def cell(self, row, col):
        """The cell at (row, col), colours normalised. Out of range is an error."""
        if not 0 <= row < self.lines:
            raise IndexError(f"row {row} outside 0..{self.lines - 1}")
        if not 0 <= col < self.cols:
            raise IndexError(f"col {col} outside 0..{self.cols - 1}")
        char = self._screen.buffer[row][col]
        return Cell(char.data, normalize_color(char.fg), normalize_color(char.bg))

    def row_text(self, row):
        """Visible text of a row with trailing blanks stripped."""
        if not 0 <= row < self.lines:
            raise IndexError(f"row {row} outside 0..{self.lines - 1}")
        return self._screen.display[row].rstrip()

    def rows_occupied(self):
        """How many rows carry at least one non-blank cell."""
        return sum(1 for row in range(self.lines) if self.row_text(row))

    def __repr__(self):
        return (
            f"<Grid {self.cols}x{self.lines} "
            f"occupied={self.rows_occupied()} exit={self.exit_status}>"
        )


def normalize_color(value):
    """Map one pyte colour token into our vocabulary (see the module docstring)."""
    if value is None:
        return DEFAULT_COLOR
    text = str(value).strip().lower().lstrip("#")
    if not text:
        return DEFAULT_COLOR
    if len(text) == 6 and all(char in "0123456789abcdef" for char in text):
        return text
    if text.isdigit():
        return int(text)
    return text


def render(zsh_snippet, *, cols=80, lines=24, env=None, timeout=5.0):
    """Run `zsh_snippet` under `zsh -f` on a cols x lines pty; return a `Grid`.

    Every byte the child writes — stdout and stderr, both wired to the pty — is fed
    to the screen, so a syntax error shows up as text on the grid rather than as a
    silent blank. The call returns once the child has exited and the pty is drained.

    A child that overruns `timeout` is killed with SIGKILL (its whole session, so a
    forked grandchild cannot outlive it) and `RenderTimeout` is raised carrying the
    partial grid. One hung render must fail its own test, never wedge the suite.
    """
    child_env = build_env(env)
    master_fd, slave_fd = pty.openpty()
    _set_winsize(slave_fd, lines, cols)

    try:
        proc = subprocess.Popen(
            ["zsh", "-f", "-c", zsh_snippet],
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            env=child_env,
            close_fds=True,
            start_new_session=True,
        )
    except BaseException:
        os.close(master_fd)
        os.close(slave_fd)
        raise

    os.close(slave_fd)
    deadline = time.monotonic() + timeout
    try:
        output, timed_out = _drain(master_fd, deadline)
        if not timed_out:
            timed_out = not _reap(proc, deadline)
    finally:
        os.close(master_fd)
        if proc.poll() is None:
            _kill(proc)
            proc.wait()

    grid = Grid(
        _screen_from(output, cols, lines),
        exit_status=proc.returncode,
        raw=output,
    )
    if timed_out:
        raise RenderTimeout(
            f"zsh child exceeded {timeout}s and was killed; "
            f"{len(output)} byte(s) rendered before the kill",
            partial=grid,
        )
    return grid


def build_env(env=None):
    """The child's environment: inherited, then pinned. Exposed for debugging."""
    child_env = dict(os.environ)
    child_env.pop("COLORTERM", None)
    child_env["TERM"] = DEFAULT_TERM
    if env:
        child_env.update(env)
    child_env["LC_ALL"] = LOCALE
    return child_env


def _screen_from(output, cols, lines):
    screen = pyte.Screen(cols, lines)
    stream = pyte.ByteStream(screen)
    stream.feed(output)
    return screen


def _set_winsize(fd, lines, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", lines, cols, 0, 0))


def _drain(master_fd, deadline):
    """Read until the child closes the pty. Returns (bytes, timed_out)."""
    chunks = []
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return b"".join(chunks), True
        readable, _, _ = select.select([master_fd], [], [], min(remaining, _POLL_INTERVAL))
        if not readable:
            continue
        try:
            data = os.read(master_fd, _READ_CHUNK)
        except OSError as exc:
            # The last slave fd went away: EOF on Linux, EIO on macOS/BSD.
            if exc.errno == errno.EIO:
                return b"".join(chunks), False
            raise
        if not data:
            return b"".join(chunks), False
        chunks.append(data)


def _reap(proc, deadline):
    """Wait for exit within the deadline. Returns True if the child exited."""
    remaining = max(deadline - time.monotonic(), 0.0)
    try:
        proc.wait(timeout=remaining)
    except subprocess.TimeoutExpired:
        return False
    return True


def _kill(proc):
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            proc.kill()
        except ProcessLookupError:
            pass
