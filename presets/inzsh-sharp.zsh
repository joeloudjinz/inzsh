# InZsh preset — inzsh-sharp: dark, navy/cream, technical — the default.
#
# A preset is a token overlay and nothing else. It may set token/role variables only: never an
# engine variable, and never a hex value. Colour has exactly one transcription point,
# lib/core/tokens.zsh, so a preset carrying a hex literal is a bug.

typeset -g _inzsh_register=dark

# Re-resolve so an already-sourced theme switches immediately. Sourced before the token layer
# this is a no-op — that file's own end-of-file resolve picks the register up.
if (( ${+functions[_inzsh_tokens_resolve]} )); then
  _inzsh_tokens_resolve
fi
