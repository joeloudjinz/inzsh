# InZsh — terminal capability detection. What can this terminal do, asked once, at source time,
# before anything draws.
#
# One global per question, and the value vocabulary is part of the answer:
#
#   `_inzsh_color_depth`  truecolor | 256 | 8   how many colours
#   `_inzsh_multibyte`    1 | 0                 whether a non-ASCII glyph is safe to write
#   `_inzsh_nerd_font`    1 | 0 | unknown       whether the private-use glyphs will draw
#   `_inzsh_tmux`         1 | 0                 inside a multiplexer pane
#   `_inzsh_tmux_rgb`     1 | 0 | unknown       whether 24-bit colour gets out of that pane
#
# Four rules hold across all of them.
#
#   No subprocesses. This file is sourced on every shell start, and a fork there is a cost every
#   prompt in the session never gets back. `tput`, `locale` and `fc-list` would each answer a
#   question below and each of them is a fork; `zsh/terminfo` is a module, loaded in-process,
#   and the environment is free to read.
#
#   Recompute, never cache. Every detector is independently callable and answers from the
#   environment as it is now — an existing value is a previous answer, not a preference.
#
#   Degrade downward. A question that cannot be answered lands on the smaller, plainer,
#   more portable side. Where "no" would itself be a claim, the answer is `unknown` instead:
#   three values are more honest than two guesses.
#
#   Overrides are validated, then obeyed or ignored — never half-obeyed. A typo in `INZSH_*`
#   falls through to detection, because an ignored override leaves a working prompt and an
#   obeyed typo does not.
#
# ---------------------------------------------------------------------------------------------
# Colour depth
# ---------------------------------------------------------------------------------------------

# The answer lands in `_inzsh_color_depth`, one of `truecolor`, `256` or `8`, and the token
# layer swaps its value table on it. Detection runs before the token layer's final resolve.
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

# ---------------------------------------------------------------------------------------------
# Multibyte — whether a non-ASCII glyph is safe to write
# ---------------------------------------------------------------------------------------------

# `_inzsh_multibyte` is 1 in a UTF-8 locale and 0 outside one, and the difference is not
# cosmetic. Outside a multibyte locale zsh cannot even PARSE a `$'…'` character literal —
# the file holding it fails to load with `character not in range`, taking every function in it
# with it — and `${(m)#...}` counts bytes rather than cells, so every width the layout computes
# for a non-ASCII glyph is wrong. A theme that assumes UTF-8 breaks a `LC_ALL=C` shell at source
# time. This flag is what stops it.
#
# The locale comes out of the environment in the order zsh itself resolves it: `LC_ALL` wins
# outright, then `LC_CTYPE` — the category that governs character handling — then `LANG`. Empty
# counts as unset at every step, which is what setlocale does with an empty string. The `locale`
# command would give the resolved answer and a fork with it; three variables give it for free.
#
# The test is the codeset spelling, case-insensitively, because `UTF-8` and `utf8` are the two
# ways systems write it. `C`, `POSIX` and an empty environment are single-byte, and so is
# anything unrecognised — an ASCII fallback is legible everywhere and mojibake is not.
_inzsh_detect_multibyte() {
  emulate -L zsh

  typeset -g _inzsh_multibyte

  # For a terminal that lies, or a locale whose name does not spell its codeset the usual way.
  case $INZSH_MULTIBYTE in
    (1|0) _inzsh_multibyte=$INZSH_MULTIBYTE; return 0 ;;
  esac

  local name=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
  case ${(L)name} in
    (*utf-8*|*utf8*) _inzsh_multibyte=1 ;;
    (*)              _inzsh_multibyte=0 ;;
  esac

  return 0
}

# ---------------------------------------------------------------------------------------------
# Nerd Font — whether the private-use glyphs will draw
# ---------------------------------------------------------------------------------------------

