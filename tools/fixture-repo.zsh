#!/usr/bin/env zsh
# InZsh — the git fixture generator. Builds a throwaway repository in a REQUESTED STATE, under
# `$TMPDIR`, deterministically, and never anywhere near the tree you are working in.
#
# It exists because the git segment has seven states and every one of them is a property of a
# repository rather than of a string. A spec that hand-wrote `# branch.ab +2 -3` would be
# asserting against our own idea of what git prints; a spec that builds the repository and asks
# git is asserting against git. The generator is therefore shared between the specs and the
# demo tapes — one definition of "a repository that is two ahead and three behind", used by
# everything that needs one.
#
# THREE RULES, and each of them is the whole reason a line is written the way it is.
#
#   Never the real tree.  Every repository lives under a directory this file created with
#   `mktemp -d` inside `$TMPDIR`, named `inzsh-fixture-*`. `_inzsh_fixture_repo_clean` refuses
#   to remove anything that does not match that pattern, so a caller that passes the wrong path
#   gets a status 1 and not a deleted checkout.
#
#   Never the user's git.  `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM` and `GIT_CONFIG_NOSYSTEM`
#   are pinned so `~/.gitconfig` cannot reach in — a user with `status.showUntrackedFiles=no`,
#   a commit template, a `core.hooksPath`, or `init.defaultBranch=trunk` would otherwise change
#   what the fixture is. `HOME` is redirected into the fixture as well, for the git that
#   predates `GIT_CONFIG_GLOBAL`.
#
#   Never the network.  "Ahead", "behind" and "diverged" all need an upstream, so the fixture
#   grows its own: a bare repository beside the checkout, added as `origin` by PATH. No
#   protocol, no daemon, no clone from anywhere. `GIT_TERMINAL_PROMPT=0` makes a fixture that
#   somehow reached for a credential fail fast rather than block a test run forever.
#
# WHAT IS DETERMINISTIC AND WHAT IS NOT. Author, committer, both dates, both identities, the
# branch name, the file contents and the number of commits are all pinned, so the object ids
# are stable for a given git object format. They are NOT pinned across a repository initialised
# with a different `extensions.objectFormat`, and nothing here asserts a literal sha for that
# reason — specs match the SHAPE of an abbreviated oid, never its value.
#
# USE. As a tool, from the shell:
#
#   zsh tools/fixture-repo.zsh dirty          # builds one, prints its path
#   zsh tools/fixture-repo.zsh --list         # the state names, one per line
#   zsh tools/fixture-repo.zsh --clean PATH   # removes one it made
#
# Or sourced, from a spec:
#
#   source tools/fixture-repo.zsh
#   _inzsh_fixture_repo diverged && repo=$REPLY
#   ...
#   _inzsh_fixture_repo_clean "$repo"

# The identity every fixture commit carries. Pinned rather than absent: git refuses to commit
# without one, and taking the user's would make the object ids depend on who ran the suite.
typeset -g _inzsh_fixture_name='InZsh Fixture'
typeset -g _inzsh_fixture_email='fixture@example.invalid'

# A pinned instant, in a pinned zone. `+0000` is part of the value — a date without an offset
# would be read in the runner's zone and the commit object would differ between machines.
typeset -g _inzsh_fixture_date='2001-01-01T00:00:00+0000'

# The branch every fixture is built on. Written down rather than left to `init.defaultBranch`,
# which differs between git versions and can be set by the user we are refusing to read.
typeset -g _inzsh_fixture_branch='main'

# The prefix that marks a directory as ours, and the only thing `_inzsh_fixture_repo_clean`
# will delete. One string, used to create and to check, so the two cannot drift apart.
typeset -g _inzsh_fixture_prefix='inzsh-fixture-'

# The seven states, in the order the segment's own documentation lists them.
typeset -ga _inzsh_fixture_state_names
_inzsh_fixture_state_names=(clean dirty staged ahead behind diverged detached)

