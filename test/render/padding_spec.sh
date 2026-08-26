Include lib/core/config.zsh
Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh

# The padding — `INZSH_SEGMENT_PAD` in `lib/core/render.zsh`. How many columns of air sit
# either side of a block's text: `1` is the shipped block shape `[ text ]`, `0` packs the row,
# up to `4` spreads it. Issue #176: the column was a literal in the builder, chosen once and
# changeable by nobody.
#
# The bound is the validator, and the validator is the invariant here: padding is LITERAL
# SPACES, the one thing in a prompt that can push a row past the terminal's edge, so an
# unreadable or unbounded value falls back to `1` rather than being obeyed. What the width
# machinery does with the resolved value is measured back off the drawn string — the builder
# and the measurer must arrive at the same number by different routes for every padding, not
# only for the default.

# Build one plain two-segment left prompt under padding `$1` and leave the built string,
# stripped of colour escapes, in `inzsh_pad_row`; the tracked width in `inzsh_pad_width`.
inzsh_pad_build() {
  emulate -L zsh
  setopt extended_glob

  local INZSH_SEGMENT_PAD=$1
  local INZSH_SEPARATOR_STYLE=divider

  _inzsh_segment_text=(A one B two)
  _inzsh_left=(A B)
  _inzsh_right=()

  _inzsh_render_build left "${_inzsh_left[@]}"
  typeset -g inzsh_pad_width=$_inzsh_render_width
  local built=$REPLY
  built=${built//(%[KF]\{[^\}]#\}|%[fk])/}
  # The separator, rewritten to an ASCII bar so the expectations stay legible in a diff and
  # hold in either locale register — no glyph is pasted into an assertion.
  built=${built//${_inzsh_sep_left}/|}
  typeset -g inzsh_pad_row=$built
  typeset -g inzsh_pad_raw=$REPLY

  return 0
}

Describe 'segment padding'
  # ------------------------------------------------------------------------------------------
  Describe 'resolving the knob'
    It 'is registered with the config layer, validator and default'
      registered() {
        print -r -- "${_inzsh_config_validators[INZSH_SEGMENT_PAD]-missing}"
        print -r -- "${_inzsh_config_defaults[INZSH_SEGMENT_PAD]-missing}"
      }
      When call registered
      The line 1 of output should eq 'int:0:4'
      The line 2 of output should eq '1'
    End

    Describe 'what a value resolves to'
      Parameters
        0       0
        1       1
        2       2
        4       4
        '+3'    3
        5       1
        -1      1
        99      1
        abc     1
        ''      1
        2.5     1
        ' 2'    1
      End

      It "resolves '$1' to $2"
        resolved() {
          local INZSH_SEGMENT_PAD=$1
          _inzsh_render_pad
          print -r -- "$_inzsh_render_pad_resolved"
        }
        When call resolved "$1"
        The output should eq "$2"
      End
    End

    It 'resolves to the default when the knob was never set at all'
      unset_knob() {
        unset INZSH_SEGMENT_PAD
        _inzsh_render_pad
        print -r -- "$_inzsh_render_pad_resolved"
      }
      When call unset_knob
      The output should eq '1'
    End

    It 'resolves without a config layer at all, refusing the same values'
      alone() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local value; local -a seen=()
          for value in 0 3 5 abc; do
            typeset -g INZSH_SEGMENT_PAD=$value
            _inzsh_render_pad
            seen+=$_inzsh_render_pad_resolved
          done
          print -r -- "${seen[*]} config=${+functions[_inzsh_config_get]}"
        ' inzsh-pad-alone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call alone
      The output should eq '0 3 1 1 config=0'
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'what the builder draws'
    Describe 'the air either side of every block'
      Parameters
        0 '[one|two|]'
        1 '[ one | two |]'
        2 '[  one  |  two  |]'
        3 '[   one   |   two   |]'
      End

      It "draws padding $1 as $2"
        drawn() {
          inzsh_pad_build "$1"
          print -r -- "[$inzsh_pad_row]"
        }
        When call drawn "$1"
        The output should eq "$2"
      End
    End

    It 'draws the shipped shape for a hostile value'
      hostile() {
        local value; local -a wrong=()
        inzsh_pad_build 1
        local shipped=$inzsh_pad_row
        for value in -1 5 abc '' 1.5; do
          inzsh_pad_build "$value"
          [[ $inzsh_pad_row == $shipped ]] || wrong+="${value:-empty}:$inzsh_pad_row"
        done
        print -r -- "${wrong[*]}"
      }
      When call hostile
      The output should eq ''
    End

    It 'reads the knob fresh on every build rather than caching the first answer'
      live() {
        inzsh_pad_build 0
        local first=$inzsh_pad_row
        inzsh_pad_build 3
        local second=$inzsh_pad_row
        local -a wrong=()
        [[ $first == 'one|two|' ]]                    || wrong+=first:$first
        [[ $second == '   one   |   two   |' ]]       || wrong+=second:$second
        print -r -- "${wrong[*]}"
      }
      When call live
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'width accounting'
    # The no-wrap rule survives every padding because nothing about it is assumed: the tracked
    # total is compared against a measurement of the finished string, so a padding the builder
    # drew and the accountant missed fails here rather than wrapping a row.
    Describe 'the running total matches the drawn row'
      Parameters
        0
        1
        2
        4
      End

      It "agrees with _inzsh_width at padding $1"
        agrees() {
          inzsh_pad_build "$1"
          _inzsh_width "$inzsh_pad_raw"
          if [[ $inzsh_pad_width == $REPLY ]]; then
            print -r -- agree
          else
            print -r -- "tracked=$inzsh_pad_width measured=$REPLY"
          fi
        }
        When call agrees "$1"
        The output should eq 'agree'
      End
    End

    It 'books each block two more columns per extra column of padding'
      booked() {
        local -a widths=()
        local -i pad
        for pad in 0 1 2; do
          inzsh_pad_build $pad
          widths+=$inzsh_pad_width
        done
        # Two blocks, two sides each: each step of padding adds four columns to the row.
        print -r -- "$(( widths[2] - widths[1] )) $(( widths[3] - widths[2] ))"
      }
      When call booked
      The output should eq '4 4'
    End
  End
End
