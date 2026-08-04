# InZsh — the prayer-time segment. One moment, on the right of the prompt, all day.
#
# THE RULE THIS FILE EXISTS TO KEEP. Everything the segment draws was computed before it ran.
# `lib/salah/cache.zsh` holds twelve moments — today's six prayers and tomorrow's — and this file
# picks one out of them and writes a string. No trigonometry, no file, no fork, no clock beyond
# the instant it is handed. `test/render/segment_salah_spec.sh` asserts that structurally, over
# the body of the build function, because a computation that is only slow at a high latitude in
# December is a computation no run of the suite would ever notice.
#
# The cache is refreshed by `_inzsh_salah_precmd` at the foot of this file — beside the render,
# never inside it, exactly as the git worker's hook sits beside `_inzsh_render`. On the great
# majority of prompts that refresh is a compare against a key and returns; a few times a day it
# is one small file read; once a day, per place, it is about five milliseconds of arithmetic.
#
# ---------------------------------------------------------------------------------------------
# WHAT IT DRAWS
#
# `INZSH_SALAH_FORMAT` picks one of four readings of the same two facts — which moment is next,
# and when. They differ in what they make easy to answer at a glance:
#
#   clock      Maghrib · 19:59       WHEN. The default: a time you can compare against a clock,
#                                    a meeting, or the thing you were about to start doing.
#   countdown  Maghrib in 24m        HOW LONG. Needs no arithmetic from the reader, at the cost
#                                    of a number that means nothing an hour later in a screenshot.
#   window     Asr · until 19:59     WHICH PRAYER IS DUE NOW, and how long it stays due.
#   full       Maghrib · 19:59 · 24m both, for a wide terminal.
#
# THE SEPARATOR IS THE DESIGN SYSTEM'S KICKER, `·`, taken from `_inzsh_glyph[dot]` in
# `lib/core/tokens.zsh` — the one table every mark the theme draws comes out of. A middle dot is
# what the design system already uses to join two facts about one subject, which is exactly what
# a name and a time are, and it is why the countdown form uses the word `in` instead: `Maghrib ·
# 24m` would read as a time.
#
# THE OVERNIGHT GAP, which is the one real decision in `window`. Between isha and the next fajr —
# and again between sunrise and dhuhr — no prayer window is open. Three things could be drawn
# there and only one of them is honest:
#
#   nothing            the segment disappears for a third of the day, every day, which reads as a
#                      bug and loses the reader the one fact the segment exists to carry.
#   `Isha · until 05:12`   asserts that isha's window runs to fajr. That is a FIQH RULING — many
#                      hold it ends at midnight — and this theme computes the sun's position and
#                      has no business ruling on anything else.
#   `Fajr · 05:12`     the next moment, in the `clock` reading.
#
# So the rule is: `window` names the window it is inside, and where the last moment to pass opened
# no window it falls back to `clock`. One sentence, two gaps, no ruling.
#
# A PRAYER THAT DOES NOT HAPPEN IS SKIPPED. Above the polar circles the sun may never reach the
# horizon and `lib/salah/calc.zsh` answers with its sentinel rather than a number. Those slots are
# passed over on the way to the next real moment; where every slot is a sentinel the segment is
# ABSENT. `00:00` is never drawn, because midnight is what a naive implementation reports for a
# prayer that has no time, and it is indistinguishable from a prayer that has one.
#
# ---------------------------------------------------------------------------------------------
# Registration.
#
# `typeset -gA` over an existing association keeps what is in it, so this file is independently
# sourceable and re-sourcing re-registers over the same keys rather than doubling anything.
#
#   rank -20      the right prompt, one place inward of the clock at -10. The clock is the
#                 reference the eye returns to and sits hard against the edge; the prayer time is
#                 the same KIND of information — a moment, not a report about the command that
#                 just ran — so it belongs beside it rather than among the status blocks.
#   importance 1  the top of the ramp. This is the segment the theme is willing to spend its
#                 loudest surface on, and the one the accent note below is about. `alternate` and
#                 `flat` ignore importance entirely.
#   fg text-body  the RESTING role, and the correct one on the surface the renderer assigns
#                 positionally. See the accent note.
#   bg accent     the fill it asks for, honoured by `INZSH_SURFACE_MODE=hue`.
#
# THE ACCENT. The theme has exactly one saturated colour — caramel, the `accent` role, the same
# value in both registers by design — and this is the segment it is meant for. It asks for it
# through `_inzsh_segment_bg_role`, the map `_inzsh_render_hues` reads, and the ink arrives with
# the fill: no segment names its own foreground for a fill it declared, because the design system
# already pairs the two and a second opinion is a second place to get it wrong.
#
# WHAT THE ASK DOES NOT BUY, and this is recorded rather than worked around. `accent` is a FILL
# like any other here, so it is held to the adjacency invariant like any other — an earlier note
# in this file argued it should be exempt, on the grounds that caramel differs from every surface
# by construction. It does; what it does not differ from is another accented block, and a rule
# with one exemption in it is a rule with a hole in it. The renderer takes the ask back where
# honouring it would put two equal fills side by side, which for one accent on the row never
# happens.
#
# AND WHAT THE DESIGN SYSTEM COULD NOT SUPPLY. `on-accent` is choc in the dark register and cream
# in the light, and on caramel those are 3.79:1 and 3.07:1 — AA-large, not AA. There is no role
# in either table that clears 4.5:1 on the accent fill, because the DS keeps the accent
# register-invariant and its on-colour register-dependent, and no single name is dark enough in
# both. This is the theme's one sub-AA pairing and it is the design system's, not this file's:
# the block still carries its meaning as text — a prayer name and a time — rather than as colour,
# so the shortfall costs contrast and not information.
#
# Outside `hue` the seam is unchanged: the per-segment override still outranks everything, and
# it is still written as ROLES rather than as colour values so a palette change reaches it.
#
#   INZSH_SALAH_BG=${_inzsh_role[accent]}
#   INZSH_SALAH_FG=${_inzsh_role[on-accent]}
typeset -gA _inzsh_segment_text _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role _inzsh_segment_bg_role _inzsh_segment_importance _inzsh_segment_priority

