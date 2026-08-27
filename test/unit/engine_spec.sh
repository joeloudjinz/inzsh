Include lib/core/engine.zsh

# The rank system: one integer per segment, deciding side, order and visibility at once. These
# examples pin SEGMENT NAMES and integers — the engine never touches colour, so this file loads
# no tokens and carries no hex.
#
# The regression this file exists for is sparseness. Ranks are a user-facing knob and users
# leave gaps, so an implementation that keys an array by rank value and then walks 1..count
# renders nothing for a lone segment at rank 10 and quietly drops the gaps out of 1, 4, 10.
# Every non-contiguous case below fails loudly against that implementation: the sparse-order
# group, the lone-high-rank example, and the conservation sweep that asserts no segment is ever
# lost between input and output.
#
# A `Parameters` block applies to every example in its group and to nested groups, so each one
# below sits in a leaf group of its own. Examples that take no parameters live outside them.
#
# ShellSpec runs each example in its own subshell, so a `typeset -g` in a helper cannot reach
# the next example. Where a helper would otherwise leave state behind inside one example, it
# says so.

# Set INZSH_<$1>_RANK to $2 and read the rank back. $3, when given, is the caller's default.
inzsh_spec_rank() {
  typeset -g "INZSH_${1}_RANK"="$2"
  _inzsh_rank_of "$1" "$3"
  print -r -- "$REPLY"
}

# Apply a table of NAME=RANK assignments in registration order, split, and print the answer as
# "[left] [right] [hidden]". The brackets keep an empty side visible in the assertion. An entry
# with no `=` leaves its variable unset, which is how the registry defaults get exercised.
inzsh_spec_split() {
  local entry name
  local -a segments=()
  for entry in "$@"; do
    name=${entry%%=*}
    segments+=$name
    [[ $entry == *=* ]] && typeset -g "INZSH_${name}_RANK"="${entry#*=}"
  done
  _inzsh_rank_split "${segments[@]}"
  print -r -- "[${_inzsh_left[*]}] [${_inzsh_right[*]}] [${_inzsh_hidden[*]}]"
}

# Sort explicit (rank, name) pairs and print the names in the order they come back.
inzsh_spec_sort() {
  _inzsh_rank_sort "$@"
  print -r -- "${reply[*]}"
}

# Every way a configuration can fail to be a rank. Each one must fall back rather than error,
# and each one must be rejected by the grammar and land the segment in `_inzsh_hidden`. The
# count is asserted alongside the failures wherever this table is swept, so adding a string
# here and forgetting to widen a gate cannot pass silently.
inzsh_spec_bad_ranks=(
  'abc'      # a word
  '1.5'      # a float
  ''         # set but empty — an `INZSH_DIR_RANK=` left behind in a zshrc
  ' 2'       # a leading space; unquoted, this would word-split into a valid 2
  '2 '       # a trailing space
  '--3'      # a doubled sign
  '+-3'      # two different signs
  '-'        # a sign with no digits
  '+'        # the other sign with no digits
  '1e3'      # scientific notation, which zsh maths would otherwise read as a float
  '0x10'     # hex, which zsh maths would otherwise read as 16
  '1,2'      # a list where a number belongs
  '1 2'      # two ranks in one value
  'true'     # a boolean, from a user who expected one
  '3rd'      # digits with a suffix
  'n3'       # digits with a prefix
)

