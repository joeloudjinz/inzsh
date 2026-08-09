# InZsh — the exit-status segment. The reason `lib/core/hooks.zsh` captures `$?` and
# `$pipestatus` on the very first line of precmd: everything below reads that capture, and
# nothing here ever reads `$?` itself. By the time a segment runs, `$?` is the status of
# whatever the render path did last, which is always 0 and always a lie.
#
# Two rules shape what it draws.
#
#   Absent on success.  A zero status writes nothing at all — no block, no separator, no
#   `✓`. A calm prompt says nothing when nothing is wrong, and the failure is then the only
#   thing on the line that was not there a moment ago.
#
#   Colour is never the only signal.  A failure carries the `✕` glyph as well as the
#   `negative` role, so the segment reads in monochrome, in a screenshot, and for a viewer who
#   cannot separate the two hues. The role is registered rather than drawn — the renderer
#   colours the fragment — so this file emits plain text and no escape of its own.
#
# The whole build is parameter expansion and arithmetic: it runs before every prompt, and the
# render path does not fork.

# Registration. `typeset -gA` over an existing association keeps what is in it, so re-sourcing
# the theme re-registers over the same three entries rather than resetting anybody's map — the
# maps themselves are declared in `lib/core/engine.zsh` and `lib/core/render.zsh`, and declared
# again here so that this file is independently sourceable and cannot create a plain array by
# accident under `warn_create_global`.
#
#   rank -1      the rightmost segment. A failure belongs at the end of the line, where the eye
#                lands after reading the command that produced it.
#   negative     the semantic role, never a ramp name and never a hex value.
#   importance 1 the top of the ramp: if any segment on the row is worth raising, it is this one.
typeset -gA _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role
typeset -gA _inzsh_segment_bg_role
typeset -gA _inzsh_segment_importance _inzsh_segment_priority

_inzsh_segment_defaults[RETVAL]=70
_inzsh_segment_fg_role[RETVAL]=negative
_inzsh_segment_importance[RETVAL]=1
_inzsh_segment_priority[RETVAL]=30

# The fill `INZSH_SURFACE_MODE=hue` gives it — see `_inzsh_render_hues`. The `negative` FILL,
# which is the same statement the foreground above makes, made louder: this block only exists
# when something failed. `on-negative` arrives with the fill, so the ink inverts rather than
# staying madder-on-madder.
_inzsh_segment_bg_role[RETVAL]=negative

# The failure mark. The glyph itself is `_inzsh_glyph[error]` in `lib/core/tokens.zsh`, which is
# where every mark the theme draws lives, along with the byte-spelling and the locale fallback
# this file used to carry alone. A segment with a literal of its own would have been the fourth
# copy of the same lesson, and the rule the copies existed to work around now has one home.
#
# Read at source time and guarded, with `x` assigned first. The entry point sources the token
# layer well above this file, but a retval segment that came up without one must still carry a
# signal that is not colour: `x` is one byte, one column, and legible on a terminal that would
# have drawn the glyph as mojibake.
typeset -g _inzsh_retval_glyph='x'
if [[ ${(t)_inzsh_glyph} == association* && -n ${_inzsh_glyph[error]} ]]; then
  _inzsh_retval_glyph=${_inzsh_glyph[error]}
fi

# The separator between pipeline stages. `|` on purpose: it is what the user typed to build the
# pipeline, it is ASCII so it needs no font and no locale, and it is deliberately NOT a
# powerline glyph — those belong to the renderer's chaining and a segment that carried one would
# read as a block boundary that is not there.
typeset -g _inzsh_retval_pipe_sep='|'

# Is `$1` a status this file will draw? Non-negative digits and nothing else — no sign, no
# spaces, no float. Anything else is not a status and the segment stays silent rather than
# painting a failure out of a value it could not read.
_inzsh_retval_readable() {
  emulate -L zsh

  [[ $1 == <-> ]]
}

