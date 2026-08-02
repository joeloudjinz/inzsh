# InZsh — the playground. A live prompt you can take apart, in a shell that cannot hurt you.
#
# Sourced by `tools/play.zsh`, which is what `make play` runs. Not part of the theme and not
# bundled: nothing here is loaded by `inzsh.zsh-theme`, and the helpers below exist only inside
# the throwaway shell the launcher builds.
#
# WHY A KNOB JUST WORKS. Every `INZSH_*` value is re-read on every render — that is the rule the
# whole config layer follows — so typing an assignment and pressing return is the entire
# workflow. The helpers here are for the parts that are NOT one assignment: seeing what knobs
# exist, filling the prompt with segments this directory does not happen to have, and looking at
# a width without dragging the window to it.

_inzsh_play_root=${0:A:h:h}
source $_inzsh_play_root/inzsh.zsh-theme

# ---------------------------------------------------------------------------------------------
# Looking at what there is

# `inzsh-knobs [pattern]` — every registered knob, its default, and what it is set to now.
#
# Read out of the registry rather than restated here, so a knob added tomorrow appears without
# this file moving — the same reason `docs/configuration.md` is gated by a test rather than by
# somebody remembering.
inzsh-knobs() {
  emulate -L zsh
  setopt extended_glob

  local pattern=${1:-*}
  local name default live spec

  print -r -- "KNOB                            DEFAULT      NOW"
  for name in ${(ok)_inzsh_config_defaults}; do
    [[ ${(U)name} == *${(U)pattern}* ]] || continue
    default=${_inzsh_config_defaults[$name]}
    live=${(P)name-}
    printf '%-31s %-12s %s\n' $name "${default:-—}" "${live:-—}"
  done

  # Families are patterns, not names, so they have no current value to show — what they have is
  # a shape, and the shape is the useful thing to print.
  print
  print -r -- "FAMILIES (one per segment — put the segment's name in capitals in the middle)"
  for spec in ${_inzsh_config_family_order}; do
    printf '%-31s %-12s %s\n' $spec \
      "${_inzsh_config_family_defaults[$spec]:-—}" \
      "${_inzsh_config_family_validators[$spec]}"
  done
}

# `inzsh-segments` — what the prompt is made of right now, in draw order, with the two numbers
# that decide where each one sits and when it goes.
inzsh-segments() {
  emulate -L zsh

  # Rendered first, so the text column is what the prompt would draw NOW rather than whatever
  # the last one happened to leave behind.
  _inzsh_render

  local seg
  print -r -- "SEGMENT   RANK  PRIORITY  TEXT"
  for seg in ${(ok)_inzsh_segment_defaults}; do
    _inzsh_priority_of $seg
    printf '%-9s %-5s %-9s %s\n' $seg \
      "${_inzsh_segment_defaults[$seg]}" "$REPLY" \
      "${_inzsh_segment_text[$seg]:-—}"
  done
}

# ---------------------------------------------------------------------------------------------
# Filling the prompt

# `inzsh-stub [off]` — give every segment something to say.
#
# A prompt only draws the segments that have anything to report, so in a directory with no repo,
# no virtualenv and no coordinates you are reviewing three blocks out of nine. This fills them
# in, which is the only way to see the surface cycle, the separator run and the drop order for
# what they are. `inzsh-stub off` puts the real ones back.
inzsh-stub() {
  emulate -L zsh

  if [[ ${1-} == (off|-) ]]; then
    local fn
    for fn in ${(k)functions[(I)_inzsh_segment_*_build]}; do
      [[ -n ${functions[${fn}_real]-} ]] || continue
      functions[$fn]=${functions[${fn}_real]}
      unfunction ${fn}_real
    done
    print -r -- "stubs off — segments report the real thing again"
    return 0
  fi

  # Saved before replacing, so `off` is a restore rather than a reload.
  local fn
  for fn in _inzsh_segment_git_build _inzsh_segment_venv_build _inzsh_segment_retval_build \
            _inzsh_segment_salah_build _inzsh_segment_host_build _inzsh_segment_user_build; do
    [[ -n ${functions[$fn]-} ]] || continue
    [[ -n ${functions[${fn}_real]-} ]] || functions[${fn}_real]=${functions[$fn]}
  done

  _inzsh_segment_git_build()    { _inzsh_segment_text[GIT]='main' }
  _inzsh_segment_venv_build()   { _inzsh_segment_text[VENV]='venv' }
  _inzsh_segment_retval_build() { _inzsh_segment_text[RETVAL]="${_inzsh_glyph[ok]} ${_inzsh_glyph[error]} ${_inzsh_glyph[warn]}" }
  _inzsh_segment_salah_build()  { _inzsh_segment_text[SALAH]='Maghrib · 19:59' }
  _inzsh_segment_host_build()   { _inzsh_segment_text[HOST]='host' }
  _inzsh_segment_user_build()   { _inzsh_segment_text[USER]='user' }

  print -r -- "stubs on — every segment has something to say. 'inzsh-stub off' to undo"
}