Describe 'rank parsing'
  Describe 'readable ranks'
    # The grammar: an optional single sign, then digits. `+3` is a rank; the sign is normalised
    # away. Leading zeros are decimal — 007 is seven, not seven-in-octal — because a user
    # padding a column of ranks in a zshrc means what the digits say.
    Parameters
      '3'       3
      '+3'      3
      '-3'      -3
      '0'       0
      '-0'      0
      '+0'      0
      '1'       1
      '10'      10
      '-10'     -10
      '007'     7
      '-007'    -7
      '9000'    9000
    End

    It "reads '$1' as $2"
      When call inzsh_spec_rank DIR "$1"
      The output should eq "$2"
    End
  End

  Describe 'unreadable ranks'
    It 'falls back to 0 for every value that is not a rank'
      unreadable() {
        local candidate; local -i checked=0; local -a bad=()
        for candidate in "${inzsh_spec_bad_ranks[@]}"; do
          (( checked++ ))
          typeset -g INZSH_DIR_RANK="$candidate"
          _inzsh_rank_of DIR
          [[ $REPLY == 0 ]] || bad+="${candidate:-empty}=$REPLY"
        done
        print -r -- "checked=$checked bad=${bad[*]}"
      }
      When call unreadable
      The output should eq 'checked=16 bad='
    End

    It 'falls back to the default for every value that is not a rank'
      defaulted() {
        local candidate; local -i checked=0; local -a bad=()
        for candidate in "${inzsh_spec_bad_ranks[@]}"; do
          (( checked++ ))
          typeset -g INZSH_DIR_RANK="$candidate"
          _inzsh_rank_of DIR 7
          [[ $REPLY == 7 ]] || bad+="${candidate:-empty}=$REPLY"
        done
        print -r -- "checked=$checked bad=${bad[*]}"
      }
      When call defaulted
      The output should eq 'checked=16 bad='
    End

    # A rank that cannot be read is a hidden segment, never a failed call. A prompt that
    # refuses to draw over a typo is worse than a prompt that quietly drops one segment.
    It 'always succeeds — an unreadable rank is not an error'
      status_of() {
        typeset -g INZSH_DIR_RANK='not a rank'
        _inzsh_rank_of DIR
        print -r -- "status=$? reply=$REPLY"
      }
      When call status_of
      The output should eq 'status=0 reply=0'
    End
  End

  Describe 'the grammar predicate'
    # Stated separately from the reader so the sweeps above cannot pass by way of a predicate
    # that says yes to everything.
    It 'accepts ranks and rejects everything else'
      grammar() {
        local candidate; local -a bad=()
        for candidate in 3 +3 -3 0 -0 007 9000 -9000; do
          _inzsh_rank_valid "$candidate" || bad+="rejected:$candidate"
        done
        for candidate in "${inzsh_spec_bad_ranks[@]}"; do
          _inzsh_rank_valid "$candidate" && bad+="accepted:${candidate:-empty}"
        done
        print -r -- "${bad[*]}"
      }
      When call grammar
      The output should eq ''
    End
  End

  Describe 'the segment name'
    Parameters
      DIR
      dir
      Dir
      dIr
    End

    It "reads INZSH_DIR_RANK for the segment written as '$1'"
      cased() {
        typeset -g INZSH_DIR_RANK=4
        _inzsh_rank_of "$1"
        print -r -- "$REPLY"
      }
      When call cased "$1"
      The output should eq '4'
    End
  End

  Describe 'precedence'
    # variable → caller's default → registry → 0. The caller's default outranks the registry
    # because the caller is closer to the call than the registration was; the user outranks
    # both, always.
    It 'uses the variable when it is set and readable'
      When call inzsh_spec_rank DIR 2 9
      The output should eq '2'
    End

    It 'uses the caller default when the variable is unset'
      unset_var() {
        unset INZSH_DIR_RANK
        _inzsh_rank_of DIR 9
        print -r -- "$REPLY"
      }
      When call unset_var
      The output should eq '9'
    End

    It 'treats a variable that is set but empty as unset'
      When call inzsh_spec_rank DIR '' 9
      The output should eq '9'
    End

    It 'uses the registry default when the variable is unset and no default was passed'
      from_registry() {
        unset INZSH_GIT_RANK
        _inzsh_segment_defaults[GIT]=5
        _inzsh_rank_of GIT
        print -r -- "$REPLY"
      }
      When call from_registry
      The output should eq '5'
    End

    It 'lets the caller default beat the registry'
      caller_first() {
        unset INZSH_GIT_RANK
        _inzsh_segment_defaults[GIT]=5
        _inzsh_rank_of GIT 9
        print -r -- "$REPLY"
      }
      When call caller_first
      The output should eq '9'
    End

    It 'lets an explicit value beat both the caller default and the registry'
      user_first() {
        _inzsh_segment_defaults[GIT]=5
        typeset -g INZSH_GIT_RANK=2
        _inzsh_rank_of GIT 9
        print -r -- "$REPLY"
      }
      When call user_first
      The output should eq '2'
    End

    It 'falls past an unreadable caller default to the registry'
      bad_default() {
        unset INZSH_GIT_RANK
        _inzsh_segment_defaults[GIT]=5
        _inzsh_rank_of GIT 'chartreuse'
        print -r -- "$REPLY"
      }
      When call bad_default
      The output should eq '5'
    End

    It 'lands on 0 when the variable, the caller default and the registry are all unreadable'
      all_bad() {
        typeset -g INZSH_GIT_RANK=1.5
        _inzsh_segment_defaults[GIT]='x'
        _inzsh_rank_of GIT 'abc'
        print -r -- "$REPLY"
      }
      When call all_bad
      The output should eq '0'
    End

    # Defaulted-off is how an opt-in segment ships: it registers 0 and only a user's variable
    # brings it out. The registry entry must therefore be honoured as 0 rather than skipped as
    # falsy.
    It 'honours a registered default of 0 — this is how a segment ships defaulted-off'
      off_by_default() {
        unset INZSH_SALAH_RANK
        _inzsh_segment_defaults[SALAH]=0
        _inzsh_rank_split SALAH
        print -r -- "hidden=${_inzsh_hidden[*]} left=${_inzsh_left[*]}"
      }
      When call off_by_default
      The output should eq 'hidden=SALAH left='
    End

    It 'lets the user bring a defaulted-off segment out'
      opted_in() {
        _inzsh_segment_defaults[SALAH]=0
        typeset -g INZSH_SALAH_RANK=2
        _inzsh_rank_split SALAH
        print -r -- "hidden=${_inzsh_hidden[*]} left=${_inzsh_left[*]}"
      }
      When call opted_in
      The output should eq 'hidden= left=SALAH'
    End
  End

  Describe 'the registry'
    It 'is a global associative array, seeded empty'
      seeded() {
        print -r -- "${(t)_inzsh_segment_defaults} ${#_inzsh_segment_defaults}"
      }
      When call seeded
      The output should eq 'association 0'
    End
  End

  # Issue #282, found alongside the same defect in `_inzsh_priority_of`. Rung 4 of the ladder in
  # this function's header — "0 — hidden. The safe landing place" — is reached by falling off the
  # end of the loop without assigning anything, so it relies entirely on the `REPLY=0` written at
  # the top. `_inzsh_config_get` answers in `REPLY` too, and it runs BETWEEN the two: with the
  # config layer loaded, a segment matching no rung came back with the `INZSH_*_RANK` family's
  # registered default, which is empty, rather than 0.
  #
  # Milder than the priority half — every caller on the render path reads a rank arithmetically,
  # where empty coerces to the 0 that was intended anyway — but the header two lines above the
  # function promises "REPLY is always set", and it was not. A caller testing the string would
  # have been the one to find out.
  #
  # This file includes only `lib/core/engine.zsh`, so `_inzsh_config_get` is undefined here and
  # the branch never runs; the example is worthless unless it arranges the shell a real theme
  # actually has. Hence the `zsh -f` with the config layer sourced first, rather than adding it to
  # this file's includes and changing what every other example runs against.
  Describe 'with the config layer loaded, as a real shell has it'
    inzsh_spec_rank_configured() {
      zsh -f -c '
        source "$1/lib/core/config.zsh"
        source "$1/lib/core/engine.zsh"
        typeset -gA _inzsh_segment_defaults
        _inzsh_segment_defaults=(DIR 40)
        eval "$2"
      ' inzsh-rank-configured "$SHELLSPEC_PROJECT_ROOT" "$1"
    }

    It 'lands an unknown segment on 0 rather than on nothing'
      stranger_configured() {
        inzsh_spec_rank_configured '_inzsh_rank_of NOSUCH; print -r -- "[$REPLY]"'
      }
      When call stranger_configured
      The output should eq '[0]'
    End

    # The same landing place for a knob the grammar refuses on a segment with no registration to
    # fall back to — the other way onto rung 4.
    It 'lands an unreadable knob on 0 with nothing registered behind it'
      rubbish_configured() {
        inzsh_spec_rank_configured 'INZSH_NOSUCH_RANK=soon _inzsh_rank_of NOSUCH; print -r -- "[$REPLY]"'
      }
      When call rubbish_configured
      The output should eq '[0]'
    End

    # And a registered segment is untouched: the ladder answered before rung 4 was reached, both
    # before the repair and after it.
    It 'leaves a registered rank exactly as it was'
      registered_configured() {
        inzsh_spec_rank_configured '
          _inzsh_rank_of DIR; print -r -- "[$REPLY]"
          INZSH_DIR_RANK=-3 _inzsh_rank_of DIR; print -r -- "[$REPLY]"
        '
      }
      When call registered_configured
      The line 1 of output should eq '[40]'
      The line 2 of output should eq '[-3]'
    End
  End