# How a status reads, in REPLY: `130` becomes `SIGINT`, everything else stays the number.
#
# THE DECISION, and it is now the DEFAULT of a knob rather than the only behaviour: a status
# above 128 is rendered as the SIGNAL NAME where zsh knows one, never as the number and never as
# both. `✕ 130` is honest but it is an encoding — the user has to know that shells report a
# signal as 128 + n, and then which n `2` is — while `✕ SIGINT` is the fact itself. The number
# is recoverable from the name; the name is not recoverable from the number without a table the
# reader has to be carrying. A status that is genuinely an exit code above 128 is misread by
# this rule, which is the price: the ambiguity is in the convention, not in the rendering, and
# the far commoner case by orders of magnitude is the signal.
#
# `INZSH_RETVAL_SIGNAL=number` takes the other side of that trade — for the reader who greps
# logs by code and would rather undo the encoding themselves. Anything unreadable is the
# default, which is the name and the argument above.
#
# The table is zsh's own `signals` parameter, so nothing here transcribes a signal list that
# would then have to track a platform. Its shape is the one piece of knowledge required: index 1
# is the pseudo-trap `EXIT`, the real signals run from index 2, and the pseudo-traps `ZERR` and
# `DEBUG` are appended at the end. Both ends are excluded by the bound AND by name, so a zsh
# that grew a third pseudo-trap would fall back to the number rather than name a signal wrongly.
_inzsh_retval_signal() {
  emulate -L zsh
  setopt extended_glob

  typeset -g REPLY=$1
  _inzsh_retval_readable "$1" || return 0

  # The knob, read before the table is consulted. `_inzsh_config_get` answers in REPLY, so the
  # status is put back afterwards; only the exact word `number` switches, which is what the
  # registered enum validates and what a segment sourced without the config layer repeats here.
  local want=${INZSH_RETVAL_SIGNAL-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_RETVAL_SIGNAL
    want=$REPLY
    typeset -g REPLY=$1
  fi
  [[ $want == number ]] && return 0

  local -i code=$1
  (( code > 128 )) || return 0

  local -i idx=code-127
  (( idx >= 2 && idx <= ${#signals} - 2 )) || return 0

  local name=${signals[idx]}
  [[ $name == [A-Z][A-Z0-9]# && $name != (EXIT|ZERR|DEBUG) ]] || return 0

  typeset -g REPLY=SIG$name

  return 0
}

# `_inzsh_segment_retval_build [status] [pipestatus…]` → `_inzsh_segment_text[RETVAL]`.
#
# The arguments are the injection seam. With none, the values come from the capture in
# `lib/core/hooks.zsh`; with some, they are the caller's, which is how a spec pins a pipeline
# that never ran. `$?` is not read here under any circumstance.
#
# One argument is a bare status and is treated as a one-stage pipeline, so a caller that knows
# only the status is not obliged to invent a `pipestatus` for it.
#
# What gets drawn:
#
#   every stage zero          nothing. The entry is written EMPTY, which every layer already
#                             reads as absent — no block and no separator.
#   one stage, non-zero       `✕ 1` — the glyph and the status.
#   several stages, any       `✕ 1|0|127` — the WHOLE chain, in the order the stages ran, even
#   of them non-zero          where the last one succeeded. A pipeline whose final command
#                             returned 0 can still have failed meaningfully, and the status
#                             alone cannot say so.
#
# Unreadable input costs the segment and never the prompt: a status that is not a number leaves
# the segment absent, and a `pipestatus` with an unreadable stage in it falls back to the status
# alone rather than drawing a chain that is partly guesswork.
_inzsh_segment_retval_build() {
  emulate -L zsh

  # The mark, re-read from the table on every build so an `INZSH_GLYPH_ERROR` set at one prompt
  # has moved by the next — the render core re-resolves the table per draw, and a source-time
  # copy would keep the mark the theme loaded with. The copy above stays as the fallback for a
  # shell with no table at all.
  if [[ ${(t)_inzsh_glyph} == association* && -n ${_inzsh_glyph[error]} ]]; then
    typeset -g _inzsh_retval_glyph=${_inzsh_glyph[error]}
  fi

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[RETVAL]=

  local code
  local -a stages
  if (( $# )); then
    code=$1
    shift
    stages=("$@")
  else
    code=${_inzsh_last_status-0}
    stages=("${_inzsh_last_pipestatus[@]}")
  fi
  (( ${#stages} )) || stages=("$code")

  _inzsh_retval_readable "$code" || return 0

  local stage
  local -i failed=0
  for stage in "${stages[@]}"; do
    if ! _inzsh_retval_readable "$stage"; then
      stages=("$code")
      break
    fi
    (( stage )) && failed=1
  done

  # Whether the whole chain is drawn at all. The chain exists because `$?` is only the last
  # stage; `INZSH_RETVAL_PIPELINE` off is choosing to trust `$?` after all, so what is drawn is
  # exactly what the status says — including nothing when the status is 0. Only an explicit off
  # value switches it off: a typo may not silently hide a failed stage.
  local -i chain=1
  local want=${INZSH_RETVAL_PIPELINE-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_RETVAL_PIPELINE
    want=$REPLY
  fi
  [[ ${(L)want} == (0|false|no|off) ]] && chain=0

  # A single stage says nothing the status does not, so the chain is drawn only where there is
  # more than one of them and at least one failed. Otherwise the status is the whole story.
  local -a shown
  if (( chain && ${#stages} > 1 && failed )); then
    for stage in "${stages[@]}"; do
      _inzsh_retval_signal "$stage"
      shown+=$REPLY
    done
  else
    (( code )) || return 0
    _inzsh_retval_signal "$code"
    shown=($REPLY)
  fi

  _inzsh_segment_text[RETVAL]="$_inzsh_retval_glyph ${(pj:$_inzsh_retval_pipe_sep:)shown}"

  return 0
}

# The knobs this segment reads, declared beside the code that reads them — the pattern
# `lib/segments/git.zsh` follows. Guarded, because this file is independently sourceable. Both
# defaults are the design decisions argued above, written down where a `doctor` can find them.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_RETVAL_SIGNAL   'enum:name|number' name
  _inzsh_config_register INZSH_RETVAL_PIPELINE bool               1
fi
