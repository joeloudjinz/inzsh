# The prompt SHAPE — `_inzsh_render` in `lib/core/render.zsh`. How many rows the prompt takes,
# what is on each of them, and where the right prompt ends up.
#
# Nothing here is `Include`d. `_inzsh_render` returns early in a shell that is not interactive —
# that guard is the theme's promise to every script and every `ssh host command` — so every
# example runs the real function in a fresh `zsh -f -i -c`, the same harness
# `test/render/entrypoint_spec.sh` uses and for the same reason. It also means no example can
# assign PROMPT in the shell running the suite, which is the other half of never sourcing work
# in progress into a live shell.
#
# The segments are a FIXTURE rather than the real ones: three names with fixed ranks and fixed
# text, so the row this file measures is one it wrote. A change to the dir segment's ladder or
# to the clock's format may not move an assertion here.
#
# No glyph is pasted into an assertion. The marker is compared against `_inzsh_glyph[prompt]`
# and its stand-in against `_inzsh_glyph_ascii[prompt]`, because a mark spelled twice is a mark
# that will one day be spelled two ways. Colours are compared against `_inzsh_role` entries for
# the same reason, so no hex reaches this file either.
#
# What is NOT here, and where it is instead:
#   the assembled string per side     test/render/render_build_spec.sh
#   how many rows the TERMINAL shows  test/ui/test_prompt_shape.py
#   the transient collapse            test/render/transient_spec.sh, test/ui/test_transient.py

