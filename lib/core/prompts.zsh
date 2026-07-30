# InZsh — the secondary prompts and the terminal title. The parts of a theme nobody notices
# until they are missing: the continuation prompt you meet the first time a quote is left open,
# the spell-correction prompt, and the text in the tab.
#
# Sourcing this file assigns nothing and registers nothing. `_inzsh_prompts_install` and
# `_inzsh_title_install` are separate calls, so the entry point decides when any of it goes
# live and a spec can load the file without a hook or a PS2 landing in the shell running it.
#
# Three rules are enforced here rather than remembered:
#
#   the environment is theirs   install SAVES the user's `PS2` and `SPROMPT` and uninstall puts
#                               them back byte for byte, including the difference between a
#                               variable that was empty and one that was never set. A theme
#                               that cannot be removed cleanly is a theme nobody can try.
#   nothing is only colour      the correction prompt marks the mistyped word and the
#                               suggestion with glyphs; the colour repeats what the glyph
#                               already said, and a terminal with no colour loses nothing.
#   the title is an escape      so every guard on it is a guard against writing bytes into
#                               somewhere that is not a terminal: non-interactive shells, and
#                               terminals that mishandle OSC. Emitting nothing is always an
#                               option; emitting into a pipe never is.
#
# No forks. This is the render path — the title is rebuilt before every prompt — so everything
# below is parameter expansion and arithmetic.

# --------------------------------------------------------------------------------------------
# Glyphs and limits
#
# Internal for now, the same way `lib/core/layout.zsh` holds its ellipsis: glyphs belong in the
# token layer and move there when it grows a table for them. Nothing here is a knob — a user
# who wants a different marker replaces the whole string through `INZSH_PS2`.
typeset -g _inzsh_prompts_marker=$'·'   # · the continuation marker
typeset -g _inzsh_prompts_wrong=$'✕'    # ✕ the word as typed
typeset -g _inzsh_prompts_right=$'✓'    # ✓ the correction
typeset -g _inzsh_title_ellipsis=$'…'   # … the truncation marker

# The default title shape. `%d` is the directory, `%c` the running command — empty at a prompt,
# so the space between them is trimmed away and an idle title is just the directory.
typeset -g _inzsh_title_format_default='%d %c'

# How long a title may get, in characters. A title bar is not a grid of cells, so this counts
# characters rather than columns — the point is that a `find` command three screens long cannot
# flood the tab, not that the tab is exactly this wide.
typeset -gi _inzsh_title_max_chars=64

# --------------------------------------------------------------------------------------------
# Colour
#
# One helper, for one reason: an unresolved role must never reach the prompt as `%F{}`. That is
# a broken escape — zsh prints it — and it is exactly what a partial source or a bundle loaded
# without the token layer would produce. No role, no colour, same text.
#
# `_inzsh_prompts_paint <role> <text>` → REPLY. Reads `_inzsh_role` directly rather than going
# through `_inzsh_seg_color`, which would invent `INZSH_PS2_FG`-shaped knobs as a side effect of
# asking; the whole string is already replaceable through `INZSH_PS2`.
_inzsh_prompts_paint() {
  emulate -L zsh

  local color=${_inzsh_role[$1]-}
  if [[ -n $color ]]; then
    typeset -g REPLY="%F{$color}$2%f"
  else
    typeset -g REPLY=$2
  fi

  return 0
}

# --------------------------------------------------------------------------------------------
# PS2 — the continuation prompt
#
# `%_` is the whole idea. zsh keeps the parser's state there — `then`, `do`, `quote`, `if if` —
# so a shell that is still waiting can say WHY it is waiting instead of showing a bare `>`. The
# state is the informative part and it is drawn muted; the marker after it is the one accented
# character, and it is what makes a continued line legible as a continued line at a glance.
#
# `INZSH_PS2` replaces the lot, verbatim. Set but empty counts as unset — an `INZSH_PS2=` left
# behind in a zshrc must fall through to the theme's own rather than blank the prompt.
_inzsh_prompts_ps2() {
  emulate -L zsh

  if [[ -n $INZSH_PS2 ]]; then
    typeset -g REPLY=$INZSH_PS2
    return 0
  fi

  local state marker
  _inzsh_prompts_paint text-muted '%_'
  state=$REPLY
  _inzsh_prompts_paint accent "$_inzsh_prompts_marker"
  marker=$REPLY

  typeset -g REPLY="$state $marker "

  return 0
}

