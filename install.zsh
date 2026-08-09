#!/usr/bin/env zsh
# The installer — idempotent, reversible, and honest about what it touches.
#
#   zsh install.zsh              install (plain source into .zshrc)
#   zsh install.zsh --uninstall  take everything back out
#
# What install does, exactly once however often it runs: back up `.zshrc` (first edit only —
# the backup is the PRE-INZSH state, and a later run never overwrites it), then add one managed
# block between two markers. Uninstall removes the block and nothing else, so `.zshrc` returns
# to its pre-install content; the backup is left for the user to delete.
#
# Everything goes through `${ZDOTDIR:-$HOME}` — never a hard-coded home — which is also what
# makes the test suite possible: point HOME at a throwaway directory and the installer cannot
# reach the real one.
emulate -L zsh
setopt err_exit no_unset pipe_fail extended_glob

typeset -g _inzsh_install_root=${${(%):-%x}:A:h}
typeset -g _inzsh_install_theme=$_inzsh_install_root/inzsh.zsh-theme
typeset -g _inzsh_install_zshrc=${ZDOTDIR:-$HOME}/.zshrc
typeset -g _inzsh_install_backup=$_inzsh_install_zshrc.inzsh.bak
typeset -g _inzsh_install_open='# >>> inzsh >>>'
typeset -g _inzsh_install_close='# <<< inzsh <<<'

# `.zshrc` as an array of lines; empty array for a missing or empty file. `$(<file)` strips
# the trailing newline, so a round trip through here and `_inzsh_install_write` normalises
# exactly that and nothing else.
_inzsh_install_read() {
  typeset -ga reply=()
  if [[ -s $_inzsh_install_zshrc ]]; then
    reply=("${(@f)$(<$_inzsh_install_zshrc)}")
  fi
}