End

# ------------------------------------------------------------------------------------------
Describe 'splitting left from right'
  Describe 'the sign decides the side'
    # $1 the rank table, $2 the expected "left | right | hidden".
    Parameters
      'A=1'                             '[A] [] []'
      'A=-1'                            '[] [A] []'
      'A=0'                             '[] [] [A]'
      'A=1 B=2 C=3'                     '[A B C] [] []'
      'A=-1 B=-2 C=-3'                  '[] [C B A] []'
      'A=0 B=0 C=0'                     '[] [] [A B C]'
      'A=1 B=-1 C=0'                    '[A] [B] [C]'
      'A=2 B=-2 C=0 D=1 E=-1'           '[D A] [B E] [C]'
    End

    It "splits ($1)"
      When call inzsh_spec_split ${=1}
      The output should eq "$2"
    End
  End

  Describe 'sparse ranks'
    # The regression gate. Every table here has gaps, and one of them has a single segment at a
    # rank far past the number of segments. An implementation that keys by rank value and walks
    # 1..count renders nothing at all for that one.
    Parameters
      'A=1 B=4 C=10'                    '[A B C] [] []'
      'A=10 B=4 C=1'                    '[C B A] [] []'
      'A=0 B=0 C=10'                    '[C] [] [A B]'
      'A=10'                            '[A] [] []'
      'A=9000'                          '[A] [] []'
      'A=5 B=3'                         '[B A] [] []'
      'A=-10 B=-4 C=-1'                 '[] [A B C] []'
      'A=0 B=-10 C=0'                   '[] [B] [A C]'
      'A=7 B=0 C=-7 D=3 E=-3'           '[D A] [C E] [B]'
      'A=1 B=4 C=9000 D=-9000 E=-1'     '[A B C] [D E] []'
    End

    It "orders ($1) without assuming contiguity"
      When call inzsh_spec_split ${=1}
      The output should eq "$2"
    End
  End

  Describe 'ties'
    # Equal ranks keep registration order. A user who gives two segments the same number has
    # said "these two, in the order I wrote them" — anything else reshuffles the prompt on a
    # value the user never changed.
    Parameters
      'A=1 B=1 C=1'                     '[A B C] [] []'
      'C=1 B=1 A=1'                     '[C B A] [] []'
      'A=2 B=1 C=2 D=1'                 '[B D A C] [] []'
      'A=-1 B=-1 C=-1'                  '[] [A B C] []'
      'A=-2 B=-1 C=-2 D=-1'             '[] [A C B D] []'
    End

    It "keeps registration order for the ties in ($1)"
      When call inzsh_spec_split ${=1}
      The output should eq "$2"
    End
  End

  Describe 'degenerate input'
    It 'leaves three empty arrays and status 0 when there is nothing to split'
      nothing() {
        _inzsh_rank_split
        print -r -- "status=$? L=${#_inzsh_left} R=${#_inzsh_right} H=${#_inzsh_hidden}"
      }
      When call nothing
      The output should eq 'status=0 L=0 R=0 H=0'
    End

    It 'hides every segment when every rank is unreadable'
      hostile() {
        local candidate; local -i checked=0 i=0; local -a segments=() bad=()
        for candidate in "${inzsh_spec_bad_ranks[@]}"; do
          (( checked++, i++ ))
          segments+="S$i"
          typeset -g "INZSH_S${i}_RANK"="$candidate"
        done
        _inzsh_rank_split "${segments[@]}"
        (( ${#_inzsh_left} )) && bad+="left=${_inzsh_left[*]}"
        (( ${#_inzsh_right} )) && bad+="right=${_inzsh_right[*]}"
        [[ ${_inzsh_hidden[*]} == ${segments[*]} ]] || bad+="hidden=${_inzsh_hidden[*]}"
        print -r -- "checked=$checked bad=${bad[*]}"
      }
      When call hostile
      The output should eq 'checked=16 bad='
    End

    It 'keeps a segment that appears twice in both of its places'
      duplicated() {
        typeset -g INZSH_A_RANK=1
        _inzsh_rank_split A A
        print -r -- "${_inzsh_left[*]}"
      }
      When call duplicated
      The output should eq 'A A'
    End
  End

  Describe 'the shape of the answer'
    It 'hands the three lists back as global arrays'
      kind() {
        typeset -g INZSH_A_RANK=1 INZSH_B_RANK=-1 INZSH_C_RANK=0
        _inzsh_rank_split A B C
        print -r -- "${(t)_inzsh_left} ${(t)_inzsh_right} ${(t)_inzsh_hidden}"
      }
      When call kind
      The output should eq 'array array array'
    End

    It 'passes segment names through untouched — only the variable lookup uppercases'
      verbatim() {
        typeset -g INZSH_DIR_RANK=1 INZSH_GIT_RANK=-1
        _inzsh_rank_split dir git
        print -r -- "${_inzsh_left[*]} ${_inzsh_right[*]}"
      }
      When call verbatim
      The output should eq 'dir git'
    End

    # A second split must not see the first one's answer. The arrays are global, so a caller
    # that forgot to clear them would accumulate segments across prompts.
    It 'clears the previous answer rather than appending to it'
      resplit() {
        typeset -g INZSH_A_RANK=1 INZSH_B_RANK=-1 INZSH_C_RANK=0
        _inzsh_rank_split A B C
        typeset -g INZSH_D_RANK=2
        _inzsh_rank_split D
        print -r -- "[${_inzsh_left[*]}] [${_inzsh_right[*]}] [${_inzsh_hidden[*]}]"
      }
      When call resplit
      The output should eq '[D] [] []'
    End

    It 'empties all three when a split of nothing follows a split of something'
      emptied() {
        typeset -g INZSH_A_RANK=1 INZSH_B_RANK=-1 INZSH_C_RANK=0
        _inzsh_rank_split A B C
        _inzsh_rank_split
        print -r -- "L=${#_inzsh_left} R=${#_inzsh_right} H=${#_inzsh_hidden}"
      }
      When call emptied
      The output should eq 'L=0 R=0 H=0'
    End
  End

  Describe 'conservation'
    # Bidirectional: every segment handed in comes back exactly once, and nothing comes back
    # that was not handed in. This is the sweep that catches a segment silently vanishing into
    # a gap — the failure the rank system is built to avoid.
    Parameters
      'A=1 B=4 C=10 D=0 E=-1 F=-4 G=-10'
      'A=10 B=0 C=0 D=0 E=0'
      'A=0 B=0 C=0'
      'A=1 B=1 C=1 D=-1 E=-1'
      'A=abc B=1.5 C= D=+3 E=--3 F=-2'
      'A=9000 B=-9000 C=1 D=-1'
    End

    It "loses and invents nothing splitting ($1)"
      conserved() {
        local entry name; local -a segments=() bad=() seen=()
        for entry in "$@"; do
          name=${entry%%=*}
          segments+=$name
          typeset -g "INZSH_${name}_RANK"="${entry#*=}"
        done
        _inzsh_rank_split "${segments[@]}"
        seen=("${_inzsh_left[@]}" "${_inzsh_right[@]}" "${_inzsh_hidden[@]}")
        (( ${#seen} == ${#segments} )) || bad+="count=${#seen}/${#segments}"
        for name in "${segments[@]}"; do
          (( ${seen[(I)$name]} )) || bad+="lost=$name"
        done
        for name in "${seen[@]}"; do
          (( ${segments[(I)$name]} )) || bad+="invented=$name"
        done
        print -r -- "${bad[*]}"
      }
      When call conserved ${=1}
      The output should eq ''
    End
  End
End

# ------------------------------------------------------------------------------------------
# `_inzsh_rank_split_pairs` — the split-and-sort half of `_inzsh_rank_split`, for a caller that
# hands in ranks it already read rather than segment names to look ranks up for. `_inzsh_render`
# is that caller, and the property under test in the last example below is the one its perf
# fix depends on: a hidden segment must be droppable from a registry read a caller already paid
# for, not merely from the render output.
Describe 'splitting from pairs already read'
  # The property the whole entry point exists for. A segment's `INZSH_<SEG>_RANK` can say
  # anything at all here — even a live, readable rank that flatly disagrees — and the pair
  # handed in wins, because the caller already read the rank it wants used and is not asking
  # this function to read it again.
  It 'never reads INZSH_<SEG>_RANK — the pair given in is the rank used'
    ignores_registry() {
      typeset -g INZSH_A_RANK=-5
      _inzsh_rank_split_pairs 3 A
      print -r -- "left=${_inzsh_left[*]} right=${_inzsh_right[*]}"
    }
    When call ignores_registry
    The output should eq 'left=A right='
  End

  # THE BUG THIS GUARDS — see `_inzsh_rank_split_pairs` in `lib/core/engine.zsh` for what
  # arithmetic assignment actually does to an ungrammatical rank. Every value in
  # `inzsh_spec_bad_ranks` is fed straight into a pair here, nowhere near `INZSH_<SEG>_RANK`, so
  # this sweeps the function's OWN grammar and not the registry ladder `_inzsh_rank_of` already
  # has a sweep for.
  It 'treats an ungrammatical rank as 0, exactly as _inzsh_rank_sort does'
    hostile() {
      local candidate; local -i checked=0 i=0; local -a segments=() pairs=() bad=()
      for candidate in "${inzsh_spec_bad_ranks[@]}"; do
        (( checked++, i++ ))
        segments+="S$i"
        pairs+=("$candidate" "S$i")
      done
      _inzsh_rank_split_pairs "${pairs[@]}"
      (( ${#_inzsh_left} )) && bad+="left=${_inzsh_left[*]}"
      (( ${#_inzsh_right} )) && bad+="right=${_inzsh_right[*]}"
      [[ ${_inzsh_hidden[*]} == ${segments[*]} ]] || bad+="hidden=${_inzsh_hidden[*]}"
      print -r -- "checked=$checked bad=${bad[*]}"
    }
    When call hostile
    The output should eq 'checked=16 bad='
  End

  It 'clears the previous answer rather than appending to it'
    resplit() {
      _inzsh_rank_split_pairs 1 A -1 B 0 C
      _inzsh_rank_split_pairs 2 D
      print -r -- "[${_inzsh_left[*]}] [${_inzsh_right[*]}] [${_inzsh_hidden[*]}]"
    }
    When call resplit
    The output should eq '[D] [] []'
  End

  # `_inzsh_rank_split` must still answer exactly as it always has: it is now a thin wrapper
  # that reads the ranks and delegates here. Every example above this line already pins the
  # observable contract of a split; this one is not a parallel copy of that sweep, it is the
  # proof that the two entry points agree on the same input.
  It 'agrees with _inzsh_rank_split, which now delegates to it'
    agree() {
      typeset -g INZSH_A_RANK=2 INZSH_B_RANK=-2 INZSH_C_RANK=0
      _inzsh_rank_split A B C
      local via_registry="${_inzsh_left[*]}|${_inzsh_right[*]}|${_inzsh_hidden[*]}"
      _inzsh_rank_split_pairs 2 A -2 B 0 C
      local via_pairs="${_inzsh_left[*]}|${_inzsh_right[*]}|${_inzsh_hidden[*]}"
      [[ $via_registry == "$via_pairs" ]] && print -r -- same ||
        print -r -- "$via_registry != $via_pairs"
    }
    When call agree
    The output should eq 'same'
  End
End

# ------------------------------------------------------------------------------------------
# The sorter on its own, driven by explicit (rank, name) pairs rather than through the config.
# Both prompts share one ascending sort; the right prompt reads that ascending order as
# "counting inward from the right edge", so -1 lands rightmost.
Describe 'sorting by rank'
  Describe 'ascending order'
    Parameters
      '1 a'                          'a'
      '2 b 1 a'                      'a b'
      '1 a 4 b 10 c'                 'a b c'
      '10 c 4 b 1 a'                 'a b c'
      '9000 z 1 a'                   'a z'
      '-1 a -2 b -3 c'               'c b a'
      '-3 c -1 a -2 b'               'c b a'
      '-1 a 1 b 0 c'                 'a c b'
      '3 c -3 a 0 b'                 'a b c'
    End

    It "sorts ($1) into ($2)"
      When call inzsh_spec_sort ${=1}
      The output should eq "$2"
    End
  End

  # The convention, written as an example rather than only as a comment. A right prompt of
  # A=-1, B=-2, C=-3 draws as `C B A`: A is hard against the right edge and each rank further
  # from zero steps one place inward, which is what "counting inward from the edge" means.
  It 'orders the right prompt most-negative first, so -1 is the rightmost'
    convention() {
      typeset -g INZSH_A_RANK=-1 INZSH_B_RANK=-2 INZSH_C_RANK=-3
      _inzsh_rank_split A B C
      print -r -- "${_inzsh_right[*]} rightmost=${_inzsh_right[-1]}"
    }
    When call convention
    The output should eq 'C B A rightmost=A'
  End

  It 'is stable — equal ranks keep the order they were given'
    stable() {
      _inzsh_rank_sort 2 b 1 a 2 c 2 d 1 e
      print -r -- "${reply[*]}"
    }
    When call stable
    The output should eq 'a e b c d'
  End

  It 'hands the names back in reply, as an array'
    kind() {
      _inzsh_rank_sort 2 b 1 a
      print -r -- "${(t)reply} ${#reply}"
    }
    When call kind
    The output should eq 'array 2'
  End

  It 'yields an empty reply for no pairs at all'
    empty() {
      _inzsh_rank_sort
      print -r -- "status=$? n=${#reply}"
    }
    When call empty
    The output should eq 'status=0 n=0'
  End

  It 'ignores a trailing rank with no name'
    dangling() {
      _inzsh_rank_sort 2 b 1 a 3
      print -r -- "${reply[*]}"
    }
    When call dangling
    The output should eq 'a b'
  End

  It 'sorts an unreadable rank as 0 rather than erroring'
    unreadable() {
      _inzsh_rank_sort 1 a 'abc' b -1 c
      print -r -- "status=$? ${reply[*]}"
    }
    When call unreadable
    The output should eq 'status=0 c b a'
  End

  # The order must come from the ranks that were given, never from a walk over a count or a
  # range. Ranks far past the number of segments, in both directions, sort exactly like the
  # small ones — and a count-driven implementation returns nothing for them.
  It 'sorts over the ranks that exist, at any magnitude'
    sparse() {
      local -a bad=()
      _inzsh_rank_sort 4000 c 40 b 400000 d 4 a
      [[ ${reply[*]} == 'a b c d' ]] || bad+="ascending=${reply[*]}"
      _inzsh_rank_sort -4 d -40 c -4000 b -400000 a
      [[ ${reply[*]} == 'a b c d' ]] || bad+="descending=${reply[*]}"
      _inzsh_rank_sort 12 only
      [[ ${reply[*]} == 'only' ]] || bad+="lone=${reply[*]}"
      print -r -- "${bad[*]}"
    }
    When call sparse
    The output should eq ''
  End
End

# ------------------------------------------------------------------------------------------
# Structural rather than behavioural: a fork on the render path is a cost you feel rather than
# see, so the gate is that the engine contains no command substitution at all. Comment lines
# are skipped — prose there quotes shell syntax.
Describe 'the render path'
  It 'ranks and sorts without forking — no command substitution in the engine'
    substitutions() {
      setopt local_options extended_glob
      local line; local -a bad=()
      while IFS= read -r line; do
        [[ $line == [[:space:]]#\#* ]] && continue
        [[ $line == *'$('* || $line == *'`'* ]] && bad+=$line
      done < "$SHELLSPEC_PROJECT_ROOT/lib/core/engine.zsh"
      print -r -- "${#bad}"
    }
    When call substitutions
    The output should eq '0'
  End

  It 'scopes its options — every function emulates zsh locally'
    emulated() {
      setopt local_options extended_glob
      local line; local -i functions=0 emulates=0
      while IFS= read -r line; do
        [[ $line == _inzsh_[a-z_]##\(\)\ \{ ]] && (( functions++ ))
        [[ $line == [[:space:]]#'emulate -L zsh' ]] && (( emulates++ ))
      done < "$SHELLSPEC_PROJECT_ROOT/lib/core/engine.zsh"
      print -r -- "functions=$functions emulates=$emulates"
    }
    When call emulated
    The output should eq 'functions=5 emulates=5'
  End
End
