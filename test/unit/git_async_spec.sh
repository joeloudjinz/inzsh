Include lib/core/tokens.zsh
Include lib/core/config.zsh
Include lib/segments/git.zsh
Include lib/segments/git-async.zsh

# The git status worker — `lib/segments/git-async.zsh`. The only asynchronous file in the repo,
# and the one place a subprocess is allowed to exist at all.
#
# Four concerns, and they are tested at different distances:
#
#   the key and the entry   pure functions over strings and files. No git, no jobs.
#   the parser              real `git status --porcelain=v2` output, produced by
#                           `tools/fixture-repo.zsh`, plus hostile output no git would ever
#                           print.
#   the worker              end to end, in a `zsh -f` of its own: a repository in a known state
#                           goes in, a rendered fragment comes out.
#   resilience              the timeout firing, a corrupt entry, a directory that is not a
#                           repository, a deleted `$PWD`, a repository far too large to walk,
#                           and two shells writing the same entry at once.
#
# The `zle -F` half — the repaint that happens with no keypress — is asserted structurally here
# and only here. It needs a real line editor on a real terminal, which is `test/ui/`'s layer and
# not this one; what this file can prove is that the registration exists, that the handler is
# the function the registration names, and that the collect-and-repaint decision is right.
#
# EVERY EXAMPLE OWNS ITS OWN CACHE DIRECTORY. `INZSH_GIT_CACHE_DIR` is pointed at a fresh
# `mktemp -d` and removed afterwards, so no example can read an entry another one wrote and
# nothing is ever written to the real `$XDG_CACHE_HOME`.

# The end-to-end fragments pin the glyph the multibyte table draws; the single-byte table
# draws a different one, which is a real difference rather than a defect — those examples are
# skipped there, through the guard in `test/spec_helper.sh`.

# A scratch cache directory, in REPLY. Named so the cleanup below can refuse anything else.
inzsh_spec_git_cache() {
  emulate -L zsh

  typeset -g REPLY=
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-git-spec-XXXXXX") || return 1
  typeset -g REPLY=$dir

  return 0
}

inzsh_spec_git_cache_clean() {
  emulate -L zsh

  local target=${1-}
  [[ ${target:t} == inzsh-git-spec-* ]] || return 1
  rm -rf -- "$target" 2>/dev/null

  return 0
}

# Run `$1` in a `zsh -f` that has loaded the whole theme, the worker and the fixture generator,
# with a scratch cache directory in `$INZSH_GIT_CACHE_DIR` and the project root in `$root`. Each
# example gets a shell of its own: the worker installs hooks, opens descriptors and starts
# background jobs, and none of that belongs in the shell running the suite.
inzsh_spec_git_shell() {
  emulate -L zsh

  zsh -f -c '
    typeset -g root=$1
    source $root/lib/core/detect.zsh
    source $root/lib/core/config.zsh
    source $root/lib/core/tokens-256.zsh
    source $root/lib/core/tokens.zsh
    source $root/lib/core/layout.zsh
    source $root/lib/core/engine.zsh
    source $root/lib/core/render.zsh
    source $root/lib/core/hooks.zsh
    source $root/lib/segments/git.zsh
    source $root/lib/segments/git-async.zsh
    source $root/tools/fixture-repo.zsh

    export INZSH_GIT_CACHE_DIR
    INZSH_GIT_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-git-spec-XXXXXX") || exit 1

    # One second rather than the shipped two. The job'"'"'s watchdog is a `sleep` that outlives
    # the job whenever git wins the race, and it holds the descriptors it inherited until it
    # expires — invisible in a real shell, and a second of dead wall time per example here.
    export INZSH_GIT_TIMEOUT=1

    eval "$2"

    cd /
    rm -rf -- "$INZSH_GIT_CACHE_DIR"
  ' inzsh-git-async "$SHELLSPEC_PROJECT_ROOT" "$1"
}

# The same, in a genuinely INTERACTIVE shell. `_inzsh_git_async_install` no-ops where there is
# no prompt — which is correct, and which means the hook examples cannot use the harness above.
# `PROMPT=` and the two `noprompt*` options are about the harness and not the theme: an
# interactive zsh writes its prompt to stderr, and these examples assert on stderr.
inzsh_spec_git_shell_live() {
  emulate -L zsh

  PROMPT= RPROMPT= PS1= zsh -f -i -o nopromptcr -o nopromptsp -c '
    typeset -g root=$1
    source $root/lib/core/config.zsh
    source $root/lib/core/engine.zsh
    source $root/lib/core/render.zsh
    source $root/lib/core/hooks.zsh
    source $root/lib/segments/git.zsh
    source $root/lib/segments/git-async.zsh

    export INZSH_GIT_CACHE_DIR
    INZSH_GIT_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-git-spec-XXXXXX") || exit 1

    eval "$2"

    rm -rf -- "$INZSH_GIT_CACHE_DIR"
  ' inzsh-git-async-live "$SHELLSPEC_PROJECT_ROOT" "$1"
}

