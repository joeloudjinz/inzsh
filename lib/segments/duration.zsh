# InZsh — the command-duration segment. How long the command that just finished took.
#
# THE ONE SEGMENT THAT NEEDS STATE ACROSS TWO HOOKS. Everything else in `lib/segments/` answers
# a question about the moment the prompt is drawn; this one answers a question about the gap
# between two moments, so something has to be recorded before the command runs and read after
# it. `preexec` marks the start, `precmd` freezes the elapsed, and the segment itself renders a
# number it is handed. All three go through `add-zsh-hook` — never `preexec=` or
# `precmd_functions=(…)`, which would discard every registration any other plugin had made.
#
# IT SHIPS OFF, at rank 0. The hooks are installed regardless of the rank, because the rank can
# change at a prompt and a timer that only starts once somebody sets a variable would report
# nothing on the first command after they did. What the hooks cost when the segment is hidden is
# one float subtraction and one comparison per command — see `_inzsh_duration_precmd`, which
# will not re-render a segment the last draw did not place.
#
# NO FORKS. `EPOCHREALTIME` is a parameter from `zsh/datetime`, a MODULE, and the arithmetic is
# the shell's own. `date +%s.%N` would cost a fork on every command line the user runs, and
# `time`, `times` and `$SECONDS` all answer a different question — CPU, or shell lifetime,
# rather than wall clock for one command.
#
# ---------------------------------------------------------------------------------------------
# WHAT IT DRAWS, and the rounding rule
#
#   9s        under a minute: whole seconds
#   2m 14s    under an hour: minutes and seconds
#   1h 3m     under a day: hours and minutes, and the seconds are dropped
#   1d 4h     a day or more: days and hours
#
# TWO UNITS, NEVER THREE, and the second is dropped when it is zero — `2m`, `1h`, `1d`. A
# duration in a prompt is read at a glance and compared with an expectation ("that took longer
# than I thought"); the third unit is precision nobody acts on and two more columns on a row
# that is already competing for them.
#
# THE ROUNDING IS TRUNCATION, on the smallest unit shown. `2m 14s` means the command ran for at
# least two minutes and fourteen seconds. Truncation rather than nearest, so the number is a
# floor and never overstates — a build reported as `1h 3m` did not take an hour and four
# minutes. It also means the transition happens where the reader expects it: the segment appears
# the instant the elapsed time reaches `INZSH_DURATION_MIN` and not half a second before.
#
# NO GLYPH, and this is not an oversight about the colour rule. "Colour is never the only
# signal" is about STATES — a state that only says `red` says nothing in monochrome. A duration
# is a MEASUREMENT, like the clock in `lib/segments/time.zsh`, and it carries its own meaning in
# its own characters: `2m 14s` reads identically with no colour at all. A mark in front of it
# would be decoration, and the unit letters are already the label.

zmodload -i zsh/datetime

# Declared, never assigned wholesale — `typeset -gA` over an existing association keeps what is
# in it. `_inzsh_left` and `_inzsh_right` belong to `lib/core/engine.zsh` and are declared here
# too so this file can be sourced on its own without creating a plain parameter by accident
# under `warn_create_global`; the precmd below reads them and never writes them.
typeset -gA _inzsh_segment_text _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role _inzsh_segment_importance
typeset -ga _inzsh_left _inzsh_right

# Registration.
#
#   rank 0       hidden until `INZSH_DURATION_RANK` asks for it.
#   text-muted   the semantic role. A duration is a fact about a command that has already
#                finished; it is worth having and it is not news.
#   importance 2 the middle of the ramp. Lower than a failure, higher than the furniture — when
#                it is on the row at all, it is because somebody wanted to read it.
_inzsh_segment_defaults[DURATION]=0
_inzsh_segment_fg_role[DURATION]=text-muted
_inzsh_segment_importance[DURATION]=2

# The floor, in whole seconds. Below it the segment is ABSENT — no block, no separator, no `0s`.
#
# Three is chosen against attention rather than against a clock: a prompt that reported a
# duration for every `cd` and every `ls` would put a number on the row that is the same number
# every time, which is the definition of a segment that carries no information. The commands
# worth timing are the ones that took long enough for you to have looked away.
#
# Restated here as well as registered, so the segment still has a floor when
# `lib/core/config.zsh` is not loaded — a half-assembled bundle, a spec that includes one file.
# `test/unit/config_registry_spec.sh` holds every such restatement equal to its registration.
typeset -gi _inzsh_duration_min_default=3

# The knob, registered where it is read. `int:0:` rather than `int:1:`: 0 is a meaningful
# setting — "show me every command, however short" — and it is the only way to ask for that.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_DURATION_MIN 'int:0:' 3
fi

