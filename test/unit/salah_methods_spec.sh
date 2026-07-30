Include lib/salah/calc.zsh
Include lib/salah/methods.zsh

# The configuration face of the arithmetic. Nobody sets up a prompt in depression angles: they
# name the authority their masjid follows, or they read two numbers off its noticeboard and
# type those. This file is about the translation, and about the fact that nothing typed into it
# can stop the prompt drawing.
#
# The table itself is checked against `test/fixtures/salah/methods.txt`, which was transcribed
# from the reference oracle's own published parameters. That is the point of the second copy: a
# table of constants with only one copy has nothing to be checked against, and the examples that
# read it are the only reason the numbers in `lib/salah/methods.zsh` are more than an assertion.

typeset -gA inzsh_spec_method_fajr inzsh_spec_method_isha
typeset -ga inzsh_spec_method_names

# Read the fixture. Fields are `name | id | fajr | isha | full name`, whitespace-padded for
# legibility, so each one is trimmed on the way in.
inzsh_spec_methods_load() {
  setopt local_options extended_glob
  (( ${#inzsh_spec_method_names} )) && return 0

  local line field
  local -a fields
  while IFS= read -r line; do
    [[ ${line##[[:space:]]#} == (\#*|'') ]] && continue
    fields=("${(@s:|:)line}")
    (( ${#fields} >= 4 )) || continue
    fields=("${(@)fields//(#s)[[:space:]]##/}")
    fields=("${(@)fields//[[:space:]]##(#e)/}")
    inzsh_spec_method_names+=${fields[1]}
    inzsh_spec_method_fajr[${fields[1]}]=${fields[3]}
    inzsh_spec_method_isha[${fields[1]}]=${fields[4]}
  done < "$SHELLSPEC_PROJECT_ROOT/test/fixtures/salah/methods.txt"

  return 0
}

# The argument list the fixture's row for `$1` describes. Derived rather than transcribed a
# third time: an isha column ending in `min` is an interval, anything else is an angle, and
# that branch is exactly the distinction the table has to keep.
inzsh_spec_method_expected() {
  inzsh_spec_methods_load
  local name=$1 isha=${inzsh_spec_method_isha[$1]}
  if [[ $isha == *min ]]; then
    print -r -- "fajr_angle=${inzsh_spec_method_fajr[$name]} isha_interval=${isha%% min}"
  else
    print -r -- "fajr_angle=${inzsh_spec_method_fajr[$name]} isha_angle=$isha"
  fi
}

inzsh_spec_method_key() {
  _inzsh_salah_method_key "$1"
  print -r -- "$REPLY"
}

# The resolved compute arguments under a given configuration. Every knob is a local, so no
# example can leave a setting behind for the next one.
inzsh_spec_params() {
  local INZSH_SALAH_METHOD=$1 INZSH_SALAH_FAJR_ANGLE=$2 INZSH_SALAH_ISHA_ANGLE=$3
  local INZSH_SALAH_ISHA_INTERVAL=$4 INZSH_SALAH_ASR=$5 INZSH_SALAH_HIGHLAT=$6
  _inzsh_salah_params
  print -r -- "$REPLY"
}

# One key out of a resolved argument list. Written out longhand rather than as a nested
# substitution, because the thing being checked is the value and not the cleverness.
inzsh_spec_param_value() {
  local key=$1 word
  shift
  for word in ${=@}; do
    [[ $word == $key=* ]] && print -r -- "${word#$key=}"
  done

  return 0
}

inzsh_spec_offset() {
  local knob=INZSH_SALAH_OFFSET_${(U)1}
  local -x $knob=$2
  _inzsh_salah_offset_of "$1"
  print -r -- "$REPLY"
}

# --------------------------------------------------------------------------------------------

Describe 'the method table'
  Describe 'against the published parameters'
    # $1 a method name. The expectation is built from the fixture, so this example fails if the
    # table drifts from what the authority publishes — in either direction.
    Parameters
      MWL
      ISNA
      UMMALQURA
      EGYPTIAN
      KARACHI
      ALGERIA
    End

    It "gives $1 the parameters its authority publishes"
      matches() {
        _inzsh_salah_method_params "$1"
        local got=$REPLY
        local want=$(inzsh_spec_method_expected "$1")
        print -r -- "$got"
        [[ $got == $want ]] || print -r -- "expected $want"
      }
      When call matches "$1"
      The lines of output should eq 1
    End
  End

  It 'ships exactly the methods the fixture lists, and no others'
    # The Parameters block above can only check names it was given. This one checks the set —
    # a method added to the table without a published row to check it against fails here.
    census() {
      inzsh_spec_methods_load
      local -a shipped=(${(ko)_inzsh_salah_methods})
      local -a documented=(${(o)inzsh_spec_method_names})
      local verdict="${shipped[*]} != ${documented[*]}"
      [[ ${shipped[*]} == ${documented[*]} ]] && verdict=matched
      print -r -- "${#shipped} $verdict"
    }
    When call census
    The output should eq '6 matched'
  End

  It 'covers both forms of isha'
    # One authority in the table has to use each form, or one of the two branches is never
    # exercised by anything above.
    forms() {
      local -a angles=() intervals=()
      local name
      for name in ${(ko)_inzsh_salah_methods}; do
        [[ ${_inzsh_salah_methods[$name]} == *isha_interval=* ]] && intervals+=$name
        [[ ${_inzsh_salah_methods[$name]} == *isha_angle=* ]] && angles+=$name
      done
      print -r -- "$(( ${#angles} > 0 )) $(( ${#intervals} > 0 ))"
    }
    When call forms
    The output should eq '1 1'
  End

  Describe 'the name someone types'
    # Punctuation and spacing carry no meaning in an authority's name, so they are removed
    # before the lookup. $1 what was typed, $2 the key it reaches.
    Parameters
      MWL                 MWL
      mwl                 MWL
      'Muslim World League' MWL
      isna                ISNA
      'Umm al-Qura'       UMMALQURA
      umm_al_qura         UMMALQURA
      ummalqura           UMMALQURA
      Makkah              UMMALQURA
      mecca               UMMALQURA
      egypt               EGYPTIAN
      Egyptian            EGYPTIAN
      Karachi             KARACHI
      algeria             ALGERIA
      ''                  ''
      '   '               ''
      '???'               ''
    End

    It "reads '$1' as the key '$2'"
      When call inzsh_spec_method_key "$1"
      The output should eq "$2"
    End
  End

  Describe 'a method nobody ships'
    # Never an error, always a prayer table. The status says the name was not recognised, for a
    # caller that wants to say so; the answer is the default either way.
    Parameters
      ''
      '   '
      banana
      'Ministry of Nowhere'
      MWL2
      0
      -1
    End

    It "computes the default for '$1'"
      fallback() {
        local answer=known
        _inzsh_salah_method_params "$1" || answer=unknown
        print -r -- "$answer $REPLY"
      }
      When call fallback "$1"
      The output should eq 'unknown fajr_angle=18 isha_angle=17'
    End
  End
End

Describe 'resolving the configuration'
  Describe 'the shipped defaults'
    # $1 the configured method, $2 everything that reaches the arithmetic. Nothing else is set,
    # so this is also the statement of what the theme does out of the box: MWL, the majority
    # school's asr, and the angle-based high-latitude convention.
    Parameters
      ''          'fajr_angle=18 isha_angle=17 asr_factor=1 highlat=angle'
      MWL         'fajr_angle=18 isha_angle=17 asr_factor=1 highlat=angle'
      ISNA        'fajr_angle=15 isha_angle=15 asr_factor=1 highlat=angle'
      'Umm al-Qura' 'fajr_angle=18.5 isha_interval=90 asr_factor=1 highlat=angle'
      EGYPTIAN    'fajr_angle=19.5 isha_angle=17.5 asr_factor=1 highlat=angle'
      KARACHI     'fajr_angle=18 isha_angle=18 asr_factor=1 highlat=angle'
      ALGERIA     'fajr_angle=18 isha_angle=17 asr_factor=1 highlat=angle'
      banana      'fajr_angle=18 isha_angle=17 asr_factor=1 highlat=angle'
    End

    It "resolves a method of '$1'"
      When call inzsh_spec_params "$1" '' '' '' '' ''
      The output should eq "$2"
    End
  End

  Describe 'an override beating the table'
    # The reason the override knobs exist: an authority the theme does not ship is a
    # two-variable configuration rather than a feature request. $1 fajr, $2 isha angle,
    # $3 isha interval, $4 what reaches the arithmetic — over ISNA, whose own numbers are 15
    # and 15, so a table value surviving where it should not is visible.
    Parameters
      19    ''   ''  'fajr_angle=19 isha_angle=15 asr_factor=1 highlat=angle'
      ''    14   ''  'fajr_angle=15 isha_angle=14 asr_factor=1 highlat=angle'
      19    14   ''  'fajr_angle=19 isha_angle=14 asr_factor=1 highlat=angle'
      ''    ''   90  'fajr_angle=15 isha_interval=90 asr_factor=1 highlat=angle'
      18.5  ''   90  'fajr_angle=18.5 isha_interval=90 asr_factor=1 highlat=angle'
      ''    14   90  'fajr_angle=15 isha_interval=90 asr_factor=1 highlat=angle'
      ''    ''   ''  'fajr_angle=15 isha_angle=15 asr_factor=1 highlat=angle'
    End

    It "resolves fajr='$1' isha='$2' interval='$3' over ISNA"
      When call inzsh_spec_params ISNA "$1" "$2" "$3" '' ''
      The output should eq "$4"
    End
  End

  It 'lets an interval override an authority that publishes an angle, and back again'
    # The two forms are exclusive, and a user has to be able to say either one over a method
    # that says the other. Both directions, because only one of them is the easy case.
    swap() {
      local -a seen=()
      seen+="${$(inzsh_spec_params MWL '' '' 90 '' '')%% asr*}"
      seen+="${$(inzsh_spec_params UMMALQURA '' 17 '' '' '')%% asr*}"
      print -r -- "${seen[1]} / ${seen[2]}"
    }
    When call swap
    The output should eq 'fajr_angle=18 isha_interval=90 / fajr_angle=18.5 isha_angle=17'
  End

  Describe 'an override that is not a number'
    # An angle that cannot be read is not an error and is never reported: it is simply not used,
    # and the method's own value stands. A prompt that stopped drawing over a typo would be a
    # worse outcome than a prayer time from the wrong authority.
    Parameters
      ''
      ' '
      banana
      -18
      0
      0.0
      30.1
      100
      1e1
      '18 '
      ' 18'
      '18,5'
      +18abc
    End

    It "ignores a fajr angle of '$1' and keeps the method's own"
      When call inzsh_spec_params MWL "$1" '' '' '' ''
      The output should eq 'fajr_angle=18 isha_angle=17 asr_factor=1 highlat=angle'
    End
  End

  Describe 'an interval that is not one'
    Parameters
      ''
      ' '
      banana
      0
      -90
      241
      90.5
      +90x
    End

    It "ignores an isha interval of '$1' and keeps the method's own angle"
      When call inzsh_spec_params MWL '' '' "$1" '' ''
      The output should eq 'fajr_angle=18 isha_angle=17 asr_factor=1 highlat=angle'
    End
  End

  It 'accepts the edges of every range it advertises'
    # The refusals above are only meaningful if the boundary on the other side is accepted.
    edges() {
      local -a seen=()
      seen+="${$(inzsh_spec_params MWL 0.1 '' '' '' '')%% *}"
      seen+="${$(inzsh_spec_params MWL 30 '' '' '' '')%% *}"
      seen+="${${$(inzsh_spec_params MWL '' '' 1 '' '')#* }%% *}"
      seen+="${${$(inzsh_spec_params MWL '' '' 240 '' '')#* }%% *}"
      print -r -- "${seen[*]}"
    }
    When call edges
    The output should eq 'fajr_angle=0.1 fajr_angle=30 isha_interval=1 isha_interval=240'
  End

  Describe 'the asr school'
    # $1 what was configured, $2 the shadow factor it resolves to. Anything unreadable is the
    # majority school, which is also the default.
    Parameters
      ''         1
      standard   1
      Standard   1
      shafi      1
      SHAFI      1
      hanafi     2
      Hanafi     2
      HANAFI     2
      banana     1
      2          1
      'hanafi '  1
    End

    It "resolves an asr setting of '$1' to a shadow factor of $2"
      school() {
        inzsh_spec_param_value asr_factor "$(inzsh_spec_params MWL '' '' '' "$1" '')"
      }
      When call school "$1"
      The output should eq "$2"
    End
  End

  Describe 'the high-latitude convention'
    Parameters
      ''          angle
      angle       angle
      Angle       angle
      seventh     seventh
      SEVENTH     seventh
      middle      middle
      none        none
      oneseventh  angle
      banana      angle
      'middle '   angle
    End

    It "resolves a high-latitude setting of '$1' to '$2'"
      convention() {
        inzsh_spec_param_value highlat "$(inzsh_spec_params MWL '' '' '' '' "$1")"
      }
      When call convention "$1"
      The output should eq "$2"
    End
  End

  It 'reads the configuration afresh on every call'
    # A knob changed at a prompt takes effect at the next one, with no re-source and no new
    # shell. Nothing here may be decided at source time.
    live() {
      local INZSH_SALAH_METHOD=MWL
      local -a seen=()
      _inzsh_salah_params; seen+="${REPLY%% asr*}"
      INZSH_SALAH_METHOD=ISNA
      _inzsh_salah_params; seen+="${REPLY%% asr*}"
      INZSH_SALAH_METHOD=
      _inzsh_salah_params; seen+="${REPLY%% asr*}"
      print -r -- "${seen[*]}"
    }
    When call live
    The output should eq \
'fajr_angle=18 isha_angle=17 fajr_angle=15 isha_angle=15 fajr_angle=18 isha_angle=17'
  End
End

Describe 'per-prayer offsets'
  # Most people calibrate against their local masjid rather than against an ephemeris, so every
  # prayer gets its own signed nudge. It is applied to the answer and never fed back into the
  # arithmetic: moving maghrib does not move an isha measured as an interval from it, because a
  # calibration is a statement about the display and not about the sun.

  Describe 'reading the knob'
    # $1 the prayer, $2 what the knob holds, $3 the minutes it resolves to. Unreadable is zero,
    # which is the prayer as computed.
    Parameters
      fajr    5    5
      fajr    -5   -5
      fajr    +5   5
      fajr    0    0
      isha    180  180
      isha    -180 -180
      isha    181  0
      isha    -181 0
      asr     ''   0
      asr     ' '  0
      asr     banana 0
      asr     2.5  0
      asr     ' 5' 0
      asr     '5 ' 0
      maghrib 1e1  0
      sunrise -1   -1
      dhuhr   007  7
    End

    It "resolves an offset of '$2' for $1 to $3 minutes"
      When call inzsh_spec_offset "$1" "$2"
      The output should eq "$3"
    End
  End

  It 'resolves an unset knob to nothing'
    unset_knob() {
      unset INZSH_SALAH_OFFSET_FAJR
      _inzsh_salah_offset_of fajr
      print -r -- "$REPLY"
    }
    When call unset_knob
    The output should eq '0'
  End

  It 'moves one prayer without moving any other'
    # Independence is the whole point: a masjid that calls fajr five minutes late is not calling
    # everything else five minutes late.
    independent() {
      local INZSH_SALAH_METHOD=MWL INZSH_SALAH_OFFSET_FAJR=5
      local -a base=() nudged=()
      local name
      unset INZSH_SALAH_OFFSET_FAJR
      _inzsh_salah_times 1785150000 36.7538 3.0588 Africa/Algiers
      for name in "${_inzsh_salah_prayers[@]}"; do base+=${_inzsh_salah_reply[$name]}; done
      INZSH_SALAH_OFFSET_FAJR=5
      _inzsh_salah_times 1785150000 36.7538 3.0588 Africa/Algiers
      for name in "${_inzsh_salah_prayers[@]}"; do nudged+=${_inzsh_salah_reply[$name]}; done

      local -i i shift_by
      local -a moved=()
      for (( i = 1; i <= ${#base}; i++ )); do
        (( shift_by = nudged[i] - base[i] ))
        (( shift_by != 0 )) && moved+="${_inzsh_salah_prayers[i]}:$shift_by"
      done
      print -r -- "${moved[*]}"
    }
    When call independent
    The output should eq 'fajr:300'
  End

  Describe 'the direction'
    # $1 the minutes configured, $2 the reading at Algiers on the anchor day, whose unmoved isha
    # is 21:35. A sign error would pass an example that only used one direction.
    Parameters
      0    21:35
      5    21:40
      -5   21:30
      60   22:35
      -60  20:35
      181  21:35
    End

    It "reads isha as $2 with an offset of $1"
      nudged() {
        local INZSH_SALAH_METHOD=MWL INZSH_SALAH_OFFSET_ISHA=$1
        _inzsh_salah_times 1785150000 36.7538 3.0588 Africa/Algiers
        _inzsh_salah_format "${_inzsh_salah_reply[isha]}" Africa/Algiers
        print -r -- "$REPLY"
      }
      When call nudged "$1"
      The output should eq "$2"
    End
  End

  It 'leaves an absent prayer absent'
    # An offset from nothing is still nothing. Adding five minutes to the sentinel would turn a
    # prayer that does not happen into one that happens at five past the epoch.
    groundless() {
      local INZSH_SALAH_METHOD=MWL
      local INZSH_SALAH_OFFSET_FAJR=5 INZSH_SALAH_OFFSET_ISHA=-5
      local INZSH_SALAH_OFFSET_SUNRISE=30 INZSH_SALAH_OFFSET_MAGHRIB=30
      _inzsh_salah_times 1782036000 78.2232 15.6267 Arctic/Longyearbyen
      print -r -- "${_inzsh_salah_reply[fajr]} ${_inzsh_salah_reply[sunrise]} \
${_inzsh_salah_reply[maghrib]} ${_inzsh_salah_reply[isha]}"
    }
    When call groundless
    The output should eq 'none none none none'
  End
End

Describe 'the whole pipeline'
  # Configuration in, six instants out. These are the same numbers the oracle matrix pins, run
  # through the configuration layer rather than handed straight to the arithmetic, which is what
  # says the two halves of `lib/salah/` agree about what they are computing.

  Describe 'the anchor day, by name'
    Parameters
      fajr    04:06
      sunrise 05:49
      dhuhr   12:54
      asr     16:44
      maghrib 19:59
      isha    21:35
    End

    It "puts $1 at $2 in Algiers under MWL"
      configured() {
        local INZSH_SALAH_METHOD=MWL
        _inzsh_salah_times 1785150000 36.7538 3.0588 Africa/Algiers
        _inzsh_salah_format "${_inzsh_salah_reply[$1]}" Africa/Algiers
        print -r -- "$REPLY"
      }
      When call configured "$1"
      The output should eq "$2"
    End
  End

  It 'follows the asr school through the configuration'
    schooled() {
      local INZSH_SALAH_METHOD=MWL INZSH_SALAH_ASR=hanafi
      _inzsh_salah_times 1785150000 36.7538 3.0588 Africa/Algiers
      _inzsh_salah_format "${_inzsh_salah_reply[asr]}" Africa/Algiers
      print -r -- "$REPLY"
    }
    When call schooled
    The output should eq '17:53'
  End

  It 'builds an authority it does not ship out of two variables'
    # Umm al-Qura reconstructed from overrides alone, on top of a method that has nothing to do
    # with it. This is the claim the override knobs are for, stated as an example.
    unshipped() {
      local INZSH_SALAH_METHOD=ISNA
      local INZSH_SALAH_FAJR_ANGLE=18.5 INZSH_SALAH_ISHA_INTERVAL=90
      local -a built=() shipped=()
      local name
      _inzsh_salah_times 1782032400 21.4225 39.8262 Asia/Riyadh
      for name in "${_inzsh_salah_prayers[@]}"; do built+=${_inzsh_salah_reply[$name]}; done
      INZSH_SALAH_METHOD=UMMALQURA
      INZSH_SALAH_FAJR_ANGLE=
      INZSH_SALAH_ISHA_INTERVAL=
      _inzsh_salah_times 1782032400 21.4225 39.8262 Asia/Riyadh
      for name in "${_inzsh_salah_prayers[@]}"; do shipped+=${_inzsh_salah_reply[$name]}; done
      print -r -- "$(( ${#built} == 6 )) $([[ ${built[*]} == ${shipped[*]} ]] && print same)"
    }
    When call unshipped
    The output should eq '1 same'
  End

  It 'refuses a location and still hands back six sentinels'
    # The status is available to a caller that wants it. The reply is safe for the caller that
    # forgot, which in a prompt is most of them.
    refused() {
      local INZSH_SALAH_METHOD=MWL
      local answer=accepted
      _inzsh_salah_times 1785150000 banana 3.0588 Africa/Algiers || answer=refused
      local name
      local -a wrong=()
      for name in "${_inzsh_salah_prayers[@]}"; do
        [[ ${_inzsh_salah_reply[$name]} == none ]] || wrong+=$name
      done
      print -r -- "$answer ${#_inzsh_salah_reply} broken=${wrong[*]}"
    }
    When call refused
    The output should eq 'refused 6 broken='
  End

  It 'reads no configuration outside its own namespace'
    # Everything this layer reads is an `INZSH_SALAH_` variable. A knob outside that prefix
    # would be a name collision waiting to happen in somebody else's zshrc.
    namespaced() {
      setopt local_options extended_glob
      local line word
      local -a bad=()
      while IFS= read -r line; do
        [[ ${line##[[:space:]]#} == \#* ]] && continue
        for word in ${(s: :)line}; do
          [[ $word == *INZSH_* ]] || continue
          # Take the identifier out of whatever punctuation it was written inside — the name is
          # what matters, not the `${…}` or the quoting around it.
          word=INZSH_${word#*INZSH_}
          word=${word%%[^A-Z0-9_]*}
          [[ $word == INZSH_SALAH_?* ]] || bad+=$word
        done
      done < "$SHELLSPEC_PROJECT_ROOT/lib/salah/methods.zsh"
      print -r -- "broken=${bad[*]}"
    }
    When call namespaced
    The output should eq 'broken='
  End
End