# The glyphs rewritten to letters, so every expectation in this file stays ASCII. Same mapping as
# `test/render/segment_git_spec.sh`: C ✓ · ! dirty · i staged · D — detached · A ↑ · B ↓.
inzsh_spec_git_mark() {
  emulate -L zsh

  local text=$1
  text=${text//$_inzsh_git_glyph_clean/C}
  text=${text//$_inzsh_git_glyph_detached/D}
  text=${text//$_inzsh_git_glyph_ahead/A}
  text=${text//$_inzsh_git_glyph_behind/B}

  print -r -- "$text"
}

# Build a fixture in state `$1`, let the worker answer, and report the fragment it produced.
inzsh_spec_git_worker() {
  emulate -L zsh

  local out
  out=$(inzsh_spec_git_shell '
    _inzsh_fixture_repo '"$1"' || { print -r -- fixture-failed; return 0 }
    typeset -g repo=$REPLY
    cd $repo
    _inzsh_git_async_start "$PWD" || { print -r -- start-failed; return 0 }
    _inzsh_git_async_wait 20 >/dev/null
    _inzsh_segment_git_build
    print -r -- "[${_inzsh_segment_text[GIT]}] ${_inzsh_segment_fg_role[GIT]}"
    cd /
    _inzsh_fixture_repo_clean $repo
  ')

  inzsh_spec_git_mark "$out"
}

# A raw porcelain file written by hand, parsed, and reported as the fields that matter.
inzsh_spec_git_parse() {
  emulate -L zsh

  local raw
  raw=$(mktemp "${TMPDIR:-/tmp}/inzsh-git-raw-XXXXXX") || return 1
  print -rl -- "$@" > "$raw"

  _inzsh_git_parse "$raw"
  local -A got=("${reply[@]}")
  rm -f -- "$raw"

  print -r -- "branch=${got[branch]} sha=${got[sha]} detached=${got[detached]}" \
    "staged=${got[staged]} dirty=${got[dirty]} untracked=${got[untracked]}" \
    "conflicts=${got[conflicts]} ahead=${got[ahead]} behind=${got[behind]}"
}

# One porcelain line, parsed, reported as the four counts it contributes.
_inzsh_git_parse_counts_of() {
  emulate -L zsh

  local raw
  raw=$(mktemp "${TMPDIR:-/tmp}/inzsh-git-raw-XXXXXX") || return 1
  print -r -- "$1" > "$raw"

  _inzsh_git_parse "$raw"
  local -A got=("${reply[@]}")
  rm -f -- "$raw"

  print -r -- "${got[staged]} ${got[dirty]} ${got[untracked]} ${got[conflicts]}"
}

# The non-comment lines of the worker source, for the structural groups.
inzsh_spec_git_async_lines() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga inzsh_spec_lines
  inzsh_spec_lines=()

  local line bare
  while IFS= read -r line; do
    bare=${line##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    inzsh_spec_lines+=$line
  done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/git-async.zsh"

  return 0
}

Describe 'the git status worker'
  # --------------------------------------------------------------------------------------------
  Describe 'the cache key'
    # The key is what stops repository A's status appearing while you stand in repository B. It
    # has to be a pure function of the path, safe as a filename, and short enough to be one.
    It 'is eight lower-case hex digits'
      shaped() {
        setopt local_options extended_glob
        _inzsh_git_cache_key /some/where
        [[ $REPLY == [0-9a-f](#c8) ]] && print -r -- shaped || print -r -- "$REPLY"
      }
      When call shaped
      The output should eq 'shaped'
    End

    It 'is the same answer every time, so an entry can be found again'
      stable() {
        _inzsh_git_cache_key /some/where
        local first=$REPLY
        _inzsh_git_cache_key /some/where
        [[ $first == $REPLY ]] && print -r -- stable || print -r -- "$first != $REPLY"
      }
      When call stable
      The output should eq 'stable'
    End

    It 'separates two directories that differ by one character'
      # The whole bug this exists to prevent is two repositories sharing an entry. A hash that
      # collided on neighbouring paths would be worse than no hash at all.
      distinct() {
        local -A seen=()
        local p
        for p in /a /b /repo/one /repo/two /repo/onf ' ' '' /repo/one/; do
          _inzsh_git_cache_key "$p"
          seen[$REPLY]=1
        done
        print -r -- ${#seen}
      }
      When call distinct
      The output should eq '8'
    End

    Describe 'it survives every character a path may legally contain'
      # A path may hold anything but `/` and NUL. The character code is read through a NAMED
      # parameter for exactly this reason — `##${…}` takes the character that follows it in the
      # SOURCE, so a space or a parenthesis would be an arithmetic syntax error rather than a
      # hash.
      Parameters
        '/a b/c'
        '/x)y'
        '/x(y'
        '/a#b'
        '/a$b'
        '/tab	here'
        '/héllo/wörld'
        '/*/?/['
      End

      It "hashes '$1' without erroring"
        hashed() {
          setopt local_options extended_glob
          _inzsh_git_cache_key "$1"
          [[ $REPLY == [0-9a-f](#c8) ]] && print -r -- ok || print -r -- "bad:$REPLY"
        }
        When call hashed "$1"
        The output should eq 'ok'
        The stderr should eq ''
      End
    End

    It 'costs no fork — it is reached from precmd'
      # Asserted structurally, over the function's own source. `printf -v` and arithmetic, and
      # nothing that could start a process.
      pure() {
        setopt local_options extended_glob
        local body=${functions[_inzsh_git_cache_key]}
        local -a bad=()
        [[ $body == *'$('* || $body == *'`'* ]] && bad+=substitution
        [[ $body == *'printf -v'* ]]            || bad+=no-printf-v
        print -r -- "${bad[*]}"
      }
      When call pure
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the entry'
    It 'round-trips every field it writes'
      trip() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_path /repo/one
        local file=$REPLY
        _inzsh_git_cache_write /repo/one "$file" tok \
          repo 1 branch main sha abcdef1 detached 0 \
          staged 2 dirty 3 untracked 4 conflicts 5 ahead 6 behind 7 timeout 0
        _inzsh_git_cache_read /repo/one
        local -i rc=$?
        print -r -- "rc=$rc repo=${_inzsh_git_status[repo]} branch=${_inzsh_git_status[branch]}" \
          "sha=${_inzsh_git_status[sha]} staged=${_inzsh_git_status[staged]}" \
          "dirty=${_inzsh_git_status[dirty]} ahead=${_inzsh_git_status[ahead]}" \
          "behind=${_inzsh_git_status[behind]}"
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call trip
      The output should eq 'rc=0 repo=1 branch=main sha=abcdef1 staged=2 dirty=3 ahead=6 behind=7'
    End

    It 'leaves no temporary behind — the write is a rename, not a copy'
      # A `.tmp` still sitting there is either a write that did not finish or a rename that was
      # really a copy, and both mean a reader can see half an entry.
      atomic() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_path /repo/one
        _inzsh_git_cache_write /repo/one "$REPLY" tok repo 1 branch main
        local -a leftovers=("$INZSH_GIT_CACHE_DIR"/*.tmp(N))
        print -r -- "temporaries=${#leftovers}"
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call atomic
      The output should eq 'temporaries=0'
    End

    It 'renames a temporary into place and never opens the entry itself'
      # The atomicity claim, asserted DIRECTLY rather than by racing for it. A rename is atomic
      # only because the content is already complete somewhere else when it happens — so the two
      # facts that matter are that the source and the destination are different paths, and that
      # the destination did not exist while the content was being written.
      #
      # `_inzsh_git_mv` is stood in with a spy for the duration. Racing readers against writers,
      # which the example below does, can only ever say "it did not happen this time": the
      # window a direct write leaves open is microseconds wide and a suite that depended on
      # landing in it would be a suite that passed on a broken cache most days.
      spied() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_path /repo/spy
        local file=$REPLY

        local saved=$functions[_inzsh_git_mv]
        typeset -g inzsh_spec_from= inzsh_spec_to= inzsh_spec_pre=
        _inzsh_git_mv() {
          inzsh_spec_from=${@[-2]}
          inzsh_spec_to=${@[-1]}
          inzsh_spec_pre=absent
          [[ -e ${@[-1]} ]] && inzsh_spec_pre=present
          command mv "$@" 2>/dev/null
        }

        _inzsh_git_cache_write /repo/spy "$file" tok repo 1 branch main
        functions[_inzsh_git_mv]=$saved

        local -a bad=()
        [[ $inzsh_spec_to == $file ]]           || bad+="renamed-onto=$inzsh_spec_to"
        [[ $inzsh_spec_from != $inzsh_spec_to ]] || bad+=source-is-the-entry
        [[ $inzsh_spec_pre == absent ]]          || bad+=entry-existed-before-the-rename
        _inzsh_git_cache_read /repo/spy          || bad+=unreadable-afterwards
        print -rl -- $bad
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call spied
      The output should eq ''
    End

    It 'never lets a reader see the moment between the old entry and the new one'
      # THE reason the temporary exists, stated as the thing a user would notice. Writing
      # straight to the target truncates it, and a read that lands in that window finds a file
      # with no `repo` line in it — a MISS, which is a git segment that blinks out of the prompt
      # and back in while nothing about the repository changed.
      #
      # An entry is written first, so every subsequent read has something to find, and then a
      # hundred reads race twenty writers. Not one of them may come back empty-handed.
      uninterrupted() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_path /repo/steady
        local file=$REPLY
        _inzsh_git_cache_write /repo/steady "$file" seed repo 1 branch seed

        local -i n
        for (( n = 1; n <= 20; n++ )); do
          _inzsh_git_cache_write /repo/steady "$file" "tok$n" repo 1 branch "b$n" dirty $n &
        done

        local -i misses=0 r
        for (( r = 1; r <= 60; r++ )); do
          _inzsh_git_cache_read /repo/steady || (( misses++ ))
        done
        wait

        print -r -- "misses=$misses"
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call uninterrupted
      The output should eq 'misses=0'
    End

    It 'reads an entry for the directory it was asked about and no other'
      # The second lock on the key. Two paths that hashed to the same eight digits would share a
      # file; the path inside the entry is what turns that from a wrong answer into a miss.
      keyed() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_path /repo/one
        local file=$REPLY
        # Written under one directory's key, claiming to be about another.
        _inzsh_git_cache_write /repo/two "$file" tok repo 1 branch main
        _inzsh_git_cache_read /repo/one
        print -r -- "rc=$? entries=${#_inzsh_git_status}"
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call keyed
      The output should eq 'rc=1 entries=0'
    End

    It 'refuses an entry written in a format this version does not know'
      versioned() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_path /repo/one
        local file=$REPLY
        local _inzsh_git_cache_version=99
        _inzsh_git_cache_write /repo/one "$file" tok repo 1 branch main
        _inzsh_git_cache_version=1
        _inzsh_git_cache_read /repo/one
        print -r -- "rc=$? entries=${#_inzsh_git_status}"
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call versioned
      The output should eq 'rc=1 entries=0'
    End

    Describe 'a corrupt entry is a miss, never a partial state'
      # An entry is a file. It outlives the shell that wrote it, a full filesystem can truncate
      # it, and a curious user can open it in an editor. None of that may reach the prompt.
      #
      # $1 what is in the file.
      #
      # The lines of the file are given as separate ARGUMENTS, joined with `|` so a whole file
      # fits on one row — shellspec reads a Parameters row as one physical line.
      Parameters
        'empty'         ''
        'noise'         'garbage'
        'header only'   'version\t1'
        'no repo field' 'version\t1|pwd\t/repo/one'
        'unreadable'    'version\t1|pwd\t/repo/one|repo\tmaybe'
        'no version'    'repo\t1|branch\tmain'
        'binary'        '\x00\x01\x02'
      End

      It "reads nothing from an entry that is $1"
        corrupt() {
          inzsh_spec_git_cache || return 1
          local INZSH_GIT_CACHE_DIR=$REPLY
          _inzsh_git_cache_path /repo/one
          print -rl -- ${(s:|:)"$(print -r -- ${(g::)1})"} > "$REPLY"
          _inzsh_git_cache_read /repo/one
          print -r -- "rc=$? entries=${#_inzsh_git_status}"
          inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
        }
        When call corrupt "$2"
        The output should eq 'rc=1 entries=0'
        The stderr should eq ''
      End
    End

    It 'reads a count that is not a count as zero rather than refusing the whole entry'
      # A field that has gone strange costs its own field and nothing else. Refusing the entry
      # over one bad number would hide a branch name that was perfectly readable.
      salvaged() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_path /repo/one
        _inzsh_git_cache_write /repo/one "$REPLY" tok \
          repo 1 branch main dirty nonsense ahead -4 behind 2.5
        _inzsh_git_cache_read /repo/one
        print -r -- "rc=$? branch=${_inzsh_git_status[branch]} dirty=${_inzsh_git_status[dirty]}" \
          "ahead=${_inzsh_git_status[ahead]} behind=${_inzsh_git_status[behind]}"
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call salvaged
      The output should eq 'rc=0 branch=main dirty=0 ahead=0 behind=0'
    End

    It 'strips control characters out of a ref on the way in'
      # A newline in a prompt fragment breaks the row the renderer has already measured. git
      # cannot make such a ref, but a truncated file can look like one.
      controlled() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_path /repo/one
        local file=$REPLY
        {
          print -r -- 'version	1'
          print -r -- 'pwd	/repo/one'
          print -r -- 'repo	1'
          print -r -- $'branch\tma\x01in'
        } > "$file"
        _inzsh_git_cache_read /repo/one
        print -r -- "branch=${_inzsh_git_status[branch]}"
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call controlled
      The output should eq 'branch=main'
    End

    It 'is a miss when there is no entry at all, which is most directories'
      absent() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_read /nowhere/at/all
        print -r -- "rc=$? entries=${#_inzsh_git_status}"
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call absent
      The output should eq 'rc=1 entries=0'
      The stderr should eq ''
    End

    It 'survives two writers racing onto the same entry'
      # Two shells in the same directory refresh at the same moment. Each writes its own
      # temporary and renames it over the target, and rename is atomic — so whatever a reader
      # sees is one writer's whole answer, never a blend of two.
      raced() {
        inzsh_spec_git_cache || return 1
        local INZSH_GIT_CACHE_DIR=$REPLY
        _inzsh_git_cache_path /repo/raced
        local file=$REPLY
        local -i n
        for (( n = 1; n <= 24; n++ )); do
          _inzsh_git_cache_write /repo/raced "$file" "tok$n" repo 1 branch "b$n" dirty $n &
        done
        # Read while they are still going, and again once they have all landed. Neither read may
        # ever see something that is not a complete entry.
        local -a bad=()
        local -i r
        for (( r = 1; r <= 24; r++ )); do
          if _inzsh_git_cache_read /repo/raced; then
            [[ ${_inzsh_git_status[branch]} == b<-> ]] || bad+="branch=${_inzsh_git_status[branch]}"
            [[ ${_inzsh_git_status[dirty]} == <-> ]]   || bad+="dirty=${_inzsh_git_status[dirty]}"
          fi
        done
        wait
        _inzsh_git_cache_read /repo/raced || bad+=final-miss
        [[ ${_inzsh_git_status[branch]} == b<-> ]] || bad+="final=${_inzsh_git_status[branch]}"
        local -a leftovers=("$INZSH_GIT_CACHE_DIR"/*.tmp(N))
        (( ${#leftovers} )) && bad+="temporaries=${#leftovers}"
        print -rl -- $bad
        inzsh_spec_git_cache_clean "$INZSH_GIT_CACHE_DIR"
      }
      When call raced
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the parser'
    # `git status --porcelain=v2 --branch` in one invocation, because one invocation is one pid
    # and one pid is what a watchdog can kill. These examples are the format written down.
    # Each example passes the raw lines as separate ARGUMENTS — shellspec reads a Parameters
    # row as one physical line, and a porcelain file is several.
    Describe 'the branch header'
      It 'reads a branch in step with its upstream'
        synced() {
          inzsh_spec_git_parse '# branch.oid abc1234' '# branch.head main' \
            '# branch.upstream origin/main' '# branch.ab +0 -0'
        }
        When call synced
        The output should eq \
          'branch=main sha=abc1234 detached=0 staged=0 dirty=0 untracked=0 conflicts=0 ahead=0 behind=0'
      End

      It 'reads a divergence in both directions'
        # `+n` is ahead and `-n` is behind, and the two are one line. A parser that read the
        # signs the other way round would be right exactly half the time.
        diverged() {
          inzsh_spec_git_parse '# branch.oid abc1234' '# branch.head main' \
            '# branch.upstream origin/main' '# branch.ab +2 -3'
        }
        When call diverged
        The output should eq \
          'branch=main sha=abc1234 detached=0 staged=0 dirty=0 untracked=0 conflicts=0 ahead=2 behind=3'
      End

      It 'reads a detached HEAD, which has a commit and no upstream'
        detached() {
          inzsh_spec_git_parse '# branch.oid abc1234' '# branch.head (detached)'
        }
        When call detached
        The output should eq \
          'branch= sha=abc1234 detached=1 staged=0 dirty=0 untracked=0 conflicts=0 ahead=0 behind=0'
      End

      It 'reads an unborn branch, whose oid git writes as `(initial)`'
        # `git init` and no commit yet. The marker is not a commit id and must not be drawn as
        # one; the branch name is still the truth about where HEAD points.
        unborn() {
          inzsh_spec_git_parse '# branch.oid (initial)' '# branch.head main'
        }
        When call unborn
        The output should eq \
          'branch=main sha= detached=0 staged=0 dirty=0 untracked=0 conflicts=0 ahead=0 behind=0'
      End
    End

    Describe 'the changed paths'
      # `X` is the index column and `Y` the worktree column; `.` means unmodified. One path can
      # legitimately be both, which is why the two counts are counted separately and only the
      # segment collapses them.
      #
      # $1 the porcelain line; $2 the counts it contributes, as `staged dirty untracked
      # conflicts` — four numbers rather than four `name=value` pairs, so a row fits on a line.
      Parameters
        '1 .M N... 100644 100644 100644 aaa bbb one.txt'        '0 1 0 0'
        '1 M. N... 100644 100644 100644 aaa bbb one.txt'        '1 0 0 0'
        '1 MM N... 100644 100644 100644 aaa bbb one.txt'        '1 1 0 0'
        '1 A. N... 000000 100644 100644 aaa bbb new.txt'        '1 0 0 0'
        '1 .D N... 100644 100644 100644 aaa bbb one.txt'        '0 1 0 0'
        '2 R. N... 100644 100644 100644 R100 new.txt	old.txt'   '1 0 0 0'
        'u UU N... 100644 100644 100644 100644 a b c both.txt'  '0 0 0 1'
        '? new.txt'                                             '0 0 1 0'
      End

      It "counts ($1)"
        counted() {
          _inzsh_git_parse_counts_of "$1"
        }
        When call counted "$1"
        The output should eq "$2"
      End
    End

    It 'counts every path in a repository with a great many of them'
      # The very-large-repository case, without building one. Five thousand changed paths is more
      # than a prompt will ever have to summarise and it is arithmetic all the way down: the
      # parser must not slow down non-linearly and must not lose count.
      many() {
        local raw
        raw=$(mktemp "${TMPDIR:-/tmp}/inzsh-git-raw-XXXXXX") || return 1
        {
          print -r -- '# branch.oid abc1234'
          print -r -- '# branch.head main'
          local -i n
          for (( n = 1; n <= 5000; n++ )); do
            print -r -- "1 .M N... 100644 100644 100644 aaa bbb file$n.txt"
          done
          for (( n = 1; n <= 5000; n++ )); do
            print -r -- "? untracked$n.txt"
          done
        } > "$raw"
        _inzsh_git_parse "$raw"
        local -A got=("${reply[@]}")
        rm -f -- "$raw"
        print -r -- "dirty=${got[dirty]} untracked=${got[untracked]} branch=${got[branch]}"
      }
      When call many
      The output should eq 'dirty=5000 untracked=5000 branch=main'
    End

    Describe 'output no git would produce is not an error'
      # The raw file is written by a background job. It can be truncated by a timeout landing
      # mid-write, and a `git` earlier on `$PATH` than the real one can print anything at all.
      Parameters
        ''
        'not porcelain at all'
        '# branch.ab garbage'
        '# branch.ab +x -y'
        '1'
        '3 unknown line type'
      End

      It "parses '$1' as a repository with nothing to report"
        When call inzsh_spec_git_parse "$1"
        The output should eq \
          'branch= sha= detached=0 staged=0 dirty=0 untracked=0 conflicts=0 ahead=0 behind=0'
        The stderr should eq ''
      End
    End

    It 'never reads the branch header as a changed path'
      # `# branch.head main` starts with `#`, not a digit, but a parser that tested only the
      # first character would count `1` inside a path name. Every header line and every path line
      # in one file.
      mixed() {
        inzsh_spec_git_parse \
          '# branch.oid abc1234' \
          '# branch.head main' \
          '# branch.ab +1 -1' \
          '1 .M N... 100644 100644 100644 aaa bbb 1.txt' \
          '? 2.txt'
      }
      When call mixed
      The output should eq \
        'branch=main sha=abc1234 detached=0 staged=0 dirty=1 untracked=1 conflicts=0 ahead=1 behind=1'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the worker, end to end'
    # A real repository in a known state, a real background job, a real cache entry, and the
    # fragment the segment renders from it. This is the whole pipeline; everything above is a
    # piece of it.
    #
    # $1 the fixture state; $2 what ends up on the prompt.
    Parameters
      clean    '[C main] positive-text'
      dirty    '[! main] negative'
      staged   '[i main] info-text'
      ahead    '[C main A2] positive-text'
      behind   '[C main B3] positive-text'
      diverged '[C main A2B3] caution-text'
    End

    It "renders a $1 repository as $2"
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      When call inzsh_spec_git_worker "$1"
      The output should eq "$2"
      The stderr should eq ''
    End
  End

  Describe 'the worker, on a detached HEAD'
    It 'draws the abbreviated commit and no divergence'
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      # Split out from the table above because the commit id is the one thing the fixture cannot
      # pin across git object formats. The shape is asserted, never the value.
      detached() {
        setopt local_options extended_glob
        local out
        out=$(inzsh_spec_git_worker detached)
        [[ $out == '[C D '[0-9a-f](#c7)'] caution-text' ]] && print -r -- shaped || print -r -- "$out"
      }
      When call detached
      The output should eq 'shaped'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'resilience'
    It 'renders nothing at all in a directory that is not a repository'
      # The commonest case by far, and the one that must cost nothing: an entry is written
      # saying so, and the segment stays absent.
      plain() {
        inzsh_spec_git_shell '
          cd ${TMPDIR:-/tmp}
          _inzsh_git_async_start "$PWD"
          _inzsh_git_async_wait 20 >/dev/null
          _inzsh_git_cache_read "$PWD"
          _inzsh_segment_git_build
          print -r -- "repo=${_inzsh_git_status[repo]} text=[${_inzsh_segment_text[GIT]}]"
        '
      }
      When call plain
      The output should eq 'repo=0 text=[]'
      The stderr should eq ''
    End

    It 'kills a status that will not answer, and says nothing rather than guessing'
      # The hard timeout. A `git` that never returns is put on `$PATH` ahead of the real one, and
      # the job must come back inside the budget with an entry that claims nothing: an entry
      # saying "clean" here would be a lie about uncommitted work.
      timed() {
        inzsh_spec_git_shell '
          typeset -g bin=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-git-spec-bin-XXXXXX")
          # `exec`, so the fake git IS the sleep rather than a shell holding one. `$!` in the
          # job is then the pid of the thing that hangs, which is the whole assumption the
          # timeout rests on: the probe is ONE process, so one `kill` ends it.
          print -r -- "#!/bin/sh"      > $bin/git
          print -r -- "exec sleep 600" >> $bin/git
          chmod +x $bin/git
          export PATH=$bin:$PATH
          export INZSH_GIT_TIMEOUT=1

          cd ${TMPDIR:-/tmp}
          typeset -F started=$EPOCHREALTIME
          _inzsh_git_async_start "$PWD"
          _inzsh_git_async_wait 20 >/dev/null
          typeset -i elapsed=$(( EPOCHREALTIME - started ))
          _inzsh_git_cache_read "$PWD"
          _inzsh_segment_git_build
          print -r -- "repo=${_inzsh_git_status[repo]} timeout=${_inzsh_git_status[timeout]}" \
            "text=[${_inzsh_segment_text[GIT]}] quick=$(( elapsed < 5 ))"
          rm -rf -- $bin
        '
      }
      When call timed
      The output should eq 'repo=0 timeout=1 text=[] quick=1'
      The stderr should eq ''
    End

    It 'draws a prompt in a directory that has been deleted underneath it'
      # `cd` into a directory, delete it from elsewhere, press Enter. `$PWD` still holds the
      # path, git cannot chdir into it, and the answer is the same one a non-repository gives.
      # Nothing here may write a diagnostic: the shell is already in a strange enough state.
      deleted() {
        inzsh_spec_git_shell '
          typeset -g doomed=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-git-spec-gone-XXXXXX")
          cd $doomed
          rmdir $doomed
          _inzsh_git_async_start "$PWD"
          _inzsh_git_async_wait 20 >/dev/null
          _inzsh_git_cache_read "$PWD"
          _inzsh_segment_git_build
          print -r -- "text=[${_inzsh_segment_text[GIT]}]"
        '
      }
      When call deleted
      The output should eq 'text=[]'
      The stderr should eq ''
    End

    It 'summarises a repository with thousands of changed paths as one mark'
      # The large-repository case with a real repository behind it. What matters is that the
      # fragment stays one glyph and one branch name however much has changed — the prompt
      # reports a state, not an inventory.
      large() {
        inzsh_spec_git_shell '
          _inzsh_fixture_repo clean || { print -r -- fixture-failed; return 0 }
          typeset -g repo=$REPLY
          cd $repo
          typeset -i n
          for (( n = 1; n <= 400; n++ )); do
            print -r -- $n > $repo/file$n.txt
          done
          _inzsh_git_async_start "$PWD"
          _inzsh_git_async_wait 30 >/dev/null
          _inzsh_git_cache_read "$PWD"
          _inzsh_segment_git_build
          print -r -- "untracked=${_inzsh_git_status[untracked]}" \
            "text=[${_inzsh_segment_text[GIT]}]"
          cd /
          _inzsh_fixture_repo_clean $repo
        '
      }
      When call large
      The output should eq "untracked=400 text=[$_inzsh_git_glyph_dirty main]"
      The stderr should eq ''
    End

    It 'launches nothing when the worker is switched off'
      # `INZSH_GIT_ASYNC=0` is the escape hatch, and it has to be an actual off switch: no job,
      # no fork, no descriptor.
      disabled() {
        inzsh_spec_git_shell '
          export INZSH_GIT_ASYNC=0
          cd ${TMPDIR:-/tmp}
          _inzsh_git_async_start "$PWD"
          print -r -- "rc=$? fd=$_inzsh_git_job_fd"
        '
      }
      When call disabled
      The output should eq 'rc=1 fd=0'
    End

    It 'runs one job at a time, however often it is asked'
      # A repository slow enough to need a second job is exactly the repository where they would
      # pile up. The second request is refused, not queued.
      single() {
        inzsh_spec_git_shell '
          cd ${TMPDIR:-/tmp}
          _inzsh_git_async_start "$PWD"
          typeset -i first=$_inzsh_git_job_fd
          _inzsh_git_async_start "$PWD"
          typeset -i second=$?
          print -r -- "started=$(( first > 0 )) refused=$second"
          _inzsh_git_async_wait 20 >/dev/null
        '
      }
      When call single
      The output should eq 'started=1 refused=1'
    End

    It 'releases the wait when a job dies without ever answering'
      # The descriptor CLOSING is the signal, not the byte the job writes down it. A job killed
      # by the reaper, by a full disk, or by an `OOM` never writes anything — and a shell that
      # waited for a byte would wait for one that is not coming, with `zle -F` still registered
      # on a descriptor nothing will ever write to.
      #
      # The fake git sleeps for ten minutes, so nothing but the kill can end this.
      orphaned() {
        inzsh_spec_git_shell '
          typeset -g bin=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-git-spec-bin-XXXXXX")
          print -r -- "#!/bin/sh"      > $bin/git
          print -r -- "exec sleep 600" >> $bin/git
          chmod +x $bin/git
          export PATH=$bin:$PATH
          export INZSH_GIT_TIMEOUT=5

          cd ${TMPDIR:-/tmp}
          _inzsh_git_async_start "$PWD"

          # The job publishes its pids as its second act, so a shell that asks the instant
          # after launching may find nothing. Poll rather than assume — and the poll is the
          # reason `_inzsh_git_async_reap` cannot promise to kill a job it started microseconds
          # ago, which is a real limit and not a test artefact.
          typeset -i tries=0
          while (( tries < 40 )) && [[ ! -s $_inzsh_git_job_pids ]]; do
            sleep 0.05
            (( tries++ ))
          done

          # Kill the job outright, the way the reaper would, without touching the descriptor.
          typeset pid
          while IFS= read -r pid; do
            kill -TERM $pid 2>/dev/null
          done < $_inzsh_git_job_pids

          typeset -F started=$EPOCHREALTIME
          _inzsh_git_async_wait 20 >/dev/null
          typeset -i elapsed=$(( EPOCHREALTIME - started ))
          print -r -- "released=$(( elapsed < 5 )) fd=$_inzsh_git_job_fd"
          rm -rf -- $bin
        '
      }
      When call orphaned
      The output should eq 'released=1 fd=0'
      The stderr should eq ''
    End

    It 'has nothing to wait for when nothing is running'
      idle() {
        inzsh_spec_git_shell '
          _inzsh_git_async_wait 1 >/dev/null
          print -r -- "rc=$?"
        '
      }
      When call idle
      The output should eq 'rc=1'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the directory changing'
    # The classic bug this whole file is shaped against: a job launched in repository A lands
    # while the shell is standing in repository B.
    It 'never files an answer about the directory it has left'
      moved() {
        inzsh_spec_git_shell '
          _inzsh_fixture_repo dirty || { print -r -- fixture-failed; return 0 }
          typeset -g one=$REPLY
          _inzsh_fixture_repo clean || { print -r -- fixture-failed; return 0 }
          typeset -g two=$REPLY

          cd $one
          _inzsh_git_async_start "$PWD"
          # Leave before the answer lands. The job is reaped, its answer is not drawn, and the
          # status map is emptied so nothing from `one` can survive into `two`.
          cd $two
          _inzsh_git_async_chpwd
          # chpwd reaps the job that was about `one` and starts one about `two`, so the
          # descriptor that is live afterwards belongs to WHERE WE ARE. The status map is empty
          # in between: nothing from `one` can survive the move.
          typeset -g moved_to=$_inzsh_git_job_pwd
          typeset -g for_=$moved_to
          [[ $moved_to == $two ]] && for_=1
          typeset -g after_move="for=$for_ entries=${#_inzsh_git_status}"

          _inzsh_git_async_wait 20 >/dev/null
          _inzsh_segment_git_build
          print -r -- "$after_move here=[${_inzsh_segment_text[GIT]}]"

          cd /
          _inzsh_fixture_repo_clean $one
          _inzsh_fixture_repo_clean $two
        '
      }
      When call moved
      The output should eq "for=1 entries=0 here=[$_inzsh_git_glyph_clean main]"
      The stderr should eq ''
    End

    It 'picks a cached answer up again on the way back, without waiting for a second job'
      # The other half of keying by `$PWD`: an entry written for a directory is still that
      # directory's answer when you return to it, so `cd -` shows a status immediately.
      returned() {
        inzsh_spec_git_shell '
          _inzsh_fixture_repo ahead || { print -r -- fixture-failed; return 0 }
          typeset -g repo=$REPLY

          cd $repo
          _inzsh_git_async_start "$PWD"
          _inzsh_git_async_wait 20 >/dev/null

          cd ${TMPDIR:-/tmp}
          _inzsh_git_async_chpwd
          _inzsh_git_async_reap
          typeset -g away="[${_inzsh_segment_text[GIT]}]"
          _inzsh_segment_git_build

          cd $repo
          # chpwd loads the entry from the cache. No job has to finish for this to be drawn.
          _inzsh_git_async_chpwd
          _inzsh_git_async_reap
          _inzsh_segment_git_build
          print -r -- "back=[${_inzsh_segment_text[GIT]}]"

          cd /
          _inzsh_fixture_repo_clean $repo
        '
      }
      When call returned
      The output should eq "back=[$_inzsh_git_glyph_clean main ${_inzsh_git_glyph_ahead}2]"
      The stderr should eq ''
    End

    It 'repaints only when the fragment actually changed'
      # A repaint costs a full render and a screen write. Doing it when the answer is the same
      # as the one already drawn is a flicker carrying no information, so `collect` reports
      # whether anything changed and the handler believes it.
      changed() {
        inzsh_spec_git_shell '
          _inzsh_fixture_repo clean || { print -r -- fixture-failed; return 0 }
          typeset -g repo=$REPLY
          cd $repo

          _inzsh_git_async_start "$PWD"
          _inzsh_git_async_wait 20 >/dev/null
          typeset -i first=$?

          _inzsh_git_async_start "$PWD"
          _inzsh_git_async_wait 20 >/dev/null
          typeset -i second=$?

          print -r -- "first=$first second=$second"

          cd /
          _inzsh_fixture_repo_clean $repo
        '
      }
      When call changed
      The output should eq 'first=0 second=1'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'reaping'
    It 'kills the git it started when the shell goes away'
      # A `git status` blocked on an unreachable mount does not care that the shell that asked
      # has gone. The pids the job published are killed on the way out; here the shell exits
      # normally and the fake git must not outlive it.
      reaped() {
        local bin
        bin=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-git-spec-XXXXXX") || return 1
        # A duration nothing else on the machine would choose, so `pgrep` below is asking about
        # THIS example's process and no other. `exec`, so the fake git is the sleep itself and
        # `$!` in the job is the pid that has to die.
        {
          print -r -- '#!/bin/sh'
          print -r -- 'exec sleep 4242'
        } > "$bin/git"
        chmod +x "$bin/git"

        inzsh_spec_git_shell "
          export PATH=$bin:\$PATH
          export INZSH_GIT_TIMEOUT=4
          cd \${TMPDIR:-/tmp}
          _inzsh_git_async_install
          _inzsh_git_async_start \"\$PWD\"
          sleep 0.5
          _inzsh_git_async_exit
        " >/dev/null

        # The timeout is four seconds and the shell lived for half of one, so anything still
        # sleeping was reaped by nothing and would have outlived the terminal.
        #
        # Counted through `ps` and an ANCHORED match rather than `pgrep -f`, which matches its
        # own command line: `pgrep -f 'sleep 4242'` is itself a process whose arguments contain
        # `sleep 4242`, so it always finds at least one and the example can never fail.
        local -i left=0
        left=$(ps -A -o args= 2>/dev/null | grep -c -x 'sleep 4242') || left=0
        pkill -x -f 'sleep 4242' 2>/dev/null
        rm -rf -- "$bin"
        print -r -- "left=$left"
      }
      When call reaped
      The output should eq 'left=0'
    End

    It 'forgets the descriptor and the job when it reaps'
      forgotten() {
        inzsh_spec_git_shell '
          cd ${TMPDIR:-/tmp}
          _inzsh_git_async_start "$PWD"
          _inzsh_git_async_reap
          print -r -- "fd=$_inzsh_git_job_fd pwd=[$_inzsh_git_job_pwd] pids=[$_inzsh_git_job_pids]"
        '
      }
      When call forgotten
      The output should eq 'fd=0 pwd=[] pids=[]'
      The stderr should eq ''
    End

    It 'reaps nothing twice over without complaining'
      twice() {
        inzsh_spec_git_shell '
          _inzsh_git_async_reap
          _inzsh_git_async_reap
          print -r -- "rc=$? fd=$_inzsh_git_job_fd"
        '
      }
      When call twice
      The output should eq 'rc=0 fd=0'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the hooks'
    It 'registers precmd, chpwd and zshexit, and only those'
      installed() {
        inzsh_spec_git_shell_live '
          autoload -Uz add-zsh-hook
          _inzsh_git_async_install
          print -r -- "precmd=${precmd_functions[(Ie)_inzsh_git_async_precmd]}" \
            "chpwd=${chpwd_functions[(Ie)_inzsh_git_async_chpwd]}" \
            "exit=${zshexit_functions[(Ie)_inzsh_git_async_exit]}"
        '
      }
      When call installed
      The output should eq 'precmd=1 chpwd=1 exit=1'
    End

    It 'installs once however many times it is called, and leaves other hooks alone'
      # `add-zsh-hook` already refuses to add a function twice, so idempotence is delegated
      # rather than tracked. A private flag would also refuse to REPAIR a registration something
      # else removed, which is worse than useless.
      idempotent() {
        inzsh_spec_git_shell_live '
          autoload -Uz add-zsh-hook
          foreign() { : }
          add-zsh-hook precmd foreign
          _inzsh_git_async_install
          _inzsh_git_async_install
          _inzsh_git_async_install
          print -r -- "precmd=${#precmd_functions} foreign=${precmd_functions[(Ie)foreign]}"
        '
      }
      When call idempotent
      The output should eq 'precmd=2 foreign=1'
    End

    It 'removes its own registrations and nobody else’s'
      uninstalled() {
        inzsh_spec_git_shell_live '
          autoload -Uz add-zsh-hook
          foreign() { : }
          add-zsh-hook chpwd foreign
          _inzsh_git_async_install
          _inzsh_git_async_uninstall
          print -r -- "chpwd=${#chpwd_functions} foreign=${chpwd_functions[(Ie)foreign]}" \
            "precmd=${#precmd_functions}"
        '
      }
      When call uninstalled
      The output should eq 'chpwd=1 foreign=1 precmd=0'
    End

    It 'never assigns a hook array, in any of its three forms'
      # An assignment discards every registration any other plugin has made, silently. The rule
      # is a property of the TEXT — a guarded assignment that is unreachable today is still an
      # assignment waiting to fire.
      unassigned() {
        inzsh_spec_git_async_lines
        local line; local -a bad=()
        (( ${#inzsh_spec_lines} > 50 )) || bad+=no-lines-scanned
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *precmd=* || $line == *precmd_functions=* ]]   && bad+=$line
          [[ $line == *chpwd=* || $line == *chpwd_functions=* ]]     && bad+=$line
          [[ $line == *zshexit_functions=* || $line == *preexec=* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call unassigned
      The output should eq ''
    End

    It 'no-ops in a shell that never draws a prompt'
      # A hook has no business in a shell that has no prompt, and an escape written into a
      # script's output is corruption in somebody else's pipeline.
      scripted() {
        inzsh_spec_git_shell '
          _inzsh_git_async_install
          print -r -- "precmd=${#precmd_functions} rc=$?"
        '
      }
      When call scripted
      The output should eq 'precmd=0 rc=0'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the repaint'
    # `zle -F` is the only mechanism zsh has for "run this when a descriptor has something on
    # it", and `zle reset-prompt` is the only way to redraw the line the user is already typing.
    # Both need a real line editor on a real terminal, so what is asserted here is that the
    # wiring exists and names the right functions; the drawing itself is `test/ui/`'s layer.
    It 'registers the handler on the job descriptor'
      wired() {
        local body=${functions[_inzsh_git_async_start]}
        [[ $body == *'zle -F $fd _inzsh_git_async_ready'* ]] && print -r -- wired || print -r -- "$body"
      }
      When call wired
      The output should eq 'wired'
    End

    It 'redraws the prompt in place rather than waiting for the next Enter'
      redrawn() {
        local body=${functions[_inzsh_git_async_ready]}
        local -a missing=()
        [[ $body == *'_inzsh_git_async_collect'* ]] || missing+=collect
        [[ $body == *'_inzsh_render'* ]]            || missing+=render
        [[ $body == *'zle reset-prompt'* ]]         || missing+=reset
        print -r -- "${missing[*]}"
      }
      When call redrawn
      The output should eq ''
    End

    It 'removes the handler before it closes the descriptor'
      # A `zle -F` registration on a closed descriptor is a handler zle calls forever. The order
      # is the fix and it is the only thing that makes the reaper safe to call from anywhere.
      ordered() {
        local body=${functions[_inzsh_git_async_reap]}
        local before=${body%%exec \{_inzsh_git_job_fd\}*}
        [[ $before == *'zle -F $_inzsh_git_job_fd'* ]] && print -r -- ordered || print -r -- "$body"
      }
      When call ordered
      The output should eq 'ordered'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/segments/git-async.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sources silently in a single-byte locale'
      quiet() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          source "$1/lib/segments/git-async.zsh"
          print -r -- "started=${+functions[_inzsh_git_async_start]}"
        ' inzsh-git-async-c "$SHELLSPEC_PROJECT_ROOT" < /dev/null
      }
      When call quiet
      The output should eq 'started=1'
      The stderr should eq ''
    End

    It 'draws nothing and starts nothing at load'
      # Sourcing must install behaviour and not perform any. A file that started a job on load
      # would fork in every shell that read it, including the ones that never draw a prompt.
      inert() {
        zsh -f -c '
          source "$1/lib/segments/git-async.zsh"
          print -r -- "fd=$_inzsh_git_job_fd entries=${#_inzsh_git_status}" \
            "hooks=${#precmd_functions}"
        ' inzsh-git-async-load "$SHELLSPEC_PROJECT_ROOT"
      }
      When call inert
      The output should eq 'fd=0 entries=0 hooks=0'
      The stderr should eq ''
    End

    It 'never replaces the user’s rm, mv or mkdir'
      # `zmodload -F zsh/files b:rm` would swap a reduced implementation in for the rest of the
      # session. Global state is the user's; the module is loaded under its own `zf_` names.
      unshadowed() {
        zsh -f -c '
          source "$1/lib/segments/git-async.zsh"
          print -r -- "rm=$(whence -w rm) mv=$(whence -w mv) mkdir=$(whence -w mkdir)"
        ' inzsh-git-async-files "$SHELLSPEC_PROJECT_ROOT"
      }
      When call unshadowed
      The output should eq 'rm=rm: command mv=mv: command mkdir=mkdir: command'
    End

    It 'never redirects the shell’s own stderr with a bare exec'
      # `exec {fd}< <(…) 2>/dev/null` applies the redirection to the SHELL, permanently, and
      # every diagnostic the user's session would ever have printed goes to `/dev/null`.
      unredirected() {
        inzsh_spec_git_async_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          # A redirection is safe only when it belongs to a BLOCK around the `exec`, never to
          # the `exec` itself. `{ exec … } 2>/dev/null` scopes it; `exec … 2>/dev/null` does not.
          [[ $line == *'exec '*'2>'* && $line != *'{ exec '*'} 2>'* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call unredirected
      The output should eq ''
    End

    Describe 'it never declares a local with a name zsh has already spoken for'
      # `path` is zsh's array view of `$PATH`. A `local path=…` sets the shell's command search
      # path to that one string for as long as the function runs, so every external command
      # inside it vanishes — and behind a `2>/dev/null` the failure is silent. It has already
      # cost this milestone one bug, in `tools/fixture-repo.zsh`, where a guarded `rm -rf`
      # reported success on a fixture it had not removed.
      #
      # The scan TOKENISES rather than pattern-matching the whole line: `local path=/tmp` has no
      # whitespace between the keyword and the name, and a pattern that assumed one reads as a
      # passing test on a file that has the bug in it.
      #
      # $1 the file, relative to the project root.
      Parameters
        lib/segments/git.zsh
        lib/segments/git-async.zsh
        tools/fixture-repo.zsh
      End

      It "keeps $1 clear of them"
        unreserved() {
          setopt local_options extended_glob
          local -a reserved=(
            path cdpath fpath manpath status argv options commands functions
            module_path prompt psvar signals histchars
          )
          local line bare word name
          local -a words bad=()
          while IFS= read -r line; do
            bare=${line##[[:space:]]#}
            [[ -z $bare || $bare == \#* ]] && continue
            words=(${=bare})
            [[ ${words[1]} == (local|typeset|declare|export|integer|float) ]] || continue
            shift words
            for word in "${words[@]}"; do
              [[ $word == -* ]] && continue
              name=${word%%=*}
              (( ${reserved[(Ie)$name]} )) && bad+="$name: $bare"
            done
          done < "$SHELLSPEC_PROJECT_ROOT/$1"
          print -rl -- $bad
        }
        When call unreserved "$1"
        The output should eq ''
      End
    End

    It 'carries no hex and no path from this machine'
      neutral() {
        setopt local_options extended_glob
        inzsh_spec_git_async_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'#'[0-9A-Fa-f](#c6)* ]] && bad+=$line
          [[ $line == *'.claude'* || $line == *'/Users/'* || $line == *'/home/'* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call neutral
      The output should eq ''
    End
  End
  # Issue #266. The job token names three files — `.tmp`, `.raw` and `.pid` — so two jobs that
  # agree on one are two jobs writing over each other's working state, in the repository's only
  # async path. The fork collision below is the defect; the second example guards the fix itself,
  # since the obvious repair reintroduces the problem one step over.
  Describe 'a job token no two jobs can share (issue #266)'
    # ACROSS FORKS. `$$` is the pid of the shell that was FIRST started, so it is identical in
    # every subshell forked from one parent, and a fork inherits the parent's `$RANDOM` state so
    # the first draw after the fork matches too. Twenty siblings therefore agreed on one token by
    # construction rather than by chance. `$sysparams[pid]` is read from the kernel per reference
    # and is the half that fixes this.
    It 'gives every forked shell its own token'
      forks() {
        inzsh_spec_git_shell '
          # Stubbed so no git runs and no watchdog is left behind: this asks what NAME the start
          # picks, which is decided before the job is ever launched.
          _inzsh_git_async_job() { : }

          local -i n
          for (( n = 1; n <= 20; n++ )); do
            (
              _inzsh_git_async_start "$INZSH_GIT_CACHE_DIR" >/dev/null 2>&1
              print -r -- "$_inzsh_git_job_token" > "$INZSH_GIT_CACHE_DIR/token.$n"
            ) &
          done
          wait

          local -a collected=("$INZSH_GIT_CACHE_DIR"/token.<->(N))
          local -a names=()
          local f
          for f in "${collected[@]}"; do names+="$(<$f)"; done
          local -i distinct=${#${(u)names}}
          print -r -- "collected=${#collected} distinct=$distinct"
        '
      }
      When call forks
      The output should eq 'collected=20 distinct=20'
    End

    # WITHIN ONE PROCESS. This is a REGRESSION GUARD rather than a second old bug: the old token
    # handled this case correctly, because `$RANDOM` does advance between two draws inside one
    # process even though a fork inherits its state. The fix is what puts it at risk — a pid is
    # constant for the life of a process, so `${sysparams[pid]}` ALONE would give two jobs started
    # by one shell the same token, trading the fork collision for a sequential one. Not a
    # contrived sequence either: `precmd` fires on every accepted line, an empty one included.
    #
    # Verified to bite: with the token reduced to the bare pid this example fails with
    # `same=<pid>`, while the forks example above still passes — which is exactly the half-fix
    # a single test would have let through.
    It 'gives a second job in the same second a different token'
      same_second() {
        inzsh_spec_git_shell '
          _inzsh_git_async_job() { : }

          _inzsh_git_async_start "$INZSH_GIT_CACHE_DIR" >/dev/null 2>&1
          local first=$_inzsh_git_job_token
          # Closes the descriptor and clears the job state, so the second start is not refused by
          # the one-at-a-time guard. Nothing else about the token is reset by it.
          _inzsh_git_async_reap
          _inzsh_git_async_start "$INZSH_GIT_CACHE_DIR" >/dev/null 2>&1
          local second=$_inzsh_git_job_token
          _inzsh_git_async_reap

          local -a bad=()
          [[ -n $first && -n $second ]] || bad+=empty
          [[ $first != $second ]] || bad+="same=$first"
          # The premise: both really did land in the same second, or this example proved nothing.
          [[ ${first%%.*} == ${second%%.*} ]] || bad+=different-seconds
          print -rl -- $bad
        '
      }
      When call same_second
      The output should eq ''
    End
  End
End