# `_inzsh_nerd_font` is 1, 0 or `unknown`, and `unknown` is the honest default rather than a
# failure to try. Nothing inside a shell can prove a font is installed: the glyphs live in the
# Unicode private-use area, the terminal picks the font that covers them, and the tools that
# could look — `fc-list`, `fc-match` — are forks this file may not make, on a machine that is
# not necessarily the one drawing the pixels. Any claim stronger than that is invented.
#
# So the ladder is short, and it never invents a 1:
#
#   1. `INZSH_NERD_FONT` — the user can see their own screen, which outranks every inference
#      below. Validated `1`/`0`; anything else falls through.
#   2. The terminal program, and only when the program BUNDLES the Nerd Font symbol range and
#      falls back to it whatever font the user configured. That is a property of the
#      application, so the environment naming the application really is the evidence.
#   3. `unknown`.
#
# There is deliberately no rung that answers 0 from the environment. Every terminal outside the
# table can still draw the glyphs the moment a Nerd Font is installed and selected, and a
# missing-font report about a font that is not missing is the more irritating half of being
# wrong.
#
# What the theme DOES about a missing font is not decided here. The policy is detect-and-warn
# and the warning belongs to `doctor`; this function answers the question and stops.
_inzsh_detect_nerd_font() {
  emulate -L zsh

  typeset -g _inzsh_nerd_font

  case $INZSH_NERD_FONT in
    (1|0) _inzsh_nerd_font=$INZSH_NERD_FONT; return 0 ;;
  esac

  # Three places a terminal writes its own name, most direct first. `TERM_PROGRAM` is the usual
  # one; `LC_TERMINAL` is the one ssh forwards, which is the case where the font is the local
  # terminal's business and the shell asking is a continent away; `TERMINAL_EMULATOR` is what
  # the JetBrains terminal sets.
  local program=${TERM_PROGRAM:-${LC_TERMINAL:-${TERMINAL_EMULATOR:-}}}

  # Ghostty and WezTerm both ship the symbol range inside the application and fall back to it
  # for glyphs the configured font lacks, so the program name is the whole proof.
  case ${(L)program} in
    (ghostty|wezterm) _inzsh_nerd_font=1; return 0 ;;
  esac

  _inzsh_nerd_font=unknown
  return 0
}

# ---------------------------------------------------------------------------------------------
# tmux — the pane, and whether 24-bit colour gets out of it
# ---------------------------------------------------------------------------------------------

# Two answers. `_inzsh_tmux` is 1 inside a pane and 0 outside it, read from `$TMUX`, which the
# server sets in every pane and nothing else sets. `_inzsh_tmux_rgb` is whether 24-bit colour
# reaches the terminal outside the pane, and it is `unknown` more often than not.
#
# It has to be. That answer lives in tmux's own configuration — `terminal-features` from 3.2,
# `terminal-overrides` before it — and reading it means `tmux show-options`, a fork this file
# may not make. What is left is what the pane's own environment shows:
#
#   1        the pane's terminfo entry advertises direct colour: the `RGB`/`Tc` capability when
#            this zsh exposes extended ones, or a colour count in the millions, which is how a
#            `*-direct` entry says the same thing on every build. A pane running one of those
#            is a pane already configured for passthrough.
#   0        the entry advertises fewer than 256 colours. Nothing 24-bit survives a pane that
#            small, however capable the terminal outside it.
#   unknown  everything else — including the ordinary `tmux-256color` pane, which is most of
#            them.
#
# `COLORTERM` is deliberately not a rung. tmux hands the server's environment to new panes, so
# a pane inherits the OUTER terminal's advertisement: real evidence about the terminal, none at
# all about whether tmux passes 24-bit through to it. Reading it as a yes is exactly how a
# multiplexer that is quietly flattening colour gets a clean bill of health, which is the one
# thing this answer exists to prevent.
#
# Outside a pane `_inzsh_tmux_rgb` is `unknown` rather than 0: the question is about a
# multiplexer that is not there, and a 0 would read as a fault.
_inzsh_detect_tmux() {
  emulate -L zsh

  typeset -g _inzsh_tmux _inzsh_tmux_rgb

  _inzsh_tmux=0
  _inzsh_tmux_rgb=unknown
  [[ -n $TMUX ]] || return 0
  _inzsh_tmux=1

  local colors=
  if zmodload zsh/terminfo 2>/dev/null; then
    colors=${terminfo[colors]}

    # Extended capabilities are not in every zsh's capability table, so their absence proves
    # nothing at all and their presence is taken at face value.
    if (( ${+terminfo[RGB]} || ${+terminfo[Tc]} )); then
      _inzsh_tmux_rgb=1
      return 0
    fi
  fi

  # `<->` for the same reason as above: an empty or non-numeric capability is a missing answer,
  # and a missing answer stays `unknown` rather than turning into either verdict.
  if [[ $colors == <-> ]]; then
    if (( colors >= 16777216 )); then
      _inzsh_tmux_rgb=1
    elif (( colors < 256 )); then
      _inzsh_tmux_rgb=0
    fi
  fi

  return 0
}

# Every capability resolved by the time the file finishes sourcing. Order is irrelevant — no
# detector reads another's answer — and each stays callable on its own afterwards.
_inzsh_detect_color_depth
_inzsh_detect_multibyte
_inzsh_detect_nerd_font
_inzsh_detect_tmux
