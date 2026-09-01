# InZsh — README screenshot: the row axis, as a still. The path and the branch keep the
# first row; who you are and the clock take the second. One prompt in the pinned fixture
# environment, photographed. `tools/tape-run.zsh` wraps it.
#
# The row arrays are set INSIDE the recording rather than on the `exec` line, because they
# are arrays and `tools/tape-env.zsh` carries only a keep-list of scalar `INZSH_` names
# across that restart. `clear` then gives a screen holding nothing but the prompt.

Output demo-out/shot-rows.gif

Set Shell bash
Set Width 1000
Set Height 200
Set FontSize 20
Set FontFamily "MesloLGSDZ Nerd Font Mono"
Set Framerate 24
Set Padding 16
Set Theme "Builtin Dark"

Hide
Type "s=${TMPDIR:-/tmp}; s=${s%/}/inzsh-tape; HOME=$s ZDOTDIR=$s HOST=joeinz-pc TAPE_USER=joeinz TZ=UTC INZSH_PRESET= exec zsh -d -i"
Enter
Wait+Screen /12:34/
Type "INZSH_ROW2_LEFT=(USER HOST); INZSH_ROW2_RIGHT=(TIME); clear"
Enter
# Waits on the clock, which under this shape draws on the SECOND row — so seeing it is
# proof both rows have been resolved and drawn, not just the first.
Wait+Screen /12:34/
Show
Sleep 1.5s
