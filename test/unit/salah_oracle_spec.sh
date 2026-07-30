Include lib/salah/calc.zsh

# The oracle matrix. Nineteen days, nine places, two hemispheres, both solstices, an equinox,
# two daylight-saving transitions, all three high-latitude conventions, both asr schools, both
# forms of isha, a midnight sun and a polar night — every one of them checked against what an
# independent service answered for the same question.
#
# The data is `test/fixtures/salah/oracle.txt` and nothing in this file may write to it. Each
# row carries the reference answer AND our own, with `=` where they agree; the examples below
# check both sides, so a drift shows up as a failing example whichever direction it drifts in.
#
# The point of pinning our own column as well as the oracle's is that a fixture holding only the
# oracle would have to be loosened to a tolerance the moment the two disagreed, and a tolerance
# hides the next disagreement. Here the disagreements are enumerated: each one is annotated in
# the fixture with the reason and with a third opinion from a high-precision ephemeris, and the
# census at the foot of this file fails if the list of them changes at all.

typeset -gA inzsh_spec_row inzsh_spec_row_oracle inzsh_spec_row_ours
typeset -ga inzsh_spec_row_ids

inzsh_spec_oracle_load() {
  setopt local_options extended_glob
  (( ${#inzsh_spec_row_ids} )) && return 0

  local line id
  local -a fields
  while IFS= read -r line; do
    [[ ${line##[[:space:]]#} == (\#*|'') ]] && continue
    fields=("${(@s:|:)line}")
    (( ${#fields} == 8 )) || continue
    fields=("${(@)fields//(#s)[[:space:]]##/}")
    fields=("${(@)fields//[[:space:]]##(#e)/}")
    id=${fields[1]}
    inzsh_spec_row_ids+=$id
    # epoch, latitude, longitude, zone, compute arguments — everything the call needs.
    inzsh_spec_row[$id]="${fields[2]}|${fields[3]}|${fields[4]}|${fields[5]}|${fields[6]}"
    inzsh_spec_row_oracle[$id]=${fields[7]}
    if [[ ${fields[8]} == '=' ]]; then
      inzsh_spec_row_ours[$id]=${fields[7]}
    else
      inzsh_spec_row_ours[$id]=${fields[8]}
    fi
  done < "$SHELLSPEC_PROJECT_ROOT/test/fixtures/salah/oracle.txt"

  return 0
}

# The six local clock readings for a row, space-separated, absent prayers as the sentinel.
inzsh_spec_oracle_compute() {
  inzsh_spec_oracle_load
  local -a parts=("${(@s:|:)inzsh_spec_row[$1]}")
  local -a drawn=()
  local name
  _inzsh_salah_compute "${parts[1]}" "${parts[2]}" "${parts[3]}" ${=parts[5]} "tz=${parts[4]}"
  for name in "${_inzsh_salah_prayers[@]}"; do
    if _inzsh_salah_format "${_inzsh_salah_reply[$name]}" "${parts[4]}"; then
      drawn+=$REPLY
    else
      drawn+=$_inzsh_salah_absent
    fi
  done
  print -r -- "${drawn[*]}"
}

# --------------------------------------------------------------------------------------------

Describe 'the oracle matrix'
  Describe 'row by row'
    # $1 a row id. One example per row so a failure names the day and the place rather than a
    # count. The expectation is the row's own `ours` column, which is the oracle's answer
    # wherever the two agree — twelve of the nineteen rows agree on all six prayers.
    Parameters
      algiers-mwl-shafi
      algiers-mwl-hanafi
      algiers-algeria
      mecca-ummalqura-jun
      mecca-ummalqura-dec
      mecca-ummalqura-hanafi
      cairo-egyptian-equinox
      karachi-karachi-equinox
      newyork-isna-dst-start
      newyork-isna-dst-end
      sydney-mwl-dec
      capetown-mwl-jun
      buenosaires-mwl-dec
      reykjavik-angle
      reykjavik-seventh
      reykjavik-middle
      ushuaia-angle-dec
      svalbard-midnight-sun
      svalbard-polar-night
    End

    It "computes $1 as the fixture records it"
      row() {
        inzsh_spec_oracle_load
        print -r -- "$(inzsh_spec_oracle_compute "$1")"
      }
      When call row "$1"
      inzsh_spec_oracle_load
      The output should eq "${inzsh_spec_row_ours[$1]}"
    End
  End

  It 'reads every row the fixture holds, and no more'
    # The Parameters block above is a transcription of the ids and could fall behind the file.
    # This example is what stops that being possible: a row added to the fixture without an
    # example to run it fails here.
    census() {
      inzsh_spec_oracle_load
      print -r -- "${#inzsh_spec_row_ids} ${inzsh_spec_row_ids[1]} ${inzsh_spec_row_ids[-1]}"
    }
    When call census
    The output should eq '19 algiers-mwl-shafi svalbard-polar-night'
  End

  It 'agrees with the oracle on every prayer in twelve of the nineteen rows'
    # The headline number. Twelve rows match the reference on all six prayers; the other seven
    # differ in one cell or four, and every one of those cells is named in the census below.
    agreement() {
      inzsh_spec_oracle_load
      local id
      local -a agreed=() differed=()
      for id in "${inzsh_spec_row_ids[@]}"; do
        if [[ ${inzsh_spec_row_ours[$id]} == ${inzsh_spec_row_oracle[$id]} ]]; then
          agreed+=$id
        else
          differed+=$id
        fi
      done
      print -rl -- "agreed=${#agreed} differed=${#differed}" "${differed[@]}"
    }
    When call agreement
    The lines of output should eq 8
    The line 1 of output should eq 'agreed=12 differed=7'
    The output should include 'mecca-ummalqura-jun'
    The output should include 'cairo-egyptian-equinox'
    The output should include 'karachi-karachi-equinox'
    The output should include 'newyork-isna-dst-start'
    The output should include 'newyork-isna-dst-end'
    The output should include 'svalbard-midnight-sun'
    The output should include 'svalbard-polar-night'
  End

  It 'differs from the oracle in exactly the cells the fixture annotates'
    # The census. Every disagreement, named by row and prayer, with what each side says. A new
    # one appearing — or an annotated one quietly going away — fails here, which is the whole
    # reason the fixture carries both columns instead of a tolerance.
    census() {
      inzsh_spec_oracle_load
      local id
      local -i i
      local -a theirs mine notes=()
      for id in "${inzsh_spec_row_ids[@]}"; do
        theirs=(${=inzsh_spec_row_oracle[$id]})
        mine=(${=inzsh_spec_row_ours[$id]})
        for (( i = 1; i <= 6; i++ )); do
          [[ ${theirs[i]} == ${mine[i]} ]] ||
            notes+="${_inzsh_salah_prayers[i]}@${id}:${theirs[i]}/${mine[i]}"
        done
      done
      print -rl -- "${notes[@]}"
    }
    When call census
    The lines of output should eq 12
    The output should include 'dhuhr@mecca-ummalqura-jun:12:22/12:23'
    The output should include 'asr@cairo-egyptian-equinox:15:29/15:30'
    The output should include 'asr@karachi-karachi-equinox:15:52/15:50'
    The output should include 'asr@newyork-isna-dst-start:16:21/16:22'
    The output should include 'asr@newyork-isna-dst-end:14:30/14:29'
    The output should include 'fajr@svalbard-midnight-sun:00:59/none'
    The output should include 'sunrise@svalbard-midnight-sun:00:59/none'
    The output should include 'maghrib@svalbard-midnight-sun:00:59/none'
    The output should include 'isha@svalbard-midnight-sun:00:59/none'
    The output should include 'sunrise@svalbard-polar-night:11:55/none'
    The output should include 'asr@svalbard-polar-night:14:46/none'
    The output should include 'maghrib@svalbard-polar-night:11:56/none'
  End

  It 'never differs from the oracle by more than two minutes where both have an answer'
    # The bound. Where the oracle reports a time and so do we, the gap is small and stated —
    # this is what would fail first if the astronomy drifted, long before any single row's
    # expectation did.
    bounded() {
      inzsh_spec_oracle_load
      local id
      local -i i worst=0 gap left right
      local -a theirs mine bad=()
      for id in "${inzsh_spec_row_ids[@]}"; do
        theirs=(${=inzsh_spec_row_oracle[$id]})
        mine=(${=inzsh_spec_row_ours[$id]})
        for (( i = 1; i <= 6; i++ )); do
          [[ ${theirs[i]} == none || ${mine[i]} == none ]] && continue
          (( left = ${theirs[i]%:*} * 60 + ${theirs[i]#*:} ))
          (( right = ${mine[i]%:*} * 60 + ${mine[i]#*:} ))
          (( gap = left - right ))
          (( gap < 0 )) && (( gap = -gap ))
          (( gap > 720 )) && (( gap = 1440 - gap ))
          (( gap > worst )) && (( worst = gap ))
          (( gap > 2 )) && bad+="$id:${_inzsh_salah_prayers[i]}:$gap"
        done
      done
      print -r -- "worst=$worst broken=${bad[*]}"
    }
    When call bounded
    The output should eq 'worst=2 broken='
  End

  It 'reports an absence only where the oracle reported a time it could not have'
    # Every sentinel in the matrix falls on a row above the Arctic circle, and on a prayer the
    # oracle answered with a number anyway. That asymmetry is the deliberate part: we are not
    # missing times the oracle found, we are declining to invent times it did not.
    absences() {
      inzsh_spec_oracle_load
      local id
      local -i i
      local -a theirs mine bad=()
      local -A rows=()
      local -i total=0
      for id in "${inzsh_spec_row_ids[@]}"; do
        theirs=(${=inzsh_spec_row_oracle[$id]})
        mine=(${=inzsh_spec_row_ours[$id]})
        for (( i = 1; i <= 6; i++ )); do
          [[ ${mine[i]} == none ]] || continue
          (( total++ ))
          rows[$id]=1
          [[ ${theirs[i]} == none ]] && bad+="$id:${_inzsh_salah_prayers[i]}"
        done
      done
      print -r -- "$total ${(ko)rows} broken=${bad[*]}"
    }
    When call absences
    The output should eq '7 svalbard-midnight-sun svalbard-polar-night broken='
  End

  It 'converges on every row in the matrix'
    # The refinement loop, exercised across the whole matrix rather than at one latitude. Nine
    # places from 21°N to 78°N and 55°S, and not one of them reaches the cap.
    passes() {
      inzsh_spec_oracle_load
      local id
      local -i worst=0
      local -a bad=()
      local -a parts
      for id in "${inzsh_spec_row_ids[@]}"; do
        parts=("${(@s:|:)inzsh_spec_row[$id]}")
        _inzsh_salah_compute "${parts[1]}" "${parts[2]}" "${parts[3]}" ${=parts[5]} \
          "tz=${parts[4]}"
        (( _inzsh_salah_passes >= _inzsh_salah_max_passes )) && bad+=$id
        (( _inzsh_salah_passes > worst )) && (( worst = _inzsh_salah_passes ))
      done
      print -r -- "worst=$worst broken=${bad[*]}"
    }
    When call passes
    The output should eq 'worst=4 broken='
  End
End

Describe 'the fixture itself'
  # A fixture nobody checks is a fixture that can rot. These examples are about the file rather
  # than about the arithmetic.

  It 'holds no path from outside the repository'
    # Everything committed is published permanently, and a fixture is the easiest place for a
    # local path or a private URL to end up.
    clean() {
      local line
      local -a bad=()
      while IFS= read -r line; do
        [[ $line == *'/Users/'* || $line == *'/home/'* || $line == *'.claude'* ]] && bad+="$line"
      done < "$SHELLSPEC_PROJECT_ROOT/test/fixtures/salah/oracle.txt"
      print -r -- "broken=${bad[*]}"
    }
    When call clean
    The output should eq 'broken='
  End

  It 'records a well-formed instant, location and zone on every row'
    wellformed() {
      inzsh_spec_oracle_load
      local id
      local -a parts bad=()
      for id in "${inzsh_spec_row_ids[@]}"; do
        parts=("${(@s:|:)inzsh_spec_row[$id]}")
        [[ ${parts[1]} == <-> ]] || bad+="$id:epoch"
        _inzsh_salah_in_range "${parts[2]}" -90 90 || bad+="$id:lat"
        _inzsh_salah_in_range "${parts[3]}" -180 180 || bad+="$id:lon"
        [[ ${parts[4]} == [A-Z]*/* || ${parts[4]} == UTC ]] || bad+="$id:tz"
        [[ ${parts[5]} == *fajr_angle=* ]] || bad+="$id:params"
      done
      print -r -- "broken=${bad[*]}"
    }
    When call wellformed
    The output should eq 'broken='
  End

  It 'records six readings in both columns of every row'
    shaped() {
      inzsh_spec_oracle_load
      local id value
      local -a bad=()
      for id in "${inzsh_spec_row_ids[@]}"; do
        (( ${#${=inzsh_spec_row_oracle[$id]}} == 6 )) || bad+="$id:oracle"
        (( ${#${=inzsh_spec_row_ours[$id]}} == 6 )) || bad+="$id:ours"
        for value in ${=inzsh_spec_row_oracle[$id]} ${=inzsh_spec_row_ours[$id]}; do
          [[ $value == none || $value == [0-2][0-9]:[0-5][0-9] ]] || bad+="$id:$value"
        done
      done
      print -r -- "broken=${bad[*]}"
    }
    When call shaped
    The output should eq 'broken='
  End

  It 'is never written to by the library or by the other specs'
    # `test/fixtures/` holds inputs. The files scanned are the two library files and the two
    # sibling specs — this one is left out because it is the file that carries the pattern, and
    # a check that fails on its own source proves nothing about anything else.
    readonly_fixture() {
      local file line
      local -a bad=()
      for file in lib/salah/calc.zsh lib/salah/methods.zsh \
                  test/unit/salah_calc_spec.sh test/unit/salah_methods_spec.sh; do
        while IFS= read -r line; do
          [[ $line == *'>'*fixtures* ]] && bad+="${file:t}:$line"
        done < "$SHELLSPEC_PROJECT_ROOT/$file"
      done
      print -r -- "broken=${bad[*]}"
    }
    When call readonly_fixture
    The output should eq 'broken='
  End
End
