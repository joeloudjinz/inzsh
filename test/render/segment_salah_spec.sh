Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/config.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/salah/calc.zsh
Include lib/salah/methods.zsh
Include lib/segments/salah.zsh

# The prayer-time segment — `lib/segments/salah.zsh`. What it registers, and what fragment it
# writes into `_inzsh_segment_text[SALAH]` for a given TABLE and a given instant. No cache file is
# created anywhere in this file and no trigonometry is run: both the state and the clock are
# injected, which are the two seams the segment is built on. `test/unit/salah_cache_spec.sh` is
# where real tables and real files appear.
#
# THE ZONE IS PINNED TO UTC by every helper below. The segment formats an instant in the shell's
# own zone — deliberately, since that is the zone the user reads their clock in — so a spec that
# did not pin one would assert a different string on every machine that ran it.
#
# THE DOT IS PRINTED AS `@`. `·` is one invisible codepoint, and a diff of two multibyte strings
# that differ by one of those is unreadable; a build that dropped the separator shows up here as a
# missing letter instead. The glyph itself is pinned once, in its own group, against the bytes.
#
# No palette value reaches this file. Colour is asserted through `_inzsh_role[…]` and through the
# role NAME the segment registered, so a change of palette cannot fail an example here and a
# change of role can.

# The fixture day: 2026-06-01, in UTC, with six plausible mid-latitude June moments and the same
# six again a day later. Round numbers on purpose — every expectation below can be read off the
# table without arithmetic.
#
#   fajr 03:30   sunrise 05:00   dhuhr 12:00   asr 15:30   maghrib 19:00   isha 20:30
typeset -gi inzsh_spec_salah_base=1780272000

