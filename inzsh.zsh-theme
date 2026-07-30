# InZsh — the entry point. A plugin manager, an oh-my-zsh theme load, or a bare `source` from
# .zshrc all arrive here.
#
# At M1 this file has exactly two jobs, and it must be right about both because everything
# downstream assumes them: refuse to run where a prompt has no meaning, and load the library in
# dependency order. There is no PROMPT assignment and no hook here — see the note at the end.

# Non-interactive shells get nothing. `ssh host command`, a script with a shebang, an editor's
# `zsh -c` — none of them draw a prompt, and every escape written there is corruption in
# somebody else's pipeline. This is the FIRST line for that reason: nothing may run above it,
# not even an assignment, or a no-op stops being a no-op.
[[ -o interactive ]] || return 0

# Where we are. Resolved from the file's own path rather than from $PWD, so a source from any
# directory works: `%x` is the file currently being sourced, and `:A` resolves the symlinks
# plugin managers are fond of. Kept afterwards rather than unset — the M2 renderer and the
# preset loader need the same answer, and computing it twice invites the two to disagree.
typeset -g _inzsh_theme_root=${${(%):-%x}:A:h}

# Dependency order, strictly downward. Detection answers how many colours we have; the reduced
# palettes must exist before the token layer's end-of-file resolve chooses between them; the
# token layer builds the roles; the render core is the surface machinery over them. No file in
# this list sources another, so this is the whole load and its order is the whole contract.
source $_inzsh_theme_root/lib/core/detect.zsh
source $_inzsh_theme_root/lib/core/tokens-256.zsh
source $_inzsh_theme_root/lib/core/tokens.zsh
source $_inzsh_theme_root/lib/core/render.zsh

# No PROMPT assignment and no `add-zsh-hook precmd` — the renderer and its hooks land at M2.
# Sourcing this file today loads the palette and the surface machinery and leaves the user's
# prompt exactly as it found it; `tools/render.zsh` draws the M1 demonstration prompt instead.
