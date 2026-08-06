# InZsh — the doctor, and the public command it hangs off. A thin formatter over the capability
# detection the theme already runs, printed as one pasteable block, because "paste the output of
# `inzsh doctor`" is what `.github/ISSUE_TEMPLATE/bug.yml` asks a reporter to do.
#
# Nothing here detects anything. Every detector in `lib/core/detect.zsh` is independently
# callable and recomputes from the environment as it is NOW — that was designed in for exactly
# this caller — so the doctor re-asks each question at the moment it prints, and the block
# describes the terminal the user is looking at rather than the one the theme was loaded in.
#
# Two policies other files deferred land here, and only here:
#
#   DETECT-AND-WARN. `lib/core/detect.zsh` refuses to infer that a Nerd Font is absent, and
#   `lib/core/render.zsh` draws the powerline for `unknown` rather than degrading the majority
#   who do have the font. What to TELL the `unknown` user was left to the doctor — so the notes
#   at the foot of the block are that warning, and they are a diagnostic, never a downgrade.
#
#   COORDINATES NEVER LEAVE. The block exists to be pasted into a public issue, and
#   CONTRIBUTING.md asks reporters not to include their position. `lib/salah/location.zsh`
#   writes the PROVENANCE of the resolved position down for this reader — `config`, `cache`,
#   or nothing — and provenance is all the doctor prints. The numbers stay on the machine.
#
# `inzsh` is the one public command the theme defines; the playground's `inzsh-*` helpers are
# dev tooling and are not sourced by the theme. Subcommands dispatch below, so a later command
# arrives beside `doctor` rather than as a second name in the user's namespace.
#
# Not on the render path — nothing calls any of this per prompt — but it keeps the house rule
# anyway: no subprocesses, parameter expansion and arithmetic only.

# One aligned row of the block: `_inzsh_doctor_row <label> <value>`.
_inzsh_doctor_row() {
  emulate -L zsh

  printf '  %-13s %s\n' "$1" "$2"

  return 0
}

# Is a valid override in force for knob `$1`? The detectors obey a well-formed override and fall
# through on anything else, so this is the same question they asked — answered through the
# registry where it is loaded, and never vouched for where it is not.
_inzsh_doctor_overridden() {
  emulate -L zsh

  local value=${(P)1}
  [[ -n $value ]] || return 1
  (( ${+functions[_inzsh_config_validate]} )) || return 1

  _inzsh_config_validate "$1" "$value"
}

# Every `INZSH_` variable that is SET to something the registry refuses, sorted, in `reply`.
#
# Issue #210. "Validate, then fall back" is the rule that stops a typo breaking the prompt: a
# value that fails its validator is not an error, it is simply not used. The cost is that a NEAR
# MISS is invisible — `INZSH_SEPARATOR_STYLE=rounded` does nothing at all, and the word is
# `round`. The registry already holds every validator, so answering this is a read over what the
# user has actually set rather than a second table.
#
# Three things are deliberately NOT listed:
#
#   an empty value        set-but-empty is UNSET at every level of this theme, so an
#                         `INZSH_DIR_BG=` left in a zshrc is falling through by design.
#   an unregistered name  there is no vocabulary to state, and nothing here can tell a
#                         misspelled knob from a variable that was never ours.
#   a valid value         the whole section is absent when everything is valid.
#
# `${parameters[(I)…]}` is the same listing `_inzsh_config_absorb_all` uses, so a knob added
# tomorrow appears here without this file moving. Not on the render path — nothing calls it per
# prompt — and no subprocesses all the same.
_inzsh_doctor_ignored() {
  emulate -L zsh

  typeset -ga reply
  reply=()

  (( ${+functions[_inzsh_config_spec_of]} )) || return 0

  local knob value spec
  for knob in ${(ko)parameters[(I)INZSH_*]}; do
    value=${(P)knob}
    [[ -n $value ]] || continue
    _inzsh_config_spec_of "$knob"
    spec=$REPLY
    [[ -n $spec ]] || continue
    _inzsh_config_check "$spec" "$value" && continue
    reply+=$knob
  done

  return 0
}

# `$1` seconds as a coarse age — minutes, then hours, then days. A bug reader needs "about a
# day", never the arithmetic.
_inzsh_doctor_age() {
  emulate -L zsh

  typeset -g REPLY=
  local -i seconds=$1

  if (( seconds < 3600 )); then
    REPLY="$(( seconds / 60 ))m"
  elif (( seconds < 172800 )); then
    REPLY="$(( seconds / 3600 ))h"
  else
    REPLY="$(( seconds / 86400 ))d"
  fi

  return 0
}

