# InZsh — the user segment. Who is this shell running as?
#
# Registration at load time, one entry in `_inzsh_segment_text` at build time, nothing else. No
# colour is resolved here and no glyph invented: the renderer asks the token layer for the role
# registered below.
#
# NO SUBPROCESS. `$USERNAME` is a parameter zsh keeps current for every shell — it moves with
# `su` and with a `setuid` change, which is the whole reason to read it rather than `$USER`, an
# ordinary environment variable that a switched shell can inherit stale. `whoami` and `id -un`
# answer the same question at the price of a fork per prompt.
#
# WHY THIS SEGMENT HIDES ITSELF. Same reasoning as the host segment, applied to the other half
# of `user@host`: the name only earns its columns when it is not the one you expect. Most people
# are one account on their own machine, all day, and a block that always reads the same thing
# carries no information — it is width spent on a constant.
#
# So the segment is a DIFFERENCE detector, and `INZSH_DEFAULT_USER` is where you say what "no
# difference" means. Configure it and the rule is exact: the segment is absent while you are
# that user and appears the moment you are not — `sudo -s`, a service account, a shared box,
# someone else's shell. That is the case the segment exists for, and it is worth drawing whether
# the shell is local or remote.
#
# With nothing configured there is no expectation to compare against, so the fallback is the
# host segment's rule: show in an SSH session, hide locally. A remote shell is the one place a
# username is routinely surprising, and it is the same sentence the block beside it is already
# telling — `user host` reads as one address.
#
# Deliberately NOT a rule here: root. `ROOT` is its own segment at rank 1 with its own warning
# colour, and a privileged shell is a state and not an identity. Two segments drawing the same
# fact in two ways is one too many.

# Declared, never assigned wholesale — `typeset -gA` over an existing association keeps what is
# in it, so re-sourcing neither empties a map nor doubles a registration. The declaration is
# also what makes this file sourceable on its own.
typeset -gA _inzsh_segment_text _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role _inzsh_segment_bg_role _inzsh_segment_importance

# The registration. Rank 2 puts the user after the root marker and before the host, so the left
# prompt reads `user host dir` — who, where, what. `text-muted` and importance 3 because it is
# context: true almost always, worth reading only when it is not what you expected.
_inzsh_segment_defaults[USER]=20
_inzsh_segment_fg_role[USER]=text-muted
_inzsh_segment_importance[USER]=3

# The fill `INZSH_SURFACE_MODE=hue` gives it, and nothing else reads it — see
# `_inzsh_render_hues`. `neutral` is the muted chip: an identity is neither good news nor bad,
# and the one thing the block must not do is look like a state. The ink comes with it —
# `on-neutral`, the DS's own pair for that fill, at 6.5:1 light and 9.7:1 dark.
_inzsh_segment_bg_role[USER]=neutral

# The knob, registered where it is read. `any` because a username is whatever the system says
# it is, and empty because there is no name that means "no expectation" — not setting it is how
# that is said, which is the registry's "empty means unset" rule rather than a special case.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_DEFAULT_USER any ''
fi

# `_inzsh_segment_user_build [username] [default-user] [ssh-marker]` — writes
# `_inzsh_segment_text[USER]`.
#
# The first two arguments are the injection seam named by the issue; the third is the same seam
# for the environmental fact the no-default rule turns on, and it is optional for the same
# reason the others are. Absent means "read the live shell parameter"; present and EMPTY means
# an empty value, which for the username is the absent case and for the default user is "not
# configured".
#
# The entry is written on every path, empty where there is nothing to say, so a prompt that hid
# the block never inherits the previous prompt's text. Always status 0.
_inzsh_segment_user_build() {
  emulate -L zsh
  setopt extended_glob

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[USER]=

  local name=${1-$USERNAME}
  local marker=${3-${SSH_CONNECTION}${SSH_TTY}}

  # The seam first, the knob second. An argument that is PRESENT — even empty — is the caller
  # speaking, and the configuration is not consulted at all; absent, the knob is read through
  # the registry where it is loaded.
  local expected
  if (( $# >= 2 )); then
    expected=$2
  elif (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_DEFAULT_USER
    expected=$REPLY
  else
    expected=${INZSH_DEFAULT_USER-}
  fi

  name=${${name##[[:space:]]#}%%[[:space:]]#}
  [[ -n $name ]] || return 0

  # A configured default that is empty, or is only spaces, is no configuration at all — the
  # same "set but empty counts as unset" rule the colour and config layers already follow for a
  # stale `INZSH_DIR_BG=` left behind in a zshrc.
  expected=${${expected##[[:space:]]#}%%[[:space:]]#}

  # Shown by default, on any session. The earlier reading — hide locally, because your own
  # username tells you nothing you did not know — is true of the information and wrong about
  # the prompt: the name is part of the shape people recognise, and a block that appears only
  # over SSH makes the prompt jump. `INZSH_DEFAULT_USER` is how you say "not this one", and
  # then the segment is a difference detector on every session rather than only some.
  #
  # Quoted on the right: this is an equality test, not a match. An `INZSH_DEFAULT_USER=*`
  # would otherwise equal every user alive and hide the segment permanently.
  if [[ -n $expected ]]; then
    [[ $name != "$expected" ]] || return 0
  fi

  # Per cent doubled — the fragment is spliced into PROMPT and expanded there, so a user called
  # `%n` must not expand to a username a second time.
  _inzsh_segment_text[USER]=${name//'%'/'%%'}

  return 0
}
