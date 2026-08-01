# InZsh — the transient prompt. What the prompt turns into once the command it introduced has
# been accepted.
#
# The problem is scrollback. A seven-block powerline is worth its width once — while you are
# deciding what to type — and after that it is a header on a line of output nobody will read
# again. Two hundred of them is a screen you cannot skim. So the moment the line editor hands
# the command over, the prompt above it collapses to one short marker and the transcript becomes
# what you ran and what it printed, in alternation, with nothing between them.
#
# Sourcing this file registers nothing and collapses nothing. `_inzsh_transient_install` is a
# separate call, so the entry point decides when it goes live and a spec can load the file
# without a widget landing in the shell that is running the spec.
#
# Three rules are enforced here rather than remembered:
#
#   wrap, never replace   `zle-line-finish` is not ours. Other plugins bind it — syntax
#                         highlighters, autosuggestion engines, history tools — and a theme that
#                         overwrites the binding silently breaks whichever of them loaded first.
#                         Install SAVES what it found and CALLS it; uninstall puts it back. This
#                         is the same rule as `add-zsh-hook` for precmd, arrived at from the
#                         other side, and it is a hard rule for the same reason: the damage is
#                         invisible to whoever caused it.
#   the environment is theirs   the collapse SAVES `PROMPT` and `RPROMPT`, including the
#                         difference between a variable that was empty and one that was never
#                         set, and puts them back on the next precmd if nothing else has drawn
#                         over them. A theme that cannot be removed cleanly is a theme nobody
#                         can try.
#   no-op without a prompt   nothing installs in a non-interactive shell, and nothing installs
#                         where there is no line editor to install into.
#
# No forks. The collapse happens between the user's keystroke and their command, which is the
# most latency-visible moment in the whole theme; everything below is parameter expansion.

# The knobs, declared where they are read — the pattern `lib/segments/git.zsh` follows. Guarded,
# because this file is independently sourceable and the config layer may not be in the shell.
#
# ON BY DEFAULT. The feature exists because the alternative is a scrollback nobody can skim, and
# a calm transcript is not a taste — it is the reason the theme draws a narrow prompt in the
# first place. A default of `0` would ship the cost of the prompt to everyone and the benefit to
# whoever read the reference. `INZSH_TRANSIENT=0` is one line for anyone who wants the full
# prompt kept in their transcript.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_TRANSIENT        bool             1
  _inzsh_config_register INZSH_TRANSIENT_FORMAT 'enum:marker|dir' marker
fi

# The registered defaults, restated so that this file degrades to the shipped behaviour when it
# is sourced without `lib/core/config.zsh` — a half-assembled bundle, a spec that includes one
# file. `test/unit/config_registry_spec.sh` holds the two copies equal.
typeset -g _inzsh_transient_format_default=marker

# What the previous `zle-line-finish` binding was, exactly as `$widgets` spelled it — `user:foo`
# for a function, empty for "there was none". Kept rather than the function name alone, because
# restoring has to be able to tell "there was a widget called foo" from "there was no widget".
typeset -g _inzsh_transient_prev=

