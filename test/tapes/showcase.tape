# InZsh — the showcase. One shareable recording: both registers, the transient collapse,
# the path and git panels, a failure state, the hue surfaces, and the prayer segment —
# greeted and signed off from the Sahara. Emojis are sparse and mirror the words.
#
# Same pins as every tape: fixture repository, clock 978352440 shown in Mecca's zone,
# identity spec/spec-host. The one Sleep-as-sync below is documented where it happens.

Output demo-out/gifs/showcase.gif
Output demo-out/showcase.txt

# bash as the OUTER shell on purpose: its prompt is plain and synchronous, so the
# hidden pre-exec frames cannot race. The recorded shell is still zsh — the exec below.
Set Shell bash
Set Width 1000
Set Height 480
Set FontSize 20
Set FontFamily "MesloLGSDZ Nerd Font Mono"
Set Framerate 24
Set Padding 16
Set Theme "Builtin Dark"
Set TypingSpeed 130ms

Hide
Type "s=${TMPDIR:-/tmp}; s=${s%/}/inzsh-tape; HOME=$s ZDOTDIR=$s HOST=joeinz-pc TAPE_USER=joeinz TZ=Asia/Riyadh INZSH_PRESET= exec zsh -d -i"
Enter
Wait+Screen /15:34/
Show

Wait+Screen /→/
Sleep 800ms

Type "echo 'salam alikoum — ahla w sahla'"
Enter
Wait+Screen /ahla w sahla/
Sleep 1.4s

Type "mkdir -p tassili/ahaggar && cd tassili/ahaggar"
Enter
Wait+Screen /ahaggar/
Sleep 1.4s

Type "cd ~/work && git status -sb"
Enter
Wait+Screen /origin\/main/
Sleep 1.4s

Type "false"
Enter
Wait+Screen /✕/
Sleep 1.4s

Type "INZSH_SURFACE_MODE=hue; echo 'colours of the oasis 🌴'"
Enter
Wait+Screen /oasis/
Sleep 1.6s

Type "INZSH_SEPARATOR_STYLE=round; echo 'curves of the dunes'"
Enter
Wait+Screen /curves of/
Sleep 1.6s

Type "INZSH_SURFACE_MODE=flat; echo 'flat as the erg'"
Enter
Wait+Screen /erg/
Sleep 1.6s

# The register flip. The new shell clears to a prompt that is textually identical to the
# one before it, so there is nothing to wait on — this Sleep is the one synchronisation
# by clock in the tapes, with a margin ten times the restart it covers.
Type "INZSH_PRESET=warm exec zsh -d -i"
Enter
Sleep 2.5s

Type "INZSH_SEPARATOR_STYLE=round; echo 'the same curves, sunlit'"
Enter
Wait+Screen /sunlit/
Sleep 1.6s

Type "INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262; echo 'prayer times — computed offline 🕌'"
Enter
Wait+Screen /Maghrib/
Sleep 1.8s

Type "echo 'bslama — from the Sahara, with salam'"
Enter
Wait+Screen /bslama —/
Sleep 2s
