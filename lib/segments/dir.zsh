# InZsh — the `dir` segment: which directory the shell is sitting in.
#
# The whole segment is two sentences. Collapse `$HOME` to `~`, because that shortening costs the
# reader nothing — `~` is not an abbreviation anyone has to decode — and then hand the result to
# `_inzsh_truncate_path` to be fitted into whatever room the row has left. The ladder that
# decides WHICH components go lives in `lib/core/layout.zsh` and is not restated here: one
# ladder, one place, and a change to it changes the prompt without this file moving.
#
# It reads no filesystem. `$PWD` is a shell parameter, not a syscall, so a directory deleted out
# from under the shell still draws — the parameter still holds the path, and saying where you
# were is more useful than an error where the prompt should be. No `pwd`, no `stat`, no
# `[[ -d ]]`: nothing in this file can block on a dead mount or cost a fork.
#
# Registration, and why these three numbers:
#
#   rank 4        left prompt, behind ROOT, USER and HOST — the three that say who and where you
#                 are before the row gets to what you are looking at.
#   importance 1  the most important thing on the row, so under `ramp` it takes the highest
#                 surface. `alternate` and `flat` ignore it; it is not a position.
#   fg text-body  the default face. The directory is the prompt's subject, not a state report,
#                 so it takes the body role and leaves the state colours to segments that have
#                 a state to report.

# `typeset -gA` over an existing association keeps what is in it, so this file is independently
# sourceable and re-sourcing it re-registers over the same three keys rather than doubling
# anything. The maps belong to `lib/core/engine.zsh` and `lib/core/render.zsh`; naming them here
# is only what lets a spec — or a bundle sourced out of order — load this segment on its own.
typeset -gA _inzsh_segment_defaults _inzsh_segment_fg_role _inzsh_segment_bg_role
typeset -gA _inzsh_segment_importance _inzsh_segment_priority

_inzsh_segment_defaults[DIR]=40
_inzsh_segment_fg_role[DIR]=text-body
_inzsh_segment_importance[DIR]=1
_inzsh_segment_priority[DIR]=20

# The fill `INZSH_SURFACE_MODE=hue` gives it, and the only mode that reads it — see
# `_inzsh_render_hues`. `info` is the design system's ink-blue, and the path is what it is for:
# the row's subject, and information rather than a state. The ink comes with the fill —
# `on-info`, the DS's own pair, at 7.8:1 light and 6.5:1 dark — so `text-body` above is what the
# path is drawn in under every other mode and `on-info` is what it is drawn in under this one.
_inzsh_segment_bg_role[DIR]=info

# `_inzsh_segment_dir_build [path] [budget]` — the DIR fragment, into `_inzsh_segment_text[DIR]`.
#
#   path    the directory to draw. Absent — or empty, which means the same thing here as it does
#           everywhere else in the tree — reads `$PWD`. This is the injection seam: a spec
#           passes a path rather than moving the shell, and the segment never fetches its own
#           state.
#   budget  how many COLUMNS the TEXT may occupy, not the block. The caller owns the column of
#           padding either side and the separator beside it, and subtracts them before asking.
#           Absent, empty or unparseable means no budget is known and the path comes back
#           collapsed but whole — the same "assume room" rule the layout layer follows.
#
# A budget of 0 is the one input that leaves this segment absent. That is `_inzsh_truncate_path`'s
# answer to "no room" and it is the honest one: a caller with no columns to spend should have
# hidden the segment on MINCOLS rather than asked for a path drawn in none.
#
# Without `lib/core/layout.zsh` loaded the path is drawn raw — uncollapsed and unshortened. The
# lookup is at call time for exactly that reason: a half-loaded theme draws a longer prompt,
# never no prompt.
_inzsh_segment_dir_build() {
  emulate -L zsh

  typeset -gA _inzsh_segment_text

  local shown=${1-$PWD}
  [[ -n $shown ]] || shown=$PWD

  if (( ${+functions[_inzsh_truncate_path]} )); then
    _inzsh_truncate_path "$shown" "${2-}"
    shown=$REPLY
  fi

  # `%` last, and never before the measuring. A directory may legally be called `100%`, and a
  # bare `%` in a prompt string opens an escape — the character after it is eaten, and one at
  # the end eats the padding. Doubling is how a prompt string says a literal per cent, and
  # `_inzsh_width` already counts `%%` as the one column it draws.
  #
  # After truncation because the ladder measures what the terminal will SHOW: a `%%` measured as
  # two columns could be cut between its halves, and half an escape is a different escape.
  _inzsh_segment_text[DIR]=${shown//'%'/'%%'}

  return 0
}
