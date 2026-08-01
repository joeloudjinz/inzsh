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

# Dependency order, strictly downward. Config is the defaults-and-validation registry everything
# above it reads through, and it comes first because it reads nothing itself — detection asks it
# what the user said about colour depth before it starts guessing; detection then answers what
# the terminal can do; the reduced palettes must exist before the token layer's end-of-file
# resolve chooses between them; the token layer builds the roles; layout and the engine are pure
# arithmetic over them; the render core is the surface machinery; hooks close the loop. No file
# in this list sources another, so this is the whole load and its order is the whole contract.
source $_inzsh_theme_root/lib/core/config.zsh
source $_inzsh_theme_root/lib/core/detect.zsh
source $_inzsh_theme_root/lib/core/tokens-256.zsh
source $_inzsh_theme_root/lib/core/tokens.zsh
source $_inzsh_theme_root/lib/core/layout.zsh
source $_inzsh_theme_root/lib/core/engine.zsh
source $_inzsh_theme_root/lib/core/render.zsh
source $_inzsh_theme_root/lib/core/prompts.zsh
source $_inzsh_theme_root/lib/core/hooks.zsh

# The segments, listed rather than globbed. A glob would load whatever happens to be in the
# directory in whatever order the filesystem answers; the load is a contract, so it is written
# down. Each registers its rank, role and importance and defines its build function — none of
# them draws anything at load time. They come after `render.zsh` and `engine.zsh`, whose
# associations they write into.
source $_inzsh_theme_root/lib/segments/root.zsh
source $_inzsh_theme_root/lib/segments/user.zsh
source $_inzsh_theme_root/lib/segments/host.zsh
source $_inzsh_theme_root/lib/segments/dir.zsh
source $_inzsh_theme_root/lib/segments/venv.zsh
source $_inzsh_theme_root/lib/segments/git.zsh
source $_inzsh_theme_root/lib/segments/git-async.zsh
source $_inzsh_theme_root/lib/segments/retval.zsh
source $_inzsh_theme_root/lib/segments/time.zsh

# Every knob declared, now that everything that declares one is loaded. Files that may call the
# config layer registered their own on the way past; a module that may NOT call it — `lib/salah/`
# imports nothing from the engine — ships a declaration table instead, and this is the one moment
# where both halves are guaranteed to be in the same shell. Idempotent, and a no-op in a load
# that pulled in no such module.
_inzsh_config_absorb_all

# Hooks first: precmd functions run in registration order, and only the first one sees an
# untouched `$?` and `$pipestatus`. `_inzsh_precmd` captures both on its first line, so anything
# registered ahead of it would cost the exit status the retval segment exists to show.
_inzsh_hooks_install
_inzsh_prompts_install
_inzsh_title_install

# The one background worker in the theme. Installed after the prompt hooks because it registers
# a precmd of its own, and the status capture has to stay first. It draws nothing itself: it
# fills a cache the git segment reads, and repaints when a fresh answer arrives.
_inzsh_git_async_install

# PROMPT is not assigned here. `_inzsh_precmd` calls `_inzsh_render`, which assigns it before
# each prompt is drawn — the values have to be current, and a value computed once at source time
# would be wrong by the second command. Sourcing this file therefore installs behaviour rather
# than a string, and the first prompt after it is the first one the theme draws.
