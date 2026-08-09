# The git fixture generator — `tools/fixture-repo.zsh`. Whether a repository it builds is
# actually in the state it was asked for, whether it is deterministic, and whether it can be
# trusted with `rm -rf`.
#
# THIS IS THE ONE SPEC IN THE TREE THAT RUNS `git`. Everything else asserts against injected
# state, which is the point of the seams; this file asserts that the injected state the other
# specs use is the state a real repository would produce. Every repository it makes lives under
# `$TMPDIR` and is removed in the same example that made it.
#
# The states are read back with `git status --porcelain=v2 --branch`, which is the same single
# invocation `lib/segments/git-async.zsh` uses. That is deliberate: if git ever changes what it
# prints, both the fixture and the worker learn about it here.

Include tools/fixture-repo.zsh

# The interesting facts about a repository, as one line: which branch (or `detached`), how the
# upstream compares, and the index/worktree columns of every changed path.
#
# Read through `_inzsh_fixture_git` so the probe is subject to the same pinned environment as
# the build — a probe that read the user's `status.showUntrackedFiles` would report a different
# repository from the one the fixture made.
inzsh_spec_fixture_facts() {
  emulate -L zsh

  local repo=$1
  local root=${repo:h}
  local head=? ab=none
  local -a changed=()
  local line

  while IFS= read -r line; do
    case $line in
      ('# branch.head '*) head=${line#'# branch.head '} ;;
      ('# branch.ab '*)   ab=${line#'# branch.ab '} ;;
      ([12]' '*)          changed+=${line[3,4]} ;;
      ('u '*)             changed+=unmerged ;;
      ('? '*)             changed+=untracked ;;
    esac
  done < <(
    _inzsh_fixture_git "$root" -C "$repo" --no-optional-locks status \
      --porcelain=v2 --branch --untracked-files=normal 2>/dev/null
  )

  print -r -- "head=$head ab=$ab changed=${changed[*]:-none}"

  return 0
}

# Build `$1`, report its facts, remove it. One example, one repository, no repository left
# behind — and the removal goes through the guarded cleanup, so every example is also an
# example of the guard accepting what it should.
inzsh_spec_fixture() {
  emulate -L zsh

  _inzsh_fixture_repo "$1" || {
    print -r -- 'build-failed'
    return 0
  }
  local repo=$REPLY

  inzsh_spec_fixture_facts "$repo"
  _inzsh_fixture_repo_clean "$repo"

  return 0
}

Describe 'the git fixture generator'
  # --------------------------------------------------------------------------------------------
  Describe 'the state list'
    It 'names the seven states the segment draws'
      # The list is the contract between this file, the segment and the demo tapes. It is
      # transcribed nowhere: `--list` prints it and a Parameters block reads it.
      states() {
        _inzsh_fixture_states
        print -r -- "${reply[*]}"
      }
      When call states
      The output should eq 'clean dirty staged ahead behind diverged detached'
    End

    It 'prints them one per line as a tool'
      listed() {
        zsh -f "$SHELLSPEC_PROJECT_ROOT/tools/fixture-repo.zsh" --list
      }
      When call listed
      The line 1 should eq 'clean'
      The line 7 should eq 'detached'
      The stderr should eq ''
    End

    It 'refuses a state it does not know, and says so on stderr rather than on stdout'
      unknown() {
        zsh -f "$SHELLSPEC_PROJECT_ROOT/tools/fixture-repo.zsh" chartreuse
      }
      When run unknown
      The status should eq 2
      The output should eq ''
      The stderr should include 'chartreuse'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'each state is the state it claims'
    # The whole point of the generator, one example per state. `changed` is the index and
    # worktree columns straight out of porcelain v2: `.M` is modified-not-staged, `M.` is
    # staged-and-clean.
    #
    # $1 the state; $2 what git says about the repository it built.
    Parameters
      clean    'head=main ab=+0 -0 changed=none'
      dirty    'head=main ab=+0 -0 changed=.M'
      staged   'head=main ab=+0 -0 changed=M.'
      ahead    'head=main ab=+2 -0 changed=none'
      behind   'head=main ab=+0 -3 changed=none'
      diverged 'head=main ab=+2 -3 changed=none'
      detached 'head=(detached) ab=none changed=none'
    End

    It "builds $1"
      When call inzsh_spec_fixture "$1"
      The output should eq "$2"
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'determinism'
    It 'produces the same commit twice, so nothing downstream can depend on the clock'
      # Author, committer, both dates, the branch name and the file contents are all pinned, so
      # the object ids are a function of the state name alone. This is what lets a golden file or
      # a demo tape carry a fixture's output.
      twice() {
        local -a oids=()
        # Declared once, above the loop. A bare `local line` INSIDE it re-declares a parameter
        # that is already local on the second turn, and zsh answers a declaration with no value
        # over an existing parameter by PRINTING it — `line=''` lands in the middle of the
        # assertion's output.
        local n repo line=
        for n in 1 2; do
          _inzsh_fixture_repo clean || { print -r -- build-failed; return 0 }
          repo=$REPLY
          while IFS= read -r line; do
            [[ $line == '# branch.oid '* ]] && oids+=${line#'# branch.oid '}
          done < <(
            _inzsh_fixture_git "${repo:h}" -C "$repo" --no-optional-locks status \
              --porcelain=v2 --branch 2>/dev/null
          )
          _inzsh_fixture_repo_clean "$repo"
        done
        if [[ -n ${oids[1]} && ${oids[1]} == ${oids[2]} ]]; then
          print -r -- same
        else
          print -r -- "${oids[*]}"
        fi
      }
      When call twice
      The output should eq 'same'
    End

    It 'shows git a pinned identity and an empty global configuration'
      # Asked of git DIRECTLY, because that is the only witness that cannot be talked round.
      # `git var GIT_AUTHOR_IDENT` prints the name, address and instant git would stamp a commit
      # with, and `git config --global --list` prints the configuration it would obey — both
      # with a hostile identity and a hostile config file exported into the environment first.
      #
      # 978307200 is the pinned date as a unix instant. Written as the number rather than
      # recomputed, because a spec that derived it from `$_inzsh_fixture_date` would agree with
      # the generator about a date they had both got wrong.
      pinned() {
        local scratch
        scratch=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-fixture-hostile-XXXXXX") || return 1
        {
          print -r -- '[user]'
          print -r -- '	name = Somebody Else'
          print -r -- '	email = somebody@example.invalid'
          print -r -- '[init]'
          print -r -- '	defaultBranch = trunk'
        } > "$scratch/gitconfig"

        local -x GIT_CONFIG_GLOBAL=$scratch/gitconfig
        local -x HOME=$scratch
        local -x GIT_AUTHOR_NAME='Somebody Else'
        local -x GIT_AUTHOR_EMAIL='somebody@example.invalid'
        local -x GIT_AUTHOR_DATE='1999-06-06T06:06:06+0000'

        print -r -- "ident=$(_inzsh_fixture_git "$scratch" var GIT_AUTHOR_IDENT 2>/dev/null)"
        print -r -- "global=[$(_inzsh_fixture_git "$scratch" config --global --list 2>/dev/null)]"

        rm -rf -- "$scratch"
      }
      When call pinned
      The line 1 should eq 'ident=InZsh Fixture <fixture@example.invalid> 978307200 +0000'
      The line 2 should eq 'global=[]'
    End

    It 'ignores the user git configuration entirely'
      # `~/.gitconfig` is the commonest reason a fixture behaves differently on two machines.
      # A hostile one is pointed at the process here — a different default branch, untracked
      # files hidden, a commit template — and the fixture must come out identical.
      hostile() {
        local scratch
        scratch=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-fixture-hostile-XXXXXX") || return 1
        {
          print -r -- '[init]'
          print -r -- '	defaultBranch = trunk'
          print -r -- '[status]'
          print -r -- '	showUntrackedFiles = no'
          print -r -- '[user]'
          print -r -- '	name = Somebody Else'
        } > "$scratch/gitconfig"

        # `local -x`, not `local`. A plain `local` on an exported parameter creates an
        # UNEXPORTED shadow, so the hostile file would never reach git at all and the example
        # would pass against a generator that had stopped pinning anything.
        local -x GIT_CONFIG_GLOBAL=$scratch/gitconfig
        local -x HOME=$scratch
        inzsh_spec_fixture dirty

        rm -rf -- "$scratch"
      }
      When call hostile
      The output should eq 'head=main ab=+0 -0 changed=.M'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'where it builds'
    It 'builds under $TMPDIR and nowhere else'
      # The safety rule, asserted on the path that comes back. Nothing in a spec or a demo ever
      # names a directory to build in, so this is the only place it can be wrong.
      located() {
        _inzsh_fixture_repo clean || { print -r -- build-failed; return 0 }
        local repo=$REPLY
        local parent=${${TMPDIR:-/tmp}%/}
        local -a wrong=()
        # Both sides resolved: on macOS `$TMPDIR` is under `/var`, which is a symlink to
        # `/private/var`, and an unresolved comparison fails on a fixture that is in exactly the
        # right place.
        [[ ${repo:h:h:A} == ${parent:A} ]]    || wrong+="parent=${repo:h:h:A}"
        [[ ${repo:h:t} == inzsh-fixture-* ]]  || wrong+="prefix=${repo:h:t}"
        [[ ${repo:t} == work ]]               || wrong+="tail=${repo:t}"
        _inzsh_fixture_repo_clean "$repo"
        print -r -- "${wrong[*]}"
      }
      When call located
      The output should eq ''
    End

    It 'leaves nothing behind when it is cleaned up'
      gone() {
        _inzsh_fixture_repo clean || { print -r -- build-failed; return 0 }
        local repo=$REPLY
        _inzsh_fixture_repo_clean "$repo"
        [[ -e ${repo:h} ]] && print -r -- "still there: ${repo:h}" || print -r -- gone
      }
      When call gone
      The output should eq 'gone'
    End

    It 'removes the whole fixture when handed the checkout inside it'
      # Callers hold the checkout, not the root — the cleanup takes either and removes the root,
      # so a caller cannot leak the bare upstream by cleaning up the only path it was given.
      whole() {
        _inzsh_fixture_repo ahead || { print -r -- build-failed; return 0 }
        local repo=$REPLY
        _inzsh_fixture_repo_clean "$repo"
        [[ -e ${repo:h}/origin.git ]] && print -r -- upstream-left || print -r -- gone
      }
      When call whole
      The output should eq 'gone'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the cleanup guard'
    # `rm -rf` on a path that came from somewhere else is how a test harness deletes somebody's
    # work. The guard is the function, and these are the inputs it has to refuse.
    Describe 'it refuses a path it did not create'
      Parameters
        '/'
        ''
        '/tmp'
        '/usr/local'
      End

      It "refuses '$1'"
        When call _inzsh_fixture_repo_clean "$1"
        The status should be failure
      End
    End

    It 'refuses a directory under $TMPDIR that does not carry the prefix'
      # Being temporary is not enough. Another suite's scratch directory is under `$TMPDIR` too.
      foreign() {
        local scratch
        scratch=$(mktemp -d "${TMPDIR:-/tmp}/somebody-else-XXXXXX") || return 1
        _inzsh_fixture_repo_clean "$scratch"
        local status_=$?
        local left=gone
        [[ -d $scratch ]] && left=intact
        rm -rf -- "$scratch"
        print -r -- "status=$status_ $left"
      }
      When call foreign
      The output should eq 'status=1 intact'
    End

    It 'cannot be walked out of the prefix with a relative path'
      # `…/inzsh-fixture-XXXX/work/../../..` resolves outside the prefix, so the check is made on
      # the RESOLVED path and not on the argument.
      escaped() {
        _inzsh_fixture_repo clean || { print -r -- build-failed; return 0 }
        local repo=$REPLY
        _inzsh_fixture_repo_clean "$repo/../../.."
        local status_=$?
        local left=gone
        [[ -d ${repo:h} ]] && left=intact
        _inzsh_fixture_repo_clean "$repo"
        print -r -- "status=$status_ $left"
      }
      When call escaped
      The output should eq 'status=1 intact'
    End

    It 'refuses through the tool as well, and says which path it refused'
      refused() {
        zsh -f "$SHELLSPEC_PROJECT_ROOT/tools/fixture-repo.zsh" --clean /usr/local
      }
      When run refused
      The status should be failure
      The stderr should include '/usr/local'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/tools/fixture-repo.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sourcing it builds nothing and prints nothing'
      # It is a library first and a tool second. `zsh_eval_context` is what tells the two apart,
      # and a file that ran its main on `source` would build a repository inside every spec that
      # loaded it.
      quiet() {
        zsh -f -c '
          source "$1/tools/fixture-repo.zsh"
          print -r -- "states=${#_inzsh_fixture_state_names} fn=${+functions[_inzsh_fixture_repo]}"
        ' inzsh-fixture-quiet "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'states=7 fn=1'
      The stderr should eq ''
    End

    It 'names no `.claude` path and no absolute path from this machine'
      neutral() {
        setopt local_options extended_glob
        local line; local -a bad=()
        while IFS= read -r line; do
          [[ ${line##[[:space:]]#} == \#* ]] && continue
          [[ $line == *'.claude'* || $line == *'/Users/'* || $line == *'/home/'* ]] && bad+=$line
        done < "$SHELLSPEC_PROJECT_ROOT/tools/fixture-repo.zsh"
        print -rl -- $bad
      }
      When call neutral
      The output should eq ''
    End

    It 'reaches no network — every remote it configures is a path on this machine'
      # `ahead`, `behind` and `diverged` all need an upstream. The upstream is a bare repository
      # beside the checkout, so a suite running with no network, or behind a proxy that eats
      # git's protocols, builds exactly the same fixtures.
      offline() {
        setopt local_options extended_glob
        local line; local -a bad=()
        while IFS= read -r line; do
          [[ ${line##[[:space:]]#} == \#* ]] && continue
          [[ $line == *'://'* || $line == *'@github'* || $line == *'git clone'* ]] && bad+=$line
        done < "$SHELLSPEC_PROJECT_ROOT/tools/fixture-repo.zsh"
        print -rl -- $bad
      }
      When call offline
      The output should eq ''
    End
  End
End
