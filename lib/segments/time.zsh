# InZsh — the clock segment. The time the prompt was drawn, which is to say the time the last
# command finished, which is the only reason a prompt carries one at all: scrolled back, it is a
# timestamp on every command in the session.
#
# The instant is INJECTED. `_inzsh_segment_time_build 1785121585` renders that second and not
# this one, which is the same seam `lib/salah/calc.zsh` is built on and for the same reason — a
# clock that reads itself can only be tested against itself. Absent an argument it falls back to
# the live `$EPOCHSECONDS`, so the seam costs the caller nothing.
#
# `strftime` comes from `zsh/datetime`, a MODULE — a builtin call, not a fork. `date` is not an
# option here at any price: this runs before every prompt, and the render path does not fork.

zmodload -i zsh/datetime

# Registration. See `lib/segments/retval.zsh` for why the maps are re-declared rather than
# assumed: `typeset -gA` keeps what is already in an association, so re-sourcing re-registers
# over the same three entries and doubles nothing.
#
#   rank -2      just inside the exit status, at the right edge. A clock is reference material,
#                not news, so it sits where the eye passes over it rather than lands on it.
#   text-muted   the semantic role. Quiet by design — it is true of every prompt equally, and a
#                value that never varies has no business drawing attention.
#   importance 3 the bottom of the ramp, for the same reason.
typeset -gA _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role
typeset -gA _inzsh_segment_bg_role
typeset -gA _inzsh_segment_importance _inzsh_segment_priority

_inzsh_segment_defaults[TIME]=-10
_inzsh_segment_fg_role[TIME]=text-muted
_inzsh_segment_importance[TIME]=3
_inzsh_segment_priority[TIME]=80

# The fill `INZSH_SURFACE_MODE=hue` gives it — see `_inzsh_render_hues`. A surface, because the
# reasoning above does not stop being true in a colourful mode: a value that never varies has no
# business drawing attention, and the accent block it sits beside is the one that should.
_inzsh_segment_bg_role[TIME]=surface-deep

# The format `INZSH_TIME_FORMAT` falls back to: hours and minutes, 24-hour, zero-padded. Held in
# a variable rather than repeated, because it is used twice — once as the default and once as
# the retry after a user's format produced nothing usable.
typeset -g _inzsh_time_format_default='%H:%M'

# The knob, registered where it is read, with that same default. `any` on purpose: `strftime` is
# the only authority on what a format means and the set of conversions is the C library's, so a
# registry that policed it would refuse formats that work on the machine it is running on. The
# validation this segment does is on the RESULT, below, which is the only honest place for it.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_TIME_FORMAT any "$_inzsh_time_format_default"
fi

# `_inzsh_time_render <format> <epoch>` → REPLY, empty when the format produced nothing this
# segment is willing to draw.
#
# Validation is deliberately LOOSE: `strftime` is the only authority on what a format means, the
# set of conversions is the C library's and differs between platforms, and a theme that policed
# it would reject formats that work on the machine it is running on. So the format is simply
# TRIED, and judged on what came back.
#
# Two ways to come back unusable. Empty is the obvious one — `INZSH_TIME_FORMAT=` or a format of
# nothing but unsupported conversions. Control characters are the other, and they are the reason
# this check exists at all: a format of `%n` renders a NEWLINE, and a newline in a prompt
# fragment breaks the row the renderer just measured. Anything with one in it is treated exactly
# as an empty result — not an error, just not used.
_inzsh_time_render() {
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

# `_inzsh_segment_time_build [epoch]` → `_inzsh_segment_text[TIME]`.
#
# The epoch is the injection seam; absent, it is the live one. An epoch that is not a whole
# number of seconds is not a time, and the fallback is the live clock rather than an empty
# segment — the argument is the theme's own to pass, so a bad one is a bug here and a user still
# gets their prompt while it is being found.
#
# The zone is the shell's. Nothing in this file sets `TZ`, reads it, or computes an offset: the
# C library owns those rules, DST included, which is why the instant is carried all the way down
# to `strftime` rather than being turned into a civil time any earlier.
#
# A per cent in the RENDERED output is doubled on the way out. The fragment is spliced into
# PROMPT and prompt expansion runs over it, so a format of `%%` — or any conversion whose
# expansion contains a per cent — would otherwise reach the screen as an escape the user never
# wrote. `_inzsh_width` already reads `%%` as one column, so the doubling costs no accuracy.
_inzsh_segment_time_build() {
  emulate -L zsh

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[TIME]=

  # Without the module there is no `strftime` and no `$EPOCHSECONDS`, and both of the checks
  # below already answer that: an empty epoch fails the grammar, and a `strftime` that is not a
  # builtin fails `_inzsh_time_render` with its diagnostic already redirected. A clock that
  # cannot be read is a segment that is not drawn — it is not an error, and it is certainly not
  # a prompt that refuses to appear. A third guard here would be a branch nothing can reach.
  local epoch=${1-${EPOCHSECONDS-}}
  [[ $epoch == (|-)<-> ]] || epoch=${EPOCHSECONDS-}
  [[ $epoch == (|-)<-> ]] || return 0

  local format=${INZSH_TIME_FORMAT:-$_inzsh_time_format_default}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_TIME_FORMAT
    format=${REPLY:-$_inzsh_time_format_default}
  fi

  if ! _inzsh_time_render "$format" "$epoch"; then
    _inzsh_time_render "$_inzsh_time_format_default" "$epoch" || return 0
  fi

  _inzsh_segment_text[TIME]=${REPLY//'%'/'%%'}

  return 0
}