# --------------------------------------------------------------------------------------------
# Is it on?
#
# `INZSH_TRANSIENT` takes the house boolean vocabulary in any case; unset, empty or unreadable
# means on, because the default is on and a typo may not disable a feature silently. The
# registry says the same thing twice over — the knob is `bool` with a default of `1` — so an
# unreadable value arrives here as that default and the `case` below never sees it.
#
# Asked on every line finish rather than at install, so `INZSH_TRANSIENT=0` typed at a prompt
# takes effect at the next one. That is the rule every knob in this tree follows.
_inzsh_transient_enabled() {
  emulate -L zsh

  local value=${INZSH_TRANSIENT-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_TRANSIENT
    value=$REPLY
  fi

  case ${(L)value} in
    (0|false|no|off) return 1 ;;
  esac

  return 0
}

# --------------------------------------------------------------------------------------------
# The collapsed form
#
# `INZSH_TRANSIENT_FORMAT` picks one of two, and there are deliberately only two:
#
#   marker   the default. The marker and nothing else, so a transcript is commands and output
#            with a single column of punctuation between them. This is the whole point of the
#            feature; anything larger is a smaller version of the problem.
#   dir      the directory, muted, then the marker. For the one thing a scrolled-back prompt is
#            genuinely asked later — "where was I when I ran that?" — which the output of the
#            command usually cannot answer.
#
# Nothing else is offered, and a free-form template is refused on purpose: a format string that
# could hold anything would let the collapsed prompt grow back into the prompt it replaced, and
# the knob would then be the feature's own undoing. The marker is shared with the second line of
# the two-line shape — the same mark, the same status colouring — so a collapsed prompt reads as
# the prompt it came from rather than as a different thing that appeared.
#
# `_inzsh_render_marker` is looked up at call time, never at source time, so this file stays
# independently sourceable and the dependency stays one way. Without it the marker is one ASCII
# column, which is a legible transcript rather than none.
_inzsh_transient_text() {
  emulate -L zsh

  local marker='>'
  if (( ${+functions[_inzsh_render_marker]} )); then
    _inzsh_render_marker
    marker=$REPLY
  fi

  local format=${INZSH_TRANSIENT_FORMAT:-$_inzsh_transient_format_default}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_TRANSIENT_FORMAT
    format=${REPLY:-$_inzsh_transient_format_default}
  fi

  local head=
  if [[ $format == dir ]]; then
    if (( ${+functions[_inzsh_render_paint]} )); then
      _inzsh_render_paint text-muted '%~'
      head="$REPLY "
    else
      head='%~ '
    fi
  fi

  typeset -g REPLY="$head$marker "

  return 0
}

# Replace the prompt with the collapsed form, remembering what was there.
#
# The saved originals live in one associative array with a companion `-set` key per variable,
# because an associative array cannot hold the difference between `RPROMPT=` and no `RPROMPT` at
# all and that difference is the whole promise. The save happens only when there is nothing
# saved, so a second collapse before a restore cannot overwrite the user's originals with the
# theme's own.
#
# `RPROMPT` is CLEARED rather than collapsed. The right prompt is live status — a clock, a
# countdown to the next prayer — and a live value is a lie the moment it stops being redrawn.
# A wrong time in the transcript is worse than no time in it.
_inzsh_transient_collapse() {
  emulate -L zsh

  _inzsh_transient_text
  local collapsed=$REPLY

  if (( ! ${+_inzsh_transient_saved} )); then
    typeset -gA _inzsh_transient_saved
    # Quoted, every one of them: an unquoted `${RPROMPT-}` for a variable that is unset or empty
    # produces no word at all, which shifts every key/value pair after it by one and makes the
    # assignment fail outright. The one case this array exists to get right is exactly the case
    # that would break it.
    _inzsh_transient_saved=(
      PROMPT  "${PROMPT-}"   PROMPT-set  "${+PROMPT}"
      RPROMPT "${RPROMPT-}"  RPROMPT-set "${+RPROMPT}"
    )
  fi

  _inzsh_transient_saved[collapsed]=$collapsed

  typeset -g PROMPT=$collapsed
  typeset -g RPROMPT=

  return 0
}

# precmd. Put back what the collapse took, unless something has already drawn over it.
#
# The guard is the comparison: `_inzsh_render` assigns both parameters on every draw, so in a
# fully loaded theme PROMPT no longer holds the collapsed string by the time this runs and
# nothing is restored — the fresh render stands. In a shell that has this file and no renderer,
# it holds the collapsed string exactly, and the user's own prompt comes back. One branch covers
# both, and neither can clobber the other.
#
# The first line captures `$?` and the last returns it. This hook does not read the exit status
# and does not need it — but precmd functions run in a row, each seeing the status the previous
# one returned, so a hook that swallows it hides the user's failed command from every hook
# behind it. That is the courtesy `_inzsh_title_precmd` already keeps.
_inzsh_transient_precmd() {
  local -i carried=$?

  emulate -L zsh

  (( ${+_inzsh_transient_saved} )) || return carried

  if [[ ${PROMPT-} == "${_inzsh_transient_saved[collapsed]}" ]]; then
    if (( ${_inzsh_transient_saved[PROMPT-set]} )); then
      typeset -g PROMPT=${_inzsh_transient_saved[PROMPT]}
    else
      unset PROMPT
    fi

    if (( ${_inzsh_transient_saved[RPROMPT-set]} )); then
      typeset -g RPROMPT=${_inzsh_transient_saved[RPROMPT]}
    else
      unset RPROMPT
    fi
  fi

  unset _inzsh_transient_saved

  return carried
}

# --------------------------------------------------------------------------------------------
# The widget
#
# Call whatever was bound to `zle-line-finish` before we were, whatever it was and whether or
# not it still exists. A widget that has been removed since we saved it is not an error — a
# plugin may have uninstalled itself — and a saved name that is our own is the one case that
# must never be called, because that is the recursion a second install would otherwise create.
_inzsh_transient_dispatch() {
  emulate -L zsh

  local prev=${_inzsh_transient_prev-}
  [[ $prev == user:?* ]] || return 0

  local fn=${prev#user:}
  [[ $fn == _inzsh_transient_line_finish ]] && return 0
  (( ${+functions[$fn]} )) || return 0

  "$fn" "$@"

  return 0
}

# `zle-line-finish` — zsh runs it as the line editor hands the command over, which is the last
# moment the prompt on screen can still be changed before it becomes scrollback.
#
# THE FOREIGN WIDGET RUNS FIRST, and the order is the contract rather than a convenience: a
# widget that reads `PROMPT`, or redraws for its own reasons, must see the prompt the user was
# looking at and not our collapsed stand-in. Collapsing afterwards makes us the last word on the
# prompt without taking anything away from whoever was there before.
#
# `zle .reset-prompt` is what makes the change visible: the parameters are already new, and the
# dot form is zsh's own builtin widget rather than whatever a user may have bound over the name.
# The knob is read here rather than at install so that switching the feature off takes effect at
# the next prompt — and, being read after the dispatch, switching it off cannot take the foreign
# widget down with it.
_inzsh_transient_line_finish() {
  emulate -L zsh

  _inzsh_transient_dispatch "$@"

  _inzsh_transient_enabled || return 0

  _inzsh_transient_collapse
  zle .reset-prompt

  return 0
}

# --------------------------------------------------------------------------------------------
# Install and uninstall
#
# Idempotent, and idempotent the honest way: a second install finds our own widget already bound
# and returns before saving anything, so it cannot record us as our own predecessor. The precmd
# registration is idempotent by delegation — `add-zsh-hook` refuses a function already in the
# array — exactly as `lib/core/hooks.zsh` does it.
#
# Two guards, and neither is optional. A non-interactive shell has no prompt to collapse, and a
# shell with no `zle` has no widget table to bind into: `zsh -c`, a script, an old build without
# the module. Both return 0 — nothing to install is not an error.
_inzsh_transient_install() {
  emulate -L zsh

  [[ -o interactive ]] || return 0
  (( ${+widgets} )) || return 0
  (( ${+builtins[zle]} )) || return 0

  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _inzsh_transient_precmd

  [[ ${widgets[zle-line-finish]-} == user:_inzsh_transient_line_finish ]] && return 0

  typeset -g _inzsh_transient_prev=${widgets[zle-line-finish]-}
  zle -N zle-line-finish _inzsh_transient_line_finish

  return 0
}

# Let go. Puts back exactly what was found — the foreign widget by name, or no widget at all
# where there was none — and forgets, so a later install saves the state it actually finds.
#
# The binding is only touched while it is still OURS. A plugin that bound `zle-line-finish`
# after us owns it now, and restoring over the top would do to them precisely what this file
# exists not to do. Unguarded on `interactive` on purpose, like the hook layer's: a shell that
# somehow acquired the widget must be able to shed it whatever it now reports.
_inzsh_transient_uninstall() {
  emulate -L zsh

  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd _inzsh_transient_precmd

  (( ${+widgets} )) || return 0
  (( ${+builtins[zle]} )) || return 0
  [[ ${widgets[zle-line-finish]-} == user:_inzsh_transient_line_finish ]] || return 0

  local prev=${_inzsh_transient_prev-}
  if [[ $prev == user:?* && ${prev#user:} != _inzsh_transient_line_finish ]]; then
    zle -N zle-line-finish "${prev#user:}"
  else
    zle -D zle-line-finish
  fi

  typeset -g _inzsh_transient_prev=

  return 0
}
