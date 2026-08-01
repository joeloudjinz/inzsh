Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/config.zsh
Include lib/core/render.zsh
Include lib/segments/duration.zsh

# The command-duration segment — `lib/segments/duration.zsh`. The one segment in the tree that
# needs state across two hooks, which makes this spec two specs in one:
#
#   the formatter   `_inzsh_segment_duration_build <seconds>` over injected numbers. Pure, and
#                   asserted exhaustively, because the shape of a duration is the whole design.
#   the timer       `preexec` marks, `precmd` freezes. Every example that touches a hook runs in
#                   a fresh `zsh -f -i` of its own — never in the runner — because what is under
#                   test is what INSTALLING does to a shell, and because work in progress is
#                   never sourced into the shell you are typing into.
#
# THE EXIT-STATUS ORDERING has three examples of its own, and they are the most important ones
# here. `_inzsh_precmd` captures `$?` and `$pipestatus` in its first command, and this file
# registers a precmd of its own — so the arrangement the theme ships in is asserted three ways:
# the pipeline's status survives it, `_inzsh_precmd` is still the first entry in
# `precmd_functions`, and nothing in the segment source assigns either captured parameter.
#
# `Include lib/core/config.zsh` because `INZSH_DURATION_MIN` is a registered knob and the
# registry is what validates it — the examples read it through the same path a prompt does.

# Runs $1 in a genuinely interactive zsh with no startup files, the project root as $1 inside.
# `PROMPT=` and the two prompt options are about the harness, not the theme: an interactive zsh
# writes its prompt and its partial-line marker to stderr, and this suite asserts on stderr.
inzsh_spec_duration_live() {
  print -r -- "$1" |
    PROMPT= RPROMPT= PS1= zsh -f -i -o nopromptcr -o nopromptsp -s "$SHELLSPEC_PROJECT_ROOT"
}

# Build for an injected number of seconds and print what the segment wrote, in brackets so that
# an empty entry — the absent case — is a visible result rather than a blank line.
inzsh_spec_duration() {
  emulate -L zsh

  _inzsh_segment_text=()
  _inzsh_segment_duration_build "$@"
  print -r -- "[${_inzsh_segment_text[DURATION]-'(no entry)'}]"
}

# The segment as the renderer draws it, on a right prompt of its own.
inzsh_spec_duration_drawn() {
  emulate -L zsh

  _inzsh_segment_text=()
  _inzsh_segment_duration_build "$@"
  _inzsh_left=()
  _inzsh_right=(DURATION)
  _inzsh_render_build right
  typeset -g inzsh_spec_drawn=$REPLY

  return 0
}

# The non-comment lines of the segment source, for the structural groups.
inzsh_spec_duration_lines() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga inzsh_spec_lines
  inzsh_spec_lines=()

  local line bare
  while IFS= read -r line; do
    bare=${line##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    inzsh_spec_lines+=$line
  done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/duration.zsh"

  return 0
}

