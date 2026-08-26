# InZsh — rows: which segment draws on which line, and where the input marker sits relative
# to what got drawn.
#
# A ROW is a pair of ordered segment lists, a left side and a right side. Rows are numbered from
# 1, top down, and the numbers are SORT KEYS, not slots: a row exists because something resolved
# onto it, so declaring rows 1 and 7 draws two rows, adjacent, and a row with nothing visible on
# either side is not drawn at all. Row 1 is where every segment goes today and where every
# segment still goes by default — an existing `.zshrc` sets no row arrays, so nothing here moves
# a segment anywhere it was not already.
#
# The rank/direction of the actual resolution — claiming a segment onto a row, and where the
# input marker attaches once rows exist — lands in later commits on this file. This one is only
# the vocabulary: the knobs this feature reads, declared so they appear where every other knob
# does.
#
# ---------------------------------------------------------------------------------------------
# The row knobs — read outside the config registry, on purpose
#
# `INZSH_ROW<n>_LEFT` / `INZSH_ROW<n>_RIGHT` are ARRAYS: `INZSH_ROW2_LEFT=(USER VENV)`. Every
# validator the registry understands — `any`, `bool`, `int`, an `enum:`, a `word:` — describes a
# single value, and `_inzsh_config_get` answers in a scalar `REPLY`; there is no array knob
# anywhere else in the theme. Rather than bend the registry into holding lists, this file will
# read these parameters itself and validate them itself, holding to the one rule the registry
# states for everything else: a value that fails is never fatal and never reported at the
# prompt.
#
# The families are registered below as `any`, purely so the names appear in the `inzsh-knobs`
# vocabulary `inzsh doctor` and the playground read from the registry. That registration is not
# validation — the reader added later in this file is — and an array-valued knob answers `any`
# happily however many words it joins into when something else asks for its value as a scalar.
#
# `INZSH_MARKER_ROW` is the one scalar knob this feature adds: `enum:inline|own`, `own` is
# today's shape — a bare marker line below every drawn row. `INZSH_PROMPT_LINES` keeps working
# as a deprecated alias for it — see `_inzsh_marker_row_resolved` below.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register        INZSH_MARKER_ROW  'enum:inline|own' own
  _inzsh_config_register_family 'INZSH_ROW*_LEFT'  any               ''
  _inzsh_config_register_family 'INZSH_ROW*_RIGHT' any               ''
fi

# `_inzsh_marker_row_resolved` → REPLY: `inline` or `own`.
#
# `INZSH_PROMPT_LINES` is the knob every existing `.zshrc` already carries, and it keeps working
# — this is the alias precedence §3.1 describes, not the removal:
#
#   1. an explicit, valid `INZSH_MARKER_ROW` wins outright
#   2. otherwise an explicit, valid `INZSH_PROMPT_LINES` resolves to the marker row it names
#      (`1` is `inline`, `2` is `own`)
#   3. otherwise the default, `own`
#
# "Explicit" is load-bearing: `_inzsh_config_get` would hand back the registered default the
# moment nothing is set, and that default must not shortcut past step 2 the way it would if this
# read `INZSH_MARKER_ROW`'s resolved value instead of its raw one. So the raw variable is read
# and validated by hand at both levels, set-but-empty counting as unset the same way it does
# everywhere else in this tree.
#
# `INZSH_PROMPT_LINES` is registered in `lib/core/render.zsh`, which loads AFTER this file — this
# file depends on nothing below it, so its grammar is restated here as the literal `1`/`2` it has
# always been, rather than asked of a registry entry that may not exist yet when THIS file is
# sourced. `INZSH_MARKER_ROW`, registered a few lines up in this same file, is instead checked
# through `_inzsh_config_validate` where the config layer is loaded, and by the literal enum
# otherwise — config.zsh loads BEFORE this file, so leaning on it here is the ordinary direction.
_inzsh_marker_row_resolved() {
  emulate -L zsh

  typeset -g REPLY=own

  local raw=${INZSH_MARKER_ROW-}
  if [[ -n $raw ]]; then
    if (( ${+functions[_inzsh_config_validate]} )); then
      if _inzsh_config_validate INZSH_MARKER_ROW "$raw"; then
        REPLY=$raw
        return 0
      fi
    elif [[ $raw == inline || $raw == own ]]; then
      REPLY=$raw
      return 0
    fi
  fi

  local lines=${INZSH_PROMPT_LINES-}
  case $lines in
    (1) REPLY=inline; return 0 ;;
    (2) REPLY=own;    return 0 ;;
  esac

  return 0
}