# ---------------------------------------------------------------------------------------------
# Looking at a width without resizing the window

# `inzsh-at <cols> [more...]` — the prompt as it would be drawn at those widths.
#
# The window is not touched: `COLUMNS` is set, the prompt rebuilt, printed, and the real width
# put back. Handy for walking the drop order in one screen — `inzsh-at 100 80 60 40 24` — where
# dragging the window loses the earlier steps as you go.
inzsh-at() {
  emulate -L zsh

  local -i real=$COLUMNS
  local cols row
  for cols in "$@"; do
    [[ $cols == <-> ]] || { print -ru2 -- "inzsh-at: not a width: $cols"; continue }
    COLUMNS=$cols
    _inzsh_render
    print -r -- "── ${cols} cols ──"
    for row in ${(f)PROMPT}; do
      print -rn -- "${(%%)row}"
      print
    done
    [[ -n $RPROMPT ]] && print -r -- "   right prompt: ${(%%)RPROMPT}"
  done
  COLUMNS=$real
  _inzsh_render
}

# `inzsh-register light|dark` — swap the palette register and redraw.
#
# NOT a knob, and deliberately named as a helper rather than dressed up as one: `_inzsh_register`
# is internal, there is no `INZSH_REGISTER`, and the light register is currently unreachable from
# configuration at all. That is issue #183's other half — worth seeing here precisely because
# reviewing both registers is what the visual sign-off is for.
inzsh-register() {
  emulate -L zsh

  case ${1-} in
    (light|dark)
      typeset -g _inzsh_register=$1
      _inzsh_tokens_resolve
      print -r -- "register: $1"
      ;;
    (*) print -ru2 -- "inzsh-register: light or dark (now: ${_inzsh_register})" ;;
  esac
}

# `inzsh-reset` — every knob back to its default, in this shell only.
inzsh-reset() {
  emulate -L zsh
  unset -m 'INZSH_*'
  print -r -- "reset — every knob back to its default"
}

# ---------------------------------------------------------------------------------------------

inzsh-help() {
  <<'HELP'
InZsh playground — this shell is a throwaway. Nothing here touches your real setup.

  Change anything, then press return. Every knob is re-read on the next prompt.

    INZSH_SURFACE_MODE=hue          alternate · ramp · flat · hue
    INZSH_SEPARATOR_STYLE=round     arrow · round · divider
    INZSH_PROMPT_LINES=1            1 or 2
    INZSH_SALAH_PRIORITY=5          give up the prayer time last
    INZSH_TIME_RANK=-30             move the clock
    INZSH_GIT_MINCOLS=60            hide the branch below 60 columns

  Helpers:

    inzsh-help                      this
    inzsh-knobs [pattern]           every knob, its default, and what it is now
    inzsh-segments                  what the prompt is made of, with rank and priority
    inzsh-stub [off]                give every segment something to say
    inzsh-at 100 80 60 40           the prompt at those widths, without resizing
    inzsh-register light|dark       swap the palette register (internal — see #183)
    inzsh-reset                     every knob back to its default

  To review the drop order: `inzsh-stub`, then `inzsh-at 100 80 60 40 24`.
  To review resizing: `inzsh-stub`, then drag the window narrow and watch.

  exit, or Ctrl-D, and none of this happened.
HELP
}

inzsh-help
