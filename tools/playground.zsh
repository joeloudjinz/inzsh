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
# A validator, in words. The registry's specs are a grammar for the code that enforces them —
# `int:0:`, `enum:arrow|round|divider` — and reading one is not the job of somebody deciding what
# to type. Same information, said out loud.
_inzsh_play_accepts() {
  emulate -L zsh
  setopt extended_glob

  local spec=$1
  case $spec in
    (bool)        REPLY='1 or 0' ;;
    (enum:*)      REPLY=${${spec#enum:}//\|/ · } ;;
    (int)         REPLY='whole number' ;;
    (int:0:)      REPLY='0 or more' ;;
    (int:*:)      REPLY="${${spec#int:}%:} or more" ;;
    (int::*)      REPLY="up to ${spec#int::}" ;;
    (int:*:*)     REPLY="${${spec#int:}%%:*} to ${spec##*:}" ;;
    (float)       REPLY='decimal number' ;;
    (float:\>*:*)
      REPLY="above ${${spec#float:\>}%%:*}"
      [[ -n ${spec##*:} ]] && REPLY+=", up to ${spec##*:}"
      ;;
    (float:*:)    REPLY="${${spec#float:}%:} or more" ;;
    (float::*)    REPLY="up to ${spec#float::}" ;;
    (float:*:*)   REPLY="${${spec#float:}%%:*} to ${spec##*:}" ;;
    (word:*)      REPLY=${${spec#word:}//\|/ · } ;;
    (any|*)       REPLY='any text' ;;
  esac
  return 0
}

# The groups, in the order they print. A pattern rather than a list, so a knob added tomorrow
# lands somewhere sensible without this file moving; anything unmatched falls into the last one.
typeset -ga _inzsh_play_groups=(
  'HOW IT LOOKS'          'INZSH_(SURFACE_MODE|SEPARATOR_STYLE|COLOR_DEPTH|NERD_FONT|MULTIBYTE)'
  'THE PROMPT ITSELF'     'INZSH_(PROMPT_*|PS2|SPROMPT|RESIZE|TRANSIENT*|TITLE*|LADDER_*)'
  'PRAYER TIMES'          'INZSH_SALAH_*'
  'INDIVIDUAL SEGMENTS'   'INZSH_(GIT_*|TIME_*|DATE_*|DURATION_*|HOST_*|DEFAULT_USER)'
  'EVERYTHING ELSE'       '*'
)

# `inzsh-knobs [word]` — every setting, grouped, with what it accepts and what it is now.
#
# Filtering is a plain substring on the NAME, so `inzsh-knobs salah` and `inzsh-knobs SALAH` do
# the same thing and `inzsh-knobs rank` finds the family. No argument means everything — which
# it did not, for a while: the old default was the pattern `*` fed into a substring match, so it
# looked for knobs with a literal asterisk in the name and found only the families.
inzsh-knobs() {
  emulate -L zsh
  setopt extended_glob

  local want=${(U)1-}
  local -i shown=0
  local title glob name value spec mark

  local -a names=(${(ok)_inzsh_config_defaults})
  local -A taken=()
  local -i g

  for (( g = 1; g <= ${#_inzsh_play_groups}; g += 2 )); do
    title=${_inzsh_play_groups[g]}
    glob=${_inzsh_play_groups[g + 1]}

    local -a rows=()
    for name in $names; do
      (( ${+taken[$name]} )) && continue
      [[ ${(U)name} == ${~${(U)glob}} ]] || continue
      taken[$name]=1
      [[ -z $want || ${(U)name} == *${want}* ]] || continue
      rows+=$name
    done
    (( ${#rows} )) || continue

    (( shown++ )) && print
    print -r -- "$title"
    for name in $rows; do
      _inzsh_play_accepts "${_inzsh_config_validators[$name]}"
      spec=$REPLY
      # What the prompt is using: yours if you set one, otherwise the shipped default. Marked,
      # because "what did I change" is the question this listing is usually asked.
      value=${(P)name-}
      mark=' '
      if [[ -n $value ]]; then
        mark='*'
      else
        value=${_inzsh_config_defaults[$name]}
        [[ -n $value ]] || value='(not set)'
      fi
      # Truncated rather than allowed to shove the last column out of line. A format string and
      # a URL are both longer than the space a listing can give them, and the listing's job is to
      # show you WHICH settings you have moved, not to be the place you read a value back from.
      (( ${#value} > 13 )) && value="${value[1,12]}…"
      printf '  %-31s %s %-13s %s\n' $name $mark "$value" "$spec"
    done
  done

  # Families are patterns rather than names — one per segment — so they have no single current
  # value, and printing a blank column for one would only invite the question.
  local -a fam=()
  for spec in ${_inzsh_config_family_order}; do
    [[ -z $want || ${(U)spec} == *${want}* ]] && fam+=$spec
  done

  if (( ${#fam} )); then
    (( shown++ )) && print
    print -r -- "ONE PER SEGMENT — put a segment's name in the middle, e.g. INZSH_GIT_RANK"
    for spec in $fam; do
      _inzsh_play_accepts "${_inzsh_config_family_validators[$spec]}"
      printf '  %-31s   %-13s %s\n' $spec \
        "${_inzsh_config_family_defaults[$spec]:-(not set)}" "$REPLY"
    done
  fi

  (( shown )) || { print -r -- "nothing matching '$1'"; return 1 }

  print
  print -r -- "  * = you set this. Anything else is the shipped default."
  print -r -- "  inzsh-segments lists the segment names."
}

# `inzsh-segments` — what the prompt is made of right now, in draw order, with the two numbers
# that decide where each one sits and when it goes.
inzsh-segments() {
  emulate -L zsh

  # Rendered first, so the text column is what the prompt would draw NOW rather than whatever
  # the last one happened to leave behind — and the prayer table refreshed first in turn, because
  # that is what precmd does before a render and this is standing in for a precmd.
  (( ${+functions[_inzsh_salah_cache_refresh]} )) && _inzsh_salah_cache_refresh
  _inzsh_render

  # Sorted by rank rather than by name — left to right, then the right-hand blocks inward — so
  # the listing reads in the order the prompt does. Hidden ones last, since rank 0 has no place
  # in a row it is not in.
  local seg rank sortable
  local -a keyed=()
  for seg in ${(k)_inzsh_segment_defaults}; do
    rank=${_inzsh_segment_defaults[$seg]}
    # Positive first ascending, then negative descending (rightmost last), then hidden.
    if (( rank > 0 ));   then (( sortable = 1000 + rank ))
    elif (( rank < 0 )); then (( sortable = 3000 + rank ))
    else                      (( sortable = 5000 ))
    fi
    keyed+=("${(l:5::0:)sortable} $seg")
  done

  print -r -- "SEGMENT     RANK  PRIORITY  SHOWING"
  local entry
  for entry in ${(o)keyed}; do
    seg=${entry##* }
    _inzsh_priority_of $seg
    rank=${_inzsh_segment_defaults[$seg]}
    printf '  %-10s %-5s %-9s %s\n' $seg "$rank" "$REPLY" \
      "${_inzsh_segment_text[$seg]:-(nothing to show)}"
  done

  print
  print -r -- "  RANK      where it sits. + from the left, - from the right, 0 hidden."
  print -r -- "  PRIORITY  what survives a narrow window. Lower lasts longer."
  print -r -- "  Change either: INZSH_<SEGMENT>_RANK, INZSH_<SEGMENT>_PRIORITY"
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
    (( ${+functions[_inzsh_salah_cache_refresh]} )) && _inzsh_salah_cache_refresh
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
# is internal and there is no `INZSH_REGISTER`. Configuration reaches the same choice by name —
# `INZSH_PRESET=warm` — but that one is read when the theme is sourced, so it is not something
# you can type at a prompt. This is what a running shell has instead, and reviewing both
# registers is what the visual sign-off is for.
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
InZsh playground — a throwaway shell. Your own setup is never read or changed.
Type a setting, press return, and the next prompt uses it.

  HOW IT LOOKS

    INZSH_SURFACE_MODE=hue        block colours: alternate · ramp · flat · hue
    INZSH_SEPARATOR_STYLE=round   the shape between blocks: arrow · round · divider
    INZSH_PROMPT_LINES=1          type on the same line as the blocks, not below
    inzsh-register light          the light palette instead of the dark one. In your own
                                  .zshrc this is INZSH_PRESET=warm, read as the theme loads

  WHAT IS SHOWN, AND WHERE

    INZSH_TIME_RANK=-30           where a block sits. Positive counts from the
                                  left, negative from the right, 0 hides it
    INZSH_DATE_RANK=65            switches on a block that ships turned off.
                                  ssh, duration and jobs switch on the same way
                                  but stay invisible until there is something
                                  to report — a remote session, a slow command,
                                  a background job
    INZSH_SALAH_LAT=21.4225       prayer times need both coordinates. Without
    INZSH_SALAH_LON=39.8262       them that block never appears at all

  WHAT GOES FIRST WHEN THE WINDOW GETS TOO NARROW

    INZSH_SALAH_PRIORITY=5        lower survives longer. Only ever consulted
                                  when something has to go — see the last
                                  section if this seems to do nothing
    INZSH_GIT_MINCOLS=60          or just hide one block below a width you pick

  COMMANDS

    inzsh-help                    this
    inzsh-knobs                   every setting, its default, and yours
    inzsh-knobs SALAH             only the ones matching a word
    inzsh-segments                what the prompt is made of right now
    inzsh-stub                    fill every block with sample text
    inzsh-stub off                put the real ones back
    inzsh-at 80 40 20             show those widths without resizing the window
    inzsh-register light          the light palette — or 'dark'
    inzsh-reset                   everything back to its default

  A GOOD FIRST LOOK

    inzsh-stub                    so you are looking at a full prompt
    inzsh-at 100 60 40 24 16      the whole range on one screen

  NOTHING CHANGED?

    Most likely you changed something that only matters when the window is too
    narrow to fit everything. At a comfortable width nothing is being dropped,
    so the order is never asked for.

    The clock and the prayer time are the last to feel it. Above roughly 22
    columns they do not compete at all — when the row runs out of room they
    simply move down beside the cursor, whole. Only below that does one of them
    have to go, and only then does priority decide which.

    So: `inzsh-at 40 24 20 16`, and watch the right-hand end.

  exit, or Ctrl-D, and none of this happened.
HELP
}

inzsh-help
