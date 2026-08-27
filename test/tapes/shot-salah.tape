# InZsh — README screenshot: the prayer-times segment, the subject rather than a detail
# The one-line shape, so the row is the ribbon alone and the prayer block carries it.
# One prompt in the pinned fixture environment, photographed. `tools/tape-run.zsh` wraps it.

Output demo-out/shot-salah.gif

Set Shell bash
Set Width 1000
Set Height 200
Set FontSize 20
Set FontFamily "MesloLGSDZ Nerd Font Mono"
Set Framerate 24
Set Padding 16
Set Theme "Builtin Dark"

Hide
Type "s=${TMPDIR:-/tmp}; s=${s%/}/inzsh-tape; HOME=$s ZDOTDIR=$s HOST=joeinz-pc TAPE_USER=joeinz TZ=Asia/Riyadh INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262 INZSH_PRESET= INZSH_MARKER_ROW=inline exec zsh -d -i"
Enter
Wait+Screen /Maghrib/
Show
# Waits on the prayer block rather than the marker at the end of the row: the marker is
# always there under `inline` (`INZSH_MARKER_ROW=inline`), drawn or not, so it says nothing
# about whether the segments have actually rendered yet — the prayer block appearing does.
Sleep 1.5s
