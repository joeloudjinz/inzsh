# The token layer comes first because the truncation marker comes out of its glyph table, exactly
# as the entry point loads them. What this file does WITHOUT one — degrade to ASCII rather than
# truncate with nothing — is a separator-and-glyph claim and lives in
# `test/render/separators_spec.sh`.
Include lib/core/tokens.zsh
Include lib/core/layout.zsh

# Layout — width accounting, hiding and truncation. Three mechanisms, one file, and the point of
# most of what follows is that they stay three: MINCOLS hides, truncation shortens, rank orders,
# and no example below is allowed to pass because one of them quietly did another's job.
#
# Nothing here loads the token layer, so no colour value appears at any point. The colour escapes
# in the width table are NAMED colours only — they exist to be thrown away by the measurement,
# and what they name never reaches an expectation.
#
# `${(m)#…}` counts BYTES rather than cells outside a multibyte locale, so every expectation
# about a non-ASCII glyph is also an expectation about the locale. CI pins `LC_ALL=C.UTF-8`; a
# developer running under `LC_ALL=C` skips those rather than watching them fail for a reason that
# is not the code's.
inzsh_spec_bytes_not_cells() {
  local sample=$'é'
  (( ${#sample} != 1 ))
}

# The fragments the width table measures, held by name so that a `Parameters` line never has to
# carry an escape through the spec parser. Every one of them is three visible columns unless the
# table says otherwise — same text, wrapped in a different way of saying nothing.
typeset -gA inzsh_spec_fragments=(
  plain          'abc'
  foreground     '%F{red}abc%f'
  bold           '%F{red}%Babc%b%f'
  both_channels  '%K{cyan}%F{black}abc%f%k'
  underline      '%Uabc%u'
  standout       '%Sabc%s'
  ansi           $'\e[31mabc\e[0m'
  ansi_extended  $'\e[1;38;5;196mabc\e[0m'
  ansi_only      $'\e[0m'
  literal_block  $'%{\e[38;5;1m%}abc'
  wrapped        $'%{\e[1m%}%F{red}abc%f%{\e[0m%}'
  padded         '%K{blue} abc %k'
  braces_in_text '%F{red}a{b}c%f'
  percent        '%%'
  percent_mid    'a%%b'
  percent_switch '%%b'
  empty          ''
  bare_percent   '%'
  open_colour    '%F{'
  open_block     '%{unterminated'
  bare_escape    $'\e'
)

# The theme's glyph vocabulary, the same way. Every one of them is one column wide, which is the
# assumption the whole layout rests on: a separator that measured two would put every prompt one
# column over its budget.
typeset -gA inzsh_spec_glyphs=(
  powerline_right $''
  powerline_left  $''
  powerline_thin  $''
  positive        '✓'
  negative        '✕'
  caution         '!'
  info            'i'
  neutral         '·'
  absent          '—'
  ellipsis        '…'
)

inzsh_spec_width() {
  _inzsh_width "$1"
  print -r -- "$REPLY"
}

Describe 'visible width'
  Describe 'a rendered fragment'
    # $1 names a fragment, $2 the columns it occupies. `abc` is three columns however it was
    # dressed — that is the whole claim, and the reason the escapes vary and the text does not.
    Parameters
      plain          3
      foreground     3
      bold           3
      both_channels  3
      underline      3
      standout       3
      ansi           3
      ansi_extended  3
      ansi_only      0
      literal_block  3
      wrapped        3
      padded         5
      braces_in_text 5
      empty          0
    End

    It "measures $1 at $2 columns"
      When call inzsh_spec_width "${inzsh_spec_fragments[$1]}"
      The output should eq "$2"
    End
  End

  Describe 'the literal per cent'
    # `%%` draws one per cent sign. It has to be taken out of the way before anything else is
    # stripped, or `%%b` reads as a literal per cent followed by a bold switch and measures one.
    Parameters
      percent        1
      percent_mid    3
      percent_switch 2
    End

    It "measures $1 at $2 columns"
      When call inzsh_spec_width "${inzsh_spec_fragments[$1]}"
      The output should eq "$2"
    End
  End

  Describe 'hostile input'
    # None of these is a prompt anyone meant to write. What matters is that each one measures
    # something finite and small: an unterminated escape leaves its text visible rather than
    # swallowing the rest of the line, which is the direction that keeps a broken segment
    # visibly broken instead of invisibly wrong.
    Parameters
      bare_percent  1
      open_colour   3
      open_block    14
      bare_escape   1
    End

    It "measures $1 at $2 columns"
      When call inzsh_spec_width "${inzsh_spec_fragments[$1]}"
      The output should eq "$2"
    End
  End

  It 'measures a missing argument as nothing'
    nothing() {
      _inzsh_width
      print -r -- "$REPLY"
    }
    When call nothing
    The output should eq '0'
  End

  Describe 'the glyph vocabulary'
    Parameters
      powerline_right
      powerline_left
      powerline_thin
      positive
      negative
      caution
      info
      neutral
      absent
      ellipsis
    End

    It "counts $1 as one column"
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      When call inzsh_spec_width "${inzsh_spec_glyphs[$1]}"
      The output should eq '1'
    End
  End

  Describe 'multibyte text'
    It 'counts a double-width character as two columns'
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      When call inzsh_spec_width '日本'
      The output should eq '4'
    End

    It 'counts an accented character as one column, coloured or not'
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      accented() {
        local -a widths=()
        _inzsh_width 'café'; widths+=$REPLY
        _inzsh_width '%F{red}café%f'; widths+=$REPLY
        print -r -- "${widths[*]}"
      }
      When call accented
      The output should eq '4 4'
    End
  End

  Describe 'cost'
    # Width is measured on the render path, once per piece of every segment. A fork here would
    # be paid on every prompt, so the file may not contain one.
    It 'measures without a subprocess anywhere in the layout'
      substitutions() {
        setopt local_options extended_glob
        local line; local -a bad=()
        while IFS= read -r line; do
          [[ $line == [[:space:]]#\#* ]] && continue
          [[ $line == *'$('* || $line == *'`'* ]] && bad+="$line"
        done < "$SHELLSPEC_PROJECT_ROOT/lib/core/layout.zsh"
        print -r -- "${#bad}"
      }
      When call substitutions
      The output should eq '0'
    End
  End
End

Describe 'the width accumulator'
  It 'tracks a total as the pieces of a line go on'
    # The reason the accumulator exists: the width of the finished string cannot be recovered
    # from the finished string by anything cheaper than measuring it again. Both numbers are
    # printed so a drifting accumulator cannot hide behind a correct re-measurement.
    build() {
      local -i used=0
      local piece rendered=''
      for piece in '%F{red}abc%f' ' ' '%K{blue}12%k'; do
        rendered+=$piece
        _inzsh_width "$piece"
        _inzsh_width_add used "$REPLY"
      done
      _inzsh_width "$rendered"
      print -r -- "$used $REPLY"
    }
    When call build
    The output should eq '6 6'
  End

  It 'keeps two accumulators apart'
    two() {
      local -i body=0 separators=0
      _inzsh_width_add body 4
      _inzsh_width_add separators 1
      _inzsh_width_add body 6
      _inzsh_width_add separators 1
      print -r -- "$body $separators"
    }
    When call two
    The output should eq '10 2'
  End

  It 'starts an accumulator that does not exist yet at zero'
    fresh() {
      _inzsh_width_add inzsh_spec_fresh_total 7
      print -r -- "$inzsh_spec_fresh_total"
    }
    When call fresh
    The output should eq '7'
  End

  It 'reads an accumulator holding something unparseable as zero'
    # `2+` and `1 2` are the ones that matter: zsh reads a bare word in an arithmetic expression
    # as zero and would carry on, but an unfinished expression is a fatal math error, and a
    # builder must not be able to abort a render by having put a string where a width goes.
    poisoned() {
      local candidate; local -a wrong=()
      for candidate in banana 2.5 -3 '1 2' '2+' '' ' ' 0x; do
        local total=$candidate
        _inzsh_width_add total 5
        (( total == 5 )) || wrong+="${candidate:-empty}:$total"
      done
      print -r -- "${wrong[*]}"
    }
    When call poisoned
    The output should eq ''
  End

  It 'adds nothing for a width that is not a non-negative integer'
    # A piece that could not be measured must not move the total. Adding a wrong number is
    # worse than adding none: the layout would hide a segment that would have fitted.
    unparseable() {
      local -i total=0
      local candidate; local -a moved=()
      for candidate in -1 x 2.5 '' ' ' +3 1e3 0x10 '3 4'; do
        total=0
        _inzsh_width_add total "$candidate"
        (( total == 0 )) || moved+=${candidate:-empty}
      done
      print -r -- "${moved[*]}"
    }
    When call unparseable
    The output should eq ''
  End

  It 'refuses a name that cannot be a variable, and touches nothing'
    refused() {
      local candidate; local -a accepted=()
      for candidate in '' ' ' 1total 'a b' 'x;y' 'a-b' 'a.b'; do
        _inzsh_width_add "$candidate" 5 && accepted+=${candidate:-empty}
      done
      print -r -- "${accepted[*]}"
    }
    When call refused
    The output should eq ''
  End

  It 'accepts a name that can be a variable'
    accepted() {
      local candidate; local -a refused=()
      for candidate in total _total t1 T_1 _; do
        _inzsh_width_add "$candidate" 1 || refused+=$candidate
      done
      print -r -- "${refused[*]}"
    }
    When call accepted
    The output should eq ''
  End
End

# ------------------------------------------------------------------------------------------
# MINCOLS. Rank says where a segment sits; MINCOLS says how much room the terminal must have
# before it is worth drawing at all. The two are independent, and the examples that matter most
# in this block are the ones that would fail if they were not.

inzsh_spec_mincols() {
  local INZSH_DIR_MINCOLS=$1
  _inzsh_mincols_of DIR
  print -r -- "$REPLY"
}

inzsh_spec_filter() {
  local INZSH_DIR_MINCOLS=0 INZSH_GIT_MINCOLS=80 INZSH_VENV_MINCOLS=100
  local INZSH_STATUS_MINCOLS=0 INZSH_CLOCK_MINCOLS=60 INZSH_SALAH_MINCOLS=120
  _inzsh_layout_filter "$1" DIR GIT VENV STATUS CLOCK SALAH
  print -r -- "${reply[*]}"
}

Describe 'MINCOLS'
  Describe 'reading the knob'
    # $1 what the config holds, $2 what it resolves to. Zero means "never hide on width", which
    # is also where everything unreadable lands: a typo shows a segment that should have hidden,
    # and that is the survivable direction.
    #
    # `+80` is 80, not a typo. `INZSH_*_MINCOLS` is registered as `int:0:` in the config layer
    # and there is one integer grammar in the theme — the same one `_inzsh_rank_of` normalises
    # `+3` under. A leading `+` that meant one thing here and another there is exactly the
    # disagreement the registry exists to remove.
    Parameters
      80    80
      0     0
      1     1
      999   999
      007   7
      ''    0
      -5    0
      2.5   0
      ' 80' 0
      '80 ' 0
      80x   0
      +80   80
      abc   0
      1e3   0
    End

    It "resolves a configured '$1' to $2"
      When call inzsh_spec_mincols "$1"
      The output should eq "$2"
    End
  End

  It 'resolves an unset knob to zero'
    unconfigured() {
      unset INZSH_DIR_MINCOLS
      _inzsh_mincols_of DIR
      print -r -- "$REPLY"
    }
    When call unconfigured
    The output should eq '0'
  End

  Describe 'the segment name'
    # The knob is `INZSH_<SEG>_MINCOLS`, so the name is upper-cased before it is used and
    # anything that cannot spell a variable has no knob at all rather than an error.
    Parameters
      DIR 80
      dir 80
      Dir 80
      'GIT-ASYNC' 0
      '' 0
      'A B' 0
      'a;b' 0
      'a.b' 0
    End

    It "reads '$1' as $2"
      named() {
        local INZSH_DIR_MINCOLS=80
        _inzsh_mincols_of "$1"
        print -r -- "$REPLY"
      }
      When call named "$1"
      The output should eq "$2"
    End
  End

  Describe 'filtering a row'
    # One configuration, read at every width. VENV and SALAH are the expensive ones and they sit
    # in the middle and at the end; DIR and STATUS never hide.
    Parameters
      200 'DIR GIT VENV STATUS CLOCK SALAH'
      120 'DIR GIT VENV STATUS CLOCK SALAH'
      119 'DIR GIT VENV STATUS CLOCK'
      100 'DIR GIT VENV STATUS CLOCK'
      99  'DIR GIT STATUS CLOCK'
      80  'DIR GIT STATUS CLOCK'
      79  'DIR STATUS CLOCK'
      60  'DIR STATUS CLOCK'
      59  'DIR STATUS'
      1   'DIR STATUS'
      0   'DIR STATUS'
    End

    It "keeps ($2) at $1 columns"
      When call inzsh_spec_filter "$1"
      The output should eq "$2"
    End
  End

  Describe 'the shape of the answer'
    It 'hands the survivors back in reply, as an array'
      kind() {
        _inzsh_layout_filter 80 DIR GIT
        print -r -- "${(t)reply} ${#reply}"
      }
      When call kind
      The output should eq 'array 2'
    End

    It 'filters nothing out of nothing'
      none() {
        _inzsh_layout_filter 80
        print -r -- "${#reply}"
      }
      When call none
      The output should eq '0'
    End
  End

  Describe 'an unknown width hides nothing'
    # A width that is not a number is a bug somewhere else, and the answer to a bug somewhere
    # else is to draw everything: a wrapped prompt is recoverable, an empty one looks broken.
    Parameters
      ''
      ' '
      x
      -1
      2.5
      ' 80'
    End

    It "keeps every segment at a width of '$1'"
      unknown() {
        local INZSH_GIT_MINCOLS=999 INZSH_SALAH_MINCOLS=999
        _inzsh_layout_filter "$1" DIR GIT SALAH
        print -r -- "${reply[*]}"
      }
      When call unknown "$1"
      The output should eq 'DIR GIT SALAH'
    End
  End

  Describe 'independence from rank'
    # The one that has to hold. MINCOLS is priority, rank is position, and the segment nearest
    # the edge is not necessarily the first to drop — here the FIRST segment in the row is the
    # one that goes, and the survivors come back in whatever order they were given.
    It 'drops the segment with the highest MINCOLS wherever it sits'
      positional() {
        local INZSH_ALPHA_MINCOLS=120 INZSH_BETA_MINCOLS=60 INZSH_OMEGA_MINCOLS=0
        local -a seen=()
        _inzsh_layout_filter 100 ALPHA BETA OMEGA; seen+="[${reply[*]}]"
        _inzsh_layout_filter 100 OMEGA BETA ALPHA; seen+="[${reply[*]}]"
        _inzsh_layout_filter 50 ALPHA BETA OMEGA; seen+="[${reply[*]}]"
        print -r -- "${seen[*]}"
      }
      When call positional
      The output should eq '[BETA OMEGA] [OMEGA BETA] [OMEGA]'
    End

    It 'never reorders what it keeps'
      order() {
        local INZSH_A_MINCOLS=0 INZSH_B_MINCOLS=90 INZSH_C_MINCOLS=0 INZSH_D_MINCOLS=90
        local -a seen=()
        _inzsh_layout_filter 100 D C B A; seen+="[${reply[*]}]"
        _inzsh_layout_filter 80 D C B A; seen+="[${reply[*]}]"
        print -r -- "${seen[*]}"
      }
      When call order
      The output should eq '[D C B A] [C A]'
    End
  End
End

# ------------------------------------------------------------------------------------------
# The ladder. 120 / 80 / 60 are placeholders due for tuning at the M3 gate, so the examples that
# pin them are separated from the examples that pin the RULE — the rule survives a re-tune, the
# numbers are expected to move, and they may only move through config.

inzsh_spec_ladder() {
  _inzsh_layout_ladder "$1"
  print -r -- "$REPLY"
}

Describe 'the degradation ladder'
  Describe 'the steps themselves'
    It 'names four steps, widest first, with a breakpoint for all but the floor'
      shape() {
        print -r -- "${_inzsh_ladder_steps[*]} / ${#_inzsh_ladder_defaults}"
      }
      When call shape
      The output should eq 'full wide narrow minimal / 3'
    End

    It 'ships the roadmap placeholders as its defaults'
      defaults() {
        unset -m 'INZSH_LADDER_*'
        _inzsh_ladder_resolve
        print -r -- "${_inzsh_ladder_bounds[*]}"
      }
      When call defaults
      The output should eq '120 80 60'
    End
  End

  Describe 'the default breakpoints'
    # Both sides of every boundary, so an off-by-one in either direction is a failure and not a
    # rounding opinion.
    Parameters
      1000 full
      121  full
      120  full
      119  wide
      81   wide
      80   wide
      79   narrow
      61   narrow
      60   narrow
      59   minimal
      1    minimal
      0    minimal
    End

    It "puts $1 columns on the $2 step"
      When call inzsh_spec_ladder "$1"
      The output should eq "$2"
    End
  End

  Describe 'an unknown width'
    Parameters
      ''
      ' '
      x
      -1
      2.5
      ' 80'
    End

    It "answers with the widest step for a width of '$1'"
      When call inzsh_spec_ladder "$1"
      The output should eq 'full'
    End
  End

  Describe 'tuning through config'
    It 'moves every breakpoint'
      tuned() {
        local INZSH_LADDER_FULL_COLS=200 INZSH_LADDER_WIDE_COLS=150
        local INZSH_LADDER_NARROW_COLS=100
        local -a seen=()
        local cols
        for cols in 250 200 199 150 149 100 99; do
          _inzsh_layout_ladder $cols
          seen+=$REPLY
        done
        print -r -- "${seen[*]}"
      }
      When call tuned
      The output should eq 'full full wide wide narrow narrow minimal'
    End

    It 'reads the config afresh on every call'
      # A breakpoint is config, not a decision taken at source time. Re-tuning must not need a
      # new shell.
      live() {
        local INZSH_LADDER_FULL_COLS=
        local -a seen=()
        _inzsh_layout_ladder 130; seen+=$REPLY
        INZSH_LADDER_FULL_COLS=140
        _inzsh_layout_ladder 130; seen+=$REPLY
        INZSH_LADDER_FULL_COLS=120
        _inzsh_layout_ladder 130; seen+=$REPLY
        print -r -- "${seen[*]}"
      }
      When call live
      The output should eq 'full wide full'
    End

    It 'lets two steps share a breakpoint, leaving one of them unreachable'
      collapsed() {
        local INZSH_LADDER_FULL_COLS=100 INZSH_LADDER_WIDE_COLS=100
        local INZSH_LADDER_NARROW_COLS=50
        local -a seen=()
        local cols
        for cols in 100 99 50 49; do
          _inzsh_layout_ladder $cols
          seen+=$REPLY
        done
        print -r -- "${seen[*]}"
      }
      When call collapsed
      The output should eq 'full narrow narrow minimal'
    End

    It 'falls back per knob for a breakpoint that is not a non-negative integer'
      # The valid neighbour is kept; only the unreadable one reverts. 200 is nothing like the
      # default, so a wholesale revert would show up here.
      partial() {
        local INZSH_LADDER_FULL_COLS=200 INZSH_LADDER_WIDE_COLS=banana
        local INZSH_LADDER_NARROW_COLS=-4
        _inzsh_ladder_resolve
        print -r -- "${_inzsh_ladder_bounds[*]}"
      }
      When call partial
      The output should eq '200 80 60'
    End

    It 'reverts the whole ladder when the breakpoints are out of order'
      # A `wide` above `full` is not a narrower prompt, it is a step nothing can reach. Repairing
      # one number would be guessing which of the three was meant; reverting is a behaviour the
      # user can recognise, and the shipped ladder is a working one.
      inverted() {
        local candidate; local -a bad=()
        local INZSH_LADDER_FULL_COLS INZSH_LADDER_WIDE_COLS INZSH_LADDER_NARROW_COLS
        for candidate in '50 90 10' '120 40 60' '10 20 30' '0 0 1'; do
          INZSH_LADDER_FULL_COLS=${${=candidate}[1]}
          INZSH_LADDER_WIDE_COLS=${${=candidate}[2]}
          INZSH_LADDER_NARROW_COLS=${${=candidate}[3]}
          _inzsh_ladder_resolve
          [[ ${_inzsh_ladder_bounds[*]} == '120 80 60' ]] || bad+=$candidate
        done
        print -r -- "${bad[*]}"
      }
      When call inverted
      The output should eq ''
    End

    It 'never answers with anything that is not one of its own steps'
      vocabulary() {
        local INZSH_LADDER_FULL_COLS INZSH_LADDER_WIDE_COLS INZSH_LADDER_NARROW_COLS
        local candidate; local -i cols; local -a bad=()
        for candidate in '120 80 60' '200 150 100' '0 0 0' '5 4 3' 'x y z'; do
          INZSH_LADDER_FULL_COLS=${${=candidate}[1]}
          INZSH_LADDER_WIDE_COLS=${${=candidate}[2]}
          INZSH_LADDER_NARROW_COLS=${${=candidate}[3]}
          for (( cols = 0; cols <= 200; cols++ )); do
            _inzsh_layout_ladder $cols
            (( ${_inzsh_ladder_steps[(Ie)$REPLY]} )) || bad+="$candidate:$cols:$REPLY"
          done
        done
        print -r -- "${bad[*]}"
      }
      When call vocabulary
      The output should eq ''
    End

    It 'never widens the step as the terminal narrows'
      monotone() {
        local INZSH_LADDER_FULL_COLS INZSH_LADDER_WIDE_COLS INZSH_LADDER_NARROW_COLS
        local candidate; local -i cols index previous; local -a bad=()
        for candidate in '120 80 60' '200 150 100' '100 100 50'; do
          INZSH_LADDER_FULL_COLS=${${=candidate}[1]}
          INZSH_LADDER_WIDE_COLS=${${=candidate}[2]}
          INZSH_LADDER_NARROW_COLS=${${=candidate}[3]}
          previous=0
          for (( cols = 200; cols >= 0; cols-- )); do
            _inzsh_layout_ladder $cols
            index=${_inzsh_ladder_steps[(Ie)$REPLY]}
            (( index >= previous )) || bad+="$candidate:$cols"
            (( previous = index ))
          done
        done
        print -r -- "${bad[*]}"
      }
      When call monotone
      The output should eq ''
    End
  End
End

# ------------------------------------------------------------------------------------------
# The invariant the whole file exists for: at every step of the ladder the prompt occupies
# EXACTLY ONE ROW. There are no segments yet, so the row cannot be assembled — but the
# arithmetic under it can, and it is the arithmetic that decides. A row of survivors whose
# widths plus separators exceed the terminal is a second row, whatever draws it.

# One modelled row. Rank order and priority order deliberately disagree: the widest segment sits
# in the middle, the first to drop sits at the end but one, and the segment that never hides is
# not the first in the row. Nothing here may be inferred from position.
typeset -ga inzsh_spec_row_names inzsh_spec_row_widths inzsh_spec_row_ranks
inzsh_spec_row_names=(DIR STATUS GIT CLOCK VENV SALAH)
inzsh_spec_row_widths=(14 5 12 7 9 17)
# 1 is kept longest. DIR outranks everything, SALAH goes first, and neither is where a
# positional rule would put it.
inzsh_spec_row_ranks=(1 4 2 3 6 5)

# Set an `INZSH_<SEG>_MINCOLS` for every modelled segment: the width at which that segment and
# everything more important than it fit together, separators included. This is how a real
# configuration is meant to be derived, and it is what makes the sweep below a claim about
# `_inzsh_layout_total` and `_inzsh_layout_filter` agreeing rather than about either alone.
inzsh_spec_derive_mincols() {
  local -i sep=$1 i j
  local -a widths=()
  for (( i = 1; i <= ${#inzsh_spec_row_names}; i++ )); do
    widths=()
    for (( j = 1; j <= ${#inzsh_spec_row_names}; j++ )); do
      (( inzsh_spec_row_ranks[j] <= inzsh_spec_row_ranks[i] )) &&
        widths+=${inzsh_spec_row_widths[j]}
    done
    _inzsh_layout_total $sep "${widths[@]}"
    typeset -g INZSH_${inzsh_spec_row_names[i]}_MINCOLS=$REPLY
  done
}

inzsh_spec_total() {
  _inzsh_layout_total "$1" ${=2}
  print -r -- "$REPLY"
}

Describe 'the one-row invariant'
  Describe 'what a row costs'
    # $1 the width of one boundary, $2 the segment widths, $3 the columns the row needs. A row
    # of n blocks has n-1 boundaries; a cap glyph at either end is drawn once whatever n is, so
    # it is the caller's arithmetic and not this function's.
    Parameters
      0 '3 4 5' 12
      1 '3 4 5' 14
      2 '3 4 5' 16
      2 '10'    10
      2 ''      0
      2 '0 0'   2
      2 '3 x 5' 12
      x '3 4'   7
      -1 '3 4'  7
      2 '3 -4 5' 12
    End

    It "needs $3 columns for ($2) with a boundary of $1"
      When call inzsh_spec_total "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe 'whether it fits'
    # $1 the terminal, $2 the boundary, $3 the widths, $4 the verdict.
    Parameters
      20 2 '3 4 5' fits
      16 2 '3 4 5' fits
      15 2 '3 4 5' overflows
      0  2 ''      fits
      0  2 '1'     overflows
      '' 2 '3 4 5' fits
      x  2 '3 4 5' fits
    End

    It "$4 at $1 columns with ($3) and a boundary of $2"
      verdict() {
        local answer=overflows
        _inzsh_layout_fits "$1" "$2" ${=3} && answer=fits
        print -r -- "$answer"
      }
      When call verdict "$1" "$2" "$3"
      The output should eq "$4"
    End
  End

  Describe 'what the predicate leaves behind'
    It 'reports the total it measured either way'
      measured() {
        local -a seen=()
        _inzsh_layout_fits 100 2 3 4 5; seen+=$REPLY
        _inzsh_layout_fits 1 2 3 4 5; seen+=$REPLY
        print -r -- "${seen[*]}"
      }
      When call measured
      The output should eq '16 16'
    End
  End

  Describe 'the sweep'
    # Every terminal width from 0 to 200, with the boundary cost varied, against a MINCOLS
    # configuration derived from the modelled widths. What is proved: the set that survives at a
    # width always fits in that width. What is also proved, by the counts printed alongside, is
    # that it does not fit by hiding everything — the survivor count only ever grows as the
    # terminal does, and at the widest the whole row is drawn.
    Parameters
      0
      1
      3
    End

    It "keeps the row inside the terminal at every width, with a boundary of $1"
      sweep() {
        local -i sep=$1 cols i checked=0 previous=0 widest=0
        local -a widths=() broken=()
        local name
        inzsh_spec_derive_mincols $sep
        for (( cols = 0; cols <= 200; cols++ )); do
          _inzsh_layout_filter $cols "${inzsh_spec_row_names[@]}"
          widths=()
          for name in "${reply[@]}"; do
            i=${inzsh_spec_row_names[(Ie)$name]}
            widths+=${inzsh_spec_row_widths[i]}
          done
          (( checked++ ))
          _inzsh_layout_fits $cols $sep "${widths[@]}" || broken+="$cols:overflows"
          (( ${#reply} >= previous )) || broken+="$cols:shrank"
          previous=${#reply}
          widest=${#reply}
        done
        print -r -- "checked=$checked widest=$widest broken=${broken[*]}"
      }
      When call sweep "$1"
      The output should eq 'checked=201 widest=6 broken='
    End
  End

  Describe 'the ladder and the row together'
    It 'holds the invariant on every step of the ladder'
      # The same sweep, reported per step, so a step that is never reached — or one that is
      # reached only with an overflowing row — is visible rather than averaged away.
      stepped() {
        local -i sep=2 cols i
        local -a widths=() broken=()
        local name step
        local -A reached=()
        inzsh_spec_derive_mincols $sep
        for (( cols = 0; cols <= 200; cols++ )); do
          _inzsh_layout_ladder $cols
          step=$REPLY
          _inzsh_layout_filter $cols "${inzsh_spec_row_names[@]}"
          widths=()
          for name in "${reply[@]}"; do
            i=${inzsh_spec_row_names[(Ie)$name]}
            widths+=${inzsh_spec_row_widths[i]}
          done
          reached[$step]=1
          _inzsh_layout_fits $cols $sep "${widths[@]}" || broken+="$step:$cols"
        done
        local -a missing=()
        for step in "${_inzsh_ladder_steps[@]}"; do
          [[ -n ${reached[$step]+set} ]] || missing+=$step
        done
        print -r -- "missing=${missing[*]} broken=${broken[*]}"
      }
      When call stepped
      The output should eq 'missing= broken='
    End
  End
End

# ------------------------------------------------------------------------------------------
# Path truncation. A separate mechanism from hide/show: this shortens a segment's TEXT, it never
# decides whether the segment is drawn. A neutral home directory is used throughout — nothing
# here reads the machine.

inzsh_spec_truncate() {
  local HOME=/spec/home
  _inzsh_truncate_path "$1" "$2"
  print -r -- "$REPLY"
}

Describe 'path truncation'
  Describe 'the ladder, one rung at a time'
    # $1 the budget, $2 what comes back for /spec/home/dev/inzsh/lib. Full, then leading
    # components traded for an ellipsis one at a time, then the basename alone — at three columns
    # the ellipsis costs more than it says — then the basename cut down.
    Parameters
      40 '~/dev/inzsh/lib'
      15 '~/dev/inzsh/lib'
      14 '…/inzsh/lib'
      11 '…/inzsh/lib'
      10 '…/lib'
      5  '…/lib'
      4  'lib'
      3  'lib'
      2  'l…'
      1  '…'
      0  ''
    End

    It "gives '$2' on a budget of $1"
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      When call inzsh_spec_truncate '/spec/home/dev/inzsh/lib' "$1"
      The output should eq "$2"
    End
  End

  Describe 'the home directory'
    # $1 the path, $2 the budget, $3 the answer. Collapsing $HOME costs nothing — `~` is not an
    # abbreviation a reader has to decode — so it happens before any rung of the ladder.
    Parameters
      '/spec/home'          10 '~'
      '/spec/home'          1  '~'
      '/spec/home'          0  ''
      '/spec/home/'         10 '~'
      '/spec/home/x'        10 '~/x'
      '/spec/homework'      20 '/spec/homework'
      '/spec/home2/x'       20 '/spec/home2/x'
      '/spec/hom'           20 '/spec/hom'
      'spec/home'           20 'spec/home'
    End

    It "renders '$1' as '$3' on a budget of $2"
      When call inzsh_spec_truncate "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe 'the home directory, awkwardly written'
    It 'compares $HOME as a string, never as a pattern'
      # A home directory is allowed to contain glob characters. Matching it as a pattern would
      # collapse the wrong paths, or none.
      globbed() {
        local HOME='/spec/h[o]me'
        local -a seen=()
        _inzsh_truncate_path '/spec/h[o]me/x' 20; seen+="[$REPLY]"
        _inzsh_truncate_path '/spec/home/x' 20; seen+="[$REPLY]"
        print -r -- "${seen[*]}"
      }
      When call globbed
      The output should eq '[~/x] [/spec/home/x]'
    End

    It 'collapses a $HOME written with a trailing slash'
      slashed() {
        local HOME=/spec/home/
        _inzsh_truncate_path '/spec/home/x' 20
        print -r -- "$REPLY"
      }
      When call slashed
      The output should eq '~/x'
    End

    It 'collapses nothing when $HOME is empty or unset'
      homeless() {
        local -a seen=()
        local HOME=
        _inzsh_truncate_path '/spec/home/x' 20; seen+="[$REPLY]"
        unset HOME
        _inzsh_truncate_path '/spec/home/x' 20; seen+="[$REPLY]"
        print -r -- "${seen[*]}"
      }
      When call homeless
      The output should eq '[/spec/home/x] [/spec/home/x]'
    End
  End

  Describe 'the shapes a path can take'
    # $1 the path, $2 the budget, $3 the answer.
    Parameters
      '/'          5  '/'
      '/'          1  '/'
      '/'          0  ''
      '/usr'       4  '/usr'
      '/usr'       3  'usr'
      '/usr'       2  'u…'
      '/usr'       1  '…'
      'single'     6  'single'
      'single'     3  'si…'
      'rel/path'   8  'rel/path'
      'rel/path'   7  '…/path'
      'rel/path'   4  'path'
      '/a/b/'      4  '/a/b'
      '/a/b/'      3  '…/b'
      '/a/b/'      1  'b'
      '/a//b'      4  '/a/b'
      '/a/b/c/'    5  '…/b/c'
      '/a/b/c/'    4  '…/c'
      ''           5  ''
      ''           0  ''
    End

    It "renders '$1' as '$3' on a budget of $2"
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      When call inzsh_spec_truncate "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe 'a component with nowhere left to go'
    It 'cuts a single very long component rather than giving up on it'
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      # The full path is 34 columns and the basename 32, so there is no ellipsis rung between
      # them: one component means the ladder is the root marker, the bare name, and then the
      # name itself cut down. The column arithmetic assumes the one-column ellipsis, so this
      # reads differently where the marker degrades to three ASCII dots.
      long() {
        local HOME=/spec/home
        local -a seen=()
        local -i budget
        for budget in 34 33 10 5 2; do
          _inzsh_truncate_path '/spec/home/averyveryverylongsinglecomponent' $budget
          seen+="[$REPLY]"
        done
        print -r -- "${seen[*]}"
      }
      When call long
      The output should eq "[~/averyveryverylongsinglecomponent]\
 [averyveryverylongsinglecomponent] [averyvery…] [aver…] [a…]"
    End
  End

  Describe 'multibyte components'
    # Neutral non-ASCII, measured in cells rather than characters: the wide components are two
    # columns each, the accented ones one.
    Parameters
      '/spec/home/日本'       7  '~/日本'
      '/spec/home/日本'       6  '~/日本'
      '/spec/home/日本'       5  '日本'
      '/spec/home/日本'       4  '日本'
      '/spec/home/日本'       3  '日…'
      '/spec/home/日本'       2  '…'
      '/spec/home/日本'       1  '…'
      '/spec/home/日本語/x'   10 '~/日本語/x'
      '/spec/home/日本語/x'   9  '…/x'
      '/spec/home/café/naïve' 13 '~/café/naïve'
      '/spec/home/café/naïve' 12 '~/café/naïve'
      '/spec/home/café/naïve' 11 '…/naïve'
      '/spec/home/café/naïve' 7  '…/naïve'
      '/spec/home/café/naïve' 6  'naïve'
      '/spec/home/café/naïve' 4  'naï…'
    End

    It "renders '$1' as '$3' on a budget of $2"
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      When call inzsh_spec_truncate "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe 'a budget that is not a budget'
    # No budget known means no truncation — the same "assume room" rule the rest of the file
    # follows. The path still comes back collapsed and normalised, because that part was never
    # about the width.
    Parameters
      ''
      ' '
      x
      -1
      2.5
      ' 5'
      +5
    End

    It "returns the whole path for a budget of '$1'"
      When call inzsh_spec_truncate '/spec/home/dev/inzsh' "$1"
      The output should eq '~/dev/inzsh'
    End
  End

  Describe 'never wider than the budget'
    # The exhaustive gate. Every path in the matrix, every budget from 0 to 40: the answer is
    # measured — with `${(m)#…}` directly, not with the function under test — and must fit.
    # Three further claims ride along, because a function that returned the empty string always
    # would pass the first one. The answer is non-empty whenever there is room for a column; it
    # never gets narrower as the budget grows; and once the budget can hold the whole path, the
    # whole path is what comes back.
    Parameters
      '/'
      '/usr'
      '/spec/home'
      '/spec/home/dev/inzsh/lib/core'
      '/spec/home/averyveryverylongsinglecomponent'
      '/spec/home/日本語/プロジェクト'
      '/spec/home/café/naïve'
      'rel/path/here'
      'single'
      '/a/b/'
      '/a//b'
      ''
    End

    It "fits '$1' into every budget from 0 to 40"
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      exhaustive() {
        local HOME=/spec/home
        local path=$1 answer full
        local -i budget width previous=0 checked=0
        local -a broken=()
        _inzsh_truncate_path "$path" 999
        full=$REPLY
        for (( budget = 0; budget <= 40; budget++ )); do
          _inzsh_truncate_path "$path" $budget
          answer=$REPLY
          width=${(m)#answer}
          (( checked++ ))
          (( width <= budget )) || broken+="$budget:wider"
          (( width >= previous )) || broken+="$budget:narrowed"
          [[ -z $path || $budget -eq 0 || -n $answer ]] || broken+="$budget:empty"
          (( budget < ${(m)#full} )) || [[ $answer == $full ]] || broken+="$budget:partial"
          (( previous = width ))
        done
        print -r -- "checked=$checked broken=${broken[*]}"
      }
      When call exhaustive "$1"
      The output should eq 'checked=41 broken='
    End
  End

  Describe 'the pieces underneath'
    Describe 'cutting text to a width'
      # $1 the text, $2 the budget, $3 the answer. The marker is dropped rather than the text
      # when there is no room for both: at two columns, two letters say more than one letter and
      # a promise of more.
      Parameters
        'abcdef' 6 'abcdef'
        'abcdef' 5 'abcd…'
        'abcdef' 2 'a…'
        'abcdef' 1 '…'
        'abcdef' 0 ''
        'abcdef' x ''
        ''       5 ''
        '日本語'  6 '日本語'
        '日本語'  5 '日本…'
        '日本語'  3 '日…'
        '日本語'  2 '…'
      End

      It "cuts '$1' to '$3' at $2"
        Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
        cut() {
          _inzsh_truncate_text "$1" "$2"
          print -r -- "$REPLY"
        }
        When call cut "$1" "$2"
        The output should eq "$3"
      End
    End

    Describe 'the widest prefix that fits'
      # Cutting by character would overshoot on a double-width glyph, which is the only reason
      # this is not `${text[1,n]}`.
      Parameters
        'abcdef' 3  'abc'
        'abcdef' 10 'abcdef'
        'abcdef' 0  ''
        'abcdef' x  ''
        ''       5  ''
        '日本語'  1  ''
        '日本語'  2  '日'
        '日本語'  3  '日'
        '日本語'  4  '日本'
        '日x本'   3  '日x'
      End

      It "takes '$3' from '$1' at $2 columns"
        Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
        prefix() {
          _inzsh_width_prefix "$1" "$2"
          print -r -- "$REPLY"
        }
        When call prefix "$1" "$2"
        The output should eq "$3"
      End
    End

    It 'drops the marker when the marker is wider than the budget'
      # In a UTF-8 locale the ellipsis is one column and this can never happen, which is exactly
      # why it is asserted with a marker forced wider: `${(m)#…}` counts BYTES outside a
      # multibyte locale, so on that path the marker really is three columns, and a marker that
      # does not fit must give way to the text rather than overflow.
      wide_marker() {
        local _inzsh_layout_ellipsis='...'
        local -a seen=()
        _inzsh_truncate_text 'abcdef' 2; seen+="[$REPLY]"
        _inzsh_truncate_text 'abcdef' 3; seen+="[$REPLY]"
        _inzsh_truncate_text 'abcdef' 4; seen+="[$REPLY]"
        print -r -- "${seen[*]}"
      }
      When call wide_marker
      The output should eq '[ab] [...] [a...]'
    End

    It 'draws its marker from one place'
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      # The marker is `_inzsh_glyph[ellipsis]` and nothing else: every mark the theme draws comes
      # out of the token layer's one table, so the expectations in the truncation tables above
      # have a stated source rather than being a second transcription of it. One column wide,
      # which is the number every rung of the ladder was budgeted against.
      marker() {
        _inzsh_width "$_inzsh_layout_ellipsis"
        print -r -- "$REPLY"
        [[ $_inzsh_layout_ellipsis == ${_inzsh_glyph[ellipsis]} ]] && print -r -- from-the-table
      }
      When call marker
      The line 1 of output should eq '1'
      The line 2 of output should eq 'from-the-table'
    End
  End
End

# Priority — the order segments are given up in, and the fit that uses it.
#
# The pair below is what makes the no-wrap rule true rather than likely. MINCOLS is a fixed number
# compared against a segment whose width changes every render, so it can only ever approximate;
# `_inzsh_layout_fit` measures what is actually about to be drawn. These examples are about the
# ORDER and the STOPPING, because those are the two things a user can predict from.
Describe 'priority'
  Describe 'resolving one'
    inzsh_spec_priority_setup() {
      unset -m 'INZSH_*_PRIORITY'
      typeset -gA _inzsh_segment_priority
      _inzsh_segment_priority=(DIR 20 GIT 40 TIME 80)
    }
    BeforeEach 'inzsh_spec_priority_setup'

    It 'reads what the segment registered for itself'
      registered() { _inzsh_priority_of GIT; print -r -- "$REPLY" }
      When call registered
      The output should eq '40'
    End

    It 'lets the knob win, because the knob is the user speaking'
      knob() { INZSH_GIT_PRIORITY=5 _inzsh_priority_of GIT; print -r -- "$REPLY" }
      When call knob
      The output should eq '5'
    End

    # Negative is not an error and not a special case: it is "kept longer than anything at zero",
    # which is how a user pins one block above every default without renumbering the defaults.
    It 'takes a negative as an ordinary answer'
      below() { INZSH_TIME_PRIORITY=-5 _inzsh_priority_of TIME; print -r -- "$REPLY" }
      When call below
      The output should eq '-5'
    End

    # Same asymmetry the rest of this file follows. A typo'd knob must not silently reorder the
    # prompt, so it falls back to what the segment registered rather than to any reading of it.
    It 'ignores a knob that is not an integer'
      rubbish() { INZSH_GIT_PRIORITY=soon _inzsh_priority_of GIT; print -r -- "$REPLY" }
      When call rubbish
      The output should eq '40'
    End

    It 'puts a segment it has never heard of last'
      stranger() { _inzsh_priority_of NOSUCH; print -r -- "$REPLY" }
      When call stranger
      The output should eq "$_inzsh_priority_unknown"
    End

    # `${(P)}` on something that cannot name a variable is fatal mid-render. The guard is the same
    # one `_inzsh_mincols_of` carries, and it is asserted rather than assumed for the same reason.
    It 'answers a name that could not be a variable instead of dying on it'
      hostile() { _inzsh_priority_of 'a b'; print -r -- "$REPLY" }
      When call hostile
      The output should eq "$_inzsh_priority_unknown"
    End
  End

  Describe 'fitting a row'
    inzsh_spec_fit_setup() {
      unset -m 'INZSH_*_PRIORITY'
      typeset -gA _inzsh_segment_priority
      # Deliberately disagreeing with the argument order below, so nothing here can pass by
      # dropping from the right-hand end instead of by priority.
      _inzsh_segment_priority=(DIR 20 RETVAL 30 GIT 40 VENV 70 TIME 80 SALAH 90)
    }
    BeforeEach 'inzsh_spec_fit_setup'

    # Widths as they are drawn: text plus a column of padding either side. The separator is two
    # columns, which is the glyph and the space after it.
    inzsh_spec_row() {
      print -r -- DIR 12 GIT 7 VENV 7 RETVAL 8 TIME 8 SALAH 18
    }

    inzsh_spec_fit_at() {
      _inzsh_layout_fit "$1" 2 $(inzsh_spec_row)
      print -r -- "${reply[*]}"
    }

    It 'keeps everything when the row fits'
      When call inzsh_spec_fit_at 100
      The output should eq 'DIR GIT VENV RETVAL TIME SALAH'
    End

    # The whole point, in one example: the widest block goes first not because it is widest but
    # because it is last in the order, and it sits in the middle of the arguments.
    It 'drops the lowest priority first, wherever it sits in the row'
      When call inzsh_spec_fit_at 62
      The output should eq 'DIR GIT VENV RETVAL TIME'
    End

    It 'keeps going down the order as the window narrows'
      When call inzsh_spec_fit_at 40
      The output should eq 'DIR GIT VENV RETVAL'
    End

    It 'answers in the order it was given, not in priority order'
      # RETVAL outranks GIT and VENV in priority and follows them in the arguments. Position is
      # the rank layer's business and this function may not touch it.
      When call inzsh_spec_fit_at 30
      The output should eq 'DIR RETVAL'
    End

    # Stopping rather than skipping. At 34 columns there is room for TIME (8) after DIR, RETVAL
    # and GIT, but not for VENV (7) which comes first in the order — and TIME must NOT slip into
    # the gap VENV was refused. What survives is a prefix of the order or the rule is unlearnable.
    It 'stops at the first refusal instead of packing what still fits'
      fit() {
        _inzsh_segment_priority=(DIR 20 RETVAL 30 GIT 40 VENV 70 TIME 80)
        _inzsh_layout_fit 40 2 DIR 12 GIT 7 VENV 20 RETVAL 8 TIME 3
        print -r -- "${reply[*]}"
      }
      When call fit
      The output should eq 'DIR GIT RETVAL'
    End

    It 'hides nothing when the width is unknown'
      # Same rule as `_inzsh_layout_filter`: assuming room too readily wraps a prompt, assuming
      # none empties it, and only one of those can be recovered by looking at it.
      When call inzsh_spec_fit_at 'not-a-width'
      The output should eq 'DIR GIT VENV RETVAL TIME SALAH'
    End

    It 'answers empty for an empty row rather than inventing one'
      empty() { _inzsh_layout_fit 80 2; print -r -- "${#reply}" }
      When call empty
      The output should eq '0'
    End

    # A budget that fits nothing at all still has to answer, and the honest answer is nothing.
    It 'drops everything when even the first block will not fit'
      When call inzsh_spec_fit_at 3
      The output should eq ''
    End
  End
End
