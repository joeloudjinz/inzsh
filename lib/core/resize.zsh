# InZsh — the resize redraw. What happens to the prompt already on screen when the window
# stops being the width it was drawn for.
#
# THE PROBLEM. A prompt is measured once, at the moment it is built, against `$COLUMNS`. In the
# two-line shape the right-hand side is not `RPROMPT` at all — `lib/core/render.zsh` pads it into
# the segment row with LITERAL SPACES, because zsh draws a real `RPROMPT` on the LAST row of a
# multi-line prompt, beside the marker, where a long command line writes over it. Literal padding
# is the price of keeping the clock on the segment row, and the price is that the row is a fixed
# string: narrow the window and a row built for 160 columns is still 159 wide, wraps, and is
# redrawn as two rows of the same ribbon. Narrow it far enough and it is four.
#
# So the row has to be rebuilt when the width changes, and there is exactly one moment the shell
# is told that it did: SIGWINCH.
#
# WHY A TRAP AND NOT A WIDGET. `zle-line-pre-redraw` looked like the better seam — it is a
# widget, so it wraps and restores exactly the way `lib/core/transient.zsh` handles
# `zle-line-finish`, and it fires while the line editor is live, which is precisely when a stale
# prompt is on screen. It does not fire on a resize. Measured on a pty in
# `test/ui/test_resize.py`: ten window changes produced ten `TRAPWINCH` calls and zero
# `zle-line-pre-redraw` calls. zsh redraws the BUFFER itself on a resize and never re-expands the
# prompt, which is the whole bug. `TRAPWINCH` is not the convenient mechanism, it is the only one.
#
# ---------------------------------------------------------------------------------------------
# THE SLOT IS SHARED, AND ONE HALF OF IT IS INVISIBLE
#
# zsh has one WINCH handler, reachable two ways:
#
#   TRAPWINCH() { … }        a function. Visible in `$functions`, so it can be saved by body,
#                            called under a name of ours, and put back verbatim. That is what
#                            this file does, and it is the same wrap-never-replace rule
#                            `lib/core/transient.zsh` keeps for `zle-line-finish`.
#   trap '…' WINCH           the POSIX form, the one that arrives in a zshrc copied from bash.
#                            It occupies the SAME slot — defining the function destroys it — and
#                            it is invisible to everything a shell can ask cheaply: not in
#                            `$functions`, not in `$dis_functions`, `whence -w` says `none`,
#                            `typeset -f` prints nothing. The `trap` builtin's own listing is the
#                            only place it exists, and a command substitution cannot read it,
#                            because a subshell resets traps to default before the listing runs —
#                            `$(trap)` comes back EMPTY. The only route is `trap > file` in the
#                            current shell, which is a temporary file written by every
#                            interactive shell that ever sources this theme, to answer a question
#                            that is almost always "no".
#
# The decision: wrap the function form exactly and do not pay a file per shell start for the
# other. What that costs is a user who wrote `trap '…' WINCH` and whose handler this file takes;
# what it buys is that the common case is free and that nothing here parses a quoted command
# string and `eval`s the result on every window drag — a mis-parse there would be a far worse
# failure than the one it was avoiding. `INZSH_RESIZE=0` is the escape hatch, and it is honoured
# per signal rather than at install, so it works without a re-source.
#
# ---------------------------------------------------------------------------------------------
# COALESCING
#
# Dragging a window emits a signal per frame. Two things keep that cheap, and neither is a timer:
#
#   the kernel      signals do not queue. A second SIGWINCH arriving while the first is still
#                   being handled is merged into it, so the shell never runs behind the drag.
#   the width       the redraw is skipped outright when `$COLUMNS` still equals the width the
#                   prompt on screen was built for. Dragging the BOTTOM edge of a window changes
#                   `$LINES` and signals every frame; nothing the prompt draws depends on it.
#
# A debounce — hold the signal, redraw once when it stops — is deliberately not built. It would
# need a timer, a timer is `zsh/sched` at one-second granularity or a background process, and a
# background process would be the second asynchronous mechanism in a repository whose conventions
# name `lib/segments/git-async.zsh` as the only one.
#
# The measurement says it is not needed. Dragged on a pty at 60 changes a second, every signal
# arrives and is handled — none is lost — at 5.2 ms each: the warm render, the reset and the
# screen write together, well inside the 30 ms a single prompt is allowed. That is 28% of the
# wall time of a drag, for as long as the drag lasts and no longer, and each individual redraw is
# an order of magnitude below anything an eye reads as a stall. The same drag by the bottom edge
# costs 0.28 ms a signal — nineteen times less — because the width comparison below answers it.
#
# ---------------------------------------------------------------------------------------------
# Sourcing this file registers nothing and redraws nothing. `_inzsh_resize_install` is a separate
# call, so the entry point decides when it goes live and a spec can load the file without a trap
# landing in the shell that is running the spec.

