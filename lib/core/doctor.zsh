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

# The public command. One name in the user's namespace, subcommands under it, so what the theme
# offers to be TYPED stays one word wide however many verbs it grows.
inzsh() {
  emulate -L zsh

  case ${1-} in
    (doctor)
      shift
      _inzsh_doctor "$@"
      ;;
    (*)
      print -ru2 -- 'usage: inzsh doctor'
      return 1
      ;;
  esac
}