# Every state name, in `reply`. The list is the tool's `--list` output and a spec's Parameters
# block, so neither transcribes it.
_inzsh_fixture_states() {
  emulate -L zsh

  typeset -ga reply
  reply=("${_inzsh_fixture_state_names[@]}")

  return 0
}

# Is `$1` a state this file knows how to build?
_inzsh_fixture_state_valid() {
  emulate -L zsh

  (( ${_inzsh_fixture_state_names[(Ie)$1]} ))
}

# `git` with everything that could vary pinned. Every git call in this file goes through here —
# there is no second place a fixture could pick up an identity, a hook or a default branch.
#
# `-c` rather than `git config`, so nothing is written into the fixture that a later command
# could read differently. `core.hooksPath=/dev/null` is the one that matters most in practice:
# a user with a global `pre-commit` hook would otherwise have it run inside every fixture.
_inzsh_fixture_git() {
  emulate -L zsh

  local root=$1
  shift

  GIT_CONFIG_NOSYSTEM=1 \
  GIT_CONFIG_SYSTEM=/dev/null \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_TERMINAL_PROMPT=0 \
  GIT_ASKPASS=true \
  HOME=$root \
  XDG_CONFIG_HOME=$root/.config \
  GIT_AUTHOR_NAME=$_inzsh_fixture_name \
  GIT_AUTHOR_EMAIL=$_inzsh_fixture_email \
  GIT_AUTHOR_DATE=$_inzsh_fixture_date \
  GIT_COMMITTER_NAME=$_inzsh_fixture_name \
  GIT_COMMITTER_EMAIL=$_inzsh_fixture_email \
  GIT_COMMITTER_DATE=$_inzsh_fixture_date \
  git \
    -c user.name=$_inzsh_fixture_name \
    -c user.email=$_inzsh_fixture_email \
    -c init.defaultBranch=$_inzsh_fixture_branch \
    -c core.hooksPath=/dev/null \
    -c commit.gpgsign=false \
    -c tag.gpgsign=false \
    -c gc.auto=0 \
    -c advice.detachedHead=false \
    -c protocol.file.allow=always \
    "$@"
}

# One commit, with `$3` written into `$2` first. Content and message both derive from the
# argument, so a caller asks for "commit three" and gets the same objects every time.
_inzsh_fixture_commit() {
  emulate -L zsh

  local root=$1 work=$2 mark=$3

  print -r -- "$mark" > "$work/$mark.txt" || return 1
  _inzsh_fixture_git "$root" -C "$work" add -A -- . >/dev/null 2>&1 || return 1
  _inzsh_fixture_git "$root" -C "$work" commit -q -m "$mark" >/dev/null 2>&1 || return 1

  return 0
}

