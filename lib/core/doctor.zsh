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

# Edit distance between `$1` and `$2`, in REPLY. Plain Levenshtein — insert, delete, substitute,
# each costing one — with a single generalisation: a literal `*` in `$1` matches a run of ZERO OR
# MORE characters of `$2` for no cost at all, the same as it does as a glob. That is what lets one
# function serve both shapes of registered knob: pass a plain name and it is ordinary Levenshtein;
# pass a family pattern such as `INZSH_*_RANK` and the wildcard absorbs whatever segment name sits
# where it does in the real registry, so a typo in the SEGMENT never counts against the match — a
# typo in `_RANK` itself is the only thing this distance can report for that family.
#
# The wildcard is only honoured in `$1`. A knob name can never contain `*` — it would not pass
# `_inzsh_config_register`'s own identifier check — so `$2` is always a plain string here, and the
# function does not need to reason about a wildcard on both sides at once.
#
# Textbook dynamic programming, two rows instead of a full table, because nothing here needs the
# rows it has already finished with. `prev` holds the row above the one being built; `cur` grows
# one cell at a time and becomes `prev` for the next row. The one departure from the textbook
# recurrence is the wildcard row: `dp[i][j] = min(dp[i-1][j], dp[i][j-1])` rather than the usual
# insert/delete/substitute triple, because finishing the wildcard here costs whatever finishing
# everything BEFORE it already cost (`dp[i-1][j]`), or one more character of `$2` absorbed into it
# for free (`dp[i][j-1]`) — never a real edit.
#
# Not on the render path, and it keeps the house rule anyway: no subprocess, `$((` arithmetic and
# parameter expansion only. `test/unit/doctor_spec.sh` greps this file for `$(` and a backtick
# outside a comment to hold it to that.
_inzsh_doctor_distance() {
  emulate -L zsh

  typeset -g REPLY=0
  local a=$1 b=$2
  local -i la=${#a} lb=${#b}

  local -a prev cur
  local -i i j cost del ins sub best
  local ai bj

  prev=(0)
  for (( j = 1; j <= lb; j++ )); do
    prev+=$j
  done

  for (( i = 1; i <= la; i++ )); do
    ai=$a[$i]
    if [[ $ai == '*' ]]; then
      cur=(${prev[1]})
      for (( j = 1; j <= lb; j++ )); do
        best=$(( prev[j+1] < cur[j] ? prev[j+1] : cur[j] ))
        cur+=$best
      done
    else
      cur=($i)
      for (( j = 1; j <= lb; j++ )); do
        bj=$b[$j]
        [[ $ai == $bj ]] && cost=0 || cost=1
        del=$(( prev[j+1] + 1 ))
        ins=$(( cur[j] + 1 ))
        sub=$(( prev[j] + cost ))
        best=$del
        (( ins < best )) && best=$ins
        (( sub < best )) && best=$sub
        cur+=$best
      done
    fi
    prev=("${cur[@]}")
  done

  REPLY=${prev[$(( lb + 1 ))]}

  return 0
}

# How close is `$1` allowed to sit to a registered shape before `_inzsh_doctor_near_miss` will
# say so? Two, chosen against the registry as it actually reads today (`make doctor` prints
# `${#_inzsh_config_validators}` names and `${#_inzsh_config_family_validators}` families — low
# forties and single digits), not against an abstract worst case:
#
#   INZSH_SEPARATOR_STYL   -> INZSH_SEPARATOR_STYLE   distance 1 (one letter short)
#   INZSH_GIT_RANNK        -> INZSH_*_RANK            distance 1 (one letter too many)
#   INZSH_DIR_MINCOL       -> INZSH_*_MINCOLS         distance 1 (one letter short)
#   INZSH_COLOUR_DEPTH     -> INZSH_COLOR_DEPTH       distance 1 (the British spelling)
#
# every one of those is a single slipped key, and 2 leaves room for a transposition (two
# substitutions in plain Levenshtein) without opening the door much wider. `INZSH_MY_OWN_THING`,
# the example the issue asks to stay silent, sits 14 away from its nearest registered NAME — comes
# nowhere close. A short name narrows how much distance 2 actually means in practice — two edits
# against `INZSH_PS2`'s three meaningful letters is most of the word — and this file accepts that:
# a wrong guess still shows the value it was made against, so it reads as a hint offered alongside
# the truth rather than a correction standing in for it.
typeset -g _inzsh_doctor_near_miss_threshold=2

# The one case the flat threshold above gets wrong on its own: a FAMILY's discriminating text can
# be shorter than the threshold once the wildcard is discounted. `INZSH_*_BG` is nine literal
# characters, but six of them are `INZSH_`, which every candidate here already starts with by
# construction — `_inzsh_doctor_near_misses` only ever calls this on names `${(I)INZSH_*}` matched
# in the first place — so the part actually doing any discriminating is `_BG`, three characters.
# Measured against the real registry: `INZSH_MY_OWN_THING`, the name the issue asks to stay silent
# for, sits exactly 2 from `INZSH_*_BG` — the wildcard swallows most of it for free and the last
# three letters happen to half-rhyme with `_BG` under substitution. A flat threshold of 2 would
# have reported it. So a family's cap is the SHORTER of the house threshold and half its own
# discriminating length: `INZSH_*_BG` (3 literal characters after the shared prefix) is capped at
# 1, `INZSH_*_RANK` (5) stays at the house threshold. The RANK and MINCOLS examples above still
# pass comfortably under their own caps; the BG one no longer passes at all.
#
# `$1` is a registered family PATTERN, always `INZSH_` plus exactly one more literal run plus one
# `*` — `_inzsh_config_register_family` refuses anything else — so trimming the leading `INZSH_`
# and the one wildcard character off its length is enough; no case analysis on where the `*` sits.
_inzsh_doctor_family_cap() {
  emulate -L zsh

  typeset -g REPLY=${_inzsh_doctor_near_miss_threshold:-2}
  local -i threshold=$REPLY
  local -i literal=$(( ${#1} - 7 ))
  local -i cap=$(( (literal - 1) / 2 ))

  (( cap > threshold )) && cap=$threshold
  (( cap < 0 )) && cap=0
  typeset -g REPLY=$cap

  return 0
}

# The registered name or family PATTERN closest to `$1`, in REPLY, when it is close enough to be
# worth a guess; status 1 with REPLY empty otherwise. `$1` is never itself a registered knob —
# `_inzsh_doctor_near_misses` only calls this once `_inzsh_config_spec_of` has already said no —
# so every candidate here is a real alternative, never the name confirming itself.
#
# A family's suggestion is the pattern itself — `INZSH_*_RANK`, verbatim — rather than a guessed
# concrete name such as `INZSH_GIT_RANK`. This file cannot know which segment the user meant any
# more than the registry can: the wildcard stands for a segment, a prayer name, a glyph key,
# whichever family it is, and `_inzsh_config_family_of` never resolved it to one because there
# WAS no clean match. `INZSH_*_RANK` is not a downgrade from a concrete guess — it is the exact
# vocabulary `lib/core/config.zsh`'s own comments already use to describe the family, so this file
# adds no second name for the same shape.
#
# The closest candidate wins outright; ties fall to whichever sorted key the loop reaches first,
# which is deterministic and not worth breaking further — this is a hint, not an authority.
_inzsh_doctor_near_miss() {
  emulate -L zsh

  typeset -g REPLY=
  local name=$1
  [[ -n $name ]] || return 1
  (( ${+_inzsh_config_validators} )) || return 1

  local -i threshold=${_inzsh_doctor_near_miss_threshold:-2}
  local -i best=$(( threshold + 1 )) dist cap
  local candidate best_name=

  for candidate in ${(ko)_inzsh_config_validators}; do
    _inzsh_doctor_distance "$candidate" "$name"
    dist=$REPLY
    (( dist < best )) || continue
    best=dist
    best_name=$candidate
  done

  for candidate in ${(ko)_inzsh_config_family_validators}; do
    _inzsh_doctor_distance "$candidate" "$name"
    dist=$REPLY
    _inzsh_doctor_family_cap "$candidate"
    cap=$REPLY
    (( dist <= cap && dist < best )) || continue
    best=dist
    best_name=$candidate
  done

  # `REPLY` is a shared name — `_inzsh_doctor_distance` and `_inzsh_doctor_family_cap` both write
  # it on every call inside the loops above, so by the time the loops are done it holds whatever
  # the LAST candidate left there, not this function's own answer. It is set explicitly here
  # either way rather than trusted to still hold the empty string from the top of this function.
  typeset -g REPLY=
  (( best <= threshold )) || return 1
  typeset -g REPLY=$best_name

  return 0
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
#   an unregistered name  there is no vocabulary to state FOR THIS FUNCTION - this list stays
#                         exactly what its name says, values the registry recognises and
#                         refuses. Issue #228 closes the harder half of that gap without
#                         widening this one: `_inzsh_doctor_near_misses`, below, answers the
#                         separate question of whether an unregistered name sits close enough
#                         to a registered one to be worth a guess, and prints its own rows
#                         immediately after this list's.
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

# Every `INZSH_` variable that is SET, that the registry has never heard of, and that sits close
# enough to a registered name or family to be worth a guess — sorted, in `reply`. The other half
# of issue #228, and deliberately a SEPARATE list from `_inzsh_doctor_ignored`'s rather than a
# widening of it: that function answers "the registry recognised this and refused it", this one
# answers "the registry never recognised this at all, but it looks like it meant to" — two
# different diagnoses, so two different reads over the same `INZSH_*` listing.
#
# An empty value is skipped for the same reason `_inzsh_doctor_ignored` skips one: set-but-empty
# is unset at every level of this theme, and a blank left in a zshrc is not a typo to chase.
_inzsh_doctor_near_misses() {
  emulate -L zsh

  typeset -ga reply
  reply=()

  (( ${+functions[_inzsh_config_spec_of]} )) || return 0
  (( ${+functions[_inzsh_doctor_near_miss]} )) || return 0

  local knob value spec
  for knob in ${(ko)parameters[(I)INZSH_*]}; do
    value=${(P)knob}
    [[ -n $value ]] || continue
    _inzsh_config_spec_of "$knob"
    spec=$REPLY
    [[ -z $spec ]] || continue
    _inzsh_doctor_near_miss "$knob" || continue
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

  # Issue #228. The other half of the same section: a name the registry has never heard of, close
  # enough to one it has that it is almost certainly the same slipped key rather than a variable
  # that was never ours. Printed as more `ignored` rows, straight after the ones above — same
  # value-flattening, same clipping, same reason for both — because the reader pasting this block
  # is asking the same question of every row here: "what did I set that is not doing anything?".
  # The tail differs on purpose: `accepts X` names a whole vocabulary the value could have been
  # from; `probably X` names one specific name the KNOB itself could have been, which is the more
  # honest claim this function is actually able to make.
  local -a misses
  _inzsh_doctor_near_misses
  misses=("${reply[@]}")
  for knob in $misses; do
    value=${${(P)knob}//[[:cntrl:]]/ }
    (( ${#value} > 24 )) && value="${value[1,23]}…"
    _inzsh_doctor_near_miss "$knob"
    _inzsh_doctor_row ignored "$knob=$value - probably $REPLY"
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
