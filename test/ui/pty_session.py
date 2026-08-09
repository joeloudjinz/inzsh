"""L3 harness — drive an INTERACTIVE zsh on a pty and read back the terminal grid.

`grid_runner.render` runs `zsh -f -c snippet`: one script, no line editor, no prompt.
That is the right tool for "what does this string look like on a screen", and the wrong
one for everything on this page. A transient prompt is a change made by a ZLE widget
between the keystroke and the command, and a widget only exists inside a line editor,
which only exists on a terminal. So this module types into a real one.

The session writes each line to the pty exactly as a person would, waits for the child
to exit, and feeds every byte it wrote — prompts, echoed input, output and all — through
a `pyte` screen. What comes back is the SCROLLBACK: the transcript as it would be left
on the user's screen, which is the only place the claim "the prompt collapses" can be
checked at all.

The environment is pinned the same way `grid_runner` pins it, and for the same reasons:
`TERM=xterm-256color`, `COLORTERM` stripped, `LC_ALL=C.UTF-8`. `PROMPT` and friends are
cleared on the way in so that a developer's exported prompt cannot appear in a grid this
suite is about to make assertions on.

The pty is made the child's CONTROLLING TERMINAL, and that is not decoration. SIGWINCH is
sent by the kernel to the foreground process group of a terminal, so a shell that merely
has a pty on its file descriptors is never told the window changed: `session.resize()`
would move the size and the shell would go on drawing for the old one, which is exactly
the bug under test passing itself off as a fix. `setsid` plus `TIOCSCTTY` in the child is
what makes the resize arrive the way it arrives on a real terminal.
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

import pyte

from grid_runner import DEFAULT_TERM, LOCALE, Grid

_READ_CHUNK = 65536
_SETTLE = 0.12


def _claim_terminal():
    """In the child, between fork and exec: take the pty as the controlling terminal.

    `start_new_session` has already made this process a session leader, and stdin is
    already the pty slave, so all that is left is the ioctl that binds the two. Without it
    the kernel has no foreground process group to deliver SIGWINCH to.
    """
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)


class Session:
    """One interactive `zsh -f -i` on a pty of the requested size."""

    def __init__(self, *, cols=80, lines=24, env=None, timeout=10.0):
        self.cols = cols
        self.lines = lines
        self.timeout = timeout
        self._output = b""

        child_env = dict(os.environ)
        child_env.pop("COLORTERM", None)
        for name in ("PROMPT", "PS1", "RPROMPT", "RPS1", "PROMPT_COMMAND"):
            child_env.pop(name, None)
        child_env["TERM"] = DEFAULT_TERM
        if env:
            child_env.update(env)
        child_env["LC_ALL"] = LOCALE

        # Every window size the session has run at, as (byte offset into `_output`, cols,
        # lines). `grid()` replays the transcript against it rather than against the final
        # size, because bytes written at 100 columns did not wrap where bytes written at 60
        # do — a screen built at one width out of output produced at two is a screen nobody
        # ever saw.
        self._sizes = [(0, cols, lines)]

        self._master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", lines, cols, 0, 0))
        try:
            self._proc = subprocess.Popen(
                ["zsh", "-f", "-i"],
                stdin=slave,
                stdout=slave,
                stderr=slave,
                env=child_env,
                close_fds=True,
                start_new_session=True,
                preexec_fn=_claim_terminal,
            )
        except BaseException:
            os.close(self._master)
            os.close(slave)
            raise
        os.close(slave)
        self._deadline = time.monotonic() + timeout
        self._settle()

    # -- typing -------------------------------------------------------------------
    def send(self, line):
        """Type one line and press return."""
        self.send_raw(line + "\r")

    def send_raw(self, text):
        """Type bytes exactly — for a control character, or a line with no return."""
        os.write(self._master, text.encode())
        self._settle()

    def interrupt(self):
        """Ctrl-C, as the key rather than as a signal: the line editor has to see it."""
        self.send_raw("\x03")

    # -- the window ---------------------------------------------------------------
    def resize(self, cols, lines=None):
        """Change the window size, the way dragging a window's edge does.

        The ioctl on the master is the whole of it: the kernel updates the size for both
        ends of the pty and sends SIGWINCH to the terminal's foreground process group,
        which is the shell, because `_claim_terminal` made this pty its controlling
        terminal. Nothing here signals the child by hand — a test that did would be
        proving that `kill -WINCH` works rather than that a resize does.
        """
        lines = self.lines if lines is None else lines
        fcntl.ioctl(
            self._master, termios.TIOCSWINSZ, struct.pack("HHHH", lines, cols, 0, 0)
        )
        self.cols = cols
        self.lines = lines
        self._sizes.append((len(self._output), cols, lines))
        self._settle()

    # -- reading ------------------------------------------------------------------
    def finish(self):
        """Exit the shell, drain the pty and return the `Grid` of what it wrote."""
        os.write(self._master, "exit\r".encode())
        self._drain_until_eof()
        if self._proc.poll() is None:
            self._kill()
        self._proc.wait()
        os.close(self._master)
        return self.grid()

    def grid(self):
        """The screen as the user would have been left looking at it.

        Replayed size by size. With no resize this is one `feed` of everything, byte for
        byte what it always was; with resizes it is the same transcript fed in the widths
        it was actually written at, with `Screen.resize` between the pieces exactly where
        the ioctl went.
        """
        _, first_cols, first_lines = self._sizes[0]
        screen = pyte.Screen(first_cols, first_lines)
        stream = pyte.ByteStream(screen)

        for index, (offset, cols, lines) in enumerate(self._sizes):
            if index:
                screen.resize(lines, cols)
            end = (
                self._sizes[index + 1][0]
                if index + 1 < len(self._sizes)
                else len(self._output)
            )
            stream.feed(self._output[offset:end])

        return Grid(screen, exit_status=self._proc.returncode, raw=self._output)

    def rows(self):
        """Every non-blank row of the transcript, in order."""
        grid = self.grid()
        return [grid.row_text(row) for row in range(grid.lines) if grid.row_text(row)]

    # -- plumbing -----------------------------------------------------------------
    def _settle(self):
        """Read whatever the child has to say, then wait for it to go quiet."""
        quiet_until = time.monotonic() + _SETTLE
        while time.monotonic() < quiet_until:
            if time.monotonic() > self._deadline:
                raise TimeoutError("interactive session outlived its timeout")
            if self._read_once(0.02):
                quiet_until = time.monotonic() + _SETTLE

    def _drain_until_eof(self):
        while True:
            if time.monotonic() > self._deadline:
                self._kill()
                return
            if self._proc.poll() is not None and not self._read_once(0.05):
                return
            if not self._read_once(0.05) and self._proc.poll() is not None:
                return

    def _read_once(self, wait):
        readable, _, _ = select.select([self._master], [], [], wait)
        if not readable:
            return False
        try:
            data = os.read(self._master, _READ_CHUNK)
        except OSError as exc:
            # The last slave fd went away: EOF on Linux, EIO on macOS/BSD.
            if exc.errno == errno.EIO:
                return False
            raise
        if not data:
            return False
        self._output += data
        return True

    def _kill(self):
        try:
            os.killpg(os.getpgid(self._proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            try:
                self._proc.kill()
            except ProcessLookupError:
                pass
