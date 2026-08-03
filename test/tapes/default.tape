# InZsh — tape 1: the default look. Dark register, alternate surfaces, two-line prompt,
# inside the dirty fixture repository at the pinned instant.
#
# Every setting is pinned — width, height, font, size, framerate, padding, theme — and every
# pause waits on what the screen must already show, never on a clock. Sleep is banned here:
# a sleep is a race with the machine's speed, a Wait is a statement about the recording.
# The environment (fixture repo, clock, identity) is pinned by tools/tape-env.zsh, which
# tools/tape-run.zsh wraps around this file.

Output demo-out/default.gif
Output demo-out/default.txt

Set Shell zsh
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
Type "s=${${TMPDIR:-/tmp}%/}/inzsh-tape; HOME=$s ZDOTDIR=$s HOST=spec-host TZ=UTC exec zsh -d -i"
Enter
Wait+Screen /12:34/
Show

# The prompt is up when the input marker is. Pacing pauses below come AFTER a Wait has
# proven the state — the ban is on sleeping INSTEAD of waiting, never on breathing room.
Wait+Screen /→/
Sleep 600ms

Type "echo 'salam from DZ'"
Enter
Wait+Screen /salam from DZ/
Sleep 900ms

Type "git status -sb"
Enter
Wait+Screen /origin\/main/
Sleep 900ms

# A command that fails: the exit-status segment turns and carries its glyph.
Type "false"
Enter
Wait+Screen /✕/
Sleep 900ms

Type "true"
Enter
Wait+Screen /→/
Sleep 1s
