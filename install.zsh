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

  if [[ "${(pj:\n:)lines}" == "${(pj:\n:)want}" ]]; then
    print -r -- "already installed — nothing to do"
    return 0
  fi

  _inzsh_install_backup_once
  _inzsh_install_write "${(@)want}"
  print -r -- "installed: ${_inzsh_install_zshrc/#$HOME/~} sources the theme"
  print -r -- "open a new shell to see the prompt"
}

_inzsh_install_uninstall() {
  local -a lines
  _inzsh_install_read; lines=("${(@)reply}")
  _inzsh_install_strip "${(@)lines}"

  if [[ "${(pj:\n:)lines}" == "${(pj:\n:)reply}" ]]; then
    print -r -- "nothing installed — nothing to do"
    return 0
  fi

  _inzsh_install_write "${(@)reply}"
  print -r -- "uninstalled: the managed block is out of ${_inzsh_install_zshrc/#$HOME/~}"
  if [[ -f $_inzsh_install_backup ]]; then
    print -r -- "your pre-install backup is untouched: ${_inzsh_install_backup/#$HOME/~}"
  fi
  return 0
}

_inzsh_install_usage() {
  print -r -- 'usage: zsh install.zsh [--plain] [--uninstall]'
  print -r -- '  --plain      source the theme from .zshrc (the default)'
  print -r -- '  --uninstall  remove everything the installer added'
}

_inzsh_install_main() {
  # NOT named `path` — that is zsh's tied PATH array, and a `local path=…` here would
  # unbind every external command for the rest of the run.
  local mode=install via=plain arg
  for arg in "$@"; do
    case $arg in
      --plain)     via=plain ;;
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
  _inzsh_install_plain
}

_inzsh_install_main "$@"
