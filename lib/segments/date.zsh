# InZsh — the calendar segment. Which DAY is this, as opposed to which minute.
#
# It is the clock's companion and deliberately not part of it. `lib/segments/time.zsh` answers
# "when did this command finish", which changes between every pair of prompts; this answers
# "what is today", which changes once a day and is therefore reference material of a much
# quieter kind. Two segments rather than one long format string, because they have different
# ranks, different widths and different reasons to be hidden — and because a user who wants the
# date and not the clock, or the clock and not the date, should not have to edit a format to
# say so.
#
# IT SHIPS OFF. `_inzsh_segment_defaults[DATE]=0` is rank 0, which the engine reads as hidden:
# the segment is complete, tested and documented, and draws nothing until an
# `INZSH_DATE_RANK` asks for it. That is the whole point of the optional set. A prompt that
# spends a dozen columns telling you what your calendar, your lock screen and your notifications
# have all told you already is a prompt that has stopped being restrained, and the restraint is
# the brand. Off by default costs it nothing and costs the people who do want it one line.
#
# The instant is INJECTED, the same seam the clock is built on and for the same reason:
# `_inzsh_segment_date_build 1785121585` renders that day and not this one, so an example can
# assert a string rather than compare a clock to a second reading of itself.
#
# `strftime` comes from `zsh/datetime`, a MODULE — a builtin call, not a fork. The `date`
# command is not an option here at any price: this runs before every prompt, and the render path
# does not fork.

zmodload -i zsh/datetime

# Registration. `typeset -gA` over an existing association keeps what is in it, so this file is
# independently sourceable and re-sourcing re-registers over the same keys rather than doubling
# anything.
#
#   rank 0       hidden. Not a default anybody is expected to keep — a default nobody has to
#                undo.
#   text-muted   the semantic role. The date is true of every prompt in the day equally, and a
#                value that changes once between midnights has no business drawing attention.
#   importance 3 the bottom of the ramp, for the same reason. `alternate` and `flat` ignore it.
typeset -gA _inzsh_segment_text _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role _inzsh_segment_bg_role _inzsh_segment_importance

_inzsh_segment_defaults[DATE]=0
_inzsh_segment_fg_role[DATE]=text-muted
_inzsh_segment_importance[DATE]=3

# The fill `INZSH_SURFACE_MODE=hue` gives it — see `_inzsh_render_hues`. The neutral wash: quiet,
# no `on-` twin so the muted ink above survives, and a different role from the clock beside it so
# the two never merge into one long block.
_inzsh_segment_bg_role[DATE]=neutral-wash

# The format `INZSH_DATE_FORMAT` falls back to. Held in a variable rather than repeated, because
# it is used twice — once as the registered default and once as the retry after a user's format
# produced nothing usable.
#
# SPELLED OUT, on purpose. `2026-07-27` is what a filename wants; a prompt is read by a person
# who already knows roughly what month it is and is looking for the WEEKDAY — which is the one
# field of a date that a working day actually turns on, and the one an all-numeric format hides
# behind arithmetic. The clock sits to its right and carries the precision, so this side is free
# to be the readable half. `%-d` is the unpadded day: `Thursday, 1 January` rather than
# `Thursday, 01 January`, since a leading zero on a day is a filename habit too.
typeset -g _inzsh_date_format_default='%A, %-d %B %Y'

# The knob, registered where it is read, with that same default. `any` on purpose, exactly as
# `INZSH_TIME_FORMAT` is: `strftime` is the only authority on what a format means, the set of
# conversions belongs to the C library and to zsh's own `ztrftime`, and a registry that policed
# it would refuse formats that work on the machine it is running on. The validation this segment
# does is on the RESULT, below, which is the only honest place for it.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_DATE_FORMAT any "$_inzsh_date_format_default"
fi

# `_inzsh_date_render <format> <epoch>` → REPLY, empty when the format produced nothing this
# segment is willing to draw.
#
# Two ways to come back unusable, and they are the same two the clock rejects. Empty is the
# obvious one — `INZSH_DATE_FORMAT=` or a format of nothing but unsupported conversions. Control
# characters are the other, and they are why the check exists at all: a format of `%n` renders a
# NEWLINE, and a newline in a prompt fragment breaks the row the renderer has just measured.
# Anything with one in it is treated exactly as an empty result — not an error, just not used.
#
# THIS IS THE SECOND COPY of a rule `lib/segments/time.zsh` already states, and that is a
# deliberate and named cost. A segment imports no sibling segment — the load order in the entry
# point is a list, not a graph, and a segment that reached into another one would make it one —
# so the shared home for this would be `lib/core/`, and moving it there is a core change this
# file does not own. When a third segment renders a `strftime` format, that is the move.
_inzsh_date_render() {
  emulate -L zsh

  typeset -g REPLY=

  local format=$1 epoch=$2 rendered=
  [[ -n $format ]] || return 1

  strftime -s rendered "$format" $epoch 2>/dev/null || return 1
  [[ -n $rendered ]] || return 1
  [[ $rendered == *[[:cntrl:]]* ]] && return 1

  typeset -g REPLY=$rendered

  return 0
}

# `_inzsh_segment_date_build [epoch]` → `_inzsh_segment_text[DATE]`.
#
# The epoch is the injection seam; absent, it is the live one. An epoch that is not a whole
# number of seconds is not an instant, and the fallback is the live clock rather than an empty
# segment — the argument is the theme's own to pass, so a bad one is a bug here, and a user
# still gets their prompt while it is being found.
#
# The zone and the language are the shell's. Nothing in this file sets `TZ`, reads it, or names
# a month: the C library owns those rules, DST and locale included, which is why the instant is
# carried all the way down to `strftime` rather than being turned into a civil date any earlier.
#
# A per cent in the RENDERED output is doubled on the way out. The fragment is spliced into
# PROMPT and prompt expansion runs over it, so a format of `%%` — or any conversion whose
# expansion contains a per cent — would otherwise reach the screen as an escape the user never
# wrote. `_inzsh_width` already reads `%%` as one column, so the doubling costs no accuracy.
#
# The entry is written on every path, empty where there is nothing to say, so a prompt that hid
# the block never inherits the previous prompt's text. Always status 0.
_inzsh_segment_date_build() {
  emulate -L zsh

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[DATE]=

  # Without the module there is no `strftime` and no `$EPOCHSECONDS`, and both checks below
  # already answer that: an empty epoch fails the grammar, and a `strftime` that is not a
  # builtin fails `_inzsh_date_render` with its diagnostic already redirected. A calendar that
  # cannot be read is a segment that is not drawn.
  local epoch=${1-${EPOCHSECONDS-}}
  [[ $epoch == (|-)<-> ]] || epoch=${EPOCHSECONDS-}
  [[ $epoch == (|-)<-> ]] || return 0

  local format=${INZSH_DATE_FORMAT:-$_inzsh_date_format_default}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_DATE_FORMAT
    format=${REPLY:-$_inzsh_date_format_default}
  fi

  if ! _inzsh_date_render "$format" "$epoch"; then
    _inzsh_date_render "$_inzsh_date_format_default" "$epoch" || return 0
  fi

  _inzsh_segment_text[DATE]=${REPLY//'%'/'%%'}

  return 0
}