# --------------------------------------------------------------------------------------------
# SPROMPT — the spell-correction prompt
#
# zsh fills in `%R` with the word as typed and `%r` with what it would rather run, and reads a
# single key: y, n, a (abort) or e (edit). All four are shown, because a prompt that offers two
# of the four choices it accepts is a prompt that teaches the wrong thing.
#
# The two words carry a glyph each — ✕ for what was typed, ✓ for the suggestion — and only then
# a colour. On a monochrome terminal the glyphs still say which is which, which is the house
# rule; on a colour one the pair reads without being read.
#
# `INZSH_SPROMPT` replaces the lot, verbatim, with the same set-but-empty rule as `INZSH_PS2`.
_inzsh_prompts_sprompt() {
  emulate -L zsh

  if [[ -n $INZSH_SPROMPT ]]; then
    typeset -g REPLY=$INZSH_SPROMPT
    return 0
  fi

  local wrong right keys
  _inzsh_prompts_paint negative-text "$_inzsh_prompts_wrong %R"
  wrong=$REPLY
  _inzsh_prompts_paint positive-text "$_inzsh_prompts_right %r"
  right=$REPLY
  _inzsh_prompts_paint text-muted '[y n a e]'
  keys=$REPLY

  typeset -g REPLY="$wrong $_inzsh_prompts_marker $right $keys "

  return 0
}

# --------------------------------------------------------------------------------------------
# Install and uninstall
#
# The saved originals live in one associative array with a companion `-set` key per variable,
# because an associative array cannot hold the difference between `PS2=` and no `PS2` at all and
# that difference is the whole promise. Restoring an unset variable as an empty one is not a
# restoration; it is a quieter kind of damage.
#
# Idempotent, and idempotent the honest way: the save happens only when there is nothing saved,
# so a second install cannot overwrite the user's originals with the theme's own. The
# assignments themselves replace rather than append, so nothing can stack either.
_inzsh_prompts_install() {
  emulate -L zsh

  [[ -o interactive ]] || return 0

  if (( ! ${+_inzsh_prompts_saved} )); then
    typeset -gA _inzsh_prompts_saved
    # Quoted, every one of them: an unquoted `${PS2-}` for a variable that is unset or empty
    # produces no word at all, which shifts every key/value pair after it by one and makes the
    # assignment fail outright. The one case this whole array exists to get right is exactly the
    # case that would break it.
    _inzsh_prompts_saved=(
      PS2         "${PS2-}"      PS2-set     "${+PS2}"
      SPROMPT     "${SPROMPT-}"  SPROMPT-set "${+SPROMPT}"
    )
  fi

  _inzsh_prompts_ps2
  typeset -g PS2=$REPLY
  _inzsh_prompts_sprompt
  typeset -g SPROMPT=$REPLY

  return 0
}

# Let go. Puts back exactly what was found, then forgets — so a later install saves the state it
# actually finds, and a second uninstall is a no-op rather than a second restoration of values
# that are no longer current. Unguarded on purpose, like the hook layer's: a shell that somehow
# acquired our PS2 must be able to shed it whatever it now reports about being interactive.
_inzsh_prompts_uninstall() {
  emulate -L zsh

  (( ${+_inzsh_prompts_saved} )) || return 0

  if (( ${_inzsh_prompts_saved[PS2-set]} )); then
    typeset -g PS2=${_inzsh_prompts_saved[PS2]}
  else
    unset PS2
  fi

  if (( ${_inzsh_prompts_saved[SPROMPT-set]} )); then
    typeset -g SPROMPT=${_inzsh_prompts_saved[SPROMPT]}
  else
    unset SPROMPT
  fi

  unset _inzsh_prompts_saved

  return 0
}

# --------------------------------------------------------------------------------------------
# The terminal title
#
# Two guards, and neither is optional.
#
#   interactive   a title is an escape sequence written to stdout. In a script, in `ssh host
#                 command`, in an editor's `zsh -c`, that is corruption of somebody else's
#                 output — the same reason the entry point refuses to load at all there.
#   the terminal  `TERM=dumb` is what an editor's shell buffer and a plain pipe report, and
#                 `TERM=linux` is the kernel console: neither swallows an OSC string, so both
#                 would show the raw bytes. An absent `TERM` is not a terminal we can address.
#
# Both answer with a status and print nothing, so either can be asked on the render path.

# Is the title switched on? `INZSH_TITLE` takes the house boolean vocabulary in any case; unset,
# empty or unreadable means on, because the default is on and a typo may not disable a feature
# silently.
_inzsh_title_enabled() {
  emulate -L zsh

  case ${(L)INZSH_TITLE} in
    (0|false|no|off) return 1 ;;
  esac

  return 0
}

# Can this terminal be told its own title without the user seeing us try?
_inzsh_title_capable() {
  emulate -L zsh

  [[ -o interactive ]] || return 1

  case $TERM in
    (''|dumb|linux) return 1 ;;
  esac

  return 0
}

