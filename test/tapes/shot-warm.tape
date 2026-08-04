# InZsh — README screenshot: the warm preset, light, full colour
# One prompt in the pinned fixture environment, photographed. `tools/tape-run.zsh` wraps it.

Output demo-out/shot-warm.gif

Set Shell bash
Set Width 1000
Set Height 200
Set FontSize 20
Set FontFamily "MesloLGSDZ Nerd Font Mono"
Set Framerate 24
Set Padding 16
Set Theme "Builtin Light"

Hide
Type "s=${TMPDIR:-/tmp}; s=${s%/}/inzsh-tape; HOME=$s ZDOTDIR=$s HOST=joeinz-pc TAPE_USER=joeinz TZ=Asia/Riyadh INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262 INZSH_PRESET=warm exec zsh -d -i"
Enter
Wait+Screen /Maghrib/
Show
Wait+Screen /→/
Sleep 1.5s
