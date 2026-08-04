Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/jobs.zsh

# The background-jobs segment — `lib/segments/jobs.zsh`. What it registers, what it draws for
# injected counts, and — the two examples that hold the design together — that the counts it
# reads live are the shell's own, taken from `$jobstates` and never from a subshell.
#
# THE SUBSHELL TRAP IS WHY THIS SPEC EXISTS IN THIS SHAPE. `$(jobs)` is the obvious
# implementation and it is not merely slow, it is WRONG: a command substitution is a child, a
# child has an empty job table, and the segment would report 0 forever while looking perfectly
# reasonable. So the live half is asserted in a real shell that really has jobs, and the drawn
# half is asserted over injected numbers.
#
# No glyph literal reaches this file. Every example that asserts a mark asserts it through
# `_inzsh_glyph`, so a token layer that respells one cannot fail this spec for the wrong reason.

# Build for injected counts and print what the segment wrote, in brackets so that an empty entry
# — the absent case — is a visible result rather than a blank line.
inzsh_spec_jobs() {
  emulate -L zsh

  _inzsh_segment_text=()
  _inzsh_segment_jobs_build "$@"
  print -r -- "[${_inzsh_segment_text[JOBS]-'(no entry)'}]"
}

# The segment as the renderer draws it, on a left prompt of its own.
inzsh_spec_jobs_drawn() {
  emulate -L zsh

  _inzsh_segment_text=()
  _inzsh_segment_jobs_build "$@"
  _inzsh_left=(JOBS)
  _inzsh_right=()
  _inzsh_render_build left
  typeset -g inzsh_spec_drawn=$REPLY

  return 0
}

# The non-comment lines of the segment source, for the structural groups.
inzsh_spec_jobs_lines() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga inzsh_spec_lines
  inzsh_spec_lines=()

  local line bare
  while IFS= read -r line; do
    bare=${line##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    inzsh_spec_lines+=$line
  done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/jobs.zsh"

  return 0
}