# `_inzsh_fixture_build <state> <root>` — everything that happens INSIDE an already-created
# fixture root. Split out from `_inzsh_fixture_repo` for one reason: every step below is
# `|| return 1`, and a failure has to leave the caller holding the root so it can be removed.
# A single function could not both bail early and clean up after itself.
#
# The layout is always the same, whatever the state:
#
#   <root>/origin.git   a bare repository, the upstream. Local path, never a URL.
#   <root>/work         the checkout.
#
# Every state starts from the same synchronised baseline — one commit, pushed, tracking
# `origin/main` — and then does the one thing that names it. That is deliberate: the diff
# between two states is exactly the lines below the `case`, so what "staged" means is readable
# rather than inferred from two separately built repositories.
_inzsh_fixture_build() {
  emulate -L zsh

  local state=$1 root=$2
  local origin=$root/origin.git
  local work=$root/work

  # The upstream first, so the checkout can be pushed the moment it has a commit.
  _inzsh_fixture_git "$root" init -q --bare -b "$_inzsh_fixture_branch" "$origin" \
    >/dev/null 2>&1 || return 1
  _inzsh_fixture_git "$root" init -q -b "$_inzsh_fixture_branch" "$work" \
    >/dev/null 2>&1 || return 1

  _inzsh_fixture_commit "$root" "$work" base || return 1
  _inzsh_fixture_git "$root" -C "$work" remote add origin "$origin" >/dev/null 2>&1 || return 1
  _inzsh_fixture_git "$root" -C "$work" push -q -u origin "$_inzsh_fixture_branch" \
    >/dev/null 2>&1 || return 1

  # From here on, one block per state, and each is the smallest thing that produces it.
  case $state in
    (clean)
      ;;

    (dirty)
      # A TRACKED file modified in the worktree and not staged. Untracked files are a separate
      # column in porcelain v2 and deserve their own fixture the day something distinguishes
      # them; this one pins the `.M` case and nothing else.
      print -r -- 'modified' >> "$work/base.txt" || return 1
      ;;

    (staged)
      # The same edit, in the index. `M.` rather than `.M`, and a clean worktree beside it.
      print -r -- 'staged' >> "$work/base.txt" || return 1
      _inzsh_fixture_git "$root" -C "$work" add -- base.txt >/dev/null 2>&1 || return 1
      ;;

    (ahead)
      _inzsh_fixture_commit "$root" "$work" ahead-1 || return 1
      _inzsh_fixture_commit "$root" "$work" ahead-2 || return 1
      ;;

    (behind)
      # Commit, push, then rewind the checkout. The remote-tracking ref is already at the new
      # tip because WE pushed it, so no fetch is needed and no second clone exists to keep in
      # step — the upstream is ahead because the local branch moved back.
      _inzsh_fixture_commit "$root" "$work" behind-1 || return 1
      _inzsh_fixture_commit "$root" "$work" behind-2 || return 1
      _inzsh_fixture_commit "$root" "$work" behind-3 || return 1
      _inzsh_fixture_git "$root" -C "$work" push -q origin "$_inzsh_fixture_branch" \
        >/dev/null 2>&1 || return 1
      _inzsh_fixture_git "$root" -C "$work" reset -q --hard HEAD~3 >/dev/null 2>&1 || return 1
      ;;

    (diverged)
      # Behind by three, then two commits of our own on top of the rewind: the two histories
      # share the base commit and nothing after it.
      _inzsh_fixture_commit "$root" "$work" remote-1 || return 1
      _inzsh_fixture_commit "$root" "$work" remote-2 || return 1
      _inzsh_fixture_commit "$root" "$work" remote-3 || return 1
      _inzsh_fixture_git "$root" -C "$work" push -q origin "$_inzsh_fixture_branch" \
        >/dev/null 2>&1 || return 1
      _inzsh_fixture_git "$root" -C "$work" reset -q --hard HEAD~3 >/dev/null 2>&1 || return 1
      _inzsh_fixture_commit "$root" "$work" local-1 || return 1
      _inzsh_fixture_commit "$root" "$work" local-2 || return 1
      ;;

    (detached)
      # HEAD at a commit rather than on a branch. There is no upstream in this state — git
      # reports no `# branch.ab` line at all — which is why the segment never draws a
      # divergence beside a detached ref.
      _inzsh_fixture_commit "$root" "$work" detached-1 || return 1
      _inzsh_fixture_git "$root" -C "$work" checkout -q --detach HEAD >/dev/null 2>&1 \
        || return 1
      ;;
  esac

  return 0
}

