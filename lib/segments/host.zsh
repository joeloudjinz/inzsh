# InZsh — the host segment. Which machine is this shell on?
#
# Two things happen in this file and nothing else: the segment registers itself at load time,
# and `_inzsh_segment_host_build` writes one entry in `_inzsh_segment_text`. No colour is
# resolved here — the renderer asks the token layer for the role registered below — and no
# glyph is invented, because glyphs belong to the token layer.
#
# NO SUBPROCESS. The hostname comes out of `$HOST`, a parameter zsh sets for every shell, and is
# cut at the first dot so a machine that knows its FQDN still draws a name and not a domain.
# `hostname` would answer the same question and cost a fork on every prompt, which is a cost the
# session never gets back.
#
# WHY THIS SEGMENT HIDES ITSELF (the judgment the roadmap asks for). A prompt segment earns its
# columns by telling you something you did not already know. On a local session the hostname is
# the machine you are sitting at: it is on the window title, it is on the case, and it is the
# same on every line of every shell you have ever opened there. Drawn anyway it is a constant —
# a block of ribbon that never changes and therefore never carries information, spending width
# that the directory and git segments have a real use for.
#
# In an SSH session the same string is the most important thing on the line. It is the answer to
# "am I about to run this on production", and it changes as you hop. So the default is: show it
# when the shell is remote, hide it when it is not. `INZSH_HOST_ALWAYS=1` forces it on for the
# people who split panes across machines and want the block in a fixed place; anything other
# than `1` or `0` is ignored rather than obeyed, the same validate-then-fall-back rule
# `lib/core/detect.zsh` follows, because an obeyed typo is worse than an ignored one.

# Declared, never assigned wholesale. `typeset -gA` over an existing association keeps what is
# in it, so re-sourcing the theme neither empties a map nor doubles a registration, and the
# declaration is what makes this file sourceable on its own — without it the build would be
# writing a subscript on a name that is not an association.
typeset -gA _inzsh_segment_text _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role _inzsh_segment_importance

# The registration. Rank 3 puts the host after the user and before the directory, which reads
# as `user host dir` — the address, narrowing. `text-muted` because it is context and not the
# subject of the line; importance 3 sits it at the bottom of the ramp for the same reason.
_inzsh_segment_defaults[HOST]=30
_inzsh_segment_fg_role[HOST]=text-muted
_inzsh_segment_importance[HOST]=3

# The knob, registered where it is read — a segment carries its own declaration, so a segment
# added later arrives configurable without anything in `lib/core/` moving. `1` and `0` and
# nothing else: this is a three-state question written as two, where not setting it is the
# third state and means "decide from the session".
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_HOST_ALWAYS 'enum:1|0' 0
fi

# `_inzsh_segment_host_build [hostname] [ssh-marker]` — writes `_inzsh_segment_text[HOST]`.
#
# Both arguments are the injection seam: absent means "read the live shell parameter", present
# means "use this". An argument that is present and EMPTY is an empty value, not a missing one —
# `_inzsh_segment_host_build ''` is a host with no name, which is the absent case.
#
# The entry is written on every path, empty where the segment has nothing to say, so a prompt
# that hid the block never inherits the previous prompt's text. Empty is absent to the renderer:
# no block, no separator, no placeholder. Always status 0 — there is nothing a prompt could
# usefully do with a failure here.
_inzsh_segment_host_build() {
  emulate -L zsh
  setopt extended_glob

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[HOST]=

  local name=${1-$HOST}
  # Either variable being non-empty is the whole test. `SSH_CONNECTION` is set by sshd for an
  # interactive session; `SSH_TTY` survives some setups where the former is scrubbed, so the two
  # are concatenated rather than chosen between — the answer is "did either say yes".
  local marker=${2-${SSH_CONNECTION}${SSH_TTY}}

  # Shortened HERE rather than in the default above, so an injected name and a live one go
  # through the same rule — a seam that behaves differently from the thing it stands in for is
  # not a seam. A name that is nothing but a domain (`.example.com`) has no first label and is
  # therefore nothing to draw.
  name=${${name##[[:space:]]#}%%[[:space:]]#}
  name=${name%%.*}
  [[ -n $name ]] || return 0

  local always=0
  local value=${INZSH_HOST_ALWAYS-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_HOST_ALWAYS
    value=$REPLY
  fi
  case $value in
    (1|0) always=$value ;;
  esac

  [[ $always == 1 || -n $marker ]] || return 0

  # Per cent doubled. The fragment is spliced into PROMPT and expanded there, so a machine
  # called `%m` would otherwise expand to a hostname a second time — and a `%{` in a name would
  # open an escape block the prompt never closes.
  _inzsh_segment_text[HOST]=${name//'%'/'%%'}

  return 0
}