Describe 'the background-jobs segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers a rank default, a foreground role and an importance'
      registered() {
        local -a got=()
        got+=rank=${_inzsh_segment_defaults[JOBS]-}
        got+=role=${_inzsh_segment_fg_role[JOBS]-}
        got+=importance=${_inzsh_segment_importance[JOBS]-}
        print -r -- "${got[*]}"
      }
      When call registered
      The output should eq 'rank=0 role=info-text importance=3'
    End

    It 'ships hidden — the engine puts it on neither side of the prompt'
      hidden() {
        _inzsh_rank_split JOBS
        print -rn -- "left=[${_inzsh_left[*]}] right=[${_inzsh_right[*]}] "
        print -r  -- "hidden=[${_inzsh_hidden[*]}]"
      }
      When call hidden
      The output should eq 'left=[] right=[] hidden=[JOBS]'
    End

    It 'comes out on whichever side the user ranks it'
      ranked() {
        local INZSH_JOBS_RANK=7
        _inzsh_rank_split JOBS
        local onleft="left=[${_inzsh_left[*]}]"
        INZSH_JOBS_RANK=-7
        _inzsh_rank_split JOBS
        print -r -- "$onleft right=[${_inzsh_right[*]}]"
      }
      When call ranked
      The output should eq 'left=[JOBS] right=[JOBS]'
    End

    It 'registers once however many times it is sourced'
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/jobs.zsh"
          source "$1/lib/segments/jobs.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${#_inzsh_segment_fg_role}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_defaults[JOBS]}"
        ' inzsh-jobs-twice "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 1 1 0'
      The stderr should eq ''
    End

    It 'draws nothing at load — sourcing registers and returns'
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local before="${PROMPT-unset}|${RPROMPT-unset}"
          source "$1/lib/segments/jobs.zsh"
          local after="${PROMPT-unset}|${RPROMPT-unset}"
          local prompt=changed
          [[ $before == $after ]] && prompt=same
          print -r -- "texts=${#_inzsh_segment_text} prompt=$prompt"
        ' inzsh-jobs-load "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'texts=0 prompt=same'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'what it draws'
    It 'is absent with nothing held — no block, no separator, no zero'
      When call inzsh_spec_jobs 0 0
      The output should eq '[]'
    End

    It 'draws the running count alone when nothing is suspended'
      When call inzsh_spec_jobs 2 0
      The output should eq "[${_inzsh_glyph[info]} 2]"
    End

    It 'draws the suspended count alone when nothing is running'
      When call inzsh_spec_jobs 0 1
      The output should eq "[${_inzsh_glyph[dash]} 1]"
    End

    It 'draws both, running first, when the shell is holding both'
      When call inzsh_spec_jobs 2 1
      The output should eq "[${_inzsh_glyph[info]} 2 ${_inzsh_glyph[dash]} 1]"
    End

    It 'keeps the two counts apart — the marks are what distinguish them'
      # A bare `2 1` would be unreadable, and a single total would answer a question nobody
      # asked. The claim is that the two facts stay two facts and that neither mark is the
      # other's.
      distinct() {
        local -a bad=()
        [[ ${_inzsh_glyph[info]} != ${_inzsh_glyph[dash]} ]] || bad+=same-mark
        _inzsh_segment_jobs_build 3 0
        local running=${_inzsh_segment_text[JOBS]}
        _inzsh_segment_jobs_build 0 3
        local suspended=${_inzsh_segment_text[JOBS]}
        [[ $running != $suspended ]] || bad+="three-of-each-reads-alike:$running"
        print -rl -- $bad
      }
      When call distinct
      The output should eq ''
    End

    It 'takes the marks from the token layer rather than literals of its own'
      tabled() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          _inzsh_glyph[info]=R
          _inzsh_glyph[dash]=S
          source "$1/lib/segments/jobs.zsh"
          _inzsh_segment_jobs_build 2 1
          print -r -- "[${_inzsh_segment_text[JOBS]}]"
        ' inzsh-jobs-glyph "$SHELLSPEC_PROJECT_ROOT"
      }
      When call tabled
      The output should eq '[R 2 S 1]'
      The stderr should eq ''
    End

    It 'carries marks as well as a colour, so it reads in monochrome'
      monochrome() {
        setopt local_options extended_glob
        inzsh_spec_jobs_drawn 2 1
        local bare=${(%%)inzsh_spec_drawn}
        bare=${bare//$'\e'\[[0-9;]#m/}
        local -a missing=()
        [[ $bare == *"${_inzsh_glyph[info]}"* ]] || missing+=running-mark
        [[ $bare == *"${_inzsh_glyph[dash]}"* ]] || missing+=suspended-mark
        [[ $bare == *2* && $bare == *1* ]]       || missing+=counts
        print -r -- "${missing[*]}"
      }
      When call monochrome
      The output should eq ''
    End

    It 'takes the foreground role it registered'
      informed() {
        inzsh_spec_jobs_drawn 2 0
        local -a missing=()
        [[ $inzsh_spec_drawn == *"%F{${_inzsh_role[info-text]}}"* ]] || missing+=role
        print -r -- "${missing[*]}"
      }
      When call informed
      The output should eq ''
    End

    It 'emits no colour of its own'
      uncoloured() {
        _inzsh_segment_jobs_build 2 1
        local -a found=()
        [[ ${_inzsh_segment_text[JOBS]} == *'%'[FKfk]* ]] && found+=escape
        print -r -- "${found[*]}"
      }
      When call uncoloured
      The output should eq ''
    End

    It 'rewrites the entry on every build rather than accumulating'
      rewritten() {
        inzsh_spec_jobs 2 1
        inzsh_spec_jobs 0 0
        inzsh_spec_jobs 1 0
      }
      When call rewritten
      The output should eq "[${_inzsh_glyph[info]} 2 ${_inzsh_glyph[dash]} 1]
[]
[${_inzsh_glyph[info]} 1]"
    End

    Describe 'large counts draw as they stand'
      Parameters
        10  0
        99  0
        0  10
        7   3
      End

      It "renders running=$1 suspended=$2 with both numbers intact"
        counted() {
          _inzsh_segment_jobs_build "$1" "$2"
          local text=${_inzsh_segment_text[JOBS]}
          local -a missing=()
          if (( $1 )); then
            [[ $text == *"${_inzsh_glyph[info]} $1"* ]] || missing+=running:$text
          fi
          if (( $2 )); then
            [[ $text == *"${_inzsh_glyph[dash]} $2"* ]] || missing+=suspended:$text
          fi
          print -r -- "${missing[*]}"
        }
        When call counted "$1" "$2"
        The output should eq ''
      End
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the injection seam'
    It 'takes one argument as the running count and leaves the other live'
      # The shape `lib/segments/host.zsh` uses: absent means "read the live tally", present
      # means "use this". The runner holds no jobs, so the live suspended count is 0.
      partial() {
        inzsh_spec_jobs 4
      }
      When call partial
      The output should eq "[${_inzsh_glyph[info]} 4]"
    End

    It 'is absent with no arguments in a shell that is holding nothing'
      When call inzsh_spec_jobs
      The output should eq '[]'
    End

    Describe 'a count that is not a count reads as none'
      Parameters
        'two'  0
        '-1'   0
        '1.5'  0
        ' 1'   0
        0      'one'
      End

      It "is absent for running='$1' suspended='$2'"
        When call inzsh_spec_jobs "$1" "$2"
        The output should eq '[]'
      End
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the live job table'
    # The half that cannot be injected, run in a real interactive shell that really has jobs.
    # `sleep` is backgrounded rather than simulated, because the whole point is that the count
    # comes out of the shell's own table.
    inzsh_spec_jobs_live() {
      print -r -- "$1" |
        PROMPT= RPROMPT= PS1= zsh -f -i -o nopromptcr -o nopromptsp -s "$SHELLSPEC_PROJECT_ROOT"
    }

    It 'counts jobs the shell is actually running'
      running() {
        inzsh_spec_jobs_live '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/segments/jobs.zsh"
          sleep 30 & sleep 30 &
          _inzsh_segment_jobs_build
          out="running=$_inzsh_jobs_running suspended=$_inzsh_jobs_suspended"
          print -r -- "$out [${_inzsh_segment_text[JOBS]}]"
          kill %1 %2 2>/dev/null
        '
      }
      When call running
      The output should eq "running=2 suspended=0 [${_inzsh_glyph[info]} 2]"
    End

    It 'tells a suspended job from a running one'
      # The classification, against a real job that has really been stopped — which is the only
      # way to assert it, since the split comes out of the state field the shell writes and not
      # out of anything a caller can hand in. This is the example that fails if `suspended` is
      # ever counted as `running`, and the whole reason the segment draws two numbers.
      stopped() {
        inzsh_spec_jobs_live '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/segments/jobs.zsh"
          sleep 30 & sleep 30 &
          kill -STOP %2
          sleep 0.3
          _inzsh_segment_jobs_build
          out="running=$_inzsh_jobs_running suspended=$_inzsh_jobs_suspended"
          print -r -- "$out"
          print -r -- "[${_inzsh_segment_text[JOBS]}]"
          kill -CONT %2 2>/dev/null; kill %1 %2 2>/dev/null
        '
      }
      When call stopped
      The output should eq "running=1 suspended=1
[${_inzsh_glyph[info]} 1 ${_inzsh_glyph[dash]} 1]"
    End

    It 'reads the shell it is in and not a subshell — the trap this segment is built around'
      # `$(…)` is a child, and a child's job table is empty. This example is the difference
      # between the implementation and the obvious one: the same shell reports 2, and the same
      # question asked through a command substitution reports 0.
      subshell() {
        inzsh_spec_jobs_live '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/segments/jobs.zsh"
          sleep 30 & sleep 30 &
          direct=${#jobstates}
          child=$(print -r -- ${#jobstates})
          print -r -- "direct=$direct child=$child"
          kill %1 %2 2>/dev/null
        '
      }
      When call subshell
      The output should eq 'direct=2 child=0'
    End

    It 'is absent in a shell that is holding nothing'
      idle() {
        inzsh_spec_jobs_live '
          source "$1/lib/segments/jobs.zsh"
          _inzsh_segment_jobs_build
          print -r -- "[${_inzsh_segment_text[JOBS]}] n=${#jobstates}"
        '
      }
      When call idle
      The output should eq '[] n=0'
      The stderr should eq ''
    End

    It 'answers zero rather than erroring in a shell with no job table to read'
      # A script, which is where a bundled theme gets sourced by accident. There is nothing to
      # count and nothing to say, and neither the tally nor the build may complain about it.
      #
      # The module's absence itself cannot be staged from a spec — `jobstates` is read-only and
      # `zmodload -u zsh/parameter` is undone by the next access, which auto-loads it again — so
      # the guard that covers that case is asserted structurally below instead.
      unloaded() {
        zsh -f -c '
          source "$1/lib/segments/jobs.zsh"
          _inzsh_jobs_tally
          print -r -- "tally=$? running=$_inzsh_jobs_running suspended=$_inzsh_jobs_suspended"
          _inzsh_segment_jobs_build
          print -r -- "build=$? [${_inzsh_segment_text[JOBS]}]"
        ' inzsh-jobs-unloaded "$SHELLSPEC_PROJECT_ROOT"
      }
      When call unloaded
      The output should eq 'tally=0 running=0 suspended=0
build=0 []'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/segments/jobs.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sources silently in a single-byte locale'
      bytes() {
        LC_ALL=C zsh -f -c '
          source "$1/lib/segments/jobs.zsh"
          (( ${+functions[_inzsh_segment_jobs_build]} )) && print -r -- loaded
        ' inzsh-jobs-bytes "$SHELLSPEC_PROJECT_ROOT" </dev/null
      }
      When call bytes
      The output should eq 'loaded'
      The stderr should eq ''
    End

    It 'builds without forking — and a fork here would also be wrong, not merely slow'
      forks() {
        inzsh_spec_jobs_lines
        local line; local -a bad=()
        (( ${#inzsh_spec_lines} > 10 )) || bad+=no-lines-scanned
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'$('* || $line == *'`'* || $line == *whence* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call forks
      The output should eq ''
    End

    It 'never calls jobs, ps, date or uptime — the table is a module parameter'
      processes() {
        inzsh_spec_jobs_lines
        local line name; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          for name in jobs ps date uptime wc; do
            # `${name}` braced: `$name[` would be read as a SUBSCRIPT of the parameter.
            [[ " $line " == *[^a-zA-Z_]${name}[^a-zA-Z_]* ]] && bad+="$name: $line"
          done
        done
        print -rl -- $bad
      }
      When call processes
      The output should eq ''
    End

    It 'writes no \u escape — one would kill the file in a single-byte locale'
      escapes() {
        inzsh_spec_jobs_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'\u'* || $line == *'\U'* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call escapes
      The output should eq ''
    End

    It 'loads the module it depends on, reads the table, and guards on its absence'
      moduled() {
        inzsh_spec_jobs_lines
        local line; local -a bad=()
        local -i module=0 table=0 guard=0
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'zmodload -i zsh/parameter'* ]] && (( module++ ))
          [[ $line == *jobstates* ]]                   && (( table++ ))
          [[ $line == *'${+jobstates}'* ]]             && (( guard++ ))
        done
        (( module == 1 )) || bad+=module:$module
        (( table >= 2 ))  || bad+=table:$table
        (( guard == 1 ))  || bad+=guard:$guard
        print -rl -- $bad
      }
      When call moduled
      The output should eq ''
    End

    It 'carries no glyph literal — both marks are read from the token table'
      glyphs() {
        inzsh_spec_jobs_lines
        local line; local -a bad=() found=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'_inzsh_glyph[info]'* ]] && found+=running
          [[ $line == *'_inzsh_glyph[dash]'* ]] && found+=suspended
        done
        # Each mark is read twice — once at source time for the fallback, once per build so an
        # `INZSH_GLYPH_*` override is live — so the claim is that BOTH marks are read, not that
        # each is read once.
        local -a unique=(${(u)found})
        (( ${#unique} == 2 )) || bad+=table-reads:${(j:,:)unique}
        print -rl -- $bad
      }
      When call glyphs
      The output should eq ''
    End

    It 'carries no hex — colour lives in the token layer and nowhere else'
      hexed() {
        setopt local_options extended_glob
        inzsh_spec_jobs_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'#'[0-9A-Fa-f](#c6)* ]] && bad+=$line
        done
        print -r -- "${#bad}"
      }
      When call hexed
      The output should eq '0'
    End
  End
End