_inzsh_segment_defaults[SALAH]=-20
_inzsh_segment_fg_role[SALAH]=text-body
_inzsh_segment_bg_role[SALAH]=accent
_inzsh_segment_importance[SALAH]=1
_inzsh_segment_priority[SALAH]=90

# The format knob, registered where it is read. `any` rather than an enum, matching
# `INZSH_SALAH_ASR` and `INZSH_SALAH_HIGHLAT`: every word-valued knob in this family is matched
# case-insensitively, the registry's `enum` is case-sensitive, and a validator that is nearly
# right is worse than one that says the module decides. The vocabulary is in
# `docs/configuration.md`, and the fallback below is what an unrecognised word gets.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_SALAH_FORMAT any clock
fi

# The registered default, restated here so the segment still draws sensibly when
# `lib/core/config.zsh` is not loaded — a half-assembled bundle, a spec that includes this file
# alone. Same reason `lib/segments/time.zsh` keeps `_inzsh_time_format_default`.
typeset -g _inzsh_salah_format_default=clock

# How a prayer's key reads on the prompt. Capitalised, transliterated, English word order —
# `Maghrib` rather than `maghrib` because it is a name, and a name in a prompt full of lower-case
# paths is easier to find.
#
# This is also the segment's list of what a slot in the table can be called: `${(k)}` of it is the
# six, and every one has a `next_` twin in the cache. `test/render/segment_salah_spec.sh` holds it
# equal to `lib/salah/calc.zsh`'s own prayer list, so a prayer added there cannot arrive here
# unlabelled.
typeset -gA _inzsh_salah_label
_inzsh_salah_label=(
  fajr     Fajr
  sunrise  Sunrise
  dhuhr    Dhuhr
  asr      Asr
  maghrib  Maghrib
  isha     Isha
)

