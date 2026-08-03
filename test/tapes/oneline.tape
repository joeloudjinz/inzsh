# InZsh — tape 6: the one-line prompt, and back.
#
# Every setting is pinned — width, height, font, size, framerate, padding, theme — and every
# pause waits on what the screen must already show, never on a clock. Sleep is banned here:
# a sleep is a race with the machine's speed, a Wait is a statement about the recording.
# The environment (fixture repo, clock, identity) is pinned by tools/tape-env.zsh, which
# tools/tape-run.zsh wraps around this file.

Output demo-out/gifs/oneline.gif
Output demo-out/oneline.txt

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

Type "INZSH_PROMPT_LINES=1; echo lines-$((1))"
Enter
Wait+Screen /lines-1/
Sleep 1.4s

Type "INZSH_PROMPT_LINES=2; echo lines-$((2))"
Enter
Wait+Screen /lines-2/
Sleep 1.4s

Type "true"
Enter
Wait+Screen /→/
Sleep 1s
