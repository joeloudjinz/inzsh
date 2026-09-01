# InZsh — the row axis. A segment's rank says where it sits along a row; `INZSH_ROW<N>_LEFT`
# and `INZSH_ROW<N>_RIGHT` say which row it sits on. Nothing here relocates on its own: a
# block named for a row is drawn on that row, and a block named nowhere derives as it always
# did.
#
# Same pins as every tape: fixture repository as ~/work, clock 978352440 shown as UTC,
# identity joeinz/joeinz-pc. Every pause waits on what the screen must already show; the
# Sleeps are pacing after a Wait has proven the state, never a substitute for one.

Output demo-out/gifs/rows.gif
Output demo-out/rows.txt

# bash as the OUTER shell on purpose: its prompt is plain and synchronous, so the
# hidden pre-exec frames cannot race. The recorded shell is still zsh — the exec below.
Set Shell bash
Set Width 1000
Set Height 400
Set FontSize 20
Set FontFamily "MesloLGSDZ Nerd Font Mono"
Set Framerate 24
Set Padding 16
Set Theme "Builtin Dark"
Set TypingSpeed 130ms

Hide
Type "s=${TMPDIR:-/tmp}; s=${s%/}/inzsh-tape; HOME=$s ZDOTDIR=$s HOST=joeinz-pc TAPE_USER=joeinz TZ=UTC INZSH_PRESET= exec zsh -d -i"
Enter
Wait+Screen /12:34/
Show

Wait+Screen /→/
Sleep 700ms

Type "echo 'one row, as it ships'"
Enter
Wait+Screen /as it ships/
Sleep 1.6s

Type "INZSH_ROW2_LEFT=(USER HOST); echo 'who you are, on a row of its own'"
Enter
Wait+Screen /on a row of its own/
Sleep 1.8s

Type "INZSH_ROW2_RIGHT=(TIME); echo 'and the clock at the end of it'"
Enter
Wait+Screen /at the end of it/
Sleep 1.8s

Type "INZSH_ROW4_LEFT=(GIT); echo 'row numbers are sort keys, not slots'"
Enter
Wait+Screen /sort keys/
Sleep 1.8s

Type "INZSH_MARKER_ROW=inline; echo 'the marker can end the last row instead'"
Enter
Wait+Screen /end the last row/
Sleep 1.8s

Type "unset INZSH_ROW2_LEFT INZSH_ROW2_RIGHT INZSH_ROW4_LEFT INZSH_MARKER_ROW; echo 'and back, unchanged'"
Enter
Wait+Screen /and back, unchanged/
Sleep 1.6s
