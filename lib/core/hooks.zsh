# InZsh — the hook layer. The one place the theme attaches itself to the shell, and the one
# place it lets go again.
#
# Sourcing this file registers nothing and draws nothing. `_inzsh_hooks_install` is a separate
# call so that the entry point decides when the theme goes live, and so that a spec can load
# the file without a hook landing in the shell that is running the spec.
#
# Four rules are enforced here rather than remembered:
#
#   status first   `$?` and `$pipestatus` are captured by the FIRST command in `_inzsh_precmd`.
#                  Anything above that line — an assignment, an `emulate`, a `typeset` — is a
#                  command, and a command overwrites both. The failure is silent: the exit
#                  segment shows 0 forever and nothing else looks wrong.
#   add-zsh-hook   registration goes through `add-zsh-hook`, never through `precmd=` or
#                  `precmd_functions=(...)`. An assignment discards every hook already
#                  registered, so a theme that assigns quietly breaks every other plugin in
#                  the user's shell.
#   non-interactive  the hooks no-op where there is no prompt. The entry point guards too;
#                  this is the second lock, for a user who sources a lib file directly.
#   no forks       `_inzsh_precmd` runs before every prompt. It is parameter expansion and
#                  arithmetic, and nothing here mutates locale, options or any global that is
#                  not ours.

# The exit state of the command line that just finished, kept for the segments that draw it.
#
# Declared here, at source time, for one reason: the capture inside `_inzsh_precmd` has to be a
# single command. `typeset` is a command like any other — running one resets `$pipestatus` to
# its own success — so a function that declared the two variables and then filled them would
# read the second one off itself and report a one-element `(0)` for every pipeline ever run.
# Declared at source time, the capture is one bare assignment and both values are the caller's.
#
# It also means the assignment cannot create a global by accident: the names already exist,
# with the right types, in a shell that has `warn_create_global` set.
typeset -g  _inzsh_last_status=0
typeset -ga _inzsh_last_pipestatus=(0)

# precmd. Everything the theme does before a prompt is drawn happens here, in this order.
#
# The first line is the whole reason the function exists, and its position is the contract:
# `$?` is the status of the command line the user just ran, `$pipestatus` the per-stage status
# of that same line, and both are gone the moment any other command runs. They are taken in one
# assignment — two assignments would be two commands, and the second would read the first.
#
# `emulate -L zsh` comes after, never before: it is a command, and it would take the status
# with it. On the second line it costs nothing and buys everything downstream — a predictable
# option set for the render path regardless of what the user has set, restored on return
# because `-L` makes it local. It leaves `interactive` alone, so the guard below still reads
# the shell the user is actually in.
_inzsh_precmd() {
  _inzsh_last_status=$? _inzsh_last_pipestatus=("${pipestatus[@]}")

  emulate -L zsh

  # No prompt, no work. A hook has no business running in a shell that never draws one, and
  # an escape sequence written there is corruption in somebody else's pipeline.
  [[ -o interactive ]] || return 0

  # The seam. The render layer defines `_inzsh_render` when there is something to draw; until
  # it does, the capture above is the whole of precmd and the user's prompt is untouched. The
  # test is `${+functions[...]}` — a parameter lookup, not a `whence`, because this is the
  # render path and the render path does not fork.
  (( ${+functions[_inzsh_render]} )) && _inzsh_render

  return 0
}

# Attach. Idempotent, and idempotent by delegation rather than by a flag of our own:
# `add-zsh-hook` already refuses to add a function that is present in `precmd_functions`, so
# installing twice registers once. A private "already installed" flag would be worse than
# useless — it would also refuse to repair the registration after a user, a plugin manager or
# a `precmd_functions=()` somewhere else had removed it.
#
# `autoload -Uz` lives here rather than at source time so that sourcing this file changes
# nothing at all. It is cheap and repeatable; both directions do it, because uninstalling is
# legitimate in a shell that never installed.
_inzsh_hooks_install() {
  emulate -L zsh

  [[ -o interactive ]] || return 0

  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _inzsh_precmd
}

# Let go. Removes our hook and leaves every other registration in place — that is what the `-d`
# form is for, and it is why we never rebuild the array ourselves. Unguarded on purpose: a
# shell that somehow acquired the hook must be able to shed it, whatever it now reports about
# being interactive. Removing a hook that was never registered is a no-op, not an error.
_inzsh_hooks_uninstall() {
  emulate -L zsh

  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd _inzsh_precmd

  return 0
}
