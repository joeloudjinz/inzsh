# InZsh — the remote-session marker. Not "where am I", but "am I away".
#
# HOW THIS DIFFERS FROM `lib/segments/host.zsh`, which is the obvious question and worth
# answering in full, because the two look like the same segment written twice and are not.
#
#   host      draws the machine's NAME. It answers WHERE the shell is — `build-07`, `db-2` —
#             and its value is that the name changes as you hop. It hides itself on a local
#             session precisely because the name is then a constant, and a constant carries no
#             information.
#   ssh       draws a MARK, and always the same one. It answers whether the shell is yours: one
#             fixed fact, in a fixed place, in a colour that is not the colour of the rest of
#             the row. It says nothing about which machine — that is the host segment's job,
#             and duplicating it here would spend the columns twice.
#
# So the two compose rather than compete: on a remote session you get `! ssh` and the hostname,
# and the mark is what makes the block a warning rather than a label. Someone who only ever hops
# between two known boxes can hide this and keep `host`; someone who wants the alarm without the
# address can hide `host` and keep this. Neither is a subset of the other.
#
# IT SHIPS OFF, at rank 0, like the rest of the optional set. The reasoning is the same and it
# is worth stating for this one especially: `host` already appears automatically in a remote
# session, so the default prompt is not silent about being remote — this segment is the LOUDER
# answer, for people who want one, and loudness is not a default this theme picks for anybody.
#
# NO SUBPROCESS, and nothing to fork for: `SSH_CONNECTION` and `SSH_TTY` are set by sshd in the
# session's own environment, so the answer was handed to us before the first prompt.

# Declared, never assigned wholesale. `typeset -gA` over an existing association keeps what is
# in it, so re-sourcing neither empties a map nor doubles a registration, and the declaration is
# what makes this file sourceable on its own.
typeset -gA _inzsh_segment_text _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role _inzsh_segment_bg_role _inzsh_segment_importance

# Registration.
#
#   rank 0        hidden until asked for. `INZSH_SSH_RANK` brings it out.
#   caution-text  the semantic role. Not `negative` — being on another machine is not a failure,
#                 and a prompt that cried wolf on every remote session would train people to
#                 stop reading the colour that means something is actually wrong.
#   importance 2  the middle of the ramp. It is context rather than the row's subject, but a
#                 context that outranks the muted furniture around it.
_inzsh_segment_defaults[SSH]=0
_inzsh_segment_fg_role[SSH]=caution-text
_inzsh_segment_importance[SSH]=2

# The fill `INZSH_SURFACE_MODE=hue` gives it — see `_inzsh_render_hues`. The `caution` FILL, not
# the wash: this is the one segment on the row whose whole point is that you are somewhere else,
# and a mode that spends colour should spend it here. `on-caution` comes with the fill, at 5.8:1
# light and 11.1:1 dark.
_inzsh_segment_bg_role[SSH]=caution

# The mark, from the token layer's glyph table — `_inzsh_glyph` in `lib/core/tokens.zsh`, where
# every glyph the theme draws lives, along with its byte spelling and its ASCII fallback. No
# literal is invented here and no `\u` escape is written anywhere: that escape is resolved when
# the file is PARSED, and outside a multibyte locale zsh cannot resolve one and abandons the
# rest of the file, functions included.
#
# `warn` rather than `info`, and it is the same choice the role above makes: the segment exists
# to be noticed, and `!` is the design system's mark for "look at this before you press Enter".
# COLOUR IS NEVER THE ONLY SIGNAL, so the mark is what carries the meaning in a screenshot, in
# monochrome, on eight colours and for a reader who cannot separate two hues.
#
# The fallback after `:-` is for a segment sourced without a token layer — a half-assembled
# bundle, or a spec that Includes this file alone. It keeps the mark drawable rather than empty,
# and it is ASCII because a file with no table has no answer about the locale either.
typeset -g _inzsh_ssh_glyph=${_inzsh_glyph[warn]:-!}

# The word beside it. Three letters, ASCII, and not configurable on purpose: a marker whose text
# a user can change is a marker whose meaning a reader cannot rely on, and the knob would buy
# nothing that `INZSH_SSH_RANK=0` does not already buy. `ssh` rather than `remote` because it is
# the name of the thing that put you here and it is one column narrower.
typeset -g _inzsh_ssh_label='ssh'

# `_inzsh_segment_ssh_build [marker]` — writes `_inzsh_segment_text[SSH]`.
#
# The argument is the injection seam: absent means "read the live environment", present means
# "use this", and present-and-EMPTY means a local session — `_inzsh_segment_ssh_build ''` is the
# absent case, which is what lets a spec assert both halves without an sshd anywhere.
#
# Either variable being non-empty is the whole test, and they are concatenated rather than
# chosen between, exactly as `lib/segments/host.zsh` does it: `SSH_CONNECTION` is what sshd sets
# for an interactive session, `SSH_TTY` survives some setups where the former is scrubbed, and
# the question is "did either of them say yes".
#
# WHAT IS DELIBERATELY NOT DETECTED. `sudo`, `su`, a container, a mosh session and a
# `$SSH_CLIENT` left behind by a screen session detached three days ago are all "not quite your
# own shell" in some sense, and none of them is this segment's question. Widening the test would
# make the mark mean "something is unusual", which is a thing no reader could act on. One fact,
# one mark.
#
# The entry is written on every path, empty where there is nothing to say, so a prompt that hid
# the block never inherits the previous one's text. Empty is absent to the renderer: no block,
# no separator, no placeholder. Always status 0.
_inzsh_segment_ssh_build() {
  emulate -L zsh

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[SSH]=

  local marker=${1-${SSH_CONNECTION}${SSH_TTY}}
  [[ -n $marker ]] || return 0

  # Per cent doubled, as everywhere. Nothing user-supplied reaches this fragment today — the
  # glyph comes from the token table and the label is a constant — so this is defence rather
  # than repair, and it costs one expansion on a segment that is hidden by default.
  local text="$_inzsh_ssh_glyph $_inzsh_ssh_label"
  _inzsh_segment_text[SSH]=${text//'%'/'%%'}

  return 0
}
