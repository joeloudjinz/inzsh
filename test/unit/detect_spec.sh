Include lib/core/detect.zsh

# Colour depth detection. Every example forces the environment it is about — `COLORTERM` and
# `TERM` are declared `local` inside the helper, so zsh re-reads terminfo for the duration of
# the call and restores the caller's terminal on return. Nothing here depends on the terminal
# the suite happens to run in.
#
# The three answers are the only three answers: `truecolor`, `256`, `8`. A fourth value, or an
# empty one, is a failure however it was arrived at. Each parameterised Describe holds exactly
# one example, so a table row means what it looks like it means.
inzsh_spec_depths=(truecolor 256 8)

Describe 'colour depth detection'
  Describe 'at source time'
    It 'leaves a depth behind just by being sourced'
      sourced() { print -r -- "$_inzsh_color_depth"; }
      When call sourced
      The output should be present
    End

    It 'answers with one of the three depths and nothing else'
      known() {
        (( ${inzsh_spec_depths[(Ie)$_inzsh_color_depth]} )) && print -r -- 'known'
      }
      When call known
      The output should eq 'known'
    End

    # The file is one link in a chain — detect, then the fallback tables, then the token
    # layer — but each link has to stand on its own for a bundle, a partial source or a spec
    # to work. `zsh -f` because this spec file has already loaded it.
    It 'is independently sourceable — no other file of ours has to be loaded first'
      standalone() {
        zsh -f -c '
          source "$1/lib/core/detect.zsh" || print -r -- "non-zero exit"
          print -r -- "$_inzsh_color_depth"
        ' inzsh-detect-standalone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call standalone
      The output should be present
    End
  End

  # Truecolor is advertised rather than discovered: terminfo has no widely-populated 24-bit
  # capability, so this variable is the whole signal. Both spellings, either case.
  Describe 'a COLORTERM that advertises truecolor'
    Parameters
      truecolor
      24bit
      TrueColor
      24BIT
    End

    It "reads COLORTERM=$1 as truecolor"
      advertised() {
        local COLORTERM=$1 TERM=linux
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call advertised "$1"
      The output should eq 'truecolor'
    End
  End

  # Set-but-not-a-truecolor-claim has to fall through to terminfo, not be treated as a claim.
  # `TERM=linux` underneath makes the fall-through visible: a wrong answer here is `truecolor`,
  # not a near miss.
  Describe 'a COLORTERM that advertises nothing'
    Parameters
      ''
      yes
      1
      truecolor-ish
      '24 bit'
      256color
    End

    It "falls through to terminfo for COLORTERM='$1'"
      through() {
        local COLORTERM=$1 TERM=linux
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call through "$1"
      The output should eq '8'
    End
  End

  Describe 'a COLORTERM that is not set at all'
    It 'falls through to terminfo rather than reading the empty value as a claim'
      unset_colorterm() {
        local TERM=linux
        unset COLORTERM
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call unset_colorterm
      The output should eq '8'
    End
  End

  # zsh repopulates `$terminfo` when `TERM` is assigned, so a local assignment is a real
  # capability change for the length of the call — no subshell needed, and no `tput`.
  #
  # `linux` is the kernel console: a known terminal that genuinely has eight colours, and the
  # case that proves the floor is reached by detection rather than by giving up.
  Describe 'terminfo'
    Parameters
      xterm-256color        256
      screen-256color       256
      tmux-256color         256
      linux                 8
      xterm                 8
      vt100                 8
      dumb                  8
      no-such-terminal-here 8
    End

    It "reads TERM=$1 as depth $2"
      capability() {
        local TERM=$1 COLORTERM=
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call capability "$1"
      The output should eq "$2"
    End
  End

  Describe 'a terminal it cannot look up'
    # An unknown TERM leaves `$terminfo` empty rather than erroring. The empty string must not
    # reach an arithmetic comparison, and the missing answer must degrade down, never up.
    It 'never guesses upward'
      unknown() {
        local TERM COLORTERM=
        local -a wrong=()
        for TERM in no-such-terminal-here '' xterm-256color-typo dumb; do
          _inzsh_detect_color_depth
          [[ $_inzsh_color_depth == 8 ]] || wrong+="${TERM:-empty}=$_inzsh_color_depth"
        done
        print -r -- "${wrong[*]}"
      }
      When call unknown
      The output should eq ''
    End
  End

  # $1 the override, $2 the environment it has to beat, $3 the depth that environment would
  # otherwise produce. Every row is a real disagreement, and the helper asserts the
  # disagreement first — an override that matched detection by accident would prove nothing.
  Describe 'the INZSH_COLOR_DEPTH override'
    Parameters
      truecolor linux          8
      256       linux          8
      8         xterm-256color 256
      truecolor xterm-256color 256
      256       xterm-256color 256
    End

    It "honours INZSH_COLOR_DEPTH=$1 over TERM=$2"
      forced() {
        local TERM=$2 COLORTERM= INZSH_COLOR_DEPTH=
        _inzsh_detect_color_depth
        [[ $_inzsh_color_depth == $3 ]] || print -r -- "the environment did not say $3"
        INZSH_COLOR_DEPTH=$1
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call forced "$1" "$2" "$3"
      The output should eq "$1"
    End
  End

  # A typo must not flatten the palette. Anything outside the three known values is ignored
  # and detection answers instead — here `COLORTERM=truecolor`, so an obeyed typo shows up as
  # anything other than `truecolor`. `24bit` is a valid COLORTERM and an invalid override; the
  # two vocabularies are not the same vocabulary.
  Describe 'an unrecognised INZSH_COLOR_DEPTH'
    Parameters
      banana
      16
      ''
      'truecolor '
      ' truecolor'
      TRUECOLOR
      24bit
      0
      '8 '
      true
    End

    It "ignores INZSH_COLOR_DEPTH='$1' and detects instead"
      invalid() {
        local COLORTERM=truecolor TERM=linux INZSH_COLOR_DEPTH=$1
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call invalid "$1"
      The output should eq 'truecolor'
    End
  End

  Describe 'recomputation'
    It 'reads the override fresh — clearing it hands the answer back to detection'
      released() {
        local TERM=linux COLORTERM= INZSH_COLOR_DEPTH=truecolor
        _inzsh_detect_color_depth
        local held=$_inzsh_color_depth
        unset INZSH_COLOR_DEPTH
        _inzsh_detect_color_depth
        print -r -- "$held $_inzsh_color_depth"
      }
      When call released
      The output should eq 'truecolor 8'
    End

    # An existing `_inzsh_color_depth` is a previous answer, not a preference. Only the
    # override survives a recompute; a stale value must not.
    It 'overwrites a stale depth rather than respecting it'
      stale() {
        local TERM=linux COLORTERM=
        typeset -g _inzsh_color_depth=truecolor
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call stale
      The output should eq '8'
    End

    It 'tracks the environment across repeated calls in both directions'
      tracked() {
        local TERM COLORTERM=
        local -a seen=()
        for TERM in linux xterm-256color linux; do
          _inzsh_detect_color_depth
          seen+=$_inzsh_color_depth
        done
        print -r -- "${seen[*]}"
      }
      When call tracked
      The output should eq '8 256 8'
    End

    It 'reports success whichever rung of the ladder answers'
      statuses() {
        local TERM COLORTERM INZSH_COLOR_DEPTH
        local -a bad=()
        TERM=linux COLORTERM= INZSH_COLOR_DEPTH=256
        _inzsh_detect_color_depth || bad+=override
        TERM=linux COLORTERM=truecolor INZSH_COLOR_DEPTH=
        _inzsh_detect_color_depth || bad+=colorterm
        TERM=xterm-256color COLORTERM= INZSH_COLOR_DEPTH=
        _inzsh_detect_color_depth || bad+=terminfo
        TERM=no-such-terminal-here COLORTERM= INZSH_COLOR_DEPTH=
        _inzsh_detect_color_depth || bad+=floor
        print -r -- "${bad[*]}"
      }
      When call statuses
      The output should eq ''
    End
  End

  # Structural rather than behavioural. This file is sourced on every shell start, so the cost
  # that matters is a fork, and a fork is invisible in the result. Comment lines are skipped —
  # the prose there names `tput` precisely because it explains why we do not call it.
  Describe 'cost'
    It 'detects without forking — no command substitution and no external lookup'
      forks() {
        setopt local_options extended_glob
        local line; local -a bad=()
        while IFS= read -r line; do
          [[ $line == [[:space:]]#\#* ]] && continue
          [[ $line == *'$('* || $line == *'`'* || $line == *tput* ]] && bad+=$line
        done < "$SHELLSPEC_PROJECT_ROOT/lib/core/detect.zsh"
        print -r -- "${#bad}"
      }
      When call forks
      The output should eq '0'
    End
  End
End
