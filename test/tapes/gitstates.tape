# InZsh — tape 8: the git states in the diverged fixture — the ahead/behind counts stay
# on screen while the state glyph walks clean, dirty, staged, committed.
# fixture: diverged
#
# Every setting is pinned — width, height, font, size, framerate, padding, theme — and every
# pause waits on what the screen must already show, never on a clock. Sleep is banned here:
# a sleep is a race with the machine's speed, a Wait is a statement about the recording.
# The environment (fixture repo, clock, identity) is pinned by tools/tape-env.zsh, which
# tools/tape-run.zsh wraps around this file.

Output demo-out/gifs/gitstates.gif
Output demo-out/gitstates.txt

# bash as the OUTER shell on purpose: its prompt is plain and synchronous, so the
# hidden pre-exec frames cannot race. The recorded shell is still zsh — the exec below.
Set Shell bash
Set Width 1000
Set Height 340
Set FontSize 20
Set FontFamily "MesloLGSDZ Nerd Font Mono"
Set Framerate 24
Set Padding 16
Set Theme "Builtin Dark"
Set TypingSpeed 130ms

# Enter the pinned environment: the stage tools/tape-run.zsh builds at a fixed path.
# Hidden — the recording opens on the theme's prompt, not on the machine's own shell.
Hide
Type "s=${TMPDIR:-/tmp}; s=${s%/}/inzsh-tape; HOME=$s ZDOTDIR=$s HOST=spec-host TZ=UTC INZSH_PRESET= exec zsh -d -i"
Enter
Wait+Screen /12:34/
Show

# The prompt is up when the input marker is. Pacing pauses below come AFTER a Wait has
# proven the state — the ban is on sleeping INSTEAD of waiting, never on breathing room.
Wait+Screen /→/
Sleep 600ms

Type "echo tweak >> base.txt; echo st-$((1))"
Enter
Wait+Screen /! main/
Sleep 1.4s

Type "git add -A; echo st-$((2))"
Enter
Wait+Screen /i main/
Sleep 1.4s

Type "git commit -q -m polish; echo st-$((3))"
Enter
Wait+Screen /↑3/
Sleep 1.4s

Type "true"
Enter
Wait+Screen /→/
Sleep 1s