# `_inzsh_fixture_repo <state> [parent]` — a repository in `<state>`, its CHECKOUT path in
# REPLY.
#
# `parent` is where the fixture's own directory is created and defaults to `$TMPDIR`. It is an
# argument only so that a caller with its own scratch area can keep everything in one place;
# the directory inside it is still made by `mktemp -d` and still carries the prefix, so the
# cleanup guarantee does not depend on the caller passing anything sensible.
#
# Status 1 with an empty REPLY when the state is unknown, when git is not installed, or when
# any step fails. A partially built fixture is REMOVED on the way out rather than returned: a
# spec that got a path is entitled to assume the state it asked for.
_inzsh_fixture_repo() {
  emulate -L zsh

  typeset -g REPLY=

  local state=$1
  _inzsh_fixture_state_valid "$state" || return 1
  (( ${+commands[git]} )) || return 1

  local parent=${2:-${TMPDIR:-/tmp}}
  parent=${parent%/}
  [[ -d $parent ]] || return 1

  local root
  root=$(mktemp -d "$parent/${_inzsh_fixture_prefix}XXXXXX" 2>/dev/null) || return 1
  [[ -n $root && -d $root ]] || return 1

  if ! _inzsh_fixture_build "$state" "$root"; then
    _inzsh_fixture_repo_clean "$root"
    return 1
  fi

  typeset -g REPLY=$root/work

  return 0
}

# Remove a fixture, whole. `$1` is either the checkout this file handed out or the directory
# above it; both resolve to the same fixture root, and anything else is refused.
#
# THE GUARD IS THE FUNCTION. `rm -rf` on a path that came from somewhere else is how a test
# harness deletes somebody's work, so the target must be under a temporary directory, must carry
# the prefix this file creates with, and must not be the temporary directory itself. All three,
# or nothing is removed and the status is 1.
#
# THE LOCAL IS CALLED `target` AND NOT `path`. `path` is zsh's array view of `$PATH`, and a
# `local path=…` in a function sets the shell's command search path to that one string for as
# long as the function runs — `rm` is then not found, the removal fails silently behind its own
# `2>/dev/null`, and the guard reports success on a fixture it did not delete. It is the single
# most expensive variable name in zsh and it costs nothing to avoid.
_inzsh_fixture_repo_clean() {
  emulate -L zsh
  setopt extended_glob

  local target=${1-}
  [[ -n $target ]] || return 1

  # The checkout is one level inside the fixture; accept either and work on the root.
  [[ ${target:t} == work ]] && target=${target:h}
  [[ -d $target ]] || return 1

  # Resolved, so `..` in the argument cannot walk out of the prefix check below.
  target=${target:A}

  [[ ${target:t} == ${_inzsh_fixture_prefix}* ]] || return 1
  [[ $target != / && $target != $HOME && ${target:h} != / ]] || return 1

  rm -rf -- "$target" 2>/dev/null || return 1

  return 0
}

# ---------------------------------------------------------------------------------------------
# The tool. Everything above is a function and stays one when this file is sourced; the block
# below runs only when the file is EXECUTED, which `zsh_eval_context` answers exactly — its
# last element is `toplevel` for a script and `file` for a `source`.

_inzsh_fixture_usage() {
  emulate -L zsh

  print -r -- 'usage: fixture-repo.zsh <state> [parent]   build one, print its path'
  print -r -- '       fixture-repo.zsh --list             the state names'
  print -r -- '       fixture-repo.zsh --clean <path>     remove one this tool made'

  return 0
}

_inzsh_fixture_main() {
  emulate -L zsh

  case ${1-} in
    (''|-h|--help)
      _inzsh_fixture_usage
      return 0
      ;;

    (--list)
      _inzsh_fixture_states
      print -rl -- "${reply[@]}"
      return 0
      ;;

    (--clean)
      _inzsh_fixture_repo_clean "${2-}" || {
        print -ru2 -- "fixture-repo: refusing to remove '${2-}'"
        return 1
      }
      return 0
      ;;
  esac

  if ! _inzsh_fixture_state_valid "$1"; then
    print -ru2 -- "fixture-repo: unknown state '$1'"
    _inzsh_fixture_usage >&2
    return 2
  fi

  _inzsh_fixture_repo "$1" "${2-}" || {
    print -ru2 -- "fixture-repo: could not build a '$1' fixture"
    return 1
  }

  print -r -- "$REPLY"

  return 0
}

if [[ ${zsh_eval_context[-1]} == toplevel ]]; then
  _inzsh_fixture_main "$@"
  exit $?
fi
