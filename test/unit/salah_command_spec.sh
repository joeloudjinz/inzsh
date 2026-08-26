Include lib/salah/calc.zsh
Include lib/salah/methods.zsh
Include lib/salah/location.zsh
Include lib/core/doctor.zsh

# `inzsh salah` — issue #230, covering #248 and #249. The library has always been able to answer
# "what time is fajr today"; nothing before this command could ask it by hand. The examples below
# read their expectations out of `test/fixtures/salah/oracle.txt` rather than retyping its
# numbers, the same discipline `salah_oracle_spec.sh` keeps, so a fixture that drifts fails here
# too rather than leaving a second, silently stale copy of the same six numbers.
#
# Every example that checks a computed time sets its own `TZ`, exported, and reads it straight
# off the fixture row — the day boundary and the display both read the AMBIENT zone rather than
# one this file could pass in as an argument, which is the whole design the header's zone line
# exists to make honest.

# The oracle row `$1`, as `epoch|lat|lon|tz|ours-six` in REPLY - pipe-delimited at the TOP level
# so the six space-separated clock readings survive as one field rather than being flattened into
# the rest by a whitespace split. Status 1 when the fixture holds no such row.
inzsh_cmd_spec_row() {
  emulate -L zsh
  setopt local_options extended_glob

  typeset -g REPLY=
  local line
  local -a fields
  while IFS= read -r line; do
    [[ ${line##[[:space:]]#} == (\#*|'') ]] && continue
    fields=("${(@s:|:)line}")
    (( ${#fields} == 8 )) || continue
    fields=("${(@)fields//(#s)[[:space:]]##/}")
    fields=("${(@)fields//[[:space:]]##(#e)/}")
    [[ ${fields[1]} == $1 ]] || continue
    local ours=${fields[7]}
    [[ ${fields[8]} == '=' ]] || ours=${fields[8]}
    typeset -g REPLY="${fields[2]}|${fields[3]}|${fields[4]}|${fields[5]}|$ours"
    return 0
  done < "$SHELLSPEC_PROJECT_ROOT/test/fixtures/salah/oracle.txt"

  return 1
}

# One day's row, exactly as `_inzsh_doctor_row` renders it: `$1` the date, `$2` the six clock
# readings space-separated in prayer order. Built once here so no example hand-counts spaces.
inzsh_cmd_spec_row_line() {
  emulate -L zsh

  local date=$1
  local -a six=(${=2})
  local -a names=(fajr sunrise dhuhr asr maghrib isha)
  local -a pairs=()
  local -i i
  for (( i = 1; i <= 6; i++ )); do
    pairs+="${names[i]} ${six[i]}"
  done

  typeset -g REPLY="$date    ${(j:  :)pairs}"
}

inzsh_cmd_spec_env() {
  emulate -L zsh
  unset INZSH_SALAH_LAT INZSH_SALAH_LON INZSH_SALAH_AUTOLOCATE INZSH_SALAH_METHOD \
        INZSH_SALAH_ASR INZSH_SALAH_HIGHLAT 2>/dev/null
  return 0
}

Describe 'inzsh salah'
  Describe 'the header'
    # UTC rather than any of the oracle's own zones, because a zone's %Z abbreviation is not
    # guaranteed to read identically across every platform's tzdata - UTC is the one name every
    # C library spells the same way, which is what this example is actually checking.
    It 'names the method, the asr school and the ambient zone - never the position'
      header() {
        inzsh_cmd_spec_env
        local -x TZ=UTC
        local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
        inzsh salah --now 1785150000
      }
      When call header
      The status should be success
      The line 1 of output should eq 'InZsh prayer times'
      The line 2 of output should eq '  method        MWL, asr standard'
      The line 3 of output should eq '  zone          UTC +0000'
      The output should not include '21.4225'
      The output should not include '39.8262'
    End
  End

  Describe 'today, against the oracle'
    It 'prints exactly the fixture row'
      today() {
        inzsh_cmd_spec_env
        inzsh_cmd_spec_row algiers-mwl-shafi || return 1
        local -a row=("${(@s:|:)REPLY}")
        inzsh_cmd_spec_row_line 2026-07-27 "${row[5]}" || return 1
        typeset -g inzsh_cmd_spec_expect=$REPLY

        local -x TZ=${row[4]}
        local INZSH_SALAH_LAT=${row[2]} INZSH_SALAH_LON=${row[3]}
        inzsh salah --now "${row[1]}"
      }
      When call today
      The status should be success
      The lines of output should eq 4
      The line 4 of output should eq "  $inzsh_cmd_spec_expect"
    End
  End

  Describe 'a multi-day run crossing a spring-forward'
    # 2026-03-08 is the day the US clocks jump forward. Requesting three days starting the
    # evening before must show all three calendar dates, never skipping the transition day the
    # way adding 86400 seconds to that evening instant would - see `lib/salah/cache.zsh`'s own
    # comment on exactly this failure.
    It 'shows the transition day, matching the fixture on it'
      dst() {
        inzsh_cmd_spec_env
        inzsh_cmd_spec_row newyork-isna-dst-start || return 1
        local -a row=("${(@s:|:)REPLY}")
        inzsh_cmd_spec_row_line 2026-03-08 "${row[5]}" || return 1
        typeset -g inzsh_cmd_spec_expect=$REPLY

        local -x TZ=${row[4]}
        local INZSH_SALAH_LAT=${row[2]} INZSH_SALAH_LON=${row[3]}
        local INZSH_SALAH_METHOD=ISNA
        # 23:30 the evening before the transition - the near-midnight instant that a naive
        # +86400 would carry past the transition day entirely.
        inzsh salah --now 1772944200 --days 3
      }
      When call dst
      The status should be success
      The lines of output should eq 6
      The line 4 of output should include '2026-03-07'
      The line 5 of output should eq "  $inzsh_cmd_spec_expect"
      The line 6 of output should include '2026-03-09'
    End
  End

  Describe 'a day with an absent prayer'
    It 'marks it rather than leaving it blank'
      svalbard() {
        inzsh_cmd_spec_env
        inzsh_cmd_spec_row svalbard-midnight-sun || return 1
        local -a row=("${(@s:|:)REPLY}")
        inzsh_cmd_spec_row_line 2026-06-21 "${row[5]}" || return 1
        typeset -g inzsh_cmd_spec_expect=$REPLY

        local -x TZ=${row[4]}
        local INZSH_SALAH_LAT=${row[2]} INZSH_SALAH_LON=${row[3]}
        inzsh salah --now "${row[1]}"
      }
      When call svalbard
      The status should be success
      The lines of output should eq 4
      The line 4 of output should eq "  $inzsh_cmd_spec_expect"
      The output should include 'fajr none'
      The output should include 'sunrise none'
      The output should include 'maghrib none'
      The output should include 'isha none'
      The output should include 'dhuhr 12:59'
    End
  End

  Describe 'no position configured'
    It 'refuses on stderr and points at the coordinate knobs and inzsh locate'
      nowhere() {
        inzsh_cmd_spec_env
        inzsh salah --now 1785150000
      }
      When call nowhere
      The status should be failure
      The stderr should include 'INZSH_SALAH_LAT'
      The stderr should include 'INZSH_SALAH_LON'
      The stderr should include 'inzsh locate'
      The output should eq ''
    End
  End

  Describe 'bad input'
    It 'refuses a --days of zero'
      badzero() {
        inzsh_cmd_spec_env
        local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
        inzsh salah --days 0
      }
      When call badzero
      The status should be failure
      The stderr should include '--days'
      The output should eq ''
    End

    It 'refuses a --days that names no number'
      badword() {
        inzsh_cmd_spec_env
        local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
        inzsh salah --days banana
      }
      When call badword
      The status should be failure
      The stderr should include '--days'
    End

    It 'refuses a --days past the bound'
      badbig() {
        inzsh_cmd_spec_env
        local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
        inzsh salah --days 400
      }
      When call badbig
      The status should be failure
      The stderr should include '--days'
    End

    It 'refuses a --now that is not an epoch'
      badnow() {
        inzsh_cmd_spec_env
        local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
        inzsh salah --now banana
      }
      When call badnow
      The status should be failure
      The stderr should include '--now'
    End

    It 'refuses a flag it does not know'
      badflag() {
        inzsh_cmd_spec_env
        local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
        inzsh salah --bogus
      }
      When call badflag
      The status should be failure
      The stderr should include 'unknown flag'
    End
  End

  Describe 'coordinates never leave'
    # The whole point of reading the position rather than a hash of it (issue #229's lesson) is
    # that nothing derived from it appears either - checked on a run that succeeds and one that
    # fails, at coordinates chosen not to collide with any clock reading this file prints.
    It 'never prints the latitude or longitude, on success'
      seen() {
        inzsh_cmd_spec_env
        local -x TZ=UTC
        local INZSH_SALAH_LAT=52.1234 INZSH_SALAH_LON=-1.5678
        inzsh salah --now 1785150000 --days 2
      }
      When call seen
      The status should be success
      The output should not include '52.1234'
      The output should not include '1.5678'
    End

    It 'never prints the latitude or longitude, on refusal'
      refused() {
        inzsh_cmd_spec_env
        local INZSH_SALAH_LAT=91 INZSH_SALAH_LON=200
        inzsh salah --now 1785150000
      }
      When call refused
      The status should be failure
      The output should eq ''
      The stderr should not include '91'
      The stderr should not include '200'
    End
  End
End
