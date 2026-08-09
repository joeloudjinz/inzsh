Include lib/salah/calc.zsh

# The astronomy. Six prayers out of one instant, one latitude and one longitude, with no clock
# read, no zone baked in and no subprocess anywhere.
#
# What this file is arranged around is the seam. `_inzsh_salah_compute` takes the moment as an
# argument, and that is the only reason any of the numbers below could be written down at all:
# every example pins a day in 2026 and asks what the sun did, and none of them can be affected
# by what the sun is doing while they run.
#
# Zones appear only where the code lets them — choosing which calendar day an instant falls on,
# and formatting an answer. Everything between those two points is UTC seconds and Julian days,
# and the examples that matter most here are the ones that would fail if that stopped being
# true.

# The two source files this layer is allowed to consist of. Named once, so the seam examples at
# the foot of the file cannot quietly stop covering one of them.
typeset -ga inzsh_spec_salah_files=(lib/salah/calc.zsh lib/salah/methods.zsh)

# How many distinct strings an array holds. Used wherever the claim is "these all agree" —
# `${#${(u)…}}` counts characters rather than elements, which is a quiet way to pass.
inzsh_spec_distinct() {
  local -A seen=()
  local row
  for row in "$@"; do seen[$row]=1; done
  print -r -- ${#seen}
}

inzsh_spec_jd() {
  _inzsh_salah_jd_civil "$1" "$2" "$3"
  print -r -- "$REPLY"
}

inzsh_spec_date() {
  _inzsh_salah_civil_date "$1" "$2"
  print -r -- "$REPLY"
}

inzsh_spec_number() {
  local answer=no
  _inzsh_salah_number "$1" && answer=yes
  print -r -- "$answer"
}

# One prayer out of a full computation, formatted in the zone it was computed for. An absent
# prayer prints the sentinel, which is what the segment will see.
inzsh_spec_prayer() {
  local prayer=$1 epoch=$2 lat=$3 lon=$4 zone=$5
  shift 5
  _inzsh_salah_compute "$epoch" "$lat" "$lon" "tz=$zone" "$@"
  if _inzsh_salah_format "${_inzsh_salah_reply[$prayer]}" "$zone"; then
    print -r -- "$REPLY"
  else
    print -r -- "${_inzsh_salah_reply[$prayer]}"
  fi
}

# --------------------------------------------------------------------------------------------

Describe 'reading a number'
  # Everything a user can type reaches an arithmetic expression eventually, and zsh reads a bare
  # word there as zero and an unfinished expression as fatal. Neither is an acceptable answer to
  # a mistyped latitude, so nothing gets in without passing through here first.
  Describe 'the grammar'
    Parameters
      18      yes
      18.5    yes
      -33.87  yes
      +5      yes
      0       yes
      .5      yes
      0.833   yes
      ''      no
      ' '     no
      ' 18'   no
      '18 '   no
      abc     no
      18x     no
      1e3     no
      0x10    no
      '1.2.3' no
      -       no
      +       no
      .       no
      '1,5'   no
      '2+'    no
      '1 2'   no
      inf     no
      nan     no
    End

    It "reads '$1' as a number: $2"
      When call inzsh_spec_number "$1"
      The output should eq "$2"
    End
  End

  Describe 'bounds'
    # $1 the value, $2 and $3 the inclusive bounds, $4 the verdict. Either bound may be empty,
    # which is how "no limit on that side" is said.
    Parameters
      18    0   30  in
      0     0   30  in
      30    0   30  in
      -1    0   30  out
      30.5  0   30  out
      -90   -90 90  in
      90    -90 90  in
      -90.1 -90 90  out
      5     ''  30  in
      -500  ''  30  in
      5     0   ''  in
      -5    0   ''  out
      abc   0   30  out
      ''    0   30  out
    End

    It "puts $1 $4 of $2..$3"
      bounded() {
        local answer=out
        _inzsh_salah_in_range "$1" "$2" "$3" && answer=in
        print -r -- "$answer"
      }
      When call bounded "$1" "$2" "$3"
      The output should eq "$4"
    End
  End
End

Describe 'the Julian day'
  Describe 'known dates'
    # The Gregorian conversion at the places it is easiest to get wrong: the Unix epoch, the
    # J2000 reference the sun position is measured from, a leap day, and the March boundary
    # where the algorithm renumbers the months.
    Parameters
      1970 1  1  2440587.5
      2000 1  1  2451544.5
      2000 3  1  2451604.5
      2024 2  29 2460369.5
      2025 3  1  2460735.5
      2026 1  1  2461041.5
      2026 3  1  2461100.5
      2026 7  27 2461248.5
      2026 12 31 2461405.5
    End

    It "puts $1-$2-$3 at $4"
      When call inzsh_spec_jd "$1" "$2" "$3"
      The output should eq "$4"
    End
  End

  It 'applies the century rule rather than a plain four-year one'
    # 1900 was not a leap year and 2000 was. A conversion that dropped the `A/4` correction gets
    # one of them right and the other wrong; both are here so that neither mistake survives.
    centuries() {
      local -a seen=()
      _inzsh_salah_jd_civil 1900 3 1; seen+=$REPLY
      _inzsh_salah_jd_civil 1900 2 28; seen+=$REPLY
      _inzsh_salah_jd_civil 2000 3 1; seen+=$REPLY
      _inzsh_salah_jd_civil 2000 2 28; seen+=$REPLY
      print -r -- "${seen[*]}"
    }
    When call centuries
    The output should eq '2415079.5 2415078.5 2451604.5 2451602.5'
  End

  It 'advances by exactly one for each day of a year'
    # A day is a day. Every month rollover and the year boundary are walked, so an off-by-one in
    # the month table shows up as a gap rather than as an absolute value nobody can check.
    steps() {
      # `previous` is deliberately untyped: a Julian day at midnight ends in .5, and an integer
      # accumulator would truncate it and make every comparison below pass for the wrong reason.
      local -i month day
      local previous
      local -a bad=()
      local -a lengths=(31 28 31 30 31 30 31 31 30 31 30 31)
      _inzsh_salah_jd_civil 2025 12 31
      previous=$REPLY
      for (( month = 1; month <= 12; month++ )); do
        for (( day = 1; day <= lengths[month]; day++ )); do
          _inzsh_salah_jd_civil 2026 $month $day
          (( REPLY == previous + 1 )) || bad+="2026-$month-$day"
          previous=$REPLY
        done
      done
      print -r -- "broken=${bad[*]}"
    }
    When call steps
    The output should eq 'broken='
  End

  Describe 'a date that is not a date'
    Parameters
      abc  7  27
      2026 x  27
      2026 7  x
      ''   7  27
      2026 '' 27
      2026 7  ''
    End

    It "refuses '$1'-'$2'-'$3' rather than computing something"
      refused() {
        local answer=accepted
        _inzsh_salah_jd_civil "$1" "$2" "$3" || answer=refused
        print -r -- "$answer"
      }
      When call refused "$1" "$2" "$3"
      The output should eq 'refused'
    End
  End
End

Describe 'the calendar day an instant falls on'
  # The one question a zone is allowed to answer. 21:00 UTC on the 27th is still the 27th in
  # Algiers, already the 28th in Auckland; 02:00 UTC is still the 26th in Honolulu. A
  # calculation that took the UTC date and called it the local one would compute the wrong day's
  # prayers for a third of the planet.
  Describe 'across the zones'
    Parameters
      1785186000 Africa/Algiers    '2026 7 27'
      1785186000 Pacific/Auckland  '2026 7 28'
      1785186000 Pacific/Honolulu  '2026 7 27'
      1785186000 UTC               '2026 7 27'
      1785117600 Africa/Algiers    '2026 7 27'
      1785117600 Pacific/Auckland  '2026 7 27'
      1785117600 Pacific/Honolulu  '2026 7 26'
      1785117600 UTC               '2026 7 27'
    End

    It "reads $1 in $2 as $3"
      When call inzsh_spec_date "$1" "$2"
      The output should eq "$3"
    End
  End

  It 'strips the zero-padding rather than handing on an octal literal'
    # `%m` and `%d` are zero-padded, and `08` in an arithmetic expression is eight in no shell
    # and fatal in some. The first of January is the example that catches it.
    padded() {
      _inzsh_salah_civil_date 1767225600 UTC
      print -r -- "$REPLY"
    }
    When call padded
    The output should eq '2026 1 1'
  End

  It 'leaves the shell zone exactly as it found it'
    # The theme does not get to change TZ. The check is the shell's own reading of an instant,
    # before and after, so it fails whether TZ was exported, unset or altered.
    untouched() {
      local -x TZ=UTC
      local before after
      strftime -s before '%Y-%m-%d %H:%M' 1785186000
      _inzsh_salah_civil_date 1785186000 Pacific/Auckland
      _inzsh_salah_civil_date 1785186000 Pacific/Honolulu
      strftime -s after '%Y-%m-%d %H:%M' 1785186000
      print -r -- "$before / $after / $TZ"
    }
    When call untouched
    The output should eq '2026-07-27 21:00 / 2026-07-27 21:00 / UTC'
  End

  Describe 'an instant that is not an instant'
    Parameters
      ''
      ' '
      abc
      2.5
      ' 1785186000'
      +1785186000
    End

    It "refuses '$1'"
      refused() {
        local answer=accepted
        _inzsh_salah_civil_date "$1" UTC || answer=refused
        print -r -- "$answer"
      }
      When call refused "$1"
      The output should eq 'refused'
    End
  End
End

Describe 'the sun'
  It 'keeps the declination inside the obliquity, every day of a year'
    # The declination is the tilt of the Earth's axis projected onto the sky. It cannot leave
    # ±23.44°, ever — and a formula that has lost a factor somewhere leaves that envelope long
    # before it produces a visibly wrong prayer time. Both extremes must also be REACHED: a
    # declination stuck at zero would satisfy the envelope and compute nothing.
    envelope() {
      local -i day
      local -a bad=()
      local low=99 high=-99
      for (( day = 0; day < 365; day++ )); do
        _inzsh_salah_sun $(( 2461041.5 + day ))
        (( _inzsh_salah_decl >= -23.45 && _inzsh_salah_decl <= 23.45 )) ||
          bad+="$day:$_inzsh_salah_decl"
        (( _inzsh_salah_decl < low )) && low=$_inzsh_salah_decl
        (( _inzsh_salah_decl > high )) && high=$_inzsh_salah_decl
      done
      (( low < -23.0 )) || bad+="never-south:$low"
      (( high > 23.0 )) || bad+="never-north:$high"
      print -r -- "broken=${bad[*]}"
    }
    When call envelope
    The output should eq 'broken='
  End

  It 'keeps the equation of time inside a quarter of an hour, every day of a year'
    # The equation of time is a correction, not a time: it runs between about -14 and +16
    # minutes. Anything outside that is the wrap this file folds away, and if the fold ever
    # stops happening it shows up here as a value near twenty-four hours rather than near zero.
    correction() {
      local -i day
      local -a bad=()
      local low=99 high=-99
      for (( day = 0; day < 365; day++ )); do
        _inzsh_salah_sun $(( 2461041.5 + day ))
        (( _inzsh_salah_eqt >= -0.3 && _inzsh_salah_eqt <= 0.3 )) ||
          bad+="$day:$_inzsh_salah_eqt"
        (( _inzsh_salah_eqt < low )) && low=$_inzsh_salah_eqt
        (( _inzsh_salah_eqt > high )) && high=$_inzsh_salah_eqt
      done
      (( low < -0.2 )) || bad+="never-early:$low"
      (( high > 0.2 )) || bad+="never-late:$high"
      print -r -- "broken=${bad[*]}"
    }
    When call correction
    The output should eq 'broken='
  End

  Describe 'the seasons'
    # $1 a Julian day at 00:00 UT, $2 the declination rounded to a whole degree — the two
    # solstices and the two equinoxes, which is the shortest description of a year that still
    # has a shape.
    Parameters
      2461041.5 -23
      2461119.5 0
      2461212.5 23
      2461306.5 0
      2461395.5 -23
    End

    It "puts the declination at $2 degrees on Julian day $1"
      seasonal() {
        _inzsh_salah_sun "$1"
        print -r -- $(( int(rint(_inzsh_salah_decl)) ))
      }
      When call seasonal "$1"
      The output should eq "$2"
    End
  End
End

Describe 'the refinement pass'
  # The sun moves while the day runs, so evaluating its position once at noon and using that for
  # every prayer is wrong by about a minute at isha, and by more as the latitude climbs. Each
  # prayer is recomputed at its own current estimate until nothing moves any further.

  It 'iterates rather than answering from the first estimate'
    # A single pass would report one. Two at minimum means the second pass had a better estimate
    # than the constants the loop starts from.
    iterates() {
      _inzsh_salah_compute 1785150000 36.7538 3.0588 fajr_angle=18 isha_angle=17
      print -r -- $(( _inzsh_salah_passes >= 2 && _inzsh_salah_passes <= 5 ))
    }
    When call iterates
    The output should eq '1'
  End

  It 'converges everywhere, without ever reaching the cap'
    # The cap is a safety net, not the stopping rule. If any location on this sweep needed all
    # eight passes, the answer would be the loop giving up rather than the loop finishing.
    everywhere() {
      local -i lat pass_max=0
      local -a bad=()
      local day
      for day in 1782043200 1797850800; do
        for (( lat = -80; lat <= 80; lat += 10 )); do
          _inzsh_salah_compute $day $lat 0 fajr_angle=18 isha_angle=17
          (( _inzsh_salah_passes >= _inzsh_salah_max_passes )) && bad+="$day:$lat"
          (( _inzsh_salah_passes > pass_max )) && pass_max=$_inzsh_salah_passes
        done
      done
      print -r -- "worst=$pass_max broken=${bad[*]}"
    }
    When call everywhere
    The output should eq 'worst=3 broken='
  End

  It 'moves the answer, and moves it by less than a minute'
    # Both halves matter. A refinement that changed nothing would be dead code dressed as
    # rigour; one that changed the answer by minutes would mean the first estimate was not an
    # estimate. Algiers is the case the milestone was opened for: unrefined, isha rounds to
    # 21:36; refined, it rounds to 21:35, and the oracle says 21:35.
    difference() {
      unrefined() {
        local _inzsh_salah_max_passes=1
        _inzsh_salah_compute 1785150000 36.7538 3.0588 fajr_angle=18 isha_angle=17
      }
      local -a once=() converged=()
      local name
      unrefined
      for name in "${_inzsh_salah_prayers[@]}"; do once+=${_inzsh_salah_reply[$name]}; done
      _inzsh_salah_compute 1785150000 36.7538 3.0588 fajr_angle=18 isha_angle=17
      for name in "${_inzsh_salah_prayers[@]}"; do converged+=${_inzsh_salah_reply[$name]}; done

      local -i i gap moved=0 worst=0
      for (( i = 1; i <= ${#once}; i++ )); do
        (( gap = converged[i] - once[i] ))
        (( gap < 0 )) && (( gap = -gap ))
        (( gap > 0 )) && (( moved++ ))
        (( gap > worst )) && (( worst = gap ))
      done
      print -r -- "moved=$(( moved > 0 )) under_a_minute=$(( worst < 60 ))"
    }
    When call difference
    The output should eq 'moved=1 under_a_minute=1'
  End

  It 'is idempotent once it has converged'
    # Computing the same instant twice gives the same six numbers. Trivially true unless some
    # state survives a call, which is the failure this catches.
    stable() {
      local -a rows=()
      local name row pass
      for pass in first second; do
        _inzsh_salah_compute 1785150000 36.7538 3.0588 fajr_angle=18 isha_angle=17
        row=''
        for name in "${_inzsh_salah_prayers[@]}"; do row+="${_inzsh_salah_reply[$name]} "; done
        rows+="$row"
      done
      inzsh_spec_distinct "${rows[@]}"
    }
    When call stable
    The output should eq '1'
  End

  It 'gives the same answer for any instant inside the same local day'
    # The moment picks a day and nothing else. The first second of the day in Algiers, noon, and
    # the last second all describe the same sky — and a calculation that used the hour as well
    # as the date would disagree with itself here.
    same_day() {
      local -a rows=()
      local epoch name row
      for epoch in 1785106800 1785150000 1785193199; do
        _inzsh_salah_compute $epoch 36.7538 3.0588 fajr_angle=18 isha_angle=17 tz=Africa/Algiers
        row=''
        for name in "${_inzsh_salah_prayers[@]}"; do row+="${_inzsh_salah_reply[$name]} "; done
        rows+="$row"
      done
      inzsh_spec_distinct "${rows[@]}"
    }
    When call same_day
    The output should eq '1'
  End

  It 'gives a different answer once the local day turns over'
    # The companion to the example above, and the reason it is not vacuous: one second later is
    # the next day in Algiers, and the next day is a different sky.
    next_day() {
      local -a seen=()
      _inzsh_salah_compute 1785193199 36.7538 3.0588 fajr_angle=18 isha_angle=17 tz=Africa/Algiers
      seen+=${_inzsh_salah_reply[dhuhr]}
      _inzsh_salah_compute 1785193200 36.7538 3.0588 fajr_angle=18 isha_angle=17 tz=Africa/Algiers
      seen+=${_inzsh_salah_reply[dhuhr]}
      print -r -- $(( seen[2] - seen[1] > 86000 && seen[2] - seen[1] < 86800 ))
    }
    When call next_day
    The output should eq '1'
  End
End

Describe 'asr'
  # Defined by shadow length rather than by a fixed depression, which is why it is the only
  # prayer whose angle changes with the season as well as with the hour.
  Describe 'the two schools'
    # $1 the shadow factor, $2 the time at Algiers on the anchor day. One shadow length or two,
    # and about seventy minutes between them at this latitude in July.
    Parameters
      1 16:44
      2 17:53
    End

    It "puts asr at $2 with a shadow factor of $1"
      When call inzsh_spec_prayer asr 1785150000 36.7538 3.0588 Africa/Algiers \
        fajr_angle=18 isha_angle=17 "asr_factor=$1"
      The output should eq "$2"
    End
  End

  It 'never puts the second school before the first'
    # Two shadow lengths cannot fall before one, anywhere, on any day. A sign error in the
    # arccot would satisfy the two examples above at one latitude and fail here.
    ordered() {
      local -i lat
      local -a bad=()
      local day shafi hanafi
      for day in 1782043200 1797850800; do
        for (( lat = -60; lat <= 60; lat += 5 )); do
          _inzsh_salah_compute $day $lat 0 asr_factor=1
          shafi=${_inzsh_salah_reply[asr]}
          _inzsh_salah_compute $day $lat 0 asr_factor=2
          hanafi=${_inzsh_salah_reply[asr]}
          if [[ $shafi != <-> || $hanafi != <-> ]]; then
            bad+="$day:$lat:absent"
          elif (( hanafi <= shafi )); then
            bad+="$day:$lat"
          fi
        done
      done
      print -r -- "broken=${bad[*]}"
    }
    When call ordered
    The output should eq 'broken='
  End

  It 'has no answer where the sun does not rise'
    # The rule measures a shadow against the one an object casts at noon. Under a polar night
    # there is no noon shadow to measure against; the arithmetic degenerates rather than
    # failing, and would hand back a time of day at which nothing happens. A midnight sun is a
    # different thing entirely — the sun never sets, but it does cast a shadow all day — and asr
    # is real there, which is what stops this from being a rule about latitude.
    shadowless() {
      local -a seen=()
      _inzsh_salah_compute 1797850800 78.2232 15.6267 asr_factor=1
      seen+=${_inzsh_salah_reply[asr]}
      _inzsh_salah_compute 1782036000 78.2232 15.6267 asr_factor=1
      seen+=$([[ ${_inzsh_salah_reply[asr]} == <-> ]] && print present || print none)
      print -r -- "${seen[*]}"
    }
    When call shadowless
    The output should eq 'none present'
  End
End

Describe 'the sentinel'
  # Beyond the polar circles some prayers have no time at all. What comes back then is a word,
  # not a number: never midnight, never the previous day's answer, never zero.

  It 'is a word that cannot be read as an epoch'
    shape() {
      local kind=opaque
      [[ $_inzsh_salah_absent == <-> ]] && kind=numeric
      print -r -- "$_inzsh_salah_absent $kind"
    }
    When call shape
    The output should eq 'none opaque'
  End

  Describe 'a midnight sun'
    # 78°N on the June solstice. The sun does not cross the horizon, so there is no sunrise, no
    # maghrib, and no night for fajr or isha to be a portion of — but it still crosses the
    # meridian and still casts a shadow, so dhuhr and asr are real. Absence is decided per
    # prayer, out of the arithmetic.
    Parameters
      fajr    none
      sunrise none
      dhuhr   12:59
      asr     19:08
      maghrib none
      isha    none
    End

    It "answers $2 for $1 under a midnight sun"
      When call inzsh_spec_prayer "$1" 1782036000 78.2232 15.6267 Arctic/Longyearbyen \
        fajr_angle=18 isha_angle=17 highlat=angle
      The output should eq "$2"
    End
  End

  Describe 'a polar night'
    # The same place in December. The sun never rises, so sunrise, maghrib and asr are absent —
    # but it climbs to within twelve degrees of the horizon, so fajr and isha, measured at
    # eighteen and seventeen degrees below it, do happen. Twilight is real there even though
    # daylight is not.
    Parameters
      fajr    07:37
      sunrise none
      dhuhr   11:56
      asr     none
      maghrib none
      isha    15:51
    End

    It "answers $2 for $1 under a polar night"
      When call inzsh_spec_prayer "$1" 1797850800 78.2232 15.6267 Arctic/Longyearbyen \
        fajr_angle=18 isha_angle=17 highlat=angle
      The output should eq "$2"
    End
  End

  It 'answers with the sentinel for a prayer no angle was given for'
    # No fajr angle means no fajr. Answering with an arbitrary one would be inventing a prayer
    # time, which is the one thing this file may never do.
    unasked() {
      _inzsh_salah_compute 1785150000 36.7538 3.0588
      local present=absent
      [[ ${_inzsh_salah_reply[dhuhr]} == <-> ]] && present=present
      print -r -- "${_inzsh_salah_reply[fajr]} ${_inzsh_salah_reply[isha]} $present"
    }
    When call unasked
    The output should eq 'none none present'
  End
End

Describe 'high latitudes'
  # Between about 48° and 66° the sun sets but never reaches eighteen degrees below the horizon.
  # There is no astronomical fajr or isha, so the night is divided instead — three conventions,
  # and a fourth answer that declines to divide it at all.

  Describe 'the portion of a night'
    # $1 the convention, $2 the night in hours, $3 the angle, $4 the portion. `seventh` and
    # `middle` ignore the angle, which is why it is passed to all three.
    Parameters
      angle   6  18 1.800
      angle   6  17 1.700
      angle   12 18 3.600
      seventh 7  18 1.000
      seventh 7  17 1.000
      middle  6  18 3.000
      middle  6  17 3.000
      middle  6  0  3.000
    End

    It "gives $4 hours for $1 out of a night of $2 at $3 degrees"
      portion() {
        _inzsh_salah_night_portion "$1" "$2" "$3"
        printf '%.3f\n' "$REPLY"
      }
      When call portion "$1" "$2" "$3"
      The output should eq "$4"
    End
  End

  Describe 'the conventions at 64 degrees'
    # Reykjavík on the June solstice, where all three are in play at once. $1 the convention,
    # $2 fajr, $3 isha. The ordering is the arithmetic's own: a seventh of that short night is
    # less than eighteen sixtieths of it, and half of it is more than either.
    Parameters
      angle   02:04 00:52
      seventh 02:31 00:28
      middle  01:30 01:30
    End

    It "puts fajr at $2 and isha at $3 under $1"
      conventions() {
        local -a seen=()
        _inzsh_salah_compute 1782043200 64.1466 -21.9426 fajr_angle=18 isha_angle=17 \
          "highlat=$1" tz=Atlantic/Reykjavik
        _inzsh_salah_format "${_inzsh_salah_reply[fajr]}" Atlantic/Reykjavik; seen+=$REPLY
        _inzsh_salah_format "${_inzsh_salah_reply[isha]}" Atlantic/Reykjavik; seen+=$REPLY
        print -r -- "${seen[*]}"
      }
      When call conventions "$1"
      The output should eq "$2 $3"
    End
  End

  It 'touches only the two prayers it is for'
    # Sunrise, dhuhr, asr and maghrib are astronomy and stay astronomy. A convention that moved
    # them would be changing what a prayer means, rather than filling in one that has no time.
    untouched() {
      local convention
      local -a rows=()
      for convention in angle seventh middle none; do
        _inzsh_salah_compute 1782043200 64.1466 -21.9426 fajr_angle=18 isha_angle=17 \
          "highlat=$convention"
        rows+="${_inzsh_salah_reply[sunrise]} ${_inzsh_salah_reply[dhuhr]} \
${_inzsh_salah_reply[asr]} ${_inzsh_salah_reply[maghrib]}"
      done
      inzsh_spec_distinct "${rows[@]}"
    }
    When call untouched
    The output should eq '1'
  End

  It 'leaves a prayer absent when told not to divide the night'
    # `none` is a convention too. At 64°N in June there is no astronomical isha, and the honest
    # answer under this setting is that there is not one.
    refusing() {
      _inzsh_salah_compute 1782043200 64.1466 -21.9426 fajr_angle=18 isha_angle=17 highlat=none
      print -r -- "${_inzsh_salah_reply[fajr]} ${_inzsh_salah_reply[isha]}"
    }
    When call refusing
    The output should eq 'none none'
  End

  It 'has no night to divide under a midnight sun, whatever the convention'
    # Every convention measures outward from sunrise and sunset. Where neither exists there is
    # nothing to measure from, and no setting may invent one.
    nightless() {
      local convention
      local -a bad=()
      for convention in angle seventh middle none; do
        _inzsh_salah_compute 1782036000 78.2232 15.6267 fajr_angle=18 isha_angle=17 \
          "highlat=$convention"
        [[ ${_inzsh_salah_reply[fajr]} == none && ${_inzsh_salah_reply[isha]} == none ]] ||
          bad+=$convention
      done
      print -r -- "broken=${bad[*]}"
    }
    When call nightless
    The output should eq 'broken='
  End

  It 'leaves a low latitude alone'
    # The conventions are a repair for a case that does not arise at Mecca. All four settings
    # agree there, which is what says the division only happens when the angle has no solution.
    unneeded() {
      local convention
      local -a rows=()
      for convention in angle seventh middle none; do
        _inzsh_salah_compute 1782032400 21.4225 39.8262 fajr_angle=18 isha_angle=17 \
          "highlat=$convention"
        rows+="${_inzsh_salah_reply[fajr]} ${_inzsh_salah_reply[isha]}"
      done
      inzsh_spec_distinct "${rows[@]}"
    }
    When call unneeded
    The output should eq '1'
  End

  It 'gives an ordered day or an absent one, at every latitude on Earth'
    # The exhaustive gate. Both solstices, both hemispheres, every second degree: each prayer is
    # either the sentinel or an epoch and never anything else, the ones that exist run in the
    # order a day runs, and noon always exists because the sun crosses the meridian everywhere.
    # This is the example that would fail if `acos` were ever handed a value outside its domain
    # and answered with something that parsed.
    sweep() {
      local -i lat checked=0
      local -a bad=()
      local day name previous moment
      for day in 1782043200 1797850800; do
        for (( lat = -88; lat <= 88; lat += 2 )); do
          _inzsh_salah_compute $day $lat 0 fajr_angle=18 isha_angle=17 highlat=angle
          (( checked++ ))
          previous=
          for name in "${_inzsh_salah_prayers[@]}"; do
            moment=${_inzsh_salah_reply[$name]}
            [[ $moment == none ]] && continue
            if [[ $moment != <-> ]]; then
              bad+="$day:$lat:$name:shape"
              continue
            fi
            [[ -n $previous ]] && (( moment <= previous )) && bad+="$day:$lat:$name:order"
            previous=$moment
          done
          (( ${#_inzsh_salah_reply} == 6 )) || bad+="$day:$lat:count"
          [[ ${_inzsh_salah_reply[dhuhr]} == <-> ]] || bad+="$day:$lat:no-noon"
        done
      done
      print -r -- "checked=$checked broken=${bad[*]}"
    }
    When call sweep
    The output should eq 'checked=178 broken='
  End
End

Describe 'time and zones'
  # Everything the calculation produces is an instant. A civil clock reading is made once, at
  # the very end, by strftime — which is the only thing in the process that knows what daylight
  # saving is.

  It 'answers with instants and not with clock readings'
    shape() {
      _inzsh_salah_compute 1785150000 36.7538 3.0588 fajr_angle=18 isha_angle=17
      local name
      local -a bad=()
      for name in "${_inzsh_salah_prayers[@]}"; do
        [[ ${_inzsh_salah_reply[$name]} == <-> ]] || bad+=$name
      done
      print -r -- "${(t)_inzsh_salah_reply} ${#_inzsh_salah_reply} broken=${bad[*]}"
    }
    When call shape
    The output should eq 'association 6 broken='
  End

  It 'gives the same instants whatever zone was used to read the day'
    # The zone chooses a date. It is not an offset and it never enters the arithmetic, so two
    # zones that agree on which day it is agree on all six answers, to the second.
    agnostic() {
      local -a rows=()
      local zone name row
      for zone in UTC Africa/Algiers Europe/London; do
        _inzsh_salah_compute 1785150000 36.7538 3.0588 fajr_angle=18 isha_angle=17 "tz=$zone"
        row=''
        for name in "${_inzsh_salah_prayers[@]}"; do row+="${_inzsh_salah_reply[$name]} "; done
        rows+="$row"
      done
      inzsh_spec_distinct "${rows[@]}"
    }
    When call agnostic
    The output should eq '1'
  End

  Describe 'rounding to the minute'
    # $1 an epoch, $2 the epoch it rounds to. Published prayer times are given to the minute and
    # every oracle rounds rather than truncates, so half past is the boundary and it rounds up.
    Parameters
      0     0
      29    0
      30    60
      59    60
      60    60
      89    60
      90    120
      -1    0
      -30   0
      -31   -60
      1785121585 1785121560
    End

    It "rounds $1 to $2"
      rounded() {
        _inzsh_salah_round_minute "$1"
        print -r -- "$REPLY"
      }
      When call rounded "$1"
      The output should eq "$2"
    End
  End

  Describe 'formatting'
    # $1 an epoch, $2 a zone, $3 the reading. The last two New York rows are the same wall clock
    # an hour apart, on the day the offset changes back — which is the proof that the instant,
    # and not a stored offset, is what reaches strftime.
    Parameters
      1785121585 Africa/Algiers    04:06
      1785121585 UTC               03:06
      1785121585 Pacific/Auckland  15:06
      1772951400 America/New_York  01:30
      1772955000 America/New_York  03:30
      1793511000 America/New_York  01:30
      1793514600 America/New_York  01:30
    End

    It "reads $1 in $2 as $3"
      formatted() {
        _inzsh_salah_format "$1" "$2"
        print -r -- "$REPLY"
      }
      When call formatted "$1" "$2"
      The output should eq "$3"
    End
  End

  It 'distinguishes the repeated hour when asked for the whole instant'
    # The two readings above really are the same clock face. Nothing was lost: the format is
    # what collapsed them, and a format carrying the offset separates them again.
    repeated() {
      local -a seen=()
      _inzsh_salah_format 1793511000 America/New_York '%H:%M %z'; seen+="$REPLY"
      _inzsh_salah_format 1793514600 America/New_York '%H:%M %z'; seen+="$REPLY"
      print -r -- "${seen[1]} / ${seen[2]}"
    }
    When call repeated
    The output should eq '01:30 -0400 / 01:30 -0500'
  End

  It 'stops rounding when the format asks for seconds'
    # The rounding is there so a displayed minute agrees with a published one. A caller that
    # wants the instant says so by asking for it, and then gets it unmoved.
    precise() {
      local -a seen=()
      _inzsh_salah_format 1785121585 UTC; seen+=$REPLY
      _inzsh_salah_format 1785121585 UTC '%H:%M:%S'; seen+=$REPLY
      print -r -- "${seen[*]}"
    }
    When call precise
    The output should eq '03:06 03:06:25'
  End

  Describe 'formatting something that is not an instant'
    # The sentinel arrives here more often than anything else does. Nothing to draw is an empty
    # answer and a failed status — never `00:00`, which is what `strftime` on an unchecked value
    # would have produced.
    Parameters
      none
      ''
      ' '
      abc
      2.5
      00:00
      ' 1785121585'
    End

    It "gives nothing back for '$1'"
      nothing() {
        local answer=drew
        _inzsh_salah_format "$1" UTC || answer=refused
        print -r -- "$answer [$REPLY]"
      }
      When call nothing "$1"
      The output should eq 'refused []'
    End
  End

  It 'leaves the shell zone alone while formatting'
    quiet() {
      local -x TZ=UTC
      local drawn after
      _inzsh_salah_format 1785121585 Pacific/Auckland
      drawn=$REPLY
      strftime -s after '%H:%M' 1785121585
      print -r -- "$drawn $after $TZ"
    }
    When call quiet
    The output should eq '15:06 03:06 UTC'
  End
End

Describe 'a location that is not a location'
  # $1 latitude, $2 longitude. None of these can produce a prayer table, and the answer to all
  # of them is the same: a status the caller may check, and six sentinels for the caller that
  # did not — because a prompt that stops drawing is worse than a prompt that says it does not
  # know.
  Parameters
    ''         3.0588
    abc        3.0588
    91         3.0588
    -91        3.0588
    '36.7538 ' 3.0588
    1e3        3.0588
    36.7538    ''
    36.7538    abc
    36.7538    181
    36.7538    -181
    36.7538    ' 3.0588'
  End

  It "refuses ($1, $2) and answers with sentinels"
    refused() {
      local answer=accepted
      _inzsh_salah_compute 1785150000 "$1" "$2" fajr_angle=18 isha_angle=17 || answer=refused
      local name
      local -a wrong=()
      for name in "${_inzsh_salah_prayers[@]}"; do
        [[ ${_inzsh_salah_reply[$name]} == none ]] || wrong+=$name
      done
      print -r -- "$answer ${#_inzsh_salah_reply} broken=${wrong[*]}"
    }
    When call refused "$1" "$2"
    The output should eq 'refused 6 broken='
  End
End

Describe 'an argument that is not one'
  # A mistyped option is not an error. It is dropped, and the computation proceeds on the
  # defaults — which for a prompt is the difference between a slightly wrong prayer time and no
  # prompt at all.
  Parameters
    'fajr_angle=banana'
    'fajr_angle='
    'fajr_angle=-5'
    'fajr_angle=90'
    'asr_factor=3'
    'asr_factor=x'
    'highlat=chartreuse'
    'highlat='
    'isha_interval=0'
    'isha_interval=abc'
    'nonsense=1'
    'nonsense'
    ''
    '=1'
  End

  It "computes a day anyway with '$1' among the arguments"
    tolerant() {
      local answer=refused
      _inzsh_salah_compute 1785150000 36.7538 3.0588 isha_angle=17 "$1" && answer=computed
      local -a present=()
      [[ ${_inzsh_salah_reply[dhuhr]} == <-> ]] && present+=dhuhr
      [[ ${_inzsh_salah_reply[maghrib]} == <-> ]] && present+=maghrib
      print -r -- "$answer ${present[*]}"
    }
    When call tolerant "$1"
    The output should eq 'computed dhuhr maghrib'
  End

  It 'lets a fixed interval replace an angle rather than fight it'
    # Both forms of isha in one argument list is a configuration nobody meant to write. The
    # interval wins, because it is the more specific instruction: an authority that publishes
    # minutes after maghrib is saying it does not use an angle.
    exclusive() {
      local -a seen=()
      _inzsh_salah_compute 1785150000 36.7538 3.0588 isha_angle=17 isha_interval=90
      seen+=${_inzsh_salah_reply[isha]}
      _inzsh_salah_compute 1785150000 36.7538 3.0588 isha_interval=90
      seen+=${_inzsh_salah_reply[isha]}
      _inzsh_salah_compute 1785150000 36.7538 3.0588
      seen+=${_inzsh_salah_reply[maghrib]}
      print -r -- $(( seen[1] == seen[2] )) $(( seen[1] - seen[3] ))
    }
    When call exclusive
    The output should eq '1 5400'
  End

  It 'leaves isha absent when the interval has nothing to measure from'
    # Ninety minutes after a maghrib that does not happen is not ninety minutes after midnight.
    groundless() {
      _inzsh_salah_compute 1782036000 78.2232 15.6267 fajr_angle=18 isha_interval=90
      print -r -- "${_inzsh_salah_reply[maghrib]} ${_inzsh_salah_reply[isha]}"
    }
    When call groundless
    The output should eq 'none none'
  End
End

Describe 'the seams'
  # The properties that make everything above testable. They are asserted against the source
  # text, because they are properties of the files rather than of any one call.

  It 'never reads the clock'
    # The central constraint. Every entry point takes the instant as an argument; a single
    # `EPOCHSECONDS` here would mean no fixture could pin what "now" is, and the entire oracle
    # matrix would stop being checkable — in one line.
    clockless() {
      setopt local_options extended_glob
      local file line
      local -a bad=()
      for file in "${inzsh_spec_salah_files[@]}"; do
        while IFS= read -r line; do
          [[ ${line##[[:space:]]#} == \#* ]] && continue
          [[ $line == *EPOCHSECONDS* || $line == *EPOCHREALTIME* ]] && bad+="${file:t}:$line"
        done < "$SHELLSPEC_PROJECT_ROOT/$file"
      done
      print -r -- "broken=${bad[*]}"
    }
    When call clockless
    The output should eq 'broken='
  End

  It 'names nothing from the engine'
    # `lib/salah/` imports nothing from `lib/core/`. The dependency points one way on paper, and
    # this is the example that keeps it pointing there: a `_inzsh_config_get` borrowed for
    # convenience would make the arithmetic depend on the prompt.
    unattached() {
      setopt local_options extended_glob
      local file line prefix
      local -a bad=()
      for file in "${inzsh_spec_salah_files[@]}"; do
        while IFS= read -r line; do
          [[ ${line##[[:space:]]#} == \#* ]] && continue
          for prefix in _inzsh_config_ _inzsh_layout_ _inzsh_render_ _inzsh_seg_ _inzsh_token \
                        _inzsh_width _inzsh_truncate _inzsh_detect_ _inzsh_hook _inzsh_ladder; do
            [[ $line == *$prefix* ]] && bad+="${file:t}:$prefix"
          done
        done < "$SHELLSPEC_PROJECT_ROOT/$file"
      done
      print -r -- "broken=${bad[*]}"
    }
    When call unattached
    The output should eq 'broken='
  End

  It 'never starts a subprocess'
    # Trigonometry in a shell is unusual enough that shelling out to a calculator would look
    # reasonable. It is not: this sits behind a prompt, and a fork here is paid every time
    # someone presses return. `$((` is arithmetic and is taken out of the way first.
    forkless() {
      setopt local_options extended_glob
      local file line bare
      local -a bad=()
      for file in "${inzsh_spec_salah_files[@]}"; do
        while IFS= read -r line; do
          [[ ${line##[[:space:]]#} == \#* ]] && continue
          bare=${line//\$\(\(/}
          [[ $bare == *'$('* || $bare == *'`'* ]] && bad+="${file:t}:$line"
        done < "$SHELLSPEC_PROJECT_ROOT/$file"
      done
      print -r -- "${#bad}"
    }
    When call forkless
    The output should eq '0'
  End

  It 'keeps every function it defines inside the theme prefix'
    prefixed() {
      local file line name
      local -a bad=() found=()
      for file in "${inzsh_spec_salah_files[@]}"; do
        while IFS= read -r line; do
          [[ $line == [A-Za-z_]*'() {' ]] || continue
          name=${line%%\(*}
          found+=$name
          [[ $name == _inzsh_salah_* ]] || bad+="${file:t}:$name"
        done < "$SHELLSPEC_PROJECT_ROOT/$file"
      done
      # The count is printed as well, so a pattern that stopped matching anything at all would
      # not pass by finding nothing to complain about.
      print -r -- "${#found} broken=${bad[*]}"
    }
    When call prefixed
    The output should eq '20 broken='
  End
End
