# InZsh — the `root` segment. A safety feature wearing a segment's clothes.
#
# The question it answers is not "who am I" — `user` answers that — but "is the next thing I
# type going to run as root". A root shell that does not say so is the accident this file
# exists to prevent, so the segment is invisible almost always and unmissable when it is not:
# no entry at all at every other effective uid, and at 0 a block at rank 1, hard against the
# left edge, ahead of everything else on the row.
#
# Two signals, never one. Colour alone is not a signal — it is gone for a reader who cannot see
# it, gone again in a screenshot, a hostile palette or a log — so the fragment carries `!`, the
# design system's caution mark, and the colour is the second statement rather than the only one.
#
# It runs no command. `$EUID` is a shell parameter zsh keeps current; there is no `id -u` here
# and there must never be one. A fork on the render path is slow, and a fork that decides
# whether to warn you about root is a fork that can fail quietly.
#
# Registration, and why these three:
#
#   rank 1           the leftmost block on the left prompt. Whatever else the row says, this is
#                    read first.
#   importance 1     the top of the ramp, alongside `dir`. Nothing on the row outranks it.
#   fg on-negative   the foreground for text sitting ON the negative fill. Half of a pair, and
#                    the half that says what the other half must be — see below.
#
# THE BACKGROUND IS NOT THIS FILE'S TO SET, and the note is here rather than in a knob because
# the rule is structural. `lib/core/render.zsh` assigns surfaces centrally: whether two adjacent
# blocks are legible is a property of the SEQUENCE, so no segment may decide its own fill. What
# this segment registers is the foreground of a pair whose other half is the `negative` role,
# and until the renderer can express that, `on-negative` ink lands on a positional surface —
# legible, but not yet the red block the segment is asking for.
#
# How a future renderer should give it one: `_inzsh_surface_assign` answers one surface role per
# POSITION, so the missing piece is a way for a segment to declare a STATE fill instead — a
# `_inzsh_segment_bg_role` map read beside `_inzsh_segment_fg_role`, consulted before the
# positional assignment and exempt from the alternation invariant, because a state fill is
# legible against its neighbours by hue rather than by elevation. `root` would register
# `negative` there and the pair would close. Until then the seam that already works is the
# override precedence in `_inzsh_seg_color`: `INZSH_ROOT_BG` fills the block, and it is the one
# place a user or a renderer can spell the intent today.
#
# One caveat on the glyph, recorded rather than worked around: under `promptbang` — a csh
# compatibility option, off in zsh by default — a bare `!` in a prompt expands to the history
# number, and no spelling of it is literal under both settings. `!` is drawn as itself.

# `typeset -gA` over an existing association keeps what is in it, so this file is independently
# sourceable and re-sourcing it re-registers over the same three keys rather than doubling
# anything. The maps belong to `lib/core/engine.zsh` and `lib/core/render.zsh`.
typeset -gA _inzsh_segment_defaults _inzsh_segment_fg_role _inzsh_segment_importance

_inzsh_segment_defaults[ROOT]=10
_inzsh_segment_fg_role[ROOT]=on-negative
_inzsh_segment_importance[ROOT]=1

# `_inzsh_segment_root_build [euid]` — the ROOT fragment, into `_inzsh_segment_text[ROOT]`.
#
# The argument is the effective uid; absent, or empty, reads `$EUID`. That is the injection
# seam, and it is the only way this can be tested at all: a spec cannot become root, so it hands
# the segment a 0 instead.
#
# The text is cleared on every call before anything else is decided. A stale root badge is the
# one failure mode worse than a missing one — a shell that stopped being root must stop saying
# it on the very next prompt — so the absent case is written, not merely not-written.
#
# The `<->` guard is load-bearing twice over. It is what makes "not a number" mean NOT ROOT,
# which is the reading that keeps the badge meaning exactly one thing: a mark that also appears
# when something went wrong is a mark people learn to ignore, and `$EUID` is an integer
# parameter, so an unreadable value cannot come from the shell in the first place. And it keeps
# an unvetted string out of `(( ))`, where zsh would evaluate it as an ARITHMETIC EXPRESSION —
# `(( euid == 0 ))` on the word `hello` reads the parameter `hello`, finds it empty, and reports
# root.
_inzsh_segment_root_build() {
  emulate -L zsh

  typeset -gA _inzsh_segment_text

  local euid=${1-$EUID}
  [[ -n $euid ]] || euid=$EUID

  _inzsh_segment_text[ROOT]=

  [[ $euid == <-> ]] || return 0
  (( euid == 0 )) || return 0

  _inzsh_segment_text[ROOT]='! root'

  return 0
}