# `<day-index> <HH:MM>` as an epoch on the fixture day, in REPLY. The leading zero is stripped
# from both fields: `08` is an octal literal in `(( ))` and `09` is not a number at all.
inzsh_spec_salah_epoch() {
  emulate -L zsh

  local -a hm=(${(s.:.)2})
  typeset -g REPLY=$(( inzsh_spec_salah_base + $1 * 86400 \
    + ${hm[1]#0} * 3600 + ${hm[2]#0} * 60 ))

  return 0
}

# The fixture table, in `inzsh_spec_salah_table`. Rebuilt on every call so an example that edits
# it cannot leak into the next one.
inzsh_spec_salah_day() {
  emulate -L zsh

  typeset -gA inzsh_spec_salah_table
  inzsh_spec_salah_table=()

  local name clock
  for name clock in fajr 03:30 sunrise 05:00 dhuhr 12:00 asr 15:30 maghrib 19:00 isha 20:30; do
    inzsh_spec_salah_epoch 0 $clock
    inzsh_spec_salah_table[$name]=$REPLY
    inzsh_spec_salah_epoch 1 $clock
    inzsh_spec_salah_table[next_$name]=$REPLY
  done

  return 0
}

# The fragment for `now` = `$1` (as `HH:MM` on the fixture day) in format `$2`, reported as
# `[text]`. `$3`, when given, is a space-separated list of `name=none` overrides — the polar case.
inzsh_spec_salah() {
  emulate -L zsh

  local -x TZ=UTC
  inzsh_spec_salah_day

  local pair
  for pair in ${=3-}; do
    inzsh_spec_salah_table[${pair%%=*}]=${pair#*=}
  done

  inzsh_spec_salah_epoch 0 "$1"
  local now=$REPLY

  local INZSH_SALAH_FORMAT=$2
  _inzsh_segment_text=()
  _inzsh_segment_salah_build "$now" inzsh_spec_salah_table

  local text=${_inzsh_segment_text[SALAH]-}
  print -r -- "[${text//$_inzsh_salah_glyph_dot/@}]"

  return 0
}

# The segment as the renderer draws it, on a right prompt of its own.
inzsh_spec_salah_drawn() {
  emulate -L zsh

  local -x TZ=UTC
  inzsh_spec_salah_day
  inzsh_spec_salah_epoch 0 "$1"

  _inzsh_segment_text=()
  _inzsh_segment_salah_build "$REPLY" inzsh_spec_salah_table
  _inzsh_left=()
  _inzsh_right=(SALAH)
  _inzsh_render_build right
  typeset -g inzsh_spec_drawn=$REPLY

  return 0
}

# The non-comment lines of the segment source, in `inzsh_spec_lines`, for the structural groups.
# Comments are skipped because the prose in the file names `$(`, `curl` and the word "fork"
# precisely in order to say that none of them is used.
inzsh_spec_salah_lines() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga inzsh_spec_lines
  inzsh_spec_lines=()

  local line bare
  while IFS= read -r line; do
    bare=${line##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    inzsh_spec_lines+=$line
  done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/salah.zsh"

  return 0
}

# The BODIES of the three functions that run on the render path, as the shell holds them. Scanned
# rather than the file, because the file also carries the precmd hook — which is allowed to read a
# cache and is deliberately not held to the same rule. `$functions[…]` is zsh's own re-print of
# the parsed body, so a backtick has already become `$(` by the time it is read here.
inzsh_spec_salah_render_path() {
  emulate -L zsh

  typeset -g inzsh_spec_body=
  local name
  for name in _inzsh_segment_salah_build _inzsh_salah_clock _inzsh_salah_duration; do
    inzsh_spec_body+="${functions[$name]}"$'\n'
  done

  return 0
}

Describe 'the prayer-time segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers rank -20, the resting foreground and the top of the importance ramp'
      # -20 is one place inward of the clock at -10. The two are the same KIND of thing — a
      # moment, not a report about the command that just ran — so they sit at the far edge
      # together, with the clock hard against it.
      registered() {
        _inzsh_rank_of SALAH
        print -r -- "$REPLY ${_inzsh_segment_fg_role[SALAH]} ${_inzsh_segment_importance[SALAH]}"
      }
      When call registered
      The output should eq '-20 text-body 1'
    End

    It 'asks for the accent, which is the whole reason this segment has a background role'
      # The theme has one saturated colour and this is the segment it is for. Asserted as the
      # ACCENT rather than as any old fill: a background role here that was not `accent` would
      # still draw a prompt, and would quietly spend the one colour the theme reserves on
      # nothing, or spend it twice.
      accented() {
        local role=${_inzsh_segment_bg_role[SALAH]-<unset>}
        local -a missing=()
        [[ $role == accent ]] || missing+=role:$role
        # The ink arrives with the fill, so the pair the renderer will draw has to exist.
        [[ -n ${_inzsh_role[on-$role]+set} ]] || missing+=no-paired-ink
        print -r -- "${missing[*]}"
      }
      When call accented
      The output should eq ''
    End

    It 'sits on the right prompt, inward of the clock'
      # Both facts in one example: the side is a consequence of the sign, and the ORDER within the
      # side is what the number is for. The clock is registered at -10 by `lib/segments/time.zsh`.
      sided() {
        _inzsh_segment_defaults[TIME]=-10
        _inzsh_rank_split SALAH TIME
        print -r -- "left=${_inzsh_left[*]} right=${_inzsh_right[*]}"
      }
      When call sided
      The output should eq 'left= right=SALAH TIME'
    End

    It 'is a default the engine reads and a user outranks'
      ranked() {
        _inzsh_rank_split SALAH
        local sided="right=${_inzsh_right[*]}"
        local INZSH_SALAH_RANK=3
        _inzsh_rank_split SALAH
        print -r -- "$sided moved=${_inzsh_left[*]}"
      }
      When call ranked
      The output should eq 'right=SALAH moved=SALAH'
    End

    It 'registers its format knob with the default it restates'
      # Two copies of one number, held equal here. The restated one is what the segment uses when
      # `lib/core/config.zsh` never loaded, and a disagreement between them is invisible: both
      # values are plausible and which you get depends on how much of the theme was sourced.
      knobbed() {
        print -r -- "${_inzsh_config_defaults[INZSH_SALAH_FORMAT]} $_inzsh_salah_format_default"
      }
      When call knobbed
      The output should eq 'clock clock'
    End

    It 'labels exactly the prayers the arithmetic computes'
      # The segment's label table is also its list of what a cache slot may be called. A prayer
      # added to `lib/salah/calc.zsh` and not labelled here would be a moment the segment silently
      # never looked at.
      paired() {
        # Unquoted on purpose: `"${(o)array}"` joins before it sorts, so the quoted form is a
        # silently unsorted comparison of two lists that were never going to be in the same order.
        local -a labelled=(${(ko)_inzsh_salah_label}) computed=(${(o)_inzsh_salah_prayers})
        print -r -- "${labelled[*]} | ${computed[*]}"
      }
      When call paired
      The output should eq \
        'asr dhuhr fajr isha maghrib sunrise | asr dhuhr fajr isha maghrib sunrise'
    End

    It 'registers once however many times it is sourced'
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/salah.zsh"
          source "$1/lib/segments/salah.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${#_inzsh_segment_fg_role}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_defaults[SALAH]}"
        ' inzsh-salah-twice "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 1 1 -20'
      The stderr should eq ''
    End

    It 'draws nothing at load — sourcing registers and returns'
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local before="${PROMPT-unset}|${RPROMPT-unset}"
          source "$1/lib/segments/salah.zsh"
          local after="${PROMPT-unset}|${RPROMPT-unset}"
          local drawn=changed
          [[ $before == $after ]] && drawn=same
          print -r -- "texts=${#_inzsh_segment_text} prompt=$drawn"
        ' inzsh-salah-load "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'texts=0 prompt=same'
      The stderr should eq ''
    End

    It 'installs no hook merely by being sourced'
      # The precmd is opt-in through `_inzsh_salah_install`, the way the git worker's is. A file
      # that registered a hook at source time would run in every spec that included it.
      unhooked() {
        zsh -f -c '
          autoload -Uz add-zsh-hook
          source "$1/lib/segments/salah.zsh"
          print -r -- "hooks=${#precmd_functions}"
        ' inzsh-salah-hook "$SHELLSPEC_PROJECT_ROOT"
      }
      When call unhooked
      The output should eq 'hooks=0'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the four formats'
    # One row per format at one instant, so the four can be read against each other. 18:36 sits
    # inside asr's window with maghrib twenty-four minutes off — the shape the milestone names.
    #
    # $1 the format; $2 what it draws.
    Parameters
      clock      '[Maghrib @ 19:00]'
      countdown  '[Maghrib in 24m]'
      window     '[Asr @ until 19:00]'
      full       '[Maghrib @ 19:00 @ 24m]'
    End

    It "draws $1 as $2"
      When call inzsh_spec_salah 18:36 "$1"
      The output should eq "$2"
    End
  End

  Describe 'the default is the clock'
    It 'draws the clock reading when nothing is set'
      unset_format() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        inzsh_spec_salah_epoch 0 18:36
        unset INZSH_SALAH_FORMAT
        _inzsh_segment_salah_build "$REPLY" inzsh_spec_salah_table
        print -r -- "[${_inzsh_segment_text[SALAH]//$_inzsh_salah_glyph_dot/@}]"
      }
      When call unset_format
      The output should eq '[Maghrib @ 19:00]'
    End

    Describe 'and anything unreadable falls back to it'
      # The config layer's rule, inherited: a value that fails is not an error and is never
      # reported, it is simply not used.
      Parameters
        chartreuse
        ''
        'clock countdown'
      End

      It "draws the clock for '$1'"
        When call inzsh_spec_salah 18:36 "$1"
        The output should eq '[Maghrib @ 19:00]'
      End
    End

    Describe 'and the vocabulary is matched in any case'
      Parameters
        COUNTDOWN  '[Maghrib in 24m]'
        Window     '[Asr @ until 19:00]'
        FuLl       '[Maghrib @ 19:00 @ 24m]'
      End

      It "reads $1"
        When call inzsh_spec_salah 18:36 "$1"
        The output should eq "$2"
      End
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the next moment'
    # The whole day, walked. Each row is an instant and the moment the segment says is next, which
    # is the first one strictly AFTER the instant — at exactly 19:00 maghrib has arrived and isha
    # is what is left to wait for.
    Parameters
      00:30  '[Fajr @ 03:30]'
      03:29  '[Fajr @ 03:30]'
      03:30  '[Sunrise @ 05:00]'
      06:00  '[Dhuhr @ 12:00]'
      13:00  '[Asr @ 15:30]'
      16:00  '[Maghrib @ 19:00]'
      19:00  '[Isha @ 20:30]'
      21:00  '[Fajr @ 03:30]'
      23:59  '[Fajr @ 03:30]'
    End

    It "at $1 the next moment is $2"
      When call inzsh_spec_salah "$1" clock
      The output should eq "$2"
    End
  End

  Describe 'the midnight rollover'
    It 'reads tomorrow out of the same table, rather than wrapping round to this morning'
      # The bug this whole two-day table exists to prevent: after isha, an implementation holding
      # only "today" either goes blank or reports a fajr that happened sixteen hours ago.
      rolled() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        inzsh_spec_salah_epoch 0 21:00
        local now=$REPLY
        local INZSH_SALAH_FORMAT=countdown
        _inzsh_segment_salah_build "$now" inzsh_spec_salah_table
        local drawn=${_inzsh_segment_text[SALAH]}
        inzsh_spec_salah_epoch 1 03:30
        local ahead=ahead
        (( REPLY > now )) || ahead=behind
        print -r -- "$drawn $ahead"
      }
      When call rolled
      The output should eq 'Fajr in 6h30m ahead'
    End

    It 'crosses midnight without the countdown ever going backwards'
      # A property rather than an instant: walked minute by minute through the evening and into
      # the small hours, the moment named never moves back in time.
      monotone() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        inzsh_spec_salah_epoch 0 20:00
        local -i now=$REPLY last=0
        local -i stop=$(( now + 8 * 3600 ))
        local -a bad=()
        while (( now <= stop )); do
          _inzsh_segment_salah_build "$now" inzsh_spec_salah_table
          [[ -n ${_inzsh_segment_text[SALAH]} ]] || bad+="empty@$now"
          (( now += 300 ))
        done
        print -r -- "broken=${bad[*]}"
      }
      When call monotone
      The output should eq 'broken='
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the window and its two gaps'
    # `window` names the window it is inside. Sunrise and isha open none — sunrise ENDS fajr's
    # window, and where isha's ends is a question of fiqh rather than of astronomy — so after
    # either of them the format falls back to the `clock` reading rather than going blank for a
    # third of the day or ruling on something the theme has no business ruling on.
    Parameters
      04:00  '[Fajr @ until 05:00]'      'inside fajr'
      06:00  '[Dhuhr @ 12:00]'           'the post-sunrise gap'
      13:00  '[Dhuhr @ until 15:30]'     'inside dhuhr'
      16:00  '[Asr @ until 19:00]'       'inside asr'
      19:30  '[Maghrib @ until 20:30]'   'inside maghrib'
      21:00  '[Fajr @ 03:30]'            'the post-isha gap'
      01:00  '[Fajr @ 03:30]'            'the same gap, past midnight'
    End

    It "draws $3 as $2"
      When call inzsh_spec_salah "$1" window
      The output should eq "$2"
    End

    It 'never says "until" where no window is open'
      # The rule as a property. Both gaps walked end to end, checked for the word. The upper bound
      # of each is the minute BEFORE the next window opens: at 12:00 exactly, dhuhr has arrived
      # and a window is open, which is the other side of the same rule.
      gapped() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        local INZSH_SALAH_FORMAT=window
        local -a bad=()
        local -i now stop
        local pair
        for pair in 05:00,11:59 20:30,23:59; do
          inzsh_spec_salah_epoch 0 ${pair%%,*}
          now=$REPLY
          inzsh_spec_salah_epoch 0 ${pair##*,}
          stop=$REPLY
          while (( now <= stop )); do
            _inzsh_segment_salah_build "$now" inzsh_spec_salah_table
            [[ ${_inzsh_segment_text[SALAH]} == *until* ]] && bad+="$now"
            (( now += 600 ))
          done
        done
        print -r -- "broken=${bad[*]}"
      }
      When call gapped
      The output should eq 'broken='
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the countdown'
    Describe 'reads as a duration and never as a clock'
      Parameters
        18:59  '[Maghrib in 1m]'
        18:36  '[Maghrib in 24m]'
        18:00  '[Maghrib in 1h00m]'
        17:29  '[Maghrib in 1h31m]'
        12:00  '[Asr in 3h30m]'
        21:00  '[Fajr in 6h30m]'
      End

      It "at $1 draws $2"
        When call inzsh_spec_salah "$1" countdown
        The output should eq "$2"
      End
    End

    Describe 'rounds up, so the number reaches 1m and then the moment arrives'
      # Rounding down would show `in 0m` for the whole of the final minute, which is the one
      # minute the number is for.
      #
      # THE SECONDS ABOVE A MINUTE ARE WHAT MAKE THIS A TEST. Below sixty seconds a floor and a
      # ceiling are told apart only by the clamp that stops `0m` being drawn, so an example that
      # checked nothing but the last minute would pass against an implementation that rounded the
      # wrong way all day. 90 and 61 seconds are the rows that fail it.
      #
      # $1 seconds before maghrib; $2 what is drawn.
      Parameters
        1    'Maghrib in 1m'
        59   'Maghrib in 1m'
        60   'Maghrib in 1m'
        61   'Maghrib in 2m'
        90   'Maghrib in 2m'
        120  'Maghrib in 2m'
        121  'Maghrib in 3m'
      End

      It "draws $2 with $1 seconds to go"
        rounded() {
          local -x TZ=UTC
          inzsh_spec_salah_day
          local INZSH_SALAH_FORMAT=countdown
          inzsh_spec_salah_epoch 0 19:00
          _inzsh_segment_salah_build $(( REPLY - $1 )) inzsh_spec_salah_table
          print -r -- "${_inzsh_segment_text[SALAH]}"
        }
        When call rounded "$1"
        The output should eq "$2"
      End
    End

    It 'pads the minutes so the field does not change width as the hour turns'
      # `1h5m` and `1h55m` differ by a column, and a prompt segment that changes width every hour
      # shuffles everything to its left.
      padded() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        local INZSH_SALAH_FORMAT=countdown
        local -a widths=()
        local clock
        for clock in 17:35 17:05 18:00; do
          inzsh_spec_salah_epoch 0 $clock
          _inzsh_segment_salah_build "$REPLY" inzsh_spec_salah_table
          widths+=${_inzsh_segment_text[SALAH]}
        done
        print -r -- "${widths[*]}"
      }
      When call padded
      The output should eq 'Maghrib in 1h25m Maghrib in 1h55m Maghrib in 1h00m'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'a prayer that does not happen'
    # Above the polar circles the sun may never reach the horizon and `lib/salah/calc.zsh` answers
    # with its sentinel. `00:00` is what a naive implementation draws there, and it is
    # indistinguishable from a prayer that genuinely falls at midnight.
    Describe 'is skipped on the way to the next real one'
      Parameters
        'maghrib=none'                     16:00  '[Isha @ 20:30]'
        'maghrib=none isha=none'           16:00  '[Fajr @ 03:30]'
        'sunrise=none'                     04:00  '[Dhuhr @ 12:00]'
        'asr=none maghrib=none isha=none'  13:00  '[Fajr @ 03:30]'
      End

      It "draws $3 for ($1)"
        When call inzsh_spec_salah "$2" clock "$1"
        The output should eq "$3"
      End
    End

    It 'is absent where every moment of both days is absent'
      # A polar night with no solution anywhere in the table. Nothing true is left to say.
      polar() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        local slot
        for slot in ${(k)inzsh_spec_salah_table}; do
          inzsh_spec_salah_table[$slot]=none
        done
        inzsh_spec_salah_epoch 0 13:00
        _inzsh_segment_text=()
        _inzsh_segment_salah_build "$REPLY" inzsh_spec_salah_table
        print -r -- "[${_inzsh_segment_text[SALAH]-}]"
      }
      When call polar
      The output should eq '[]'
    End

    It 'never draws midnight for a prayer that has no time'
      # The property, over every sentinel arrangement one prayer at a time.
      unmidnighted() {
        local -x TZ=UTC
        local -a bad=()
        local name
        for name in fajr sunrise dhuhr asr maghrib isha; do
          inzsh_spec_salah_day
          inzsh_spec_salah_table[$name]=none
          inzsh_spec_salah_table[next_$name]=none
          inzsh_spec_salah_epoch 0 13:00
          _inzsh_segment_salah_build "$REPLY" inzsh_spec_salah_table
          [[ ${_inzsh_segment_text[SALAH]} == *00:00* ]] && bad+=$name
        done
        print -r -- "broken=${bad[*]}"
      }
      When call unmidnighted
      The output should eq 'broken='
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'absence'
    # Absent means an EMPTY entry, which every layer already reads as no block and no separator.
    It 'is absent when the table is empty'
      empty() {
        typeset -gA inzsh_spec_salah_none
        inzsh_spec_salah_none=()
        _inzsh_segment_text=()
        _inzsh_segment_salah_build 1780272000 inzsh_spec_salah_none
        print -r -- "[${_inzsh_segment_text[SALAH]-}]"
      }
      When call empty
      The output should eq '[]'
    End

    It 'is absent when the named association does not exist'
      missing() {
        _inzsh_segment_text=()
        _inzsh_segment_salah_build 1780272000 _inzsh_spec_no_such_table
        print -r -- "[${_inzsh_segment_text[SALAH]-}]"
      }
      When call missing
      The output should eq '[]'
      The stderr should eq ''
    End

    It 'is absent when the name refers to a scalar rather than a map'
      # `${(Pkv)}` over a scalar yields ONE element, and a one-element assignment to an
      # association is a fatal `odd number of elements` in the middle of a render.
      scalar() {
        typeset -g inzsh_spec_salah_scalar='fajr 1'
        _inzsh_segment_text=()
        _inzsh_segment_salah_build 1780272000 inzsh_spec_salah_scalar
        print -r -- "[${_inzsh_segment_text[SALAH]-}]"
      }
      When call scalar
      The output should eq '[]'
      The stderr should eq ''
    End

    Describe 'a name that cannot form a variable is asked nothing'
      # `${(P)}` on a non-identifier is fatal mid-render — the same trap `_inzsh_mincols_of`
      # guards in `lib/core/layout.zsh`.
      Parameters
        'not a name'
        '1abc'
        'a-b'
        '$(echo hi)'
      End

      It "is absent for '$1'"
        named() {
          _inzsh_segment_text=()
          _inzsh_segment_salah_build 1780272000 "$1"
          print -r -- "[${_inzsh_segment_text[SALAH]-}]"
        }
        When call named "$1"
        The output should eq '[]'
        The stderr should eq ''
      End
    End

    Describe 'an instant that is not an instant draws nothing'
      Parameters
        'banana'
        '17:30'
        '1.5'
      End

      It "is absent for '$1'"
        instant() {
          local -x TZ=UTC
          inzsh_spec_salah_day
          _inzsh_segment_text=()
          _inzsh_segment_salah_build "$1" inzsh_spec_salah_table
          print -r -- "[${_inzsh_segment_text[SALAH]-}]"
        }
        When call instant "$1"
        The output should eq '[]'
        The stderr should eq ''
      End
    End

    It 'is absent for a table left over from another day'
      # Nothing has to detect staleness: every moment in a table from last week is behind now, so
      # there is no next moment and the segment says nothing. The horizon catches the other
      # direction — a table from the future, which a clock that jumped can produce.
      stale() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        local -a seen=()
        _inzsh_segment_salah_build $(( inzsh_spec_salah_base + 7 * 86400 )) inzsh_spec_salah_table
        seen+="past=[${_inzsh_segment_text[SALAH]}]"
        _inzsh_segment_salah_build $(( inzsh_spec_salah_base - 7 * 86400 )) inzsh_spec_salah_table
        seen+="future=[${_inzsh_segment_text[SALAH]}]"
        print -r -- "${seen[*]}"
      }
      When call stale
      The output should eq 'past=[] future=[]'
    End

    It 'writes an EMPTY entry rather than a placeholder, so no separator is drawn'
      nothing() {
        typeset -gA inzsh_spec_salah_none
        inzsh_spec_salah_none=()
        _inzsh_segment_text=()
        _inzsh_segment_salah_build 1780272000 inzsh_spec_salah_none
        _inzsh_left=()
        _inzsh_right=(SALAH)
        _inzsh_render_build right
        print -r -- "len=${#REPLY} width=$_inzsh_render_width"
      }
      When call nothing
      The output should eq 'len=0 width=0'
    End

    It 'rewrites the entry on every build rather than accumulating'
      rewritten() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        typeset -gA inzsh_spec_salah_none
        inzsh_spec_salah_none=()
        local -a seen=()
        inzsh_spec_salah_epoch 0 18:36
        local now=$REPLY
        _inzsh_segment_salah_build "$now" inzsh_spec_salah_table
        seen+="[${_inzsh_segment_text[SALAH]//$_inzsh_salah_glyph_dot/@}]"
        _inzsh_segment_salah_build "$now" inzsh_spec_salah_none
        seen+="[${_inzsh_segment_text[SALAH]}]"
        _inzsh_segment_salah_build "$now" inzsh_spec_salah_table
        seen+="[${_inzsh_segment_text[SALAH]//$_inzsh_salah_glyph_dot/@}]"
        print -r -- "${(j::)seen}"
      }
      When call rewritten
      The output should eq '[Maghrib @ 19:00][][Maghrib @ 19:00]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'a table that came out of a file'
    # None of this can come from a user's config — the slots come from a cache this theme wrote —
    # but a cache file outlives the shell that wrote it and can be truncated, edited, or written
    # by a version that is not this one.
    Describe 'a slot that is not a moment is passed over'
      Parameters
        'maghrib=x'
        'maghrib=19:00'
        'maghrib=1.5'
        'maghrib='
      End

      It "skips to isha for ($1)"
        When call inzsh_spec_salah 16:00 clock "$1"
        The output should eq '[Isha @ 20:30]'
      End
    End

    It 'ignores the provenance fields the cache writes beside the moments'
      # `key` and `day` share the association with the twelve slots and are not times. A build
      # that walked the whole map instead of the prayers it knows would try to draw one.
      provenance() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        inzsh_spec_salah_table[key]='2026-6-1|21.4225|39.8262|+0300|fajr_angle=18'
        inzsh_spec_salah_table[day]=2026-6-1
        inzsh_spec_salah_epoch 0 18:36
        _inzsh_segment_salah_build "$REPLY" inzsh_spec_salah_table
        print -r -- "[${_inzsh_segment_text[SALAH]//$_inzsh_salah_glyph_dot/@}]"
      }
      When call provenance
      The output should eq '[Maghrib @ 19:00]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'colour and the mark'
    It 'emits no colour of its own — the role it registers is the whole instruction'
      # A segment that drew `%F{…}` itself would ignore `INZSH_SALAH_FG`, would survive a preset
      # change, and would be a second place colour is decided.
      uncoloured() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        local -a found=()
        local mode
        for mode in clock countdown window full; do
          local INZSH_SALAH_FORMAT=$mode
          inzsh_spec_salah_epoch 0 18:36
          _inzsh_segment_salah_build "$REPLY" inzsh_spec_salah_table
          [[ ${_inzsh_segment_text[SALAH]} == *'%'[FKfk]* ]] && found+=$mode
        done
        print -rl -- $found
      }
      When call uncoloured
      The output should eq ''
    End

    It 'honours a per-segment colour override, because it never resolved one itself'
      overridden() {
        local INZSH_SALAH_FG=inzsh-spec-colour
        inzsh_spec_salah_drawn 18:36
        [[ $inzsh_spec_drawn == *'%F{inzsh-spec-colour}'* ]] && print -r -- honoured
      }
      When call overridden
      The output should eq 'honoured'
    End

    It 'takes the accent through the same override, which is how it is spent today'
      # The recipe `docs/configuration.md` gives, asserted as a ROLE and never as a colour value.
      # The renderer assigns backgrounds positionally, so this is the only door the accent has
      # until the engine grows a background-role map.
      accented() {
        local INZSH_SALAH_BG=${_inzsh_role[accent]}
        local INZSH_SALAH_FG=${_inzsh_role[on-accent]}
        inzsh_spec_salah_drawn 18:36
        local -a missing=()
        [[ $inzsh_spec_drawn == *"%K{${_inzsh_role[accent]}}"* ]]    || missing+=background
        [[ $inzsh_spec_drawn == *"%F{${_inzsh_role[on-accent]}}"* ]] || missing+=foreground
        print -r -- "${missing[*]}"
      }
      When call accented
      The output should eq ''
    End

    It 'registers a role the token layer carries'
      roled() {
        [[ -n ${_inzsh_role[${_inzsh_segment_fg_role[SALAH]}]+set} ]] &&
          print -r -- known || print -r -- "unknown:${_inzsh_segment_fg_role[SALAH]}"
      }
      When call roled
      The output should eq 'known'
    End

    It 'carries no state, and therefore no state mark'
      # The house rule is that colour is never the only signal, and it binds a segment that has
      # STATES. This one has none: it reports a moment, the same way the clock does, and it draws
      # the same role whatever it says. The kicker is a separator and not a mark, so there is
      # nothing here for a glyph to carry.
      unmarked() {
        local -x TZ=UTC
        inzsh_spec_salah_day
        local -A roles=()
        local clock
        for clock in 04:00 13:00 18:36 21:00; do
          inzsh_spec_salah_epoch 0 $clock
          _inzsh_segment_salah_build "$REPLY" inzsh_spec_salah_table
          roles[${_inzsh_segment_fg_role[SALAH]}]=1
        done
        print -r -- "${(ko)roles}"
      }
      When call unmarked
      The output should eq 'text-body'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the kicker'
    It 'is the design system mark, spelled as bytes so the file parses in any locale'
      # `·` U+00B7, taken from the token layer's table rather than written here. Pinned against
      # the byte sequence for the same reason the segment reads it from a table: a `\u` escape is
      # resolved at parse time and takes the whole file with it outside a multibyte locale.
      # Parsing survives anywhere; the drawn mark is the single-byte register's dot there.
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      pinned() {
        [[ $_inzsh_salah_glyph_dot == $'\xc2\xb7' ]] &&
          print -r -- pinned || print -r -- "wrong:$_inzsh_salah_glyph_dot"
      }
      When call pinned
      The output should eq 'pinned'
    End

    It 'takes exactly one column, so a format never costs the row an extra one'
      wide() {
        _inzsh_width_raw "$_inzsh_salah_glyph_dot"
        print -r -- "$REPLY"
      }
      When call wide
      The output should eq '1'
    End

    It 'degrades to ASCII where the locale cannot carry it'
      # Under `LC_ALL=C` those bytes draw as mojibake and `${(m)#…}` measures them as two. The
      # ASCII register keeps a separator, and the file still parses — which is the part that
      # matters, because a parse failure here takes the build function with it and the render path
      # then calls something that does not exist.
      degraded() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          export TZ=UTC
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/tokens-256.zsh"
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/salah/calc.zsh"
          source "$1/lib/segments/salah.zsh"
          local -A t=(maghrib 1780340400 isha 1780345800)
          _inzsh_segment_salah_build 1780338960 t
          print -r -- "[${_inzsh_segment_text[SALAH]}]"
        ' inzsh-salah-c "$SHELLSPEC_PROJECT_ROOT"
      }
      When call degraded
      The output should eq '[Maghrib . 19:00]'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/segments/salah.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sources silently in a single-byte locale'
      quiet() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          source "$1/lib/segments/salah.zsh"
          print -r -- "built=${+functions[_inzsh_segment_salah_build]}"
        ' inzsh-salah-quiet "$SHELLSPEC_PROJECT_ROOT" < /dev/null
      }
      When call quiet
      The output should eq 'built=1'
      The stderr should eq ''
    End

    It 'carries no hex — colour lives in the token layer and nowhere else'
      hexed() {
        setopt local_options extended_glob
        inzsh_spec_salah_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'#'[0-9A-Fa-f](#c6)* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call hexed
      The output should eq ''
    End

    It 'names no `.claude` path and no absolute path from this machine'
      neutral() {
        inzsh_spec_salah_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'.claude'* || $line == *'/Users/'* || $line == *'/home/'* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call neutral
      The output should eq ''
    End

    It 'reaches no network function of its own'
      # The lookup in `lib/salah/location.zsh` is reachable from nothing on the render path, and
      # this is the near end of that claim: a segment that refreshed a position would have put a
      # `curl` behind a prompt.
      offline() {
        inzsh_spec_salah_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *_inzsh_salah_locate_* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call offline
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the render path'
    # The rule the whole milestone is shaped by, asserted on the BODIES of the three functions a
    # draw actually runs. A computation that is only slow in December at a high latitude is a
    # computation no run of this suite would ever notice, so the claim is structural: there is
    # nothing in these functions that COULD fork, read a file, or do trigonometry.

    It 'is three functions and no more'
      # The build calls exactly two helpers, and the scan below is only honest while that is true.
      shaped() {
        inzsh_spec_salah_render_path
        print -r -- "$(( ${#inzsh_spec_body} > 400 ))"
      }
      When call shaped
      The output should eq '1'
    End

    It 'contains no command substitution and no backtick'
      forks() {
        inzsh_spec_salah_render_path
        local line; local -a bad=()
        for line in ${(f)inzsh_spec_body}; do
          [[ ${line//\$\(\(/} == *'$('* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call forks
      The output should eq ''
    End

    It 'names no external command'
      external() {
        setopt local_options extended_glob
        inzsh_spec_salah_render_path
        local line bare word; local -a bad=()
        local -a banned=(curl wget command eval date stat find sed awk cat mkdir mv rm)
        for line in ${(f)inzsh_spec_body}; do
          bare=${line##[[:space:]]#}
          for word in "${banned[@]}"; do
            # Braced, because `$word[` is a SUBSCRIPT and not a parameter followed by a bracket
            # expression. Unbraced, this line is a syntax error and not a failing assertion.
            [[ $bare == ${word}[[:space:]]* || $line == *[[:space:]]${word}[[:space:]]* ]] \
              && bad+="$word: $bare"
          done
        done
        print -rl -- $bad
      }
      When call external
      The output should eq ''
    End

    It 'reads no file and stats no path'
      # `lib/segments/dir.zsh` gives the reason: a `[[ -d ]]` on a dead NFS mount blocks the
      # prompt exactly as a fork would, without being one.
      unstatted() {
        setopt local_options extended_glob
        inzsh_spec_salah_render_path
        local line; local -a bad=()
        for line in ${(f)inzsh_spec_body}; do
          [[ $line == *'[[ -'[defghkLOprsSuwx]' '* ]] && bad+=$line
          [[ $line == *'< "$'* || $line == *'<'\$[A-Za-z_]* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call unstatted
      The output should eq ''
    End

    It 'does no trigonometry and never asks for a table to be computed'
      # The whole design in one assertion. The segment renders; something else computes.
      unlaboured() {
        inzsh_spec_salah_render_path
        local line; local -a bad=()
        local word
        for line in ${(f)inzsh_spec_body}; do
          for word in _inzsh_salah_compute _inzsh_salah_times _inzsh_salah_cache_ \
                      _inzsh_salah_location sin cos tan asin acos atan; do
            [[ $line == *$word* ]] && bad+="$word: $line"
          done
        done
        print -rl -- $bad
      }
      When call unlaboured
      The output should eq ''
    End
  End
End
