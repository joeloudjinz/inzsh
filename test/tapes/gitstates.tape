# InZsh — tape 8: the git states in the diverged fixture — every render the segment has, as a tour
# of seven real fixture repositories — counts both ways, each glyph, detached HEAD.
# fixture: all
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
Type "s=${TMPDIR:-/tmp}; s=${s%/}/inzsh-tape; HOME=$s ZDOTDIR=$s HOST=joeinz-pc TAPE_USER=joeinz TZ=UTC INZSH_PRESET= exec zsh -d -i"
Enter
Wait+Screen /12:34/
Show

# The prompt is up when the input marker is. Pacing pauses below come AFTER a Wait has
# proven the state — the ban is on sleeping INSTEAD of waiting, never on breathing room.
Wait+Screen /→/
Sleep 600ms

Type "cd ~/s-dirty"
Enter
Wait+Screen /! main/
Sleep 1.3s

Type "cd ~/s-staged"
Enter
Wait+Screen /i main/
Sleep 1.3s

Type "cd ~/s-ahead"
Enter
Wait+Screen /↑2/
Sleep 1.3s

Type "cd ~/s-behind"
Enter
Wait+Screen /↓3/
Sleep 1.3s

Type "cd ~/s-diverged"
Enter
Wait+Screen /↑2↓3/
Sleep 1.3s

Type "cd ~/s-detached"
Enter
Wait+Screen /— [0-9a-f]/
Sleep 1.3s

Type "cd ~/s-clean"
Enter
Wait+Screen /→/
Sleep 1s