# Which moments OPEN a window, for the `window` format. Fajr, dhuhr, asr and maghrib each begin a
# period during which that prayer is due; sunrise and isha do not — sunrise ENDS fajr's window and
# opens nothing, and where isha's ends is a question of fiqh rather than of astronomy. See the
# overnight-gap note at the top: those two are exactly the gaps `window` falls back through.
typeset -gA _inzsh_salah_window
_inzsh_salah_window=(
  fajr     1
  sunrise  0
  dhuhr    1
  asr      1
  maghrib  1
  isha     0
)

# The furthest ahead the segment will look, in seconds. Thirty-six hours: comfortably past the
# longest real gap between two moments — an Arctic winter can put thirteen hours between isha and
# the next fajr — and comfortably short of a table left over from a clock that jumped. Anything
# beyond it means the table is not about now, and the segment draws nothing rather than a time
# from another day.
typeset -gi _inzsh_salah_horizon=129600

# The kicker, read from the token layer's glyph table at source time and guarded, with the ASCII
# stand-in assigned first. The entry point sources the token layer well above this file, but a
# segment that came up without one must still draw a separator between two facts: `.` is one byte,
# one column, and legible on a terminal that would have drawn the dot as mojibake. Spelled through
# the table rather than as a literal, and never as a `\u` escape — that escape is resolved when
# the file is PARSED, and outside a multibyte locale it takes the rest of the file with it.
typeset -g _inzsh_salah_glyph_dot='.'
if [[ ${(t)_inzsh_glyph} == association* && -n ${_inzsh_glyph[dot]} ]]; then
  _inzsh_salah_glyph_dot=${_inzsh_glyph[dot]}
fi

# ---------------------------------------------------------------------------------------------
# Two small pure functions the build is written out of.

# The epoch `$1` as `HH:MM` in the shell's own zone, in REPLY.
#
# Delegated to `lib/salah/calc.zsh`, which is the one place in the tree with an opinion about how
# an instant reads and the only place a zone appears in an ANSWER rather than in a question.
# Nothing here sets `TZ`, computes an offset or knows about daylight saving: the instant is
# carried all the way down to `strftime`, and those rules are the C library's.
#
# The fallback is for this file sourced without `lib/salah/`. `strftime` comes from `zsh/datetime`
# and is a BUILTIN — a module call, not a fork — which is the only reason a clock may be formatted
# on the render path at all.
_inzsh_salah_clock() {
  emulate -L zsh

  typeset -g REPLY=

  [[ $1 == (|-)<-> ]] || return 1

  if (( ${+functions[_inzsh_salah_format]} )); then
    _inzsh_salah_format "$1" '' '%H:%M'
    return $?
  fi

  local rendered
  strftime -s rendered '%H:%M' $1 2>/dev/null || return 1
  typeset -g REPLY=$rendered

  return 0
}

# `$1` seconds as a duration a person reads, in REPLY: `24m`, `1h05m`, `6h`.
#
# ROUNDED UP, ALWAYS. The table holds moments rounded to the minute and the next moment is chosen
# as the first one strictly after now, so the remainder is between one second and a day; rounding
# it down would draw `in 0m` for the last minute before every prayer, which is the one minute the
# number matters. Rounding up means the countdown reaches `1m` and then the moment arrives.
#
# The hours and minutes are ONE WORD. `6h 12m` reads as two facts about two things; there is one
# gap and it is six hours and twelve minutes long — the same reasoning the git segment's `↑2↓3`
# is written under.
#
# ONCE THERE IS AN HOUR, THE MINUTES ARE ALWAYS DRAWN, padded to two digits: `1h00m` and not `1h`,
# `1h05m` and not `1h5m`. A prompt segment whose width changes on the hour shuffles everything to
# its left, and `1h` would be the one reading a glance could mistake for a whole number of hours
# when it is anything from sixty minutes to sixty exactly.
_inzsh_salah_duration() {
  emulate -L zsh

  typeset -g REPLY=

  [[ $1 == (|-)<-> ]] || return 1

  local -i seconds=$1
  (( seconds < 0 )) && seconds=0

  local -i minutes=$(( (seconds + 59) / 60 ))
  (( minutes < 1 )) && minutes=1

  if (( minutes < 60 )); then
    typeset -g REPLY="${minutes}m"
    return 0
  fi

  printf -v REPLY '%dh%02dm' $(( minutes / 60 )) $(( minutes % 60 ))

  return 0
}