# The knob, declared where it is read — the pattern `lib/core/transient.zsh` follows. Guarded,
# because this file is independently sourceable and the config layer may not be in the shell.
#
# ON BY DEFAULT, for the reason the transient prompt is: a prompt that is wrong until you press
# Enter is the shipped behaviour otherwise, and nobody reads a reference to find out that their
# prompt could have been right. `INZSH_RESIZE=0` is one line for anyone who has their own WINCH
# handling, or who would rather the prompt only ever change when they ask it to.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_RESIZE bool 1
fi

# What the previous `TRAPWINCH` was — its BODY, exactly as `$functions` spelled it — and whether
# there was one at all. Two variables rather than one, for the reason `_inzsh_transient_saved`
# carries its `-set` keys: a `TRAPWINCH() { }` with an empty body and no `TRAPWINCH` at all are
# different states, and only one of them is put back by an assignment.
typeset -g  _inzsh_resize_prev=
typeset -gi _inzsh_resize_prev_set=0

# --------------------------------------------------------------------------------------------
# Is it on?
#
# `INZSH_RESIZE` takes the house boolean vocabulary in any case; unset, empty or unreadable means
# on, because the default is on and a typo may not disable a feature silently. Asked on every
# signal rather than at install, so `INZSH_RESIZE=0` typed at a prompt takes effect at the next
# resize. That is the rule every knob in this tree follows.
_inzsh_resize_enabled() {
  emulate -L zsh

  local value=${INZSH_RESIZE-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_RESIZE
    value=$REPLY
  fi

  case ${(L)value} in
    (0|false|no|off) return 1 ;;
  esac

  return 0
}

# --------------------------------------------------------------------------------------------
# The handler
#
# Call whatever was bound to `TRAPWINCH` before we were. The saved body was copied into a
# function of ours at install, so this is a name lookup and a call — a body re-parsed on every
# signal would be an `eval` per frame of a window drag.
#
# A predecessor that has since been removed is not an error; a plugin may have uninstalled
# itself. The status is dropped on purpose: a foreign handler's return value is about its own
# work, and letting it decide whether the prompt is redrawn would make our behaviour depend on
# somebody else's convention.
_inzsh_resize_dispatch() {
  emulate -L zsh

  (( ${+functions[_inzsh_resize_prev_winch]} )) || return 0

  _inzsh_resize_prev_winch "$@"

  return 0
}

# What runs on SIGWINCH.
#
# THE FOREIGN HANDLER RUNS FIRST, and the order is the contract rather than a convenience —
# exactly as in `lib/core/transient.zsh`. A handler that redraws for its own reasons must see the
# terminal as the user left it, and going last makes us the last word on the prompt without
# taking anything away from whoever was there before.
#
# `zle .reset-prompt` is what makes the new prompt visible: the parameters are already new, and
# the dot form is zsh's own builtin widget rather than whatever a user may have bound over the
# name. It re-expands the prompt and redraws around the buffer, so a half-typed command line
# survives the resize with the cursor where it was — which is the difference between a redraw and
# an interruption.
#
# `zle` with no arguments is the guard: it is true only while the line editor is actually on
# screen. A resize that arrives during a long-running command has no prompt to fix and no widget
# context to fix it from, and the next precmd will build against the new width anyway.
_inzsh_resize_winch() {
  emulate -L zsh

  _inzsh_resize_dispatch "$@"

  # No prompt, no work — the same second lock every hook in this tree keeps.
  [[ -o interactive ]] || return 0

  _inzsh_resize_enabled || return 0

  # The coalescing, and the whole of it. `_inzsh_render_cols` is the width the prompt on screen
  # was built for; while it still matches, the row is exactly as wide as it should be and a
  # redraw would be a screen write for no information.
  [[ ${COLUMNS:-0} == ${_inzsh_render_cols-0} ]] && return 0

  (( ${+functions[_inzsh_render]} )) || return 0
  _inzsh_render

  (( ${+builtins[zle]} )) || return 0
  zle || return 0
  zle .reset-prompt

  return 0
}

# The shape `TRAPWINCH` is given. Defined as an ordinary function so that install can COPY its
# body — `${functions[TRAPWINCH]} == ${functions[_inzsh_resize_trap]}` is then an exact test for
# "the trap is still ours", with both sides spelled by the same shell, which is what makes
# install idempotent and uninstall able to keep its hands off a binding somebody else has taken.
_inzsh_resize_trap() {
  _inzsh_resize_winch "$@"
}

# --------------------------------------------------------------------------------------------
# Install and uninstall
#
# Idempotent the honest way, as `_inzsh_transient_install` is: a second install finds our own
# body already in the slot and returns before saving anything, so it cannot record us as our own
# predecessor and cannot build a handler that calls itself.
#
# Two guards. A non-interactive shell has no prompt to redraw — and a trap installed there would
# fire in every script that sources a lib file directly. The second is structural: without our
# own template function there is nothing to copy and nothing to compare against, so a
# half-assembled bundle installs nothing rather than installing an empty trap.
#
# `unsetopt local_traps`, and it is not optional. `emulate -L zsh` sets LOCAL_TRAPS along with
# LOCAL_OPTIONS, and under LOCAL_TRAPS a trap set inside a function is UNSET AGAIN when that
# function returns — including a `TRAPWINCH` defined by assigning to `$functions`, which zsh
# treats as setting a trap like any other. The install then reports success, the parameter reads
# back as installed from inside the function, and there is no trap in the shell a moment later.
# LOCAL_OPTIONS is still in force, so this line is itself undone on return: what leaves the
# function is the trap, and nothing else.
_inzsh_resize_install() {
  emulate -L zsh
  unsetopt local_traps

  [[ -o interactive ]] || return 0
  (( ${+functions[_inzsh_resize_trap]} )) || return 0

  [[ ${functions[TRAPWINCH]-} == ${functions[_inzsh_resize_trap]} ]] && return 0

  typeset -gi _inzsh_resize_prev_set=${+functions[TRAPWINCH]}
  if (( _inzsh_resize_prev_set )); then
    typeset -g _inzsh_resize_prev=${functions[TRAPWINCH]}
    functions[_inzsh_resize_prev_winch]=$_inzsh_resize_prev
  else
    typeset -g _inzsh_resize_prev=
    (( ${+functions[_inzsh_resize_prev_winch]} )) && unfunction _inzsh_resize_prev_winch
  fi

  functions[TRAPWINCH]=${functions[_inzsh_resize_trap]}

  return 0
}

# Let go. Puts back exactly what was found — the foreign handler's body, or no `TRAPWINCH` at all
# where there was none — and forgets, so a later install saves the state it actually finds.
#
# The slot is only touched while it is still OURS. Something that installed a `TRAPWINCH` after
# us owns it now, and restoring over the top would do to them precisely what this file exists not
# to do. Unguarded on `interactive`, like the hook layer's: a shell that somehow acquired the
# trap must be able to shed it whatever it now reports.
#
# `unsetopt local_traps` again, and here it is insurance rather than a fix. Under LOCAL_TRAPS it
# is the RESTORE that gets undone: the foreign handler comes back for the length of this function
# and then vanishes, which is the exact damage this file is arranged to avoid arriving through
# the code written to prevent it. Whether it fires depends on how the trap now in the slot was
# set — measured, a trap that install put there with LOCAL_TRAPS off is not re-saved here, so on
# this shell removing the line changes nothing. It stays because the condition it depends on is
# zsh's own trap bookkeeping rather than anything this file controls, and because the failure it
# would let through is silent.
_inzsh_resize_uninstall() {
  emulate -L zsh
  unsetopt local_traps

  (( ${+functions[_inzsh_resize_trap]} )) || return 0
  [[ ${functions[TRAPWINCH]-} == ${functions[_inzsh_resize_trap]} ]] || return 0

  if (( _inzsh_resize_prev_set )); then
    functions[TRAPWINCH]=$_inzsh_resize_prev
  else
    unfunction TRAPWINCH
  fi

  (( ${+functions[_inzsh_resize_prev_winch]} )) && unfunction _inzsh_resize_prev_winch

  typeset -g  _inzsh_resize_prev=
  typeset -gi _inzsh_resize_prev_set=0

  return 0
}