# Write lines back atomically: a temp file in the same directory, then `mv`. A crash mid-write
# leaves the old `.zshrc`, never half of a new one.
_inzsh_install_write() {
  local tmp=$_inzsh_install_zshrc.inzsh-tmp.$$
  if (( $# )); then
    print -rl -- "$@" > $tmp
  else
    : > $tmp
  fi
  mv -- $tmp $_inzsh_install_zshrc
}

# The one backup, taken before the first edit and only then. `-e` rather than `-f` on the
# backup check: if the user put a directory or a symlink there, that is theirs to resolve,
# not ours to overwrite.
_inzsh_install_backup_once() {
  [[ -f $_inzsh_install_zshrc && ! -e $_inzsh_install_backup ]] || return 0
  cp -- $_inzsh_install_zshrc $_inzsh_install_backup
  print -r -- "backed up ${_inzsh_install_zshrc/#$HOME/~} → ${_inzsh_install_backup/#$HOME/~}"
}

# Lines with the managed block taken out, in `reply`. The blank line the installer adds above
# the block is removed with it — stripping must be the exact inverse of adding, or a
# reinstall would grow the file by one blank line each time.
_inzsh_install_strip() {
  local -a out=()
  local line
  local -i in_block=0
  for line in "$@"; do
    if [[ $line == $_inzsh_install_open ]]; then
      in_block=1
      if (( ${#out} )) && [[ ${out[-1]} == '' ]]; then
        out=("${(@)out[1,-2]}")
      fi
      continue
    fi
    if (( in_block )); then
      [[ $line == $_inzsh_install_close ]] && in_block=0
      continue
    fi
    out+=("$line")
  done
  typeset -ga reply=("${(@)out}")
}

# ── verification ────────────────────────────────────────────────────────────────────────────
#
# Writing the edit and the theme loading are two different facts. Everything above knows only
# the first, and a user who runs an installer is asking about the second — so before the word
# "installed" is printed, a shell is started against the rc that was just written and asked
# whether the theme is there. That answer is the report.
#
# The check is a real interactive zsh — `-i` because the theme refuses to load in a shell that
# draws no prompt — reading the same `$HOME`/`$ZDOTDIR` the installer wrote to. In the spec
# suite that is a throwaway directory, so the check cannot reach a real one either.
#
# Three answers, not two. "Did not load" and "could not tell" are different things, and
# collapsing them would put us back where we started: claiming a result we do not have.

typeset -g _inzsh_install_verify_timeout=${_inzsh_install_verify_timeout:-20}
typeset -g _inzsh_install_verify_marker='inzsh-verify-loaded'
# The theme's own evidence, not ours: the render entry point exists AND our precmd is actually
# registered. A file that was sourced but never installed its hooks fails this, which is the
# point — sourcing is not loading.
typeset -g _inzsh_install_verify_probe='
  (( ${+functions[_inzsh_render]} )) && (( ${precmd_functions[(I)_inzsh_precmd]} )) &&
    print -r -- '$_inzsh_install_verify_marker

# 0 the theme loaded · 1 it did not · 2 the check could not finish
#
# The deadline is enforced by a watchdog rather than by polling: the wrapper waits on the exact
# child and a second process kills it when time is up, so there is no race between "still
# running" and "finished a moment ago", and a `.zshrc` that blocks forever costs us
# `$_inzsh_install_verify_timeout` seconds and nothing else. Stdin comes from /dev/null so an
# rc that reads never waits for a person who is not there, and the shell's own output is
# discarded — a noisy rc is the user's business, not a verification result.
_inzsh_install_verify() {
  [[ $_inzsh_install_verify_timeout == <1-> ]] || _inzsh_install_verify_timeout=20

  local out
  out=$(mktemp "${TMPDIR:-/tmp}/inzsh-verify.XXXXXX") || return 2

  local -i signalled=0
  zsh -f -c '
    local out=$1 timeout=$2 probe=$3 zdotdir=$4
    [[ -n $zdotdir ]] && export ZDOTDIR=$zdotdir
    zsh -o NO_GLOBAL_RCS -i -c $probe </dev/null >|$out 2>/dev/null &
    local -i child=$!
    # The deadline. `zselect` waits inside this shell rather than forking a `sleep`, so the
    # kill below takes the whole watchdog with it and no stray process outlives the install.
    #
    # KILL rather than TERM, and not out of impatience: an INTERACTIVE zsh ignores SIGTERM, and
    # the probe has to be interactive or the theme would decline to load in it. TERM here is a
    # deadline that never fires.
    {
      if zmodload -i zsh/zselect 2>/dev/null; then
        zselect -t $(( timeout * 100 )) || true
      else
        sleep $timeout
      fi
      kill -KILL $child 2>/dev/null
    } &
    local -i watchdog=$!
    wait $child
    local -i answer=$?
    kill -TERM $watchdog 2>/dev/null
    exit $answer
  ' inzsh-install-verify \
    "$out" "$_inzsh_install_verify_timeout" "$_inzsh_install_verify_probe" "${ZDOTDIR:-}" \
    2>/dev/null || signalled=$?

  local seen=''
  [[ -s $out ]] && seen=$(<$out)
  rm -f -- $out

  [[ $seen == *$_inzsh_install_verify_marker* ]] && return 0
  # Above 128 is a signal, and the only signal we send is the deadline.
  (( signalled > 128 )) && return 2
  return 1
}

# The one place an install is called done, and the only place that word is printed. `$1` is
# what is now on disk, `$2` whether this run put it there.
_inzsh_install_verdict() {
  local state=$1 wrote=$2
  local -i answer=0
  _inzsh_install_verify || answer=$?

  if (( answer == 0 )); then
    if [[ $wrote == wrote ]]; then
      print -r -- "installed: $state — verified in a test shell"
      print -r -- "open a new shell to see the prompt"
    else
      print -r -- "already installed: $state — verified in a test shell"
    fi
    return 0
  fi

  if (( answer == 1 )); then
    print -ru2 -- "install.zsh: $state, but a test shell did not load the theme"
    print -ru2 -- "install.zsh: nothing is rolled back — see docs/install.md, or run --uninstall"
    return 1
  fi

  print -ru2 -- "install.zsh: $state, but the check did not finish in ${_inzsh_install_verify_timeout}s"
  print -ru2 -- "install.zsh: unverified — open a new shell to see whether the prompt is there"
  return 2
}

_inzsh_install_plain() {
  local -a lines want block
  _inzsh_install_read; lines=("${(@)reply}")
  block=("$_inzsh_install_open" "source '$_inzsh_install_theme'" "$_inzsh_install_close")

  _inzsh_install_strip "${(@)lines}"
  want=("${(@)reply}")
  if (( ${#want} )); then
    want+=('')
  fi
  want+=("${(@)block}")

  local state="${_inzsh_install_zshrc/#$HOME/~} sources the theme"
  if [[ "${(pj:\n:)lines}" == "${(pj:\n:)want}" ]]; then
    _inzsh_install_verdict "$state" unchanged
    return
  fi

  _inzsh_install_backup_once
  _inzsh_install_write "${(@)want}"
  _inzsh_install_verdict "$state" wrote
}

# ── the oh-my-zsh path ──────────────────────────────────────────────────────────────────────
#
# Two edits instead of a block: a symlink in the custom themes directory, and the `ZSH_THEME`
# line. The previous theme line is not deleted — it is commented out and tagged, so uninstall
# can put back exactly what was there:
#
#   #ZSH_THEME="robbyrussell" # inzsh:disabled
#   ZSH_THEME="inzsh" # inzsh:managed
#
# The tags are the reversibility: `inzsh:managed` lines are ours to remove, `inzsh:disabled`
# lines are the user's to get back.

typeset -g _inzsh_install_tag_managed='# inzsh:managed'
typeset -g _inzsh_install_tag_disabled='# inzsh:disabled'
typeset -g _inzsh_install_theme_line="ZSH_THEME=\"inzsh\" $_inzsh_install_tag_managed"

# The oh-my-zsh root, or failure: `$ZSH` when it points at a directory, the stock location
# otherwise. Printed rather than assigned so the caller can `$(…)` it.
_inzsh_install_omz_root() {
  if [[ -n ${ZSH:-} && -d ${ZSH:-} ]]; then
    print -r -- $ZSH
    return 0
  fi
  if [[ -d $HOME/.oh-my-zsh ]]; then
    print -r -- $HOME/.oh-my-zsh
    return 0
  fi
  return 1
}

# Does this line load oh-my-zsh? The one predicate for it, because two would drift: the same
# answer decides whether the omz path applies at all and where the managed theme line goes.
#
# Commented lines are not a load — a `#source $ZSH/oh-my-zsh.sh` left by someone moving off the
# framework is the exact case this is here to reject. The rest is deliberately loose about what
# comes before the verb: `[[ -f $ZSH/oh-my-zsh.sh ]] && source $ZSH/oh-my-zsh.sh` is a guarded
# load and still a load.
_inzsh_install_is_omz_source() {
  local line=${1##[[:space:]]#}
  [[ $line == \#* ]] && return 1
  [[ $line == *(source|.)[[:space:]]##*oh-my-zsh.sh* ]]
}

# Does the rc we are about to edit actually load oh-my-zsh?
#
# This — not a directory, not `$ZSH` — is what makes the omz path meaningful. `~/.oh-my-zsh`
# survives an uninstall and an `export ZSH=` survives the line that used it, so either one on
# its own says nothing about the shell the user is in. If the rc never sources `oh-my-zsh.sh`,
# nothing will ever read `ZSH_THEME` or look in the custom themes directory, and an install
# that writes both is inert.
_inzsh_install_rc_loads_omz() {
  local -a lines
  local line
  _inzsh_install_read; lines=("${(@)reply}")
  for line in "${(@)lines}"; do
    if _inzsh_install_is_omz_source "$line"; then
      return 0
    fi
  done
  return 1
}

# Lines with the omz edits undone, in `reply` — managed lines out, disabled lines restored.
# Used by uninstall, and by install to compute its target from a clean base whatever state
# the file is in now.
_inzsh_install_omz_restore() {
  local -a out=()
  local line
  for line in "$@"; do
    if [[ $line == *" $_inzsh_install_tag_managed" ]]; then
      continue
    fi
    if [[ $line == \#*" $_inzsh_install_tag_disabled" ]]; then
      line=${line% $_inzsh_install_tag_disabled}
      out+=("${line#\#}")
      continue
    fi
    out+=("$line")
  done
  typeset -ga reply=("${(@)out}")
}

# Lines with the omz edits applied, in `reply`. The managed line lands where the old theme
# line was; with no theme line it goes just above the `oh-my-zsh.sh` source, which is the
# last place omz still reads it; with neither it is appended.
_inzsh_install_omz_apply() {
  local -a out=()
  local line
  local -i placed=0
  for line in "$@"; do
    if [[ ${line##[[:space:]]#} == ZSH_THEME=* ]]; then
      out+=("#$line $_inzsh_install_tag_disabled")
      if (( ! placed )); then
        out+=("$_inzsh_install_theme_line")
        placed=1
      fi
      continue
    fi
    if (( ! placed )) && _inzsh_install_is_omz_source "$line"; then
      out+=("$_inzsh_install_theme_line" "$line")
      placed=1
      continue
    fi
    out+=("$line")
  done
  if (( ! placed )); then
    out+=("$_inzsh_install_theme_line")
  fi
  typeset -ga reply=("${(@)out}")
}

# The symlink into the custom themes directory. A correct link is left alone; a stale one —
# ours, pointing at a checkout that moved — is replaced; anything that is NOT a symlink is
# somebody's file and refusing is the only safe answer.
_inzsh_install_omz_link() {
  local themes=$1/themes link=$1/themes/inzsh.zsh-theme
  mkdir -p -- $themes
  if [[ -L $link ]]; then
    if [[ ${link:A} != ${_inzsh_install_theme:A} ]]; then
      ln -sfn -- $_inzsh_install_theme $link
      print -r -- "relinked: ${link/#$HOME/~} → the current checkout"
    fi
    return 0
  fi
  if [[ -e $link ]]; then
    print -ru2 -- "install.zsh: ${link/#$HOME/~} exists and is not a symlink — move it aside first"
    return 1
  fi
  ln -s -- $_inzsh_install_theme $link
  print -r -- "linked: ${link/#$HOME/~}"
}

_inzsh_install_omz() {
  local omz
  if ! omz=$(_inzsh_install_omz_root); then
    print -ru2 -- 'install.zsh: no oh-my-zsh found ($ZSH unset, no ~/.oh-my-zsh) — try --plain'
    return 1
  fi

  # Before anything is written, and this is the whole point of writing nothing first: the omz
  # path is two edits that only oh-my-zsh reads. An rc that never loads it would read neither,
  # and an install nobody reads is not an install — so we refuse rather than produce one and
  # call it done. `--omz` is deliberate, so this refuses a deliberate request; the alternative
  # is named because it is the one that works here.
  if ! _inzsh_install_rc_loads_omz; then
    print -ru2 -- "install.zsh: ${_inzsh_install_zshrc/#$HOME/~} never sources oh-my-zsh.sh, so nothing would read ZSH_THEME"
    print -ru2 -- 'install.zsh: refusing to write an install that cannot take effect — use --plain'
    return 1
  fi

  _inzsh_install_omz_link ${ZSH_CUSTOM:-$omz/custom}

  local -a lines want
  _inzsh_install_read; lines=("${(@)reply}")
  _inzsh_install_omz_restore "${(@)lines}"
  _inzsh_install_omz_apply "${(@)reply}"
  want=("${(@)reply}")

  local state="ZSH_THEME is \"inzsh\" in ${_inzsh_install_zshrc/#$HOME/~}"
  if [[ "${(pj:\n:)lines}" == "${(pj:\n:)want}" ]]; then
    _inzsh_install_verdict "$state" unchanged
    return
  fi

  _inzsh_install_backup_once
  _inzsh_install_write "${(@)want}"
  _inzsh_install_verdict "$state" wrote
}

# Uninstall undoes BOTH paths, whichever was used — the managed block, the theme-line edits,
# and the symlink — so one verb takes everything back out. The backup is deliberately left:
# it is the user's pre-inzsh state, and deleting a backup is never the installer's call.
_inzsh_install_uninstall() {
  local -i changed=0

  local -a lines
  _inzsh_install_read; lines=("${(@)reply}")
  _inzsh_install_strip "${(@)lines}"
  _inzsh_install_omz_restore "${(@)reply}"

  if [[ "${(pj:\n:)lines}" != "${(pj:\n:)reply}" ]]; then
    _inzsh_install_write "${(@)reply}"
    print -r -- "uninstalled: ${_inzsh_install_zshrc/#$HOME/~} is back to its pre-install content"
    changed=1
  fi

  local omz
  if omz=$(_inzsh_install_omz_root); then
    local link=${ZSH_CUSTOM:-$omz/custom}/themes/inzsh.zsh-theme
    if [[ -L $link ]]; then
      rm -- $link
      print -r -- "removed: ${link/#$HOME/~}"
      changed=1
    fi
  fi

  if (( ! changed )); then
    print -r -- "nothing installed — nothing to do"
    return 0
  fi
  if [[ -f $_inzsh_install_backup ]]; then
    print -r -- "your pre-install backup is untouched: ${_inzsh_install_backup/#$HOME/~}"
  fi
  return 0
}

_inzsh_install_usage() {
  print -r -- 'usage: zsh install.zsh [--plain|--omz] [--uninstall]'
  print -r -- '  --plain      source the theme from .zshrc'
  print -r -- '  --omz        install as an oh-my-zsh custom theme'
  print -r -- '  (no flag)    oh-my-zsh when one is found, plain otherwise'
  print -r -- '  --uninstall  remove everything the installer added, whichever path put it there'
}

_inzsh_install_main() {
  # NOT named `path` — that is zsh's tied PATH array, and a `local path=…` here would
  # unbind every external command for the rest of the run.
  local mode=install via=auto arg
  for arg in "$@"; do
    case $arg in
      --plain)     via=plain ;;
      --omz)       via=omz ;;
      --uninstall) mode=uninstall ;;
      -h|--help)   _inzsh_install_usage; return 0 ;;
      *) print -ru2 -- "install.zsh: unknown option: $arg"; _inzsh_install_usage >&2; return 1 ;;
    esac
  done

  if [[ $mode == uninstall ]]; then
    _inzsh_install_uninstall
    return
  fi

  [[ -f $_inzsh_install_theme ]] || {
    print -ru2 -- "install.zsh: cannot find $_inzsh_install_theme — run from a full checkout"
    return 1
  }

  # Auto. The rc decides, and the directory only says where to write if it does: a framework
  # that is installed but not loaded is a framework that reads nothing we could write for it.
  # Both have to hold — an rc that loads oh-my-zsh from a directory that is gone is broken in a
  # way the plain path happens to fix.
  if [[ $via == auto ]]; then
    if _inzsh_install_omz_root >/dev/null && _inzsh_install_rc_loads_omz; then
      via=omz
    else
      via=plain
    fi
  fi
  if [[ $via == omz ]]; then
    _inzsh_install_omz
  else
    _inzsh_install_plain
  fi
}

_inzsh_install_main "$@"
