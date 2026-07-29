# L2 render helpers — pure zsh, no forks, no dependencies.

# Expand prompt escapes the way zsh would when printing PROMPT.
inzsh_test_expand_prompt() {
  emulate -L zsh
  print -rn -- "${(%%)1}"
}

# Strip ANSI SGR escapes -> visible text.
inzsh_test_strip_ansi() {
  emulate -L zsh
  setopt extended_glob
  print -rn -- "${1//$'\e'\[[0-9;]#m/}"
}

# Display width of the visible text, multibyte-aware (${(m)#…}).
inzsh_test_visible_width() {
  emulate -L zsh
  setopt extended_glob
  local stripped="${1//$'\e'\[[0-9;]#m/}"
  print -rn -- "${(m)#stripped}"
}