Describe 'the command-duration segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers a rank default, a foreground role and an importance'
      registered() {
        local -a got=()
        got+=rank=${_inzsh_segment_defaults[DURATION]-}
        got+=role=${_inzsh_segment_fg_role[DURATION]-}
        got+=importance=${_inzsh_segment_importance[DURATION]-}
        print -r -- "${got[*]}"
      }
      When call registered
      The output should eq 'rank=0 role=text-muted importance=2'
    End

    It 'ships hidden — the engine puts it on neither side of the prompt'
      hidden() {
        _inzsh_rank_split DURATION
        print -rn -- "left=[${_inzsh_left[*]}] right=[${_inzsh_right[*]}] "
        print -r  -- "hidden=[${_inzsh_hidden[*]}]"
      }
      When call hidden
      The output should eq 'left=[] right=[] hidden=[DURATION]'
    End

    It 'comes out on whichever side the user ranks it'
      ranked() {
        local INZSH_DURATION_RANK=8
        _inzsh_rank_split DURATION
        local onleft="left=[${_inzsh_left[*]}]"
        INZSH_DURATION_RANK=-8
        _inzsh_rank_split DURATION
        print -r -- "$onleft right=[${_inzsh_right[*]}]"
      }
      When call ranked
      The output should eq 'left=[DURATION] right=[DURATION]'
    End

    It 'registers the floor it reads, with the default it restates'
      declared() {
        local -a bad=()
        [[ ${_inzsh_config_validators[INZSH_DURATION_MIN]} == 'int:0:' ]] ||
          bad+=spec:${_inzsh_config_validators[INZSH_DURATION_MIN]}
        [[ ${_inzsh_config_defaults[INZSH_DURATION_MIN]} == $_inzsh_duration_min_default ]] ||
          bad+=default:${_inzsh_config_defaults[INZSH_DURATION_MIN]}
        print -r -- "${bad[*]}"
      }
      When call declared
      The output should eq ''
    End

    It 'registers once however many times it is sourced'
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/duration.zsh"
          source "$1/lib/segments/duration.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${#_inzsh_segment_fg_role}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_defaults[DURATION]}"
        ' inzsh-duration-twice "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 1 1 0'
      The stderr should eq ''
    End

    It 'draws nothing and registers no hook at load'
      # Sourcing installs neither a prompt nor a hook. `_inzsh_duration_install` is a separate
      # call so the entry point decides when the timer goes live, and so a spec can load the
      # file without a hook landing in the shell that is running it.
      quiet() {
        zsh -f -i -c '
          local before="${PROMPT-unset}|${RPROMPT-unset}"
          source "$1/lib/segments/duration.zsh"
          local -a leaked=()
          [[ "${PROMPT-unset}|${RPROMPT-unset}" == $before ]] || leaked+=PROMPT
          (( ${+precmd_functions} ))  && leaked+=precmd:${precmd_functions[*]}
          (( ${+preexec_functions} )) && leaked+=preexec:${preexec_functions[*]}
          (( ${#_inzsh_segment_text} )) && leaked+=texts
          print -r -- "${leaked[*]}"
        ' inzsh-duration-load "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq ''
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the shape of a duration'
    # Two units, never three, largest first, second dropped when it is zero. The whole table is
    # here rather than sampled: this is the segment's entire visible design, and every boundary
    # in it is a place an off-by-one lives.
    Describe 'renders'
      Parameters
        3      '[3s]'
        9      '[9s]'
        59     '[59s]'
        60     '[1m]'
        61     '[1m 1s]'
        134    '[2m 14s]'
        3599   '[59m 59s]'
        3600   '[1h]'
        3660   '[1h 1m]'
        3725   '[1h 2m]'
        86399  '[23h 59m]'
        86400  '[1d]'
        90061  '[1d 1h]'
        172800 '[2d]'
        950400 '[11d]'
      End

      It "$1 seconds as $2"
        When call inzsh_spec_duration "$1"
        The output should eq "$2"
      End
    End

    It 'never renders a five-digit number of seconds, however long the command ran'
      # The property behind the table, swept rather than enumerated: a day, a week and a year
      # all come back as two units and neither of them is a raw second count.
      swept() {
        setopt local_options extended_glob
        local -i seconds
        local -a bad=()
        for seconds in 3 60 3600 86400 604800 31536000 999999999; do
          _inzsh_segment_duration_build $seconds
          local text=${_inzsh_segment_text[DURATION]}
          # The grammar: one unit, or two separated by a single space, and nothing else.
          [[ $text == <->[dhms]( <->[dhms]|) ]] || bad+="$seconds:$text"
          # And never the raw count, which is the failure this example is named for.
          [[ $text != "${seconds}s" || $seconds -lt 60 ]] || bad+="raw:$seconds:$text"
        done
        print -rl -- $bad
      }
      When call swept
      The output should eq ''
    End

    It 'truncates rather than rounds — the number is a floor'
      # `_inzsh_duration_freeze` truncates toward zero, so `2m 14s` means AT LEAST that. Asserted
      # through the freeze rather than the formatter, because truncation is where it happens.
      floored() {
        local -a got=()
        local -F now
        for now in 100.0 100.999999 102.5 163.75; do
          _inzsh_duration_mark 100.0
          _inzsh_duration_freeze $now
          got+=$_inzsh_duration_elapsed
        done
        print -r -- "${got[*]}"
      }
      When call floored
      The output should eq '0 0 2 63'
    End

    It 'takes the foreground role it registered'
      muted() {
        inzsh_spec_duration_drawn 134
        local -a missing=()
        [[ $inzsh_spec_drawn == *"%F{${_inzsh_role[text-muted]}}"* ]] || missing+=role
        [[ $inzsh_spec_drawn == *' 2m 14s '* ]]                      || missing+=text
        print -r -- "${missing[*]}"
      }
      When call muted
      The output should eq ''
    End

    It 'emits no colour of its own'
      uncoloured() {
        _inzsh_segment_duration_build 3725
        local -a found=()
        [[ ${_inzsh_segment_text[DURATION]} == *'%'[FKfk]* ]] && found+=escape
        print -r -- "${found[*]}"
      }
      When call uncoloured
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'INZSH_DURATION_MIN'
    Describe 'below the floor the segment is absent'
      Parameters
        0 ''
        1 ''
        2 ''
        3 '3s'
        4 '4s'
      End

      It "renders $1 seconds as '[$2]' at the shipped floor of three"
        When call inzsh_spec_duration "$1"
        The output should eq "[$2]"
      End
    End

    Describe 'the floor moves with the knob'
      floored() {
        local INZSH_DURATION_MIN=$1
        _inzsh_segment_text=()
        _inzsh_segment_duration_build "$2"
        print -r -- "[${_inzsh_segment_text[DURATION]}]"
      }

      Parameters
        0   0  '[0s]'
        0   1  '[1s]'
        10  9  '[]'
        10 10  '[10s]'
        60 59  '[]'
        60 60  '[1m]'
      End

      It "with a floor of $1, $2 seconds draws $3"
        When call floored "$1" "$2"
        The output should eq "$3"
      End
    End

    Describe 'a floor that is not a floor falls back to the shipped one'
      # Validate then fall back, the rule the whole config layer keeps: a value that fails its
      # validator is not an error and is never reported, it is simply not used.
      unfloored() {
        local INZSH_DURATION_MIN=$1
        _inzsh_segment_text=()
        _inzsh_segment_duration_build 2
        local low=${_inzsh_segment_text[DURATION]}
        _inzsh_segment_duration_build 3
        print -r -- "[$low][${_inzsh_segment_text[DURATION]}]"
      }

      Parameters
        'soon'
        '-5'
        '2.5'
        ''
        ' 1'
      End

      It "ignores a floor of '$1'"
        When call unfloored "$1"
        The output should eq '[][3s]'
      End
    End

    It 'reads the knob at build time, so a change takes effect at the next prompt'
      relive() {
        local INZSH_DURATION_MIN=3
        inzsh_spec_duration 2
        INZSH_DURATION_MIN=1
        inzsh_spec_duration 2
      }
      When call relive
      The output should eq '[]
[2s]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the timer'
    It 'measures the gap between a mark and a freeze'
      timed() {
        _inzsh_duration_mark 1000.000000
        _inzsh_duration_freeze 1134.750000
        inzsh_spec_duration
        print -r -- "elapsed=$_inzsh_duration_elapsed"
      }
      When call timed
      The output should eq '[2m 14s]
elapsed=134'
    End

    It 'freezes once — a second freeze with no command in between reports nothing'
      # The case that makes the running flag worth having: a prompt drawn without a command in
      # front of it must not report the age of the shell, and a repaint must not re-time.
      once() {
        _inzsh_duration_mark 1000.0
        _inzsh_duration_freeze 1134.0
        local first=$_inzsh_duration_elapsed
        _inzsh_duration_freeze 2000.0
        print -r -- "first=$first second=$_inzsh_duration_elapsed"
      }
      When call once
      The output should eq 'first=134 second=0'
    End

    It 'renders the same number however often the prompt is rebuilt'
      # The git worker can re-render a prompt seconds after it was first drawn. A duration that
      # ticked upward while the user sat at the line would be a stopwatch, not a report.
      steady() {
        _inzsh_duration_mark 1000.0
        _inzsh_duration_freeze 1134.0
        local -i i
        for (( i = 1; i <= 3; i++ )); do
          inzsh_spec_duration
        done
      }
      When call steady
      The output should eq '[2m 14s]
[2m 14s]
[2m 14s]'
    End

    It 'clamps a clock that went backwards rather than drawing a negative age'
      backwards() {
        _inzsh_duration_mark 2000.0
        _inzsh_duration_freeze 1000.0
        inzsh_spec_duration
        print -r -- "elapsed=$_inzsh_duration_elapsed"
      }
      When call backwards
      The output should eq '[]
elapsed=0'
    End

    Describe 'a mark that is not an instant times nothing'
      unmarked() {
        _inzsh_duration_running=0
        _inzsh_duration_mark "$1"
        _inzsh_duration_freeze 2000.0
        print -r -- "running=$_inzsh_duration_running elapsed=$_inzsh_duration_elapsed"
      }

      Parameters
        'soon'
        '-1'
        '1e9'
        '1000.'
        ' 1000'
      End

      It "ignores a mark of '$1'"
        When call unmarked "$1"
        The output should eq 'running=0 elapsed=0'
      End
    End

    It 'times a real command through the real hooks'
      # The whole lifecycle in a genuinely interactive shell: preexec fires before `sleep`,
      # precmd fires after it, and the number that comes out is the one a prompt would draw.
      real() {
        inzsh_spec_duration_live '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/duration.zsh"
          _inzsh_duration_install
          sleep 3.2
          print -r -- "[${_inzsh_segment_text[DURATION]}]"
        '
      }
      When call real
      The output should eq '[3s]'
      The stderr should eq ''
    End

    It 'is absent for a command that finished under the floor'
      brief() {
        inzsh_spec_duration_live '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/duration.zsh"
          _inzsh_duration_install
          true
          print -r -- "[${_inzsh_segment_text[DURATION]}]"
        '
      }
      When call brief
      The output should eq '[]'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the hooks'
    It 'registers one preexec and one precmd, however many times it is asked'
      # Idempotence by delegation: `add-zsh-hook` refuses to add a function the array already
      # holds. Installing three times is what a reload, a second plugin manager and a bundled
      # copy of the same theme add up to.
      twice() {
        inzsh_spec_duration_live '
          source "$1/lib/segments/duration.zsh"
          _inzsh_duration_install; _inzsh_duration_install; _inzsh_duration_install
          print -r -- "precmd=${precmd_functions[*]} preexec=${preexec_functions[*]}"
        '
      }
      When call twice
      The output should eq 'precmd=_inzsh_duration_precmd preexec=_inzsh_duration_preexec'
      The stderr should eq ''
    End

    It 'lets go of both, and leaves a foreign hook where it found it'
      # The regression the add-zsh-hook rule exists to prevent: an assignment would discard every
      # registration any other plugin had made.
      released() {
        inzsh_spec_duration_live '
          source "$1/lib/segments/duration.zsh"
          autoload -Uz add-zsh-hook
          alien() { : }; add-zsh-hook precmd alien; add-zsh-hook preexec alien
          _inzsh_duration_install
          local during="${precmd_functions[*]}|${preexec_functions[*]}"
          _inzsh_duration_uninstall
          print -r -- "during=[$during]"
          print -r -- "after=[${precmd_functions[*]}|${preexec_functions[*]}]"
        '
      }
      When call released
      The output should eq 'during=[alien _inzsh_duration_precmd|alien _inzsh_duration_preexec]
after=[alien|alien]'
      The stderr should eq ''
    End

    It 'uninstalls cleanly when there is nothing to uninstall'
      idle() {
        inzsh_spec_duration_live '
          source "$1/lib/segments/duration.zsh"
          _inzsh_duration_uninstall; _inzsh_duration_uninstall
          print -r -- "status=$? registered=${+precmd_functions}${+preexec_functions}"
        '
      }
      When call idle
      The output should eq 'status=0 registered=00'
      The stderr should eq ''
    End

    It 'registers nothing in a non-interactive shell'
      inert() {
        zsh -f -c '
          source "$1/lib/segments/duration.zsh"
          _inzsh_duration_install
          local -a leaked=()
          (( ${+precmd_functions} ))  && leaked+=precmd
          (( ${+preexec_functions} )) && leaked+=preexec
          print -r -- "${leaked[*]}"
        ' inzsh-duration-inert "$SHELLSPEC_PROJECT_ROOT"
      }
      When call inert
      The output should eq ''
      The stderr should eq ''
    End

    # ------------------------------------------------------------------------------------------
    # THE ORDERING. The most important pair of examples in this file.
    It 'keeps the exit status when it is installed after the hook layer'
      # The capture is read into `out` on the very next INPUT LINE, and printed on the one after.
      # Each line is one prompt here, so a precmd cycle runs between them and overwrites the
      # capture with the status of whatever ran last — reading it two lines later would report
      # the `print` and not the pipeline, which is a trap rather than a test.
      after() {
        inzsh_spec_duration_live '
          source "$1/lib/core/hooks.zsh"
          source "$1/lib/segments/duration.zsh"
          _inzsh_hooks_install
          _inzsh_duration_install
          true | false | (exit 7)
          out="status=$_inzsh_last_status pipes=${(j:,:)_inzsh_last_pipestatus}"
          print -r -- "order=${precmd_functions[*]} $out"
        '
      }
      When call after
      The output should eq 'order=_inzsh_precmd _inzsh_duration_precmd status=7 pipes=0,1,7'
      The stderr should eq ''
    End

    It 'leaves the status capture first in the array, which is where the contract puts it'
      # The positional half of the rule, asserted rather than described. `_inzsh_precmd` has to
      # be the first entry after this file has installed, and the entry point is what arranges
      # that by calling `_inzsh_hooks_install` above `_inzsh_duration_install`.
      first() {
        inzsh_spec_duration_live '
          source "$1/lib/core/hooks.zsh"
          source "$1/lib/segments/duration.zsh"
          _inzsh_hooks_install
          _inzsh_duration_install
          out="first=${precmd_functions[1]} count=${#precmd_functions}"
          print -r -- "$out"
        '
      }
      When call first
      The output should eq 'first=_inzsh_precmd count=2'
      The stderr should eq ''
    End

    It 'never writes the captured exit state itself'
      # The other half, and the one a spec can hold forever: whatever the hook order turns out
      # to be, this file must never ASSIGN `_inzsh_last_status` or `_inzsh_last_pipestatus`. The
      # capture belongs to `lib/core/hooks.zsh` and the retval segment reads what it wrote.
      untouched() {
        inzsh_spec_duration_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'_inzsh_last_status='* ]]      && bad+=$line
          [[ $line == *'_inzsh_last_pipestatus'*'='* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call untouched
      The output should eq ''
    End

    It 'puts this command''s duration into the prompt, not the previous one''s'
      # THE CONSEQUENCE OF REGISTERING AFTER, end to end. `_inzsh_precmd` renders while it runs,
      # which is before this hook has frozen anything — so the prompt it built carries the
      # PREVIOUS command's duration. Every precmd function runs before zsh expands PROMPT,
      # though, so the re-render here still reaches THIS prompt. Without it the segment would be
      # one command late, which is worse than absent.
      #
      # TWO THINGS ABOUT THE HARNESS, and both of them have already cost a debugging session.
      #
      # WHICH PARAMETER. The claim is about THE PROMPT, and which of `PROMPT` and `RPROMPT`
      # carries the right-hand side is `INZSH_PROMPT_LINES`'s business rather than this
      # segment's: at one line the right side stays in `RPROMPT`, and at two — the default —
      # `_inzsh_render` pads it into `PROMPT` and leaves `RPROMPT` empty. So `holds` reads the
      # two TOGETHER. An example that named one of them was asserting the shape by accident, and
      # broke the day the shape changed without the segment changing at all.
      #
      # WHICH LINE, AND HOW MANY. Every input line here is one prompt, so a precmd cycle runs
      # between any two of them. The command that follows `sleep` is fast, so that cycle freezes
      # an elapsed time under the floor, empties the fragment AND RE-RENDERS — which is the very
      # behaviour under test, and it wipes the block out of the prompt. The whole reading must
      # therefore happen on the ONE input line after the command, semicolons and all. Split it
      # over two lines and it reports a miss at every shape, for a reason that has nothing to do
      # with what it is asking about.
      #
      # That same re-render is the second half of the claim, so it is asserted rather than
      # merely survived: after a fast command the block is GONE. A prompt that kept it would be
      # showing the previous command's duration, which is the failure this example is named for.
      current() {
        inzsh_spec_duration_live '
          source "$1/lib/core/config.zsh"
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/tokens-256.zsh"
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/layout.zsh"
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/core/hooks.zsh"
          source "$1/lib/segments/duration.zsh"
          typeset -g INZSH_DURATION_RANK=-1
          typeset -g COLUMNS=80
          _inzsh_hooks_install
          _inzsh_duration_install
          holds() { [[ $PROMPT$RPROMPT == *$1* ]] }
          sleep 3.2
          t=${_inzsh_segment_text[DURATION]}; s=no; [[ -n $t ]] && holds "$t" && s=yes
          true
          u=${_inzsh_segment_text[DURATION]}; g=stale; [[ -z $u ]] && ! holds "$t" && g=cleared
          print -r -- "[$t] in-prompt=$s then=$g"
        '
      }
      When call current
      The output should eq '[3s] in-prompt=yes then=cleared'
      # The one example in this file that does not assert an empty stderr, and the reason is the
      # harness rather than the theme: this is the only script here that lets `_inzsh_render`
      # assign PROMPT, and an interactive zsh writes its prompt to stderr. So the assertion is
      # narrowed to the thing that would actually be wrong.
      The stderr should not include 'not found'
    End

    It 'does not re-render a prompt that never placed it'
      # The cost of the hook when the segment is hidden, which is the configuration it ships in.
      # `_inzsh_render` is replaced by a counter: a five-second command at rank 0 updates a
      # string nobody is drawing and stops there. Then the same thing with the segment ranked
      # onto the right prompt, and a different elapsed so the fragment genuinely changes.
      #
      # No `#` line appears inside the script below, here or in any other example in this file:
      # an INTERACTIVE zsh does not set `interactive_comments`, so a comment would be run as a
      # command and the shell would say so on stderr.
      cheap() {
        inzsh_spec_duration_live '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/duration.zsh"
          typeset -gi drew=0
          _inzsh_render() { (( drew++ )) }
          _inzsh_left=(); _inzsh_right=()
          (( _inzsh_duration_start = EPOCHREALTIME - 5 ))
          _inzsh_duration_running=1
          _inzsh_duration_precmd
          local hidden="hidden=$drew [${_inzsh_segment_text[DURATION]}]"
          drew=0
          _inzsh_right=(DURATION)
          (( _inzsh_duration_start = EPOCHREALTIME - 7 ))
          _inzsh_duration_running=1
          _inzsh_duration_precmd
          print -r -- "$hidden shown=$drew [${_inzsh_segment_text[DURATION]}]"
        '
      }
      When call cheap
      The output should eq 'hidden=0 [5s] shown=1 [7s]'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'hostile input'
    Describe 'an elapsed time that is not a count draws nothing'
      Parameters
        'soon'
        '-5'
        '2.5'
        ''
        ' 100'
      End

      It "is absent for an elapsed of '$1'"
        When call inzsh_spec_duration "$1"
        The output should eq '[]'
      End
    End

    It 'is absent rather than broken when the datetime module is not there'
      unloaded() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/duration.zsh"
          zmodload -u zsh/datetime
          _inzsh_duration_mark
          print -r -- "mark=$? running=$_inzsh_duration_running"
          _inzsh_duration_running=1
          _inzsh_duration_freeze
          print -r -- "freeze=$? elapsed=$_inzsh_duration_elapsed"
          _inzsh_segment_duration_build
          print -r -- "build=$? [${_inzsh_segment_text[DURATION]}]"
        ' inzsh-duration-unloaded "$SHELLSPEC_PROJECT_ROOT"
      }
      When call unloaded
      The output should eq 'mark=0 running=0
freeze=0 elapsed=0
build=0 []'
      The stderr should eq ''
    End

    It 'rewrites the entry on every build rather than accumulating'
      rewritten() {
        inzsh_spec_duration 134
        inzsh_spec_duration 1
        inzsh_spec_duration 3600
      }
      When call rewritten
      The output should eq '[2m 14s]
[]
[1h]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/segments/duration.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sources silently in a single-byte locale'
      bytes() {
        LC_ALL=C zsh -f -c '
          source "$1/lib/segments/duration.zsh"
          (( ${+functions[_inzsh_segment_duration_build]} )) && print -r -- loaded
        ' inzsh-duration-bytes "$SHELLSPEC_PROJECT_ROOT" </dev/null
      }
      When call bytes
      The output should eq 'loaded'
      The stderr should eq ''
    End

    It 'builds without forking — this runs before every prompt'
      forks() {
        inzsh_spec_duration_lines
        local line; local -a bad=()
        (( ${#inzsh_spec_lines} > 20 )) || bad+=no-lines-scanned
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'$('* || $line == *'`'* || $line == *whence* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call forks
      The output should eq ''
    End

    It 'never calls date, ps, uptime or time — the clock is a module parameter'
      processes() {
        inzsh_spec_duration_lines
        local line name; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          for name in date ps uptime times; do
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
        inzsh_spec_duration_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'\u'* || $line == *'\U'* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call escapes
      The output should eq ''
    End

    It 'registers its hooks through add-zsh-hook and never by assignment'
      # `precmd_functions=(…)` discards every registration any other plugin had made. The rule
      # is asserted over the source rather than only over the behaviour, because an assignment
      # that only fires on somebody else's setup is one no run of ours would see.
      hooked() {
        inzsh_spec_duration_lines
        local line; local -a bad=() found=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'precmd_functions='* || $line == *'preexec_functions='* ]] && bad+=$line
          [[ $line == *'precmd='* || $line == *'preexec='* ]] && bad+=$line
          [[ $line == *'add-zsh-hook'* ]] && found+=hook
        done
        (( ${#found} >= 4 )) || bad+=too-few-add-zsh-hook:${#found}
        print -rl -- $bad
      }
      When call hooked
      The output should eq ''
    End

    It 'carries no hex — colour lives in the token layer and nowhere else'
      hexed() {
        setopt local_options extended_glob
        inzsh_spec_duration_lines
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