# ---------------------------------------------------------------------------------------------
# `_inzsh_segment_salah_build [now] [table-assoc-name]` → `_inzsh_segment_text[SALAH]`.
#
# BOTH ARGUMENTS ARE INJECTION SEAMS, and they are the same two `lib/salah/calc.zsh` is built on.
# The instant is a number, not a clock read — `_inzsh_segment_salah_build 1782050000` renders that
# second and no other. The state is a NAME, not a table — a spec fills `local -A pinned=(fajr …)`
# and calls `_inzsh_segment_salah_build "" pinned`, and no cache file exists anywhere. With
# neither, the instant is the live one and the state is what the hook below refreshed.
#
# THE SEARCH IS A MINIMUM, NOT A WALK IN ORDER. The twelve slots are read and the one closest
# ahead of now is taken, along with the last one behind it. Ordering the slots and stopping at the
# first future one would be one comparison cheaper and would assume that today's isha always
# precedes tomorrow's fajr — true everywhere anyone lives, and not something a segment needs to
# bet a wrong time on when a scan costs twelve integer compares.
#
# Always status 0. An unreadable table, a location that has gone away, a polar night with no
# moment in it and a table left over from last week all produce the same thing: an EMPTY entry,
# which every layer already reads as no block and no separator.
_inzsh_segment_salah_build() {
  emulate -L zsh
  setopt extended_glob

  # The kicker, re-read from the table on every build so an `INZSH_GLYPH_DOT` override set at
  # one prompt has moved by the next. The source-time copy above stays as the fallback for a
  # shell with no table at all.
  if [[ ${(t)_inzsh_glyph} == association* && -n ${_inzsh_glyph[dot]} ]]; then
    typeset -g _inzsh_salah_glyph_dot=${_inzsh_glyph[dot]}
  fi

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[SALAH]=

  local now=${1:-${EPOCHSECONDS-}}
  [[ $now == (|-)<-> ]] || return 0

  # `${(P)}` on something that is not an identifier is a fatal error mid-render, the same trap
  # `_inzsh_mincols_of` guards in `lib/core/layout.zsh`. A name that cannot form a variable is
  # read as no state at all.
  local src=${2:-_inzsh_salah_table}
  [[ $src == [A-Za-z_][A-Za-z0-9_]# ]] || return 0

  # Copied through a flat array first. `${(Pkv)}` on a SCALAR yields one element, and a
  # one-element assignment to an association is a fatal `odd number of elements` — so the count is
  # checked before the map is built rather than after.
  local -a flat
  flat=("${(@Pkv)src}")
  (( ${#flat} && ${#flat} % 2 == 0 )) || return 0

  local -A state
  state=("${flat[@]}")

  local -i now_i=$now
  local -i epoch nearest=0 latest=0 have_next=0 have_prev=0
  local nearest_name= latest_name=
  local base slot value

  for base in ${(k)_inzsh_salah_label}; do
    for slot in $base next_$base; do
      value=${state[$slot]-}
      [[ $value == (|-)<-> ]] || continue
      epoch=$value
      if (( epoch > now_i )); then
        if (( ! have_next || epoch < nearest )); then
          nearest=$epoch
          nearest_name=$base
          have_next=1
        fi
      elif (( ! have_prev || epoch > latest )); then
        latest=$epoch
        latest_name=$base
        have_prev=1
      fi
    done
  done

  (( have_next )) || return 0
  (( nearest - now_i <= _inzsh_salah_horizon )) || return 0

  _inzsh_salah_clock "$nearest" || return 0
  local when=$REPLY

  _inzsh_salah_duration $(( nearest - now_i )) || return 0
  local left=$REPLY

  # The knob, read fresh. `lib/core/config.zsh` owns it and its answer is preferred because it
  # knows about registered defaults; the `case` below repeats the vocabulary rather than trusting
  # what came back, because this file is independently sourceable and an older bundle may never
  # have registered anything.
  local mode=${INZSH_SALAH_FORMAT:-$_inzsh_salah_format_default}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_SALAH_FORMAT
    mode=${REPLY:-$_inzsh_salah_format_default}
  fi
  mode=${(L)mode}

  local dot=$_inzsh_salah_glyph_dot
  local label=${_inzsh_salah_label[$nearest_name]}
  local text="$label $dot $when"

  case $mode in
    (countdown)
      text="$label in $left"
      ;;
    (full)
      text="$label $dot $when $dot $left"
      ;;
    (window)
      # The gap rule, in one condition. A window is named only where the last moment to pass
      # opened one; otherwise this is the `clock` reading, which `text` already holds.
      if (( have_prev )) && [[ ${_inzsh_salah_window[$latest_name]-0} == 1 ]]; then
        text="${_inzsh_salah_label[$latest_name]} $dot until $when"
      fi
      ;;
  esac

  # `%` doubled LAST, over the finished fragment. Nothing this segment draws can contain one
  # today — the labels are ours and the rest is digits — but the fragment is spliced into PROMPT
  # and prompt expansion runs over it, and the day a label or a separator glyph acquires a per
  # cent is not the day to discover that. `_inzsh_width` already reads `%%` as the one column it
  # draws, so the doubling costs no accuracy.
  _inzsh_segment_text[SALAH]=${text//'%'/'%%'}

  return 0
}

# ---------------------------------------------------------------------------------------------
# The hook
#
# One precmd, and it is where the cost lives. Registered through `add-zsh-hook` — assigning
# `precmd_functions` directly would discard every registration any other plugin had made, which
# is the rule `lib/core/hooks.zsh` states and this applies rather than restates.
#
# Registered AFTER `_inzsh_precmd`, which is the only order `add-zsh-hook` can produce for a file
# installed later, and it is the order that works: precmd functions all run BEFORE zsh expands
# PROMPT, so a later hook that re-renders still reaches THIS prompt and not the next one. That is
# what makes the very first prompt of a shell — the one where the table is still empty — draw the
# segment rather than skip it.
#
# This is NOT asynchronous and does not want to be. The whole cost it can ever pay is bounded and
# small: a key compare on most prompts, a small file read a few times a day, and about five
# milliseconds of arithmetic once a day per place. The git worker is asynchronous because
# `git status` is UNBOUNDED — it can block for seconds on a network mount — and this cannot.
_inzsh_salah_precmd() {
  emulate -L zsh

  [[ -o interactive ]] || return 0
  (( ${+functions[_inzsh_salah_cache_refresh]} )) || return 0

  local before=${_inzsh_segment_text[SALAH]-}

  _inzsh_salah_cache_refresh

  _inzsh_segment_salah_build
  if [[ ${_inzsh_segment_text[SALAH]-} != $before ]] &&
     (( ${+functions[_inzsh_render]} )); then
    _inzsh_render
  fi

  return 0
}

# Attach. Idempotent by delegation, exactly as `lib/core/hooks.zsh` is: `add-zsh-hook` refuses to
# register a function that is already in the array, so installing twice registers once and repairs
# a registration something else removed.
_inzsh_salah_install() {
  emulate -L zsh

  [[ -o interactive ]] || return 0

  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _inzsh_salah_precmd

  return 0
}

# Let go. Unguarded on purpose, like the hook layer's: a shell that somehow acquired this must be
# able to shed it.
_inzsh_salah_uninstall() {
  emulate -L zsh

  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd _inzsh_salah_precmd

  return 0
}