# The block itself. Always status 0: a diagnostic that can fail is a diagnostic nobody can run
# in the broken environment it exists for, so every line degrades to an honest word — `unknown`,
# `none` — rather than to an error.
_inzsh_doctor() {
  emulate -L zsh

  # Re-ask every question. Recompute-never-cache is each detector's own contract; calling them
  # here is what makes the block current rather than a memory of source time.
  (( ${+functions[_inzsh_detect_color_depth]} )) && _inzsh_detect_color_depth
  (( ${+functions[_inzsh_detect_multibyte]} ))   && _inzsh_detect_multibyte
  (( ${+functions[_inzsh_detect_nerd_font]} ))   && _inzsh_detect_nerd_font
  (( ${+functions[_inzsh_detect_tmux]} ))        && _inzsh_detect_tmux

  local -a notes=()
  local value

  print -r -- 'InZsh doctor'

  _inzsh_doctor_row zsh "${ZSH_VERSION:-unknown}"

  # The terminal names itself in one of three places — `TERM_PROGRAM` is the usual one,
  # `LC_TERMINAL` is what ssh forwards, `TERMINAL_EMULATOR` is the JetBrains spelling — and a
  # terminal that names itself usually versions itself beside it.
  if [[ -n ${TERM_PROGRAM-} ]]; then
    value="$TERM_PROGRAM${TERM_PROGRAM_VERSION:+ $TERM_PROGRAM_VERSION}"
  elif [[ -n ${LC_TERMINAL-} ]]; then
    value="$LC_TERMINAL${LC_TERMINAL_VERSION:+ $LC_TERMINAL_VERSION}"
  elif [[ -n ${TERMINAL_EMULATOR-} ]]; then
    value=$TERMINAL_EMULATOR
  else
    value=unknown
  fi
  _inzsh_doctor_row terminal "$value"

  _inzsh_doctor_row TERM "${TERM:-unset}"

  value=${_inzsh_color_depth:-unknown}
  _inzsh_doctor_overridden INZSH_COLOR_DEPTH && value+=' (INZSH_COLOR_DEPTH)'
  _inzsh_doctor_row 'colour depth' "$value"

  # The locale as zsh itself resolves it — `LC_ALL`, then `LC_CTYPE`, then `LANG` — beside the
  # verdict the theme drew from it.
  value=${LC_ALL:-${LC_CTYPE:-${LANG:-none}}}
  case ${_inzsh_multibyte-} in
    (1) value+=' (multibyte: yes' ;;
    (0) value+=' (multibyte: no' ;;
    (*) value+=' (multibyte: unknown' ;;
  esac
  _inzsh_doctor_overridden INZSH_MULTIBYTE && value+=', INZSH_MULTIBYTE'
  value+=')'
  _inzsh_doctor_row locale "$value"

  case ${_inzsh_nerd_font-} in
    (1) value=yes ;;
    (0) value=no
        notes+='without a Nerd Font, separator styles resolve to divider' ;;
    (*) value=unknown
        notes+='a font cannot be proven from a shell - if separators draw as boxes, set INZSH_NERD_FONT=0' ;;
  esac
  _inzsh_doctor_overridden INZSH_NERD_FONT && value+=' (INZSH_NERD_FONT)'
  _inzsh_doctor_row 'nerd font' "$value"

  if [[ ${_inzsh_tmux-} == 1 ]]; then
    _inzsh_doctor_row tmux yes
    [[ ${_inzsh_tmux_rgb-} == 1 ]] ||
      notes+='tmux may be flattening 24-bit colour - see the README for RGB passthrough'
  else
    _inzsh_doctor_row tmux no
  fi
  case ${_inzsh_tmux_rgb-} in
    (1) value=yes ;;
    (0) value=no ;;
    (*) value=unknown ;;
  esac
  _inzsh_doctor_row 'tmux rgb' "$value"

  # The registered invariants, straight out of the registry — the listing
  # `_inzsh_config_guard_names` exists to make cheap.
  if (( ${+functions[_inzsh_config_guard_names]} )); then
    _inzsh_config_guard_names
    (( ${#reply} )) && _inzsh_doctor_row invariants "${(j:, :)reply}"
  fi

  # What the user set and the theme is not using — one row per value, with the vocabulary it
  # should have used, rendered from the registered spec by `_inzsh_config_accepts` so the words
  # here and the words `inzsh-knobs` prints are the same words.
  #
  # NOTHING IS PRINTED WHEN EVERYTHING IS VALID. A clean shell does not grow a section telling it
  # so; the rows exist to be noticed.
  #
  # The value is flattened and clipped before it is shown. This block is pasted into an issue, so
  # a newline in a value would end the row early, a control character would move somebody's
  # cursor, and a format string long enough to be a config file in its own right would push the
  # block off the screen. Where it came from is the diagnostic; reading the whole value back is
  # what the variable itself is for.
  local knob
  local -a ignored
  _inzsh_doctor_ignored
  ignored=("${reply[@]}")
  for knob in $ignored; do
    value=${${(P)knob}//[[:cntrl:]]/ }
    (( ${#value} > 24 )) && value="${value[1,23]}…"
    _inzsh_config_spec_of "$knob"
    _inzsh_config_accepts "$REPLY"
    _inzsh_doctor_row ignored "$knob=$value - accepts $REPLY"
  done

  # Where the prayer segment's position came from — never where it is. Omitted entirely when
  # the salah library is not loaded: a partial load has nothing honest to say here.
  if (( ${+functions[_inzsh_salah_location]} )); then
    if _inzsh_salah_location "${EPOCHSECONDS-}"; then
      value=$_inzsh_salah_location_source
      if [[ $value == cache ]] && (( _inzsh_salah_location_age >= 0 )); then
        _inzsh_doctor_age $_inzsh_salah_location_age
        value+=" (refreshed ${REPLY} ago)"
      fi
    else
      value=none
    fi
    _inzsh_doctor_row salah "location: $value"
  fi

  local note
  for note in $notes; do
    _inzsh_doctor_row note "$note"
  done

  return 0
}

# `inzsh locate [--force] [now]` — refresh the stored position, on purpose. The public face of
# `INZSH_SALAH_AUTOLOCATE` (issue #186): the knob PERMITS the theme's one network call, and this
# command is the only shipped way to MAKE it. It is typed by a person — never reached from a
# hook, the segment, or the render path — which is the whole safety story of
# `lib/salah/location.zsh` kept intact with a name you can find.
#
#   inzsh locate            look the position up if the stored one is older than the TTL
#   inzsh locate --force    look it up now, whatever the stored one's age — for after you move
#   (inzsh locate &!)       from `.zshrc`, detached, so login does not wait
#
# The trailing `[now]` is the injected clock every salah function takes, for the suite that
# pins time; unset, the wall clock answers.
#
# The TTL gate is the same one `_inzsh_salah_locate_refresh` keeps, restated here for one
# reason: the command has to be able to SAY which side of it you are on — "current, refreshed
# 2h ago, --force to insist" is the answer somebody who just moved actually needs — and to step
# over it when told to. Outcomes go to stdout; refusals and failures go to stderr with status 1.
_inzsh_locate() {
  emulate -L zsh

  local -i force=0
  if [[ ${1-} == (-f|--force) ]]; then
    force=1
    shift
  fi

  if ! (( ${+functions[_inzsh_salah_locate_fetch]} )); then
    print -ru2 -- 'inzsh locate: the prayer library is not loaded'
    return 1
  fi

  if ! _inzsh_salah_autolocate_on; then
    print -ru2 -- 'inzsh locate: the lookup is off - set INZSH_SALAH_AUTOLOCATE=1 to permit it'
    return 1
  fi

  local now=${1:-${EPOCHSECONDS-}}
  if [[ $now != <-> ]]; then
    print -ru2 -- 'inzsh locate: no clock to age the stored position against'
    return 1
  fi

  if (( ! force )); then
    _inzsh_salah_autolocate_ttl
    local -i ttl=$REPLY
    if _inzsh_salah_location_read "$now" &&
       (( _inzsh_salah_location_age >= 0 && _inzsh_salah_location_age < ttl )); then
      _inzsh_doctor_age $_inzsh_salah_location_age
      print -r -- "position current (refreshed $REPLY ago) - 'inzsh locate --force' looks it up anyway"
      return 0
    fi
  fi

  if _inzsh_salah_locate_fetch "$now"; then
    print -r -- 'position refreshed'
    return 0
  fi

  # The lookup did not work, and the two aftermaths deserve different sentences: a stale answer
  # still on disk is what the segment keeps running on, and no answer at all means the segment
  # stays absent until one arrives.
  if _inzsh_salah_location_read "$now"; then
    print -ru2 -- 'inzsh locate: the lookup failed - the previously stored position is kept'
  else
    print -ru2 -- 'inzsh locate: the lookup failed and no position is stored'
  fi

  return 1
}

# `inzsh preset [name]` — the register, switched in the shell you are already typing in.
#
# The other half of `INZSH_PRESET` (issue #211). That knob is read at SOURCE time, and correctly
# so: `PS2`, `SPROMPT` and the title are built once from the roles resolved then, so a register
# applied later would move the ribbon and quietly leave those behind. Setting the knob at a
# prompt therefore does nothing, and the only live switch was `source <install>/presets/
# inzsh-warm.zsh` — a path nobody remembers, and one that does not exist in a bundle at all.
#
#   inzsh preset          the register in force, and the names there are
#   inzsh preset warm     switch, now, for every prompt after this one
#
# It reads NO FILE. `_inzsh_preset_registers` in `lib/core/tokens.zsh` is the whole vocabulary —
# a preset is a name for a register and nothing more — which is what makes this work identically
# from a clone with a `presets/` directory and from the single-file bundle without one.
#
# What it covers, and it is deliberately the whole of what the load-time knob covers: the roles,
# the knob itself, and the secondary prompts the theme owns. What it cannot do is reach a shell
# that is not this one, or the prompt already on the screen — the next one is drawn from the new
# roles. Outcomes go to stdout; refusals go to stderr with status 1.
_inzsh_preset() {
  emulate -L zsh

  if (( ! ${+_inzsh_preset_registers} )); then
    print -ru2 -- 'inzsh preset: the token layer is not loaded'
    return 1
  fi

  local -a names=(${(ko)_inzsh_preset_registers})
  local offer="${(j: · :)names}"

  if (( $# > 1 )); then
    print -ru2 -- "inzsh preset: one name at a time - $offer"
    return 1
  fi

  # Nothing typed: what is in force and what else there is. The REGISTER is the truth rather than
  # the knob — somebody who sourced a preset file by hand moved one and not the other — so the
  # name is read back OUT of the table, and a register the table cannot name is printed as itself
  # rather than guessed at. Empty is unset at every level of this theme, so an argument that
  # expanded to nothing is this case too and not a refusal.
  if [[ -z ${1-} ]]; then
    local current=${(k)_inzsh_preset_registers[(r)${_inzsh_register-}]}
    print -r -- "preset: ${current:-${_inzsh_register:-unknown}}"
    print -r -- "available: $offer"
    return 0
  fi

  _inzsh_preset_normalize "$1"
  local name=$REPLY
  if [[ -z ${_inzsh_preset_registers[$name]-} ]]; then
    print -ru2 -- "inzsh preset: '$1' is not a preset - $offer"
    return 1
  fi

  # The knob is set to the canonical name and the applier reads it, so this command and the
  # entry point run the same code to reach the same register. Setting it is not bookkeeping: a
  # shell whose knob disagreed with the register it is drawing would be lying to everything that
  # reads it back — `inzsh doctor`, the report above, a plugin manager that re-sources the theme.
  typeset -g INZSH_PRESET=$name
  _inzsh_preset_apply

  # And the part the load-time rule exists for. The secondary prompts are built once, at install,
  # so a switch has to rebuild them or the continuation prompt stays in the register the shell
  # started in. Only when the theme OWNS them: `_inzsh_prompts_saved` holds what install found,
  # so its absence means somebody else's `PS2` is in force and it is none of our business.
  if (( ${+_inzsh_prompts_saved} && ${+functions[_inzsh_prompts_ps2]} )); then
    _inzsh_prompts_ps2
    typeset -g PS2=$REPLY
    _inzsh_prompts_sprompt
    typeset -g SPROMPT=$REPLY
  fi

  print -r -- "preset: $name"

  return 0
}

# The public command. One name in the user's namespace, subcommands under it, so what the theme
# offers to be TYPED stays one word wide however many verbs it grows.
inzsh() {
  emulate -L zsh

  case ${1-} in
    (doctor)
      shift
      _inzsh_doctor "$@"
      ;;
    (locate)
      shift
      _inzsh_locate "$@"
      ;;
    (preset)
      shift
      _inzsh_preset "$@"
      ;;
    (*)
      print -ru2 -- 'usage: inzsh doctor | inzsh locate [--force] | inzsh preset [name]'
      return 1
      ;;
  esac
}