# Run `$1` with the render core loaded, three fixture segments registered and an 80-column
# terminal. Arguments after the body reach it as `$1`, `$2`… so a swept example passes a value
# rather than pasting one into a script.
#
# `unset -m 'INZSH_*'` first, so a knob in the developer's own zshrc cannot change what this file
# asserts. `ALFA` and `BRAVO` rank into the left prompt and `CHARLIE` into the right — the
# smallest fixture that has both sides, which is what every claim about where the right prompt
# goes needs.
inzsh_spec_shape() {
  local body=$1
  shift
  zsh -f -i -c '
    local root=$1 body=$2
    shift 2
    unset -m "INZSH_*"

    local file
    for file in config detect tokens-256 tokens layout engine rows render; do
      source $root/lib/core/$file.zsh
    done

    typeset -gA _inzsh_segment_defaults _inzsh_segment_text
    _inzsh_segment_defaults=(ALFA 1 BRAVO 2 CHARLIE -1)
    _inzsh_segment_text=(ALFA alfa BRAVO bravo CHARLIE charlie)
    typeset -g COLUMNS=80

    # The visible text of a prompt fragment, in REPLY: the colour escapes taken back off and
    # nothing else touched. Deliberately NOT `${(%%)…}` — expanding a prompt string to look at
    # it means every later assertion is really about zsh escape handling, and a fixture whose
    # text is three plain words has nothing to expand.
    inzsh_shape_text() {
      setopt local_options extended_glob
      local out=${1//\%[FK]\{[^\}]#\}/}
      typeset -g REPLY=${out//\%[fk]/}
    }

    # Its width in COLUMNS — `${(m)#…}` — because a prompt is a row of cells and not a string.
    inzsh_shape_width() {
      inzsh_shape_text "$1"
      typeset -gi REPLY_WIDTH=${(m)#REPLY}
    }

    eval "$body"
  ' inzsh-prompt-shape "$SHELLSPEC_PROJECT_ROOT" "$body" "$@"
}

# The same, with nothing but `lib/core/render.zsh` in the shell — no config layer, no token
# layer, no engine. The degradation path, asked directly.
inzsh_spec_shape_alone() {
  zsh -f -i -c '
    local root=$1 body=$2
    unset -m "INZSH_*"
    source $root/lib/core/render.zsh
    eval "$body"
  ' inzsh-prompt-shape-alone "$SHELLSPEC_PROJECT_ROOT" "$1"
}

Describe 'the prompt shape'
  # -------------------------------------------------------------------------------------------
  Describe 'two lines, the default'
    # The shape itself. One newline in PROMPT, which is two rows, and the split is where the
    # segments stop and the input begins.
    It 'draws the segments on one row and the marker on the next'
      rows() {
        inzsh_spec_shape '
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          print -r -- "rows=${#rows}"
        '
      }
      When call rows
      The output should eq 'rows=2'
      The stderr should eq ''
    End

    It 'puts every left segment on the first row and none of them on the second'
      split() {
        inzsh_spec_shape '
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          local -a wrong=()
          inzsh_shape_text "${rows[1]}"; local first=$REPLY
          inzsh_shape_text "${rows[2]}"; local second=$REPLY
          [[ $first == *alfa*bravo* ]]                || wrong+=first:$first
          [[ $second != *alfa* && $second != *bravo* ]] || wrong+=second:$second
          print -r -- "${wrong[*]}"
        '
      }
      When call split
      The output should eq ''
      The stderr should eq ''
    End

    # The second row is the line you type on, so it is one mark and one space and nothing else.
    # Asserted against the token layer's entry rather than against a pasted glyph — no mark in
    # this repo is spelled twice.
    It 'ends the second row with the marker and a single space'
      marker_row() {
        inzsh_spec_shape '
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          inzsh_shape_text "${rows[2]}"
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] && print -r -- exact ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call marker_row
      The output should eq 'exact'
      The stderr should eq ''
    End

    # THE DECISION THIS SHAPE EXISTS FOR. The clock and the prayer countdown belong beside the
    # segments, not beside the cursor — zsh draws `RPROMPT` on the LAST row of a multi-row
    # prompt, so keeping them on the first one means padding them into it and leaving `RPROMPT`
    # empty. Both halves are asserted: the text is up there, and the parameter that would have
    # put it down here is not carrying anything.
    It 'keeps the right prompt on the segment row and leaves RPROMPT empty'
      right_side() {
        inzsh_spec_shape '
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          local -a wrong=()
          inzsh_shape_text "${rows[1]}"; local first=$REPLY
          inzsh_shape_text "${rows[2]}"; local second=$REPLY
          [[ $first  == *charlie* ]] || wrong+=not-on-row-one
          [[ $second != *charlie* ]] || wrong+=on-row-two
          [[ -z $RPROMPT ]]          || wrong+=rprompt-carried-something
          print -r -- "${wrong[*]}"
        '
      }
      When call right_side
      The output should eq ''
      The stderr should eq ''
    End

    # Two lines is a SHAPE, not a quota. A row with nothing on it is a blank line above the
    # cursor, which is the noise this theme exists to remove.
    It 'draws only the marker row when every segment is absent'
      bare() {
        inzsh_spec_shape '
          _inzsh_segment_text=()
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          inzsh_shape_text "$PROMPT"
          local -a wrong=()
          (( ${#rows} == 1 ))                      || wrong+=rows:${#rows}
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] || wrong+=text:$REPLY
          print -r -- "${wrong[*]}"
        '
      }
      When call bare
      The output should eq ''
      The stderr should eq ''
    End

    # Where the two sides cannot both fit, the right one is not thrown away to `RPROMPT` any
    # more — nothing relocates between rows in this design. It drops by priority instead, on the
    # row it was placed on, exactly like any other block that will not fit; `RPROMPT` stays empty
    # because this is the default row, `own`'s marker row, never the last physical line.
    It 'drops the right side by priority when the two sides cannot both fit on the row'
      narrow() {
        inzsh_spec_shape '
          typeset -g COLUMNS=20
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          inzsh_shape_text "${rows[1]}"
          local -a wrong=()
          (( ${#rows} == 2 ))      || wrong+=rows:${#rows}
          [[ $REPLY != *charlie* ]] || wrong+=drawn-anyway
          [[ $PROMPT != *charlie* ]] || wrong+=carried-somewhere-in-prompt
          [[ -z $RPROMPT ]]         || wrong+=rprompt-carried-something
          print -r -- "${wrong[*]}"
        '
      }
      When call narrow
      The output should eq ''
      The stderr should eq ''
    End

    # An unknown terminal width is the same case as a terminal too narrow to hold both: there is
    # no arithmetic that can right-align against a width nobody knows, so the right side is
    # dropped rather than relocated — the same outcome the narrow terminal above gets, for the
    # same reason.
    It 'drops the right side when the terminal width is unknown'
      unknown() {
        inzsh_spec_shape '
          typeset -g COLUMNS=0
          _inzsh_render
          [[ -z $RPROMPT ]] && print -r -- dropped || print -r -- "fell-back=<$RPROMPT>"
        '
      }
      When call unknown
      The output should eq 'dropped'
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  # Issue #185. A rank of 0 is switched off, and switched off must mean genuinely free: no build
  # call, no width-filter registry read. `DELTA` is added to the fixture's own
  # `_inzsh_segment_defaults` here rather than swapped in for ALFA/BRAVO/CHARLIE, so every
  # example still exercises a real split across all three rank signs alongside the one segment
  # under test. The rank sort's own no-second-read property is a claim about every survivor,
  # not only a hidden one, and sits in its own group below this one.
  Describe 'a segment ranked zero costs nothing to draw'
    It 'never calls the build function of a segment ranked zero'
      unbuilt() {
        inzsh_spec_shape '
          typeset -gi inzsh_spec_delta_calls=0
          _inzsh_segment_delta_build() { (( inzsh_spec_delta_calls++ )) }
          _inzsh_segment_defaults[DELTA]=0

          _inzsh_render
          print -r -- "calls=$inzsh_spec_delta_calls hidden=${_inzsh_hidden[*]}"
        '
      }
      When call unbuilt
      The output should eq 'calls=0 hidden=DELTA'
      The stderr should eq ''
    End

    # The membership change the paragraph above `_inzsh_render` itself describes, pinned:
    # `INZSH_DELTA_MINCOLS` is set far past the fixture's 80 columns specifically so this is the
    # example width could have excluded, if width still ran before rank.
    It 'still lands in _inzsh_hidden when its own MINCOLS exceeds the terminal'
      too_wide() {
        inzsh_spec_shape '
          _inzsh_segment_defaults[DELTA]=0
          typeset -g INZSH_DELTA_MINCOLS=999

          _inzsh_render
          print -r -- "hidden=${_inzsh_hidden[*]}"
        '
      }
      When call too_wide
      The output should eq 'hidden=DELTA'
      The stderr should eq ''
    End

    # The width filter is what `_inzsh_mincols_of` answers on behalf of — see
    # `lib/core/layout.zsh`. A segment that is already known to be hidden must never reach it,
    # because reaching it is itself a registry read (`INZSH_<SEG>_MINCOLS`) this segment has no
    # business paying for.
    #
    # Asserted as a per-name COUNT rather than against the literal `ALFA BRAVO CHARLIE`, so a
    # fixture segment added to `inzsh_spec_shape` for some unrelated reason cannot break this
    # example on a name it never mentions: DELTA must be asked zero times, and every OTHER
    # registered segment — whatever the fixture happens to hold — exactly once.
    It 'never asks the width filter about a segment ranked zero'
      unfiltered() {
        inzsh_spec_shape '
          typeset -ga inzsh_spec_asked=()
          _inzsh_mincols_of() { inzsh_spec_asked+=$1; typeset -g REPLY=0 }
          _inzsh_segment_defaults[DELTA]=0

          _inzsh_render

          local -A tally
          local name
          for name in "${inzsh_spec_asked[@]}"; do (( tally[$name]++ )); done

          local -a wrong=()
          for name in ${(ok)_inzsh_segment_defaults}; do
            if [[ $name == DELTA ]]; then
              (( ${tally[$name]:-0} == 0 )) || wrong+="$name=${tally[$name]}"
            else
              (( tally[$name] == 1 )) || wrong+="$name=${tally[$name]:-0}"
            fi
          done
          print -r -- "${wrong[*]}"
        '
      }
      When call unfiltered
      The output should eq ''
      The stderr should eq ''
    End

    # THE CORRECTNESS CONCERN. `_inzsh_segment_text` is a persistent global map, so a build
    # skipped while hidden must never leave a stale entry that could be drawn later. Walked
    # through the exact trip a user causes by editing a rank at a live prompt: visible, then
    # hidden, then visible again — three draws, three checks.
    It 'rebuilds fresh text the moment a rank returns from zero — nothing stale survives the trip'
      churn() {
        inzsh_spec_shape '
          typeset -gi inzsh_spec_delta_calls=0
          _inzsh_segment_delta_build() {
            (( inzsh_spec_delta_calls++ ))
            _inzsh_segment_text[DELTA]="delta-$inzsh_spec_delta_calls"
          }
          _inzsh_segment_defaults[DELTA]=0
          typeset -g INZSH_DELTA_RANK=5

          local -a wrong=()

          _inzsh_render
          [[ ${_inzsh_segment_text[DELTA]-} == delta-1 ]] || wrong+=first:${_inzsh_segment_text[DELTA]-unset}
          (( ${_inzsh_left[(Ie)DELTA]} )) || wrong+=not-drawn-first

          typeset -g INZSH_DELTA_RANK=0
          _inzsh_render
          (( inzsh_spec_delta_calls == 1 )) || wrong+=built-while-hidden:$inzsh_spec_delta_calls
          (( ${_inzsh_left[(Ie)DELTA]} == 0 )) || wrong+=drawn-while-hidden

          typeset -g INZSH_DELTA_RANK=5
          _inzsh_render
          (( inzsh_spec_delta_calls == 2 )) || wrong+=not-rebuilt:$inzsh_spec_delta_calls
          [[ ${_inzsh_segment_text[DELTA]-} == delta-2 ]] || wrong+=stale-text:${_inzsh_segment_text[DELTA]-unset}
          (( ${_inzsh_left[(Ie)DELTA]} )) || wrong+=not-drawn-again

          print -r -- "${wrong[*]}"
        '
      }
      When call churn
      The output should eq ''
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  # A property of every render, not only a hidden one — no fixture segment here is ranked zero
  # — so it sits in its own group rather than inside "costs nothing to draw". The rank sort must
  # not pay for a second registry read on a segment it already knows the rank of: each survivor
  # is asked its rank exactly once, by the pass that decides whether it is worth building at
  # all, and never again by the sort that places it afterwards.
  Describe "the rank sort does not re-read a survivor's rank"
    # Asserted as a per-name count rather than against the literal `ALFA BRAVO CHARLIE`, for the
    # same reason the width-filter example above is: a fixture segment added later for an
    # unrelated reason must not break this example on a name it never mentions.
    It "reads a surviving segment's rank exactly once, never again for the sort"
      once() {
        inzsh_spec_shape '
          typeset -ga inzsh_spec_ranked=()
          functions[_inzsh_rank_of_orig]=$functions[_inzsh_rank_of]
          _inzsh_rank_of() { inzsh_spec_ranked+=$1; _inzsh_rank_of_orig "$@" }

          _inzsh_render

          local -A tally
          local name
          for name in "${inzsh_spec_ranked[@]}"; do (( tally[$name]++ )); done

          local -a wrong=()
          for name in ${(ok)_inzsh_segment_defaults}; do
            (( tally[$name] == 1 )) || wrong+="$name=${tally[$name]:-0}"
          done
          print -r -- "${wrong[*]}"
        '
      }
      When call once
      The output should eq ''
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  # The padding is arithmetic over two widths the builder already tracked, and the answer is one
  # column short of the terminal — which is exactly where zsh puts `RPROMPT` itself. A row that
  # fills the last cell is the classic off-by-one that turns two rows into three on a terminal
  # that wraps eagerly, and the row below already keeps the same column back for the cursor.
  #
  # Swept rather than sampled, because it is an arithmetic claim: whatever the terminal is, the
  # segment row ends one column in from the edge.
  Describe 'the padding that puts the right prompt on the segment row'
    Parameters
      60
      72
      80
      100
      160
    End

    It "pads the segment row to one column short of $1"
      padded() {
        inzsh_spec_shape '
          typeset -g COLUMNS=$1
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          inzsh_shape_width "${rows[1]}"
          print -r -- "$REPLY_WIDTH"
        ' "$1"
      }
      When call padded "$1"
      The output should eq "$(( $1 - 1 ))"
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  # The guard under that arithmetic. The padding is the one thing in the prompt that can push a
  # row past the edge of its terminal — it is literal spaces, and a row that overflows does not
  # merely look wrong, it WRAPS, and a wrapped prompt is redrawn as the same ribbon twice. So the
  # rule "left + gap + right fits in cols - 1" is written down as a function rather than left to
  # emerge from a subtraction, and a gap that cannot satisfy it is answered as 0, which the caller
  # already reads as "put the right side in RPROMPT".
  Describe 'the gap the padding is allowed to be'
    Parameters
      #cols left right gap
      80    10   10    59
      80    40   38    1     # the smallest gap that is still drawn
      80    40   39    0     # exactly none left over
      80    50   50    0     # the two sides already overlap
      1     0    0     0     # a terminal with no room for anything
      0     10   10    0     # an unknown width: no arithmetic can right-align against it
      abc   10   10    0     # nor against one that is not a number
      80    ''   10    0     # nor over a width that was never measured
      80    10   x     0
    End

    It "answers $4 for cols=$1 left=$2 right=$3"
      gap() {
        inzsh_spec_shape '
          _inzsh_render_gap "$1" "$2" "$3"
          print -r -- "$REPLY"
        ' "$1" "$2" "$3"
      }
      When call gap "$1" "$2" "$3" "$4"
      The output should eq "$4"
      The stderr should eq ''
    End
  End

  # The other half of the guard, and the half that can actually fire. The gap is arithmetic over
  # two numbers, so `left + gap + right <= cols - 1` is true by construction and a check of it
  # would gate on the arithmetic's own opinion of itself. What can be wrong is the INPUTS, so the
  # row that came out is measured instead — a different question from the one the gap answered.
  Describe 'the row the padding produced'
    Parameters
      #row                cols verdict
      'aaaa'              10   fits
      'aaaaaaaaa'         10   fits    # exactly one column short of the edge
      'aaaaaaaaaa'        10   refused # the last cell, which is the off-by-one that wraps
      'aaaaaaaaaaaa'      10   refused
      '%F{red}aaaa%f'     10   fits    # escapes occupy no cells and must not be counted
      'aaaa'              0    refused # nothing to measure against
      'aaaa'              abc  refused
    End

    It "answers $3 for a row of '$1' at $2 columns"
      fits() {
        inzsh_spec_shape '
          _inzsh_render_row_fits "$1" "$2" && print -r -- fits || print -r -- refused
        ' "$1" "$2"
      }
      When call fits "$1" "$2" "$3"
      The output should eq "$3"
      The stderr should eq ''
    End

    # A guard that cannot answer says no — the rule `lib/core/config.zsh` states for its own
    # guards. A render core sourced without the layout layer has nothing to measure with, and "I
    # could not check" has to read as "do not trust this": refusing to vouch costs a fallback,
    # vouching wrongly costs a wrapped prompt.
    It 'refuses to vouch for a row it has no way to measure'
      unmeasurable() {
        inzsh_spec_shape_alone '
          _inzsh_render_row_fits aaaa 80 && print -r -- vouched || print -r -- refused
        '
      }
      When call unmeasurable
      The output should eq 'refused'
      The stderr should eq ''
    End

    # And what it is for. `_inzsh_render_width` is accumulated as a side effect of assembly, so a
    # block or a separator that stopped being accounted for would leave the gap arithmetic
    # confidently wrong and every check made of the NUMBERS agreeing with it. Here the accounting
    # is silenced outright, which is the extreme of that: both sides come back as 0 wide, the gap
    # comes out as nearly the whole terminal, and only measuring the finished row can tell —
    # `_inzsh_render_row_fits` still catches it even though the arithmetic that proposed the pad
    # cannot, and the row never wraps. `RPROMPT` stays empty regardless: it is not where a row
    # this file could not vouch for goes any more, on this row or any other but the last under
    # `inline`.
    It 'never wraps and never falls back to RPROMPT when the accounting under-reports the row'
      lied() {
        inzsh_spec_shape '
          _inzsh_width_add() { : }
          typeset -g COLUMNS=80
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          inzsh_shape_width "${rows[1]}"
          local -a wrong=()
          (( REPLY_WIDTH < 80 ))    || wrong+=overflowed:$REPLY_WIDTH
          [[ -z $RPROMPT ]]         || wrong+=rprompt-carried-something
          print -r -- "${wrong[*]}"
        '
      }
      When call lied
      The output should eq ''
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  # `v1.3.0 · Prompt rows`. `_inzsh_rows_resolve` (issue #220) decides WHICH segment sits on
  # WHICH row; this group is about what `_inzsh_render` does with that answer — newline count
  # and position, marker placement per `INZSH_MARKER_ROW`, and whether `RPROMPT` carries
  # anything. The row arrays claim ALFA/BRAVO/CHARLIE explicitly rather than leaning on their
  # fixture ranks, which is what lets a row's LEFT and RIGHT be chosen independently of which
  # side each segment would otherwise have derived onto.
  Describe 'multiple resolved rows'
    # `own`: every drawn row gets its right side padded in — including a row that is not the
    # last one, which is the case this fixture is built to exercise — and the marker always
    # gets a bare line below all of them. `RPROMPT` carries nothing at all.
    It 'draws every resolved row on its own line, padded, under own — plus a bare marker line'
      own_rows() {
        inzsh_spec_shape '
          INZSH_ROW1_LEFT=(ALFA) INZSH_ROW1_RIGHT=(CHARLIE) INZSH_ROW2_LEFT=(BRAVO)
          INZSH_MARKER_ROW=own
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          local -a wrong=()
          (( ${#rows} == 3 )) || wrong+=rows:${#rows}
          inzsh_shape_text "${rows[1]}"
          [[ $REPLY == *alfa*charlie* ]]        || wrong+=row1:$REPLY
          inzsh_shape_text "${rows[2]}"
          [[ $REPLY == *bravo* && $REPLY != *charlie* ]] || wrong+=row2:$REPLY
          inzsh_shape_text "${rows[3]}"
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]]     || wrong+=row3:$REPLY
          [[ -z $RPROMPT ]]                              || wrong+=rprompt:$RPROMPT
          print -r -- "${wrong[*]}"
        '
      }
      When call own_rows
      The output should eq ''
      The stderr should eq ''
    End

    # `inline`: the LAST drawn row terminates with the marker instead of taking a row of its
    # own, so the prompt is one line shorter than `own` over the same rows — but every EARLIER
    # row still gets its right side padded in exactly as `own` would, which is the half of the
    # rule that is easy to get wrong by assuming `inline` means "never pad".
    It 'pads every row but the last under inline, and shortens the prompt by the marker row'
      inline_rows() {
        inzsh_spec_shape '
          INZSH_ROW1_LEFT=(ALFA) INZSH_ROW1_RIGHT=(CHARLIE) INZSH_ROW2_LEFT=(BRAVO)
          INZSH_MARKER_ROW=inline
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          local -a wrong=()
          (( ${#rows} == 2 )) || wrong+=rows:${#rows}
          inzsh_shape_text "${rows[1]}"
          [[ $REPLY == *alfa*charlie* ]] || wrong+=row1:$REPLY
          inzsh_shape_text "${rows[2]}"
          [[ $REPLY == *bravo*"${_inzsh_glyph[prompt]} " ]] || wrong+=row2:$REPLY
          [[ -z $RPROMPT ]]                                 || wrong+=rprompt:$RPROMPT
          print -r -- "${wrong[*]}"
        '
      }
      When call inline_rows
      The output should eq ''
      The stderr should eq ''
    End

    # The other half of the same rule: when the LAST drawn row does have a right side, `inline`
    # hands it to a real `RPROMPT` rather than padding it in — the one row `RPROMPT` is ever
    # assigned something on. `test/ui/test_prompt_shape.py` is what settles WHERE zsh actually
    # draws it; this only settles that this file put it there and nowhere else.
    It "puts the last row's right side in RPROMPT under inline, not padded into the row"
      inline_last_right() {
        inzsh_spec_shape '
          INZSH_ROW1_LEFT=(ALFA) INZSH_ROW2_LEFT=(BRAVO) INZSH_ROW2_RIGHT=(CHARLIE)
          INZSH_MARKER_ROW=inline
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          local -a wrong=()
          (( ${#rows} == 2 ))      || wrong+=rows:${#rows}
          inzsh_shape_text "${rows[1]}"
          [[ $REPLY != *charlie* ]] || wrong+=row1-carried-charlie:$REPLY
          inzsh_shape_text "${rows[2]}"
          [[ $REPLY == *bravo* && $REPLY != *charlie* ]] || wrong+=row2:$REPLY
          inzsh_shape_text "$RPROMPT"
          [[ $REPLY == *charlie* ]] || wrong+=rprompt:$REPLY
          print -r -- "${wrong[*]}"
        '
      }
      When call inline_last_right
      The output should eq ''
      The stderr should eq ''
    End

    # A row whose every segment turned out to have no text is not a row at all, at any
    # position — not only the single row the pre-rows renderer ever had to worry about. The
    # gap does not leave a blank line: what was row three renumbers into the second physical
    # line the moment the middle one draws nothing.
    It 'drops a row whose segments have no text, without leaving a blank line behind'
      empty_middle_row() {
        inzsh_spec_shape '
          _inzsh_segment_text=(ALFA alfa CHARLIE charlie)
          INZSH_ROW1_LEFT=(ALFA) INZSH_ROW2_LEFT=(BRAVO) INZSH_ROW3_LEFT=(CHARLIE)
          INZSH_MARKER_ROW=own
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          local -a wrong=()
          (( ${#rows} == 3 )) || wrong+=rows:${#rows}
          inzsh_shape_text "${rows[1]}"
          [[ $REPLY == *alfa* ]] || wrong+=row1:$REPLY
          inzsh_shape_text "${rows[2]}"
          [[ $REPLY == *charlie* ]] || wrong+=row2:$REPLY
          inzsh_shape_text "${rows[3]}"
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] || wrong+=row3:$REPLY
          print -r -- "${wrong[*]}"
        '
      }
      When call empty_middle_row
      The output should eq ''
      The stderr should eq ''
    End

    # A RIGHT-ONLY row — legitimate under "override is per side" (§2.3) — has no left content
    # to pad away from. `_inzsh_render_gap` demands a gap of at least one column because with
    # content on BOTH sides a gap of zero would run them together; with nothing on the left
    # there is no collision to avoid, and the width below (11, with `charlie` filling all but
    # one column) is exactly the case where the gap comes out to precisely zero rather than
    # negative — the one width previously joined as an EMPTY STRING instead of the row's own
    # content, leaving a blank physical line.
    #
    # `${(f)PROMPT}` is deliberately NOT used to count rows here: zsh drops an empty field from
    # a `(f)` split, so a genuine `$'\n\n'` in the raw string reads back as one fewer line than
    # it draws — which is exactly how this bug passed the newline-count style of every other
    # example in this file. Newline BYTES in the raw string are counted instead.
    It "draws a right-only row bare rather than as a blank line, at the width its gap is exactly zero"
      right_only_row() {
        inzsh_spec_shape '
          typeset -g COLUMNS=11
          INZSH_ROW1_LEFT=(ALFA) INZSH_ROW2_RIGHT=(CHARLIE)
          INZSH_MARKER_ROW=own
          _inzsh_render
          local -a wrong=()
          [[ $PROMPT == *$'"'"'\n'"'"'$'"'"'\n'"'"'* ]] && wrong+=blank-line-present
          [[ $PROMPT == *charlie* ]]                    || wrong+=charlie-missing
          print -r -- "${wrong[*]}"
        '
      }
      When call right_only_row
      The output should eq ''
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  Describe 'INZSH_MARKER_ROW=inline'
    It 'puts the whole prompt back on one row'
      one_line() {
        inzsh_spec_shape '
          INZSH_MARKER_ROW=inline
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          inzsh_shape_text "$RPROMPT"
          local -a wrong=()
          (( ${#rows} == 1 ))    || wrong+=rows:${#rows}
          [[ $PROMPT == *" " ]]  || wrong+=no-trailing-space
          [[ $REPLY == *charlie* ]] || wrong+=right-side-lost
          print -r -- "${wrong[*]}"
        '
      }
      When call one_line
      The output should eq ''
      The stderr should eq ''
    End

    # A prompt may never come back empty, under either marker setting — with nothing drawn at
    # all, the marker itself is the whole prompt. This used to fall back to zsh's own `%#`
    # instead: that was a property of the old one-row shape never drawing this theme's own marker
    # at all when there was content on the row, and inline is no longer that shape — it draws the
    # same marker `own` does, just on the row rather than below it, and a row with nothing on it
    # is exactly the case with nothing to append it to.
    It 'still falls back to the marker alone on one row when there is nothing to draw'
      one_line_bare() {
        inzsh_spec_shape '
          INZSH_MARKER_ROW=inline
          _inzsh_segment_text=()
          _inzsh_render
          inzsh_shape_text "$PROMPT"
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] && print -r -- exact ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call one_line_bare
      The output should eq 'exact'
      The stderr should eq ''
    End

    # Read at render time, like every knob in this tree: no re-source, no new shell.
    It 'takes effect at the next draw rather than at the next login'
      live() {
        inzsh_spec_shape '
          _inzsh_render
          local -a before=("${(f)PROMPT}")
          INZSH_MARKER_ROW=inline
          _inzsh_render
          local -a after=("${(f)PROMPT}")
          print -r -- "${#before} then ${#after}"
        '
      }
      When call live
      The output should eq '2 then 1'
      The stderr should eq ''
    End
  End

  # `v2.0.0` retired `INZSH_PROMPT_LINES` outright — see `.claude/docs/DESIGN-prompt-rows.md`
  # §3.1. It is no longer registered, no longer read, and no longer resolved through at any
  # precedence, so every value below — the two that used to be valid and every typo of them —
  # is now equally inert: the prompt draws the plain default, `own`, two rows, whatever a stale
  # `.zshrc` still says. That is the whole of the promise: no error, no blank prompt, no third
  # row, not even a different one from before.
  Describe 'a stale INZSH_PROMPT_LINES'
    Parameters
      '1'
      '2'
      '3'
      '0'
      '-1'
      'two'
      'one'
      '1 '
      ' 1'
      'true'
      ''
    End

    It "is ignored entirely for '$1'"
      stale() {
        inzsh_spec_shape '
          INZSH_PROMPT_LINES=$1
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          print -r -- "rows=${#rows} resolved=$_inzsh_prompt_lines_resolved"
        ' "$1"
      }
      When call stale "$1"
      The output should eq 'rows=2 resolved=2'
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  Describe 'the marker'
    It 'takes its mark from the token layer and carries no literal of its own'
      from_the_table() {
        inzsh_spec_shape '
          _inzsh_render_marker
          inzsh_shape_text "$REPLY"
          [[ $REPLY == ${_inzsh_glyph[prompt]} ]] && print -r -- from-the-table ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call from_the_table
      The output should eq 'from-the-table'
      The stderr should eq ''
    End

    # The failure this repo has already paid for three times is a mark that cannot be drawn
    # outside a multibyte locale. The marker is the line the user types on, which is the worst
    # possible place for one.
    It 'degrades to a single ASCII column where the locale cannot carry the glyph'
      degraded() {
        inzsh_spec_shape '
          typeset -g _inzsh_multibyte=0
          _inzsh_glyphs_resolve
          _inzsh_render_marker
          inzsh_shape_text "$REPLY"
          local mark=$REPLY
          local -a wrong=()
          [[ $mark == ${_inzsh_glyph_ascii[prompt]} ]] || wrong+=not-the-fallback:$mark
          (( ${#mark} == 1 ))                          || wrong+=width:${#mark}
          print -r -- "${wrong[*]}"
        '
      }
      When call degraded
      The output should eq ''
      The stderr should eq ''
    End

    It 'is replaced verbatim by INZSH_PROMPT_MARKER'
      replaced() {
        inzsh_spec_shape '
          INZSH_PROMPT_MARKER="=>"
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          inzsh_shape_text "${rows[2]}"
          print -r -- "<$REPLY>"
        '
      }
      When call replaced
      The output should eq '<=> >'
      The stderr should eq ''
    End

    # Set but empty is unset, at every level — an `INZSH_PROMPT_MARKER=` left behind in a zshrc
    # must fall through to the theme's own rather than blank the line you type on.
    It 'treats a set-but-empty INZSH_PROMPT_MARKER as unset'
      empty_override() {
        inzsh_spec_shape '
          INZSH_PROMPT_MARKER=
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          inzsh_shape_text "${rows[2]}"
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] && print -r -- fell-through ||
            print -r -- "blanked=<$REPLY>"
        '
      }
      When call empty_override
      The output should eq 'fell-through'
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  Describe 'what the marker says about the last command'
    # The marker repeats the last status in COLOUR and changes nothing else. The glyph half of
    # that signal is `lib/segments/retval.zsh`, one row up, which already draws `✕ 1`; a second
    # copy beside the cursor would be the same fact twice in a prompt whose point is calm.
    It 'takes the accent role after a command that succeeded'
      clean() {
        inzsh_spec_shape '
          typeset -g _inzsh_last_status=0
          _inzsh_render_marker
          [[ $REPLY == "%F{${_inzsh_role[accent]}}"* ]] && print -r -- accent ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call clean
      The output should eq 'accent'
      The stderr should eq ''
    End

    It 'takes the negative role after a command that failed'
      failed() {
        inzsh_spec_shape '
          typeset -g _inzsh_last_status=1
          _inzsh_render_marker
          [[ $REPLY == "%F{${_inzsh_role[negative]}}"* ]] && print -r -- negative ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call failed
      The output should eq 'negative'
      The stderr should eq ''
    End

    # Read from the capture in `lib/core/hooks.zsh`, never from `$?`. By the time a marker is
    # drawn, `$?` is the status of whatever the render path did last, which is always 0 and
    # always a lie — so a command that SUCCEEDED immediately before the call must not be able to
    # talk the marker out of the failure the capture is holding.
    It 'reads the capture rather than $? — a successful call in between changes nothing'
      capture() {
        inzsh_spec_shape '
          typeset -g _inzsh_last_status=1
          true
          _inzsh_render_marker
          [[ $REPLY == "%F{${_inzsh_role[negative]}}"* ]] && print -r -- negative ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call capture
      The output should eq 'negative'
      The stderr should eq ''
    End

    # It says WHETHER, never WHAT. The number is the retval block's business, one row up, and
    # the mark itself does not move either — a marker that changed shape would be a second
    # vocabulary for a state the theme already has marks for.
    It 'never draws the status itself, however the command failed'
      no_number() {
        inzsh_spec_shape '
          typeset -g _inzsh_last_status=127
          _inzsh_render
          local -a rows=("${(f)PROMPT}")
          inzsh_shape_text "${rows[2]}"
          local -a wrong=()
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] || wrong+=text:$REPLY
          [[ $REPLY != *[0-9]* ]]                    || wrong+=carries-a-number
          print -r -- "${wrong[*]}"
        '
      }
      When call no_number
      The output should eq ''
      The stderr should eq ''
    End

    # An unresolved role must never reach the prompt as `%F{}` — that is a broken escape zsh
    # prints verbatim, and it is exactly what a bundle loaded without the token layer produces.
    # No role, no colour, same mark.
    It 'draws the mark uncoloured rather than broken when no role table is loaded'
      roleless() {
        inzsh_spec_shape '
          typeset -gA _inzsh_role
          _inzsh_role=()
          _inzsh_render_marker
          [[ $REPLY == ${_inzsh_glyph[prompt]} ]] && print -r -- plain ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call roleless
      The output should eq 'plain'
      The stderr should eq ''
    End
  End

  # A capture that is missing or unreadable reads as success. A marker must not claim a failure
  # it cannot see, and `_inzsh_last_status` is a number the hook layer owns — anything else in
  # it means the hook layer is not there to be read.
  Describe 'a capture the marker cannot read'
    Parameters
      'oops'
      '-1'
      '1.5'
      ''
    End

    It "reads a captured status of '$1' as success"
      unreadable() {
        inzsh_spec_shape '
          typeset -g _inzsh_last_status=$1
          _inzsh_render_marker
          [[ $REPLY == "%F{${_inzsh_role[accent]}}"* ]] && print -r -- accent ||
            print -r -- "got=<$REPLY>"
        ' "$1"
      }
      When call unreadable "$1"
      The output should eq 'accent'
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  Describe 'a render core sourced on its own'
    # `lib/core/render.zsh` is independently sourceable, and the shape has to degrade the way
    # the separators already do: no config layer means the registered default, and no token
    # layer means the ASCII stand-in. A prompt with a plain marker beats a prompt with none.
    It 'resolves to two rows with no config layer in the shell'
      alone_lines() {
        inzsh_spec_shape_alone '
          _inzsh_render_lines
          print -r -- "$_inzsh_prompt_lines_resolved"
        '
      }
      When call alone_lines
      The output should eq '2'
      The stderr should eq ''
    End

    It 'draws the ASCII marker with no token layer in the shell'
      alone_marker() {
        inzsh_spec_shape_alone '
          _inzsh_render_marker
          [[ $REPLY == $_inzsh_render_marker_ascii ]] && print -r -- ascii ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call alone_marker
      The output should eq 'ascii'
      The stderr should eq ''
    End
  End
End