# The timer's own state, and all of it.
#
#   running   1 between a preexec and the precmd that answers it. A flag rather than "is the
#             start non-empty", because 0.0 is a legitimate start value on a shell that has
#             just begun and an empty float is not a thing zsh has.
#   start     the mark, as a native float. Never read except by the freeze below.
#   elapsed   whole seconds, frozen. This is what the build renders, and what makes a repaint
#             mid-prompt draw the same number rather than a growing one: the git worker can
#             re-render this prompt seconds after it was first drawn, and a duration that ticked
#             upward while the user sat at the line would be a stopwatch, not a report.
typeset -gi _inzsh_duration_running=0
typeset -gF _inzsh_duration_start=0
typeset -gi _inzsh_duration_elapsed=0

# The floor as an integer, in REPLY. Never negative and never unreadable: an unregistered or
# invalid value lands on the restated default rather than on whatever the user typed.
_inzsh_duration_min() {
  emulate -L zsh

  local value=${INZSH_DURATION_MIN-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_DURATION_MIN
    value=$REPLY
  fi

  typeset -g REPLY=$_inzsh_duration_min_default
  [[ $value == <-> ]] && typeset -g REPLY=$value

  return 0
}

# `_inzsh_duration_mark [now]` — record the start. Called from preexec; the argument is the
# injection seam, so a spec can drive a whole command lifetime without one existing.
#
# The value is taken through ARITHMETIC rather than through string assignment, and that is not
# style. `$EPOCHREALTIME` is formatted with the locale's decimal separator on some builds, so a
# shell under a comma locale hands back `1785121585,25` — a string the next subtraction could
# not parse. In arithmetic the parameter is the double the module holds and the locale never
# enters into it. An injected value is validated against a dotted grammar first, because that
# one really is a string.
#
# Without the module there is no clock and there is no timing: the flag stays down and the
# segment is absent, which is the same answer `lib/segments/time.zsh` gives to the same loss.
_inzsh_duration_mark() {
  emulate -L zsh

  _inzsh_duration_running=0

  if [[ -n ${1-} ]]; then
    [[ $1 == <->(.<->|) ]] || return 0
    (( _inzsh_duration_start = $1 ))
  else
    (( ${+EPOCHREALTIME} )) || return 0
    (( _inzsh_duration_start = EPOCHREALTIME ))
  fi

  _inzsh_duration_running=1

  return 0
}

# `_inzsh_duration_freeze [now]` — the elapsed time, in whole seconds, into
# `_inzsh_duration_elapsed`. Called from precmd; the argument is the same seam.
#
# The flag is lowered whatever happens, so a prompt drawn without a command in front of it — the
# user pressed Enter on an empty line, or the shell has only just started — freezes 0 and the
# segment is absent. That is the case that makes the flag worth having: without it, the first
# prompt of a session would report the age of the shell.
#
# A negative interval is clamped to 0 rather than drawn. The clock can go backwards under NTP,
# and `1970-01-01` on a prompt because a time server stepped is worse than saying nothing.
_inzsh_duration_freeze() {
  emulate -L zsh

  local -i was=$_inzsh_duration_running
  _inzsh_duration_running=0
  _inzsh_duration_elapsed=0

  (( was )) || return 0

  local -F now=0
  if [[ -n ${1-} ]]; then
    [[ $1 == <->(.<->|) ]] || return 0
    (( now = $1 ))
  else
    (( ${+EPOCHREALTIME} )) || return 0
    (( now = EPOCHREALTIME ))
  fi

  # The subtraction is an arithmetic COMMAND rather than an arithmetic substitution, so that no
  # `$(` appears anywhere in this file. The structural check in the spec cannot tell `$((` from
  # `$(`, and a fork guard that has to carve out an exception is a fork guard with a hole in it.
  local -F delta=0
  (( delta = now - _inzsh_duration_start ))
  (( delta > 0 )) || return 0

  # Assignment into an integer parameter truncates toward zero, which IS the rounding rule
  # stated at the head of this file. Written as an arithmetic assignment rather than a
  # substitution so that no float ever becomes a string on the way.
  (( _inzsh_duration_elapsed = delta ))

  return 0
}

# `_inzsh_duration_format <seconds>` → REPLY. Status 1 and an empty REPLY for anything that is
# not a whole number of seconds.
#
# Two units at most, largest first, second dropped when it is zero. Integer arithmetic
# throughout — this runs on the render path, and the render path is arithmetic and parameter
# expansion.
_inzsh_duration_format() {
  emulate -L zsh

  typeset -g REPLY=

  [[ $1 == <-> ]] || return 1

  local -i total=$1
  local -i days=total/86400
  local -i hours=total%86400/3600
  local -i minutes=total%3600/60
  local -i seconds=total%60

  if (( days )); then
    typeset -g REPLY="${days}d"
    (( hours )) && REPLY+=" ${hours}h"
  elif (( hours )); then
    typeset -g REPLY="${hours}h"
    (( minutes )) && REPLY+=" ${minutes}m"
  elif (( minutes )); then
    typeset -g REPLY="${minutes}m"
    (( seconds )) && REPLY+=" ${seconds}s"
  else
    typeset -g REPLY="${seconds}s"
  fi

  return 0
}

# `_inzsh_segment_duration_build [seconds]` → `_inzsh_segment_text[DURATION]`.
#
# The argument is the injection seam and it is the whole of the segment's input: absent, it is
# the frozen elapsed the hooks computed. Nothing in this function reads a clock, and that is
# what makes it a pure formatter — the same seam `lib/segments/git.zsh` has, with two hooks on
# the far side of it rather than a background job.
#
# The entry is written on every path, empty where the segment has nothing to say, so a prompt
# that hid the block never inherits the previous prompt's number. Always status 0.
_inzsh_segment_duration_build() {
  emulate -L zsh

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[DURATION]=

  local elapsed=${1-$_inzsh_duration_elapsed}
  [[ $elapsed == <-> ]] || return 0

  _inzsh_duration_min
  local -i min=$REPLY

  (( elapsed >= min )) || return 0

  _inzsh_duration_format "$elapsed" || return 0

  # Per cent doubled, as everywhere: the fragment is spliced into PROMPT and prompt expansion
  # runs over it. Nothing here can produce one today — digits and four unit letters — so this is
  # defence rather than repair.
  _inzsh_segment_text[DURATION]=${REPLY//'%'/'%%'}

  return 0
}

# ---------------------------------------------------------------------------------------------
# The hooks
#
# preexec takes the command line in `$1`..`$3` and ignores all three: what is being timed is the
# gap, not the text, and reading the text would be one more thing to get wrong about quoting.

_inzsh_duration_preexec() {
  emulate -L zsh

  [[ -o interactive ]] || return 0

  _inzsh_duration_mark

  return 0
}

# precmd. THE ORDER THIS MUST BE REGISTERED IN IS PART OF THE CONTRACT, and it is the one thing
# about this file that cannot be inferred from reading it alone.
#
# `_inzsh_precmd` in `lib/core/hooks.zsh` captures `$?` and `$pipestatus` in its FIRST command,
# and the house rule is that nothing may be registered ahead of it. This hook is therefore
# installed AFTER `_inzsh_hooks_install`, and the entry point is where that is arranged.
#
# The rule is kept as an invariant rather than as a hope: nothing in this file ever writes
# `_inzsh_last_status` or `_inzsh_last_pipestatus`, and the spec asserts both the position in
# `precmd_functions` and the absence of those assignments. Two locks, because the failure they
# guard against is silent — an exit segment that shows 0 forever, with nothing else looking
# wrong.
#
# Registering after has a consequence, and the re-render below is the answer to it. `_inzsh_
# precmd` renders while it runs, which is before this hook has frozen anything, so the prompt it
# built carries the PREVIOUS command's duration. Every precmd function runs before zsh expands
# PROMPT, though, so a later hook that reassigns it still reaches THIS prompt — which is exactly
# the property `lib/segments/git-async.zsh` relies on for the same reason. So: freeze, rebuild,
# and re-render only if the fragment changed AND the last draw actually placed this segment.
#
# That second condition is what keeps a hidden segment free. At rank 0 the engine never puts
# DURATION on either side, so a five-second command updates a string nobody is drawing and
# stops there — no second render, no measurable cost on a prompt that shows none of this.
_inzsh_duration_precmd() {
  emulate -L zsh

  [[ -o interactive ]] || return 0

  _inzsh_duration_freeze

  (( ${+functions[_inzsh_segment_duration_build]} )) || return 0

  local before=${_inzsh_segment_text[DURATION]-}
  _inzsh_segment_duration_build
  [[ ${_inzsh_segment_text[DURATION]-} != $before ]] || return 0

  (( ${_inzsh_left[(Ie)DURATION]} || ${_inzsh_right[(Ie)DURATION]} )) || return 0

  (( ${+functions[_inzsh_render]} )) && _inzsh_render

  return 0
}

# Attach. Idempotent by delegation rather than by a flag of our own: `add-zsh-hook` already
# refuses to add a function that is present in the array, so installing twice registers once —
# and a private flag would also refuse to REPAIR a registration that a plugin manager or a
# stray `precmd_functions=()` had removed.
#
# `autoload -Uz` lives here rather than at source time so that sourcing this file changes
# nothing at all. Both directions do it, because uninstalling is legitimate in a shell that
# never installed.
_inzsh_duration_install() {
  emulate -L zsh

  [[ -o interactive ]] || return 0

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _inzsh_duration_preexec
  add-zsh-hook precmd  _inzsh_duration_precmd

  return 0
}

# Let go, and stop the timer with it. Unguarded on purpose, exactly as `lib/core/hooks.zsh` is:
# a shell that somehow acquired these must be able to shed them, whatever it now reports about
# being interactive. Removing a hook that was never registered is a no-op, not an error.
_inzsh_duration_uninstall() {
  emulate -L zsh

  autoload -Uz add-zsh-hook
  add-zsh-hook -d preexec _inzsh_duration_preexec
  add-zsh-hook -d precmd  _inzsh_duration_precmd

  _inzsh_duration_running=0
  _inzsh_duration_elapsed=0

  return 0
}
