# InZsh — terminal capability detection. Answers one question: how many colours can we use?
#
# The answer lands in `_inzsh_color_depth`, one of `truecolor`, `256` or `8`, and the token
# layer swaps its value table on it. Detection runs once, at source time, before the token
# layer's final resolve.
#
# No subprocesses. `tput` would be the obvious way to ask terminfo how many colours a terminal
# has and it is exactly the way we may not: this file is sourced on every shell start, and a
# fork there is a cost every prompt in the session never gets back. `zsh/terminfo` is a module,
# loaded in-process, and gives the same number.
#
# The ladder, most trustworthy first:
#
#   1. `INZSH_COLOR_DEPTH` — the escape hatch. Terminal capability detection is guesswork
#      dressed as a lookup; multiplexers, remote sessions and terminals that lie about `TERM`
#      all exist. A user who can see their own screen outranks anything we can infer. Only the
#      three known values are honoured — an unrecognised setting is ignored rather than
#      obeyed, because a typo must not silently flatten the palette.
#   2. `COLORTERM` — the de-facto truecolor advertisement. terminfo has no widely-populated
#      entry for 24-bit support, so a terminal that can do it says so here instead.
#   3. `terminfo[colors]` — the honest number, when there is one.
#   4. 8. Every guess we cannot make degrades downward, never upward. An 8-colour prompt on a
#      256-colour terminal is plain; a 256-colour prompt on an 8-colour terminal is garbage.
#
# `TERM=linux` — the kernel console — reports 8 and must land on 8. It is the case that makes
# the conservative floor visible: it is not an unknown terminal, it is a known small one.

# Recompute `_inzsh_color_depth` from the environment. Always recomputes: an existing value is
# a previous answer, not a preference, and re-sourcing after `TERM` changes must move it. The
# only input that survives is the `INZSH_COLOR_DEPTH` override, which is read fresh each time.
_inzsh_detect_color_depth() {
  emulate -L zsh

  typeset -g _inzsh_color_depth

  # The user's word, if it is one of the three we understand. Anything else falls through to
  # detection — an ignored override leaves a working prompt, an obeyed typo does not.
  case $INZSH_COLOR_DEPTH in
    (truecolor|256|8) _inzsh_color_depth=$INZSH_COLOR_DEPTH; return 0 ;;
  esac

  # Truecolor is advertised, never discovered. Lowercased because the value is written by
  # terminals, not by a standard, and both spellings appear in both cases in the wild.
  case ${(L)COLORTERM} in
    (truecolor|24bit) _inzsh_color_depth=truecolor; return 0 ;;
  esac

  # `zsh/terminfo` populates `$terminfo` from the entry for the current `TERM`. An unknown or
  # absent `TERM` leaves the array empty rather than failing, so the guard is on the value.
  local colors=
  if zmodload zsh/terminfo 2>/dev/null; then
    colors=${terminfo[colors]}
  fi

  # `<->` matches digits only, so a non-numeric or empty capability cannot reach the
  # comparison. Both unknowns — no module, no entry — land on the same floor as a small
  # terminal, which is the point.
  if [[ $colors == <-> ]] && (( colors >= 256 )); then
    _inzsh_color_depth=256
  else
    _inzsh_color_depth=8
  fi

  return 0
}

_inzsh_detect_color_depth
