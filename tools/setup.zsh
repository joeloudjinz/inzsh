#!/usr/bin/env zsh
# Installs the native dev toolchain. Idempotent — safe to re-run.
emulate -L zsh
setopt err_exit no_unset pipe_fail

say() { print -- "==> $1" }
warn() { print -u2 -- "!!  $1" }

# zsh floor
autoload -Uz is-at-least
if ! is-at-least 5.8 "$ZSH_VERSION"; then
  warn "zsh >= 5.8 required (found $ZSH_VERSION)"
  exit 1
fi
say "zsh $ZSH_VERSION"

# required zsh modules
if ! zmodload zsh/mathfunc zsh/datetime 2>/dev/null; then
  warn "zsh/mathfunc and zsh/datetime are required"
  exit 1
fi
say "zsh modules: mathfunc, datetime"

# brew-provided tools
if (( $+commands[brew] )); then
  local pkg
  for pkg in shellspec vhs gitleaks; do
    if (( $+commands[$pkg] )); then
      say "$pkg: present"
    else
      say "$pkg: installing"
      brew install "$pkg"
    fi
  done
else
  warn "brew not found — install shellspec, vhs and gitleaks manually"
fi

# python venv + pyte for the L3 grid runner
if (( $+commands[python3] )); then
  [[ -d .venv ]] || python3 -m venv .venv
  ./.venv/bin/pip install --quiet --requirement test/ui/requirements.txt
  say "python venv: .venv (pyte pinned)"
else
  warn "python3 not found — L3 grid tests unavailable"
fi

# repo-local git hooks
git config core.hooksPath tools/hooks
say "git hooks: core.hooksPath -> tools/hooks"

say "setup complete"