# The title text, in REPLY. `$1` is the command line being run — passed by the preexec hook and
# absent at a prompt.
#
# `INZSH_TITLE_FORMAT` is a template over two placeholders and nothing else:
#
#   %d  the current directory, collapsed to `~` and to named directories
#   %c  the running command; empty at a prompt
#   %%  a literal per cent
#
# A tiny grammar on purpose. The obvious alternative — hand the format to prompt expansion and
# let the user write `%~` — would mean expanding a string that has the command line pasted into
# it, so a directory or a command containing a `%` would be read as an instruction. Here the
# scan is one pass and the substituted text is never rescanned, so nothing a user can type or
# `cd` into can change the shape of the title.
#
# Config may not break the title either: an empty format is the default one, an unknown `%x` is
# kept literally rather than dropped, and a format that produces nothing at all falls back to
# the directory. Control characters — a newline in a command line, an ESC in a filename — are
# flattened to spaces before anything else, because they are how a title escapes its own string.
_inzsh_title_text() {
  emulate -L zsh
  setopt local_options extended_glob

  typeset -g REPLY=

  local format=${INZSH_TITLE_FORMAT:-$_inzsh_title_format_default}
  local dir=${${(%):-%~}//[[:cntrl:]]/ }
  local cmd=${1//[[:cntrl:]]/ }

  local out= rest=$format head
  while [[ -n $rest ]]; do
    head=${rest%%\%*}
    if [[ $head == $rest ]]; then
      out+=$rest
      break
    fi
    out+=$head
    rest=${rest[${#head} + 2,-1]}
    case ${rest[1]} in
      (d) out+=$dir ;;
      (c) out+=$cmd ;;
      (%) out+='%'  ;;
      (*) out+="%${rest[1]}" ;;
    esac
    rest=${rest[2,-1]}
  done

  # Trim the ends. The default format has a space between the two placeholders, so an idle
  # prompt would otherwise carry a trailing one into the tab.
  out=${${out##[[:space:]]##}%%[[:space:]]##}
  [[ -n $out ]] || out=$dir

  if (( ${#out} > _inzsh_title_max_chars )); then
    out=${out[1,_inzsh_title_max_chars - 1]}$_inzsh_title_ellipsis
  fi

  REPLY=$out

  return 0
}

# Emit the title `$1`, and leave the prompt-safe form of what was emitted in REPLY.
#
# The sequence is wrapped in `%{…%}` so that the same string may be pasted into a prompt without
# moving the cursor: everything between those markers is zero width by definition, which is what
# stops zsh from mis-measuring a line whose first ten characters are an escape. What goes to the
# terminal is the wrapper's prompt expansion — the markers removed, the bytes kept — so the tab
# gets an OSC string and never a literal `%{`.
#
# Per cent signs in the text are doubled first. The wrapped form is a prompt string; an
# un-escaped `%` in a directory name would be read as an escape by whoever expands it, here or
# in a prompt later.
#
# OSC 0 sets the icon name and the window title together and is terminated with BEL, which is
# the pair the widest set of terminals agrees on.
#
# Every refusal is silent and returns 0, with an empty REPLY: nothing to draw is not an error,
# and an empty REPLY concatenates into a prompt string harmlessly.
_inzsh_title_set() {
  emulate -L zsh

  typeset -g REPLY=

  [[ -n $1 ]] || return 0
  _inzsh_title_capable || return 0
  _inzsh_title_enabled || return 0

  local text=${1//\%/%%}
  REPLY="%{"$'\e'"]0;$text"$'\a'"%}"

  print -rn -- "${(%%)REPLY}"

  return 0
}

# precmd. The title goes back to the directory once the command line has finished.
#
# The first line captures `$?` and the last returns it. This hook does not read the exit status
# and does not need it — but precmd functions run in a row, each one seeing the status the
# previous one returned, so a hook that swallows it hides the user's failed command from every
# hook behind it. `$pipestatus` cannot be carried this way, which is why `_inzsh_precmd` is
# registered first and captures both; this is the courtesy owed to everyone after us.
_inzsh_title_precmd() {
  local -i carried=$?

  emulate -L zsh

  _inzsh_title_text
  _inzsh_title_set "$REPLY"

  return carried
}

# preexec. zsh hands the line as the user wrote it in `$1`; that is the one worth showing, since
# it is what they would recognise in a tab.
_inzsh_title_preexec() {
  local -i carried=$?

  emulate -L zsh

  _inzsh_title_text "$1"
  _inzsh_title_set "$REPLY"

  return carried
}

# Attach. Idempotent by delegation — `add-zsh-hook` refuses a function already in the array — so
# installing twice registers once, exactly as the hook layer does it.
#
# Order matters at the call site rather than here: this must be installed AFTER
# `_inzsh_hooks_install`, because `_inzsh_precmd` has to be the first precmd function in the
# array to read an untouched `$pipestatus`.
_inzsh_title_install() {
  emulate -L zsh

  [[ -o interactive ]] || return 0

  autoload -Uz add-zsh-hook
  add-zsh-hook precmd  _inzsh_title_precmd
  add-zsh-hook preexec _inzsh_title_preexec

  return 0
}

# Let go. `-d` removes our two registrations and leaves every other one in place. Removing a
# hook that was never registered is a no-op, not an error.
_inzsh_title_uninstall() {
  emulate -L zsh

  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd  _inzsh_title_precmd
  add-zsh-hook -d preexec _inzsh_title_preexec

  return 0
}
