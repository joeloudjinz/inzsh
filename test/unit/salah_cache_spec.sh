Include lib/salah/calc.zsh
Include lib/salah/methods.zsh
Include lib/salah/cache.zsh
Include lib/salah/location.zsh

# The prayer-time day cache — `lib/salah/cache.zsh`. What is in an entry, what makes an entry
# wrong, and what happens when it cannot be read, cannot be written, or two shells write it at
# once.
#
# Four concerns, at different distances:
#
#   the key         a pure function of a date, a place, a UTC offset and a set of calculation
#                   parameters. Every one of the four is checked for the property that matters:
#                   change it and the key changes.
#   the table       twelve moments out of two computations, seeded so that the second one lands
#                   on tomorrow whatever the clocks did overnight.
#   the entry       written atomically, validated on the way back in, and a miss rather than a
#                   guess whenever anything about it is wrong.
#   resilience      no directory, a truncated file, an edited file, a clock that moved, a
#                   location that went away, and twenty writers on one entry.
#
# THE CLOCK IS INJECTED EVERYWHERE. Every example below hands `_inzsh_salah_cache_refresh` an
# instant, so not one of them can be affected by what the sun is doing while it runs. That is the
# same seam `lib/salah/calc.zsh` is built on, carried one layer up.
#
# EVERY EXAMPLE OWNS ITS OWN CACHE DIRECTORY. `INZSH_SALAH_CACHE_DIR` is pointed at a fresh
# `mktemp -d` and removed afterwards, so no example can read an entry another one wrote and
# nothing is ever written to the real `$XDG_CACHE_HOME`.
#
# The fixture instant, the neutral position, the scratch directory and the environment builder
# — `inzsh_spec_salah_now`, `inzsh_spec_salah_dir`, `inzsh_spec_salah_clean`,
# `inzsh_spec_salah_env` — live in `test/spec_helper.sh` now, shared with `doctor_spec.sh`, which
# exercises this same cache through `inzsh doctor` rather than through these functions directly.

# The only entry file in the scratch directory, in REPLY. Status 1 when there is not exactly one,
# which is itself a fact worth failing on.
inzsh_spec_salah_entry() {
  emulate -L zsh
  setopt local_options extended_glob

  typeset -g REPLY=
  local -a files=("$inzsh_spec_salah_cache"/[0-9a-f](#c8)(N))
  (( ${#files} == 1 )) || return 1
  typeset -g REPLY=${files[1]}

  return 0
}

# The six moments of a day, or of tomorrow with `next_` as `$1`, as local `HH:MM` readings.
inzsh_spec_salah_clocks() {
  emulate -L zsh

  local prefix=${1-}
  local name
  local -a drawn=()
  for name in "${_inzsh_salah_prayers[@]}"; do
    if _inzsh_salah_format "${_inzsh_salah_table[$prefix$name]-}" ''; then
      drawn+=$REPLY
    else
      drawn+=${_inzsh_salah_table[$prefix$name]-missing}
    fi
  done

  print -r -- "${drawn[*]}"
}

# `sed` over an entry, in place. A `>` onto the file being read truncates it before `sed` opens
# it, so the rewrite goes through a temporary — which is also the shape a person editing the file
# by hand would leave behind.
inzsh_spec_salah_edit() {
  emulate -L zsh

  local file=$1 script=$2
  sed "$script" "$file" > "$file.x" && command mv "$file.x" "$file"
}

# The Julian day number the epoch `$1` falls on in the ambient zone, in REPLY. Calendar
# arithmetic borrowed from `lib/salah/calc.zsh` rather than restated, so an example that compares
# two days is comparing them the way the library counts them.
inzsh_spec_salah_jd() {
  emulate -L zsh

  _inzsh_salah_civil_date "$1" '' || return 1
  local -a parts=(${=REPLY})
  _inzsh_salah_jd_civil "${parts[1]}" "${parts[2]}" "${parts[3]}"
}

Describe 'the day cache'
  # --------------------------------------------------------------------------------------------
  Describe 'the key'
    # A cached table is valid for one day, at one place, under one clock, computed one way. All
    # four are in the key, and each example below changes exactly one of them.

    It 'names the date, the position, the offset and the recipe'
      shaped() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_keys $inzsh_spec_salah_now "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON"
        local -a bad=()
        [[ $_inzsh_salah_day == '2026-6-1' ]]        || bad+="day=$_inzsh_salah_day"
        [[ $_inzsh_salah_key == "$_inzsh_salah_day|"* ]] || bad+=date-missing
        [[ $_inzsh_salah_key == *'21.4225'* ]]       || bad+=lat-missing
        [[ $_inzsh_salah_key == *'39.8262'* ]]       || bad+=lon-missing
        [[ $_inzsh_salah_key == *'+0300'* ]]         || bad+=offset-missing
        [[ $_inzsh_salah_key == *'fajr_angle=18'* ]] || bad+=recipe-missing
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call shaped
      The output should eq ''
    End

    Describe 'changes when anything it describes changes'
      # $1 what to change, as shell to evaluate; $2 the fact it stands for.
      Parameters
        'inzsh_spec_salah_now=$(( inzsh_spec_salah_now + 86400 ))'  'tomorrow'
        'INZSH_SALAH_LAT=31.63'                                     'a different latitude'
        'INZSH_SALAH_LON=-7.99'                                     'a different longitude'
        'TZ=Europe/London'                                          'a different zone'
        'INZSH_SALAH_METHOD=UmmAlQura'                              'a different method'
        'INZSH_SALAH_ASR=hanafi'                                    'a different school'
        'INZSH_SALAH_FAJR_ANGLE=15'                                 'an overridden angle'
        'INZSH_SALAH_OFFSET_MAGHRIB=5'                              'a display offset'
      End

      It "changes for $2"
        moved() {
          inzsh_spec_salah_env || return 1
          _inzsh_salah_cache_keys $inzsh_spec_salah_now "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON"
          local before=$_inzsh_salah_key
          eval "$1"
          _inzsh_salah_cache_keys $inzsh_spec_salah_now "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON"
          [[ $_inzsh_salah_key == $before ]] && print -r -- "unchanged: $before"
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call moved "$1"
        The output should eq ''
      End
    End

    It 'does not change across the same day, so a table is computed once'
      steady() {
        inzsh_spec_salah_env || return 1
        # 2026-06-01 00:00 in Riyadh, then four readings across the day up to 23:00.
        local -i midnight=$(( inzsh_spec_salah_now - 15 * 3600 ))
        local -A seen=()
        local -i offset
        for offset in 0 3600 43200 82800; do
          _inzsh_salah_cache_keys $(( midnight + offset )) "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON"
          seen[$_inzsh_salah_key]=1
        done
        print -r -- "distinct=${#seen}"
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call steady
      The output should eq 'distinct=1'
    End

    It 'is refused for an instant that is not one, and for a position that is not one'
      refused() {
        inzsh_spec_salah_env || return 1
        local -a bad=()
        _inzsh_salah_cache_keys banana "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON" && bad+=instant
        [[ -n $_inzsh_salah_key ]] && bad+=key-left-behind
        _inzsh_salah_cache_keys $inzsh_spec_salah_now '' '' && bad+=position
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call refused
      The output should eq ''
      The stderr should eq ''
    End

    It 'hashes to a name a filesystem will take'
      # The entry file is named from the stable half of the key, so a directory holds one file per
      # place and per method rather than one per day, forever.
      named() {
        setopt local_options extended_glob
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_key 'a key with spaces, a slash / and a longitude of -7.99'
        local -a bad=()
        [[ $REPLY == [0-9a-f](#c8) ]] || bad+="name=$REPLY"
        _inzsh_salah_cache_key 'a key with spaces, a slash / and a longitude of -7.99'
        local again=$REPLY
        _inzsh_salah_cache_key 'something else'
        [[ $REPLY == $again ]] && bad+=collides-with-everything
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call named
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the table'
    It 'holds today and tomorrow, twelve moments, and nothing else that is a time'
      twelve() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
        local -a bad=()
        local slot
        _inzsh_salah_slots
        for slot in "${reply[@]}"; do
          [[ -n ${_inzsh_salah_table[$slot]-} ]] || bad+="missing=$slot"
        done
        (( ${#reply} == 12 )) || bad+="slots=${#reply}"
        (( ${#_inzsh_salah_table} == 14 )) || bad+="entries=${#_inzsh_salah_table}"
        [[ -n ${_inzsh_salah_table[key]} && -n ${_inzsh_salah_table[day]} ]] || bad+=provenance
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call twelve
      The output should eq ''
    End

    It 'computes the day the reference oracle computes'
      # The whole pipeline in one reading, against the same place and day
      # `test/unit/salah_oracle_spec.sh` pins the arithmetic on. This is the layer above it: the
      # numbers arrive here through the cache, rounded and stored, rather than out of a call.
      pinned() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
        inzsh_spec_salah_clocks
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call pinned
      The output should eq '04:14 05:38 12:19 15:35 18:59 20:18'
    End

    It 'rounds every moment to the minute, so a clock and a countdown cannot disagree'
      # Rounded once, on the way in. A table holding raw seconds would let the clock reading round
      # one way and the countdown the other, and `19:59, in 25m` would be arithmetic nobody could
      # check.
      rounded() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now
        local -a bad=()
        local slot value
        _inzsh_salah_slots
        for slot in "${reply[@]}"; do
          value=${_inzsh_salah_table[$slot]}
          [[ $value == <-> ]] || continue
          (( value % 60 == 0 )) || bad+="$slot=$value"
        done
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call rounded
      The output should eq ''
    End

    It 'puts tomorrow exactly one calendar day after today'
      # The rollover, as the property it is. Six moments, each a day after its own twin.
      dayed() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now
        local -a bad=()
        local name
        local -i today tomorrow
        for name in "${_inzsh_salah_prayers[@]}"; do
          [[ ${_inzsh_salah_table[$name]} == <-> ]] || continue
          inzsh_spec_salah_jd "${_inzsh_salah_table[$name]}"     || { bad+="$name"; continue }
          today=$REPLY
          inzsh_spec_salah_jd "${_inzsh_salah_table[next_$name]}" || { bad+="$name"; continue }
          tomorrow=$REPLY
          (( tomorrow - today == 1 )) || bad+="$name:$today/$tomorrow"
        done
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call dayed
      The output should eq ''
    End

    It 'reaches tomorrow through solar noon, which a spring-forward evening cannot skip'
      # THE reason the second computation is seeded from `dhuhr` and not from `now + 86400`. On
      # the evening before the clocks go forward in London, twenty-four hours after 23:30 is
      # 00:30 the day after TOMORROW — the day the table is meant to hold is missed entirely.
      # Both readings are taken here, so the example states the bug as well as the fix.
      sprung() {
        inzsh_spec_salah_env || return 1
        typeset -gx TZ=Europe/London
        typeset -g INZSH_SALAH_LAT=51.50 INZSH_SALAH_LON=-0.12

        # 2026-03-28 23:30 UTC, the evening before British Summer Time begins.
        local -i eve=1774740600
        _inzsh_salah_cache_refresh $eve || print -r -- refresh-failed

        local -a bad=()
        inzsh_spec_salah_jd $eve;                     local -i today=$REPLY
        inzsh_spec_salah_jd $(( eve + 86400 ));       local -i naive=$REPLY
        inzsh_spec_salah_jd "${_inzsh_salah_table[next_dhuhr]}"; local -i seeded=$REPLY

        (( naive - today == 2 ))  || bad+="the-naive-reading-is-not-the-trap:$(( naive - today ))"
        (( seeded - today == 1 )) || bad+="seeded=$(( seeded - today ))"
        [[ ${_inzsh_salah_table[day]} == '2026-3-28' ]] || bad+="day=${_inzsh_salah_table[day]}"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call sprung
      The output should eq ''
    End

    It 'keeps the sentinel for a prayer that does not happen, rather than a number'
      # A polar night. `lib/salah/calc.zsh` answers `none`; the cache stores that word, and every
      # reader downstream already knows it is not a time.
      polar() {
        inzsh_spec_salah_env || return 1
        typeset -gx TZ=UTC
        typeset -g INZSH_SALAH_LAT=78.22 INZSH_SALAH_LON=15.63
        _inzsh_salah_cache_refresh 1766750400 || print -r -- refresh-failed
        local -a absent=()
        local name
        for name in "${_inzsh_salah_prayers[@]}"; do
          [[ ${_inzsh_salah_table[$name]} == $_inzsh_salah_absent ]] && absent+=$name
        done
        print -r -- "${absent[*]}"
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call polar
      The output should eq 'sunrise asr maghrib'
    End

    It 'refuses a position the arithmetic cannot use, and empties the table doing it'
      # A table that stayed behind after the location went away would draw yesterday's city.
      emptied() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now
        local -i filled=${#_inzsh_salah_table}
        typeset -g INZSH_SALAH_LAT= INZSH_SALAH_LON=
        local -a bad=()
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now && bad+=refresh-succeeded
        (( filled == 14 )) || bad+="filled=$filled"
        (( ${#_inzsh_salah_table} == 0 )) || bad+="left=${#_inzsh_salah_table}"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call emptied
      The output should eq ''
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the entry on disk'
    It 'writes one file, reads it back, and computes nothing the second time'
      # The round trip, and the reason the file exists: a second shell on the same morning pays a
      # file read rather than the arithmetic. `_inzsh_salah_compute_table` is stood in with a spy
      # for the second half, so "did not compute" is asserted rather than inferred from a clock.
      trip() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now
        local first=$(inzsh_spec_salah_clocks)

        inzsh_spec_salah_entry || { print -r -- 'no single entry'; return }

        local saved=$functions[_inzsh_salah_compute_table]
        typeset -g inzsh_spec_computed=0
        _inzsh_salah_compute_table() { inzsh_spec_computed=1; return 1 }

        _inzsh_salah_table=()
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- second-refresh-failed
        local second=$(inzsh_spec_salah_clocks)
        functions[_inzsh_salah_compute_table]=$saved

        print -r -- "computed=$inzsh_spec_computed same=$([[ $first == $second ]] && print yes)"
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call trip
      The output should eq 'computed=0 same=yes'
    End

    It 'answers from memory without touching the file at all'
      # The warm path, which is every prompt but a handful a day. The entry is deleted underneath
      # the shell and the table is still there, because the key has not changed and the key is
      # what changing would change.
      warm() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now
        inzsh_spec_salah_entry && rm -f -- "$REPLY"
        local -a bad=()
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now || bad+=refresh-failed
        (( ${#_inzsh_salah_table} == 14 )) || bad+="entries=${#_inzsh_salah_table}"
        inzsh_spec_salah_entry && bad+=rewrote-the-file
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call warm
      The output should eq ''
    End

    It 'leaves no temporary behind — the write is a rename, not a copy'
      # A `.tmp` still sitting there is either a write that did not finish or a rename that was
      # really a copy, and both mean a reader can see half an entry.
      atomic() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now
        local -a leftovers=("$inzsh_spec_salah_cache"/*.tmp(N))
        print -r -- "temporaries=${#leftovers}"
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call atomic
      The output should eq 'temporaries=0'
    End

    It 'renames a temporary into place and never opens the entry itself'
      # The atomicity claim, asserted DIRECTLY rather than by racing for it. A rename is atomic
      # only because the content is already complete somewhere else when it happens — so the two
      # facts that matter are that the source and the destination are different paths, and that
      # the destination did not exist while the content was being written. `_inzsh_salah_mv` is
      # stood in with a spy for the duration.
      spied() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_keys $inzsh_spec_salah_now "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON"
        _inzsh_salah_cache_path "$_inzsh_salah_seed" || { print -r -- no-path; return }
        local file=$REPLY

        _inzsh_salah_compute_table $inzsh_spec_salah_now "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON"
        _inzsh_salah_table[key]=$_inzsh_salah_key
        _inzsh_salah_table[day]=$_inzsh_salah_day

        local saved=$functions[_inzsh_salah_mv]
        typeset -g inzsh_spec_from= inzsh_spec_to= inzsh_spec_pre=
        _inzsh_salah_mv() {
          inzsh_spec_from=${@[-2]}
          inzsh_spec_to=${@[-1]}
          inzsh_spec_pre=absent
          [[ -e ${@[-1]} ]] && inzsh_spec_pre=present
          command mv "$@" 2>/dev/null
        }

        _inzsh_salah_cache_write "$file"
        functions[_inzsh_salah_mv]=$saved

        local -a bad=()
        [[ $inzsh_spec_to == $file ]]            || bad+="renamed-onto=$inzsh_spec_to"
        [[ $inzsh_spec_from != $inzsh_spec_to ]] || bad+=source-is-the-entry
        [[ $inzsh_spec_pre == absent ]]          || bad+=entry-existed-before-the-rename
        _inzsh_salah_cache_read "$_inzsh_salah_key" "$file" || bad+=unreadable-afterwards
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call spied
      The output should eq ''
    End

    It 'survives twenty writers racing onto the same entry'
      # Several shells wake up on the same morning and all of them find the entry missing. Each
      # writes its own temporary and renames it over, and whatever a reader sees is one writer's
      # whole answer — never a blend of two, and never nothing.
      raced() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now
        inzsh_spec_salah_entry || { print -r -- no-entry; return }
        local file=$REPLY
        local key=${_inzsh_salah_table[key]}
        local isha=${_inzsh_salah_table[isha]}

        local -i n
        for (( n = 1; n <= 20; n++ )); do
          _inzsh_salah_cache_write "$file" &
        done

        local -a bad=()
        local -i r misses=0
        for (( r = 1; r <= 40; r++ )); do
          if _inzsh_salah_cache_read "$key" "$file"; then
            [[ ${_inzsh_salah_table[isha]} == $isha ]] || bad+="isha=${_inzsh_salah_table[isha]}"
          else
            (( misses++ ))
          fi
        done
        wait

        _inzsh_salah_cache_read "$key" "$file" || bad+=final-miss
        local -a leftovers=("$inzsh_spec_salah_cache"/*.tmp(N))
        (( ${#leftovers} )) && bad+="temporaries=${#leftovers}"
        (( misses )) && bad+="misses=$misses"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call raced
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'an entry that cannot be trusted'
    # None of this comes from a user's config — the file is one this theme wrote — but it outlives
    # the shell that wrote it, a full filesystem can truncate it, and a person can open it in an
    # editor. Every one of these is a MISS, which recomputes, which is slower and still right.

    Describe 'is a miss and is recomputed'
      # $1 what to do to the file; $2 the fault it stands for.
      Parameters
        'print -r -- junk > $file'                        'garbage'
        ': > $file'                                       'an empty file'
        'head -8 $file > $file.x; command mv $file.x $file'  'a truncated write'
        'inzsh_spec_salah_edit "$file" "s/^version.*/version	9/"'   'a future format'
        'inzsh_spec_salah_edit "$file" "s/^key.*/key	somewhere/"'    'another day'
        'inzsh_spec_salah_edit "$file" "s/^isha.*/isha	soon/"'       'a slot that is not a moment'
        'sed "/^maghrib	/d" $file > $file.x; command mv $file.x $file'  'a missing slot'
        'chmod 000 $file'                                 'a file that cannot be read'
      End

      It "recovers from $2"
        damaged() {
          inzsh_spec_salah_env || return 1
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now
          local expected=$(inzsh_spec_salah_clocks)
          inzsh_spec_salah_entry || { print -r -- no-entry; return }
          local file=$REPLY

          eval "$1"

          _inzsh_salah_table=()
          local -a bad=()
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now || bad+=refresh-failed
          [[ $(inzsh_spec_salah_clocks) == $expected ]] || bad+=different-answer
          print -rl -- $bad
          chmod 644 "$file" 2>/dev/null
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call damaged "$1"
        The output should eq ''
        The stderr should eq ''
      End
    End

    It 'refuses an entry written for another position, however it is named'
      # The second lock on the key. Two keys that hashed to the same eight digits would share a
      # file; the key stored inside the entry is what turns that from a wrong answer into a miss.
      keyed() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now
        inzsh_spec_salah_entry || { print -r -- no-entry; return }
        local file=$REPLY
        local -a bad=()
        _inzsh_salah_cache_read 'a key this entry was not written for' "$file" && bad+=accepted
        (( ${#_inzsh_salah_table} )) && bad+="left=${#_inzsh_salah_table}"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call keyed
      The output should eq ''
    End

    It 'reads nothing at all when there is no entry, and says so'
      absent() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_cache_read 'any key' "$inzsh_spec_salah_cache/nothing-here"
        print -r -- "rc=$? entries=${#_inzsh_salah_table}"
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call absent
      The output should eq 'rc=1 entries=0'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'a cache directory that cannot be had'
    It 'still answers, from memory, for the life of the shell'
      # The degradation that matters: no file cache is slower, not broken. The table is computed
      # once and held, so the segment draws exactly as it would have.
      memoried() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_CACHE_DIR=$inzsh_spec_salah_cache/a-file/not-a-directory
        : > "$inzsh_spec_salah_cache/a-file"

        local -a bad=()
        _inzsh_salah_cache_refresh $inzsh_spec_salah_now || bad+=refresh-failed
        (( ${#_inzsh_salah_table} == 14 )) || bad+="entries=${#_inzsh_salah_table}"
        [[ $(inzsh_spec_salah_clocks) == '04:14 05:38 12:19 15:35 18:59 20:18' ]] ||
          bad+=wrong-answer
        _inzsh_salah_cache_dir && bad+=made-a-directory-anyway
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call memoried
      The output should eq ''
      The stderr should eq ''
    End

    It 'creates the directory it was told about, rather than assuming one'
      made() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_CACHE_DIR=$inzsh_spec_salah_cache/deep/down/here
        local -a bad=()
        _inzsh_salah_cache_dir || bad+=refused
        [[ -d $REPLY ]] || bad+="not-a-directory=$REPLY"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call made
      The output should eq ''
    End

    It 'falls back to the XDG cache directory when it is told about none'
      # Derived data with no value once tomorrow arrives, so it lives under the cache directory
      # and never under a config one. Asserted against a scratch `XDG_CACHE_HOME`, so the real one
      # is never touched.
      xdg() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_CACHE_DIR=
        local -x XDG_CACHE_HOME=$inzsh_spec_salah_cache/xdg
        _inzsh_salah_cache_dir
        print -r -- "${REPLY#$inzsh_spec_salah_cache/}"
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call xdg
      The output should eq 'xdg/inzsh/salah'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the parse split leaves no trace of it on the caller — review findings N-3, N-4'
    # Before the parse extraction, `_inzsh_salah_cache_read` never touched `REPLY` at all — it is
    # a render-path function, and the caller here (`_inzsh_salah_cache_refresh`) captures `file`
    # from a DIFFERENT call before this one runs, so there is no live bug — but
    # `_inzsh_salah_cache_parse` answers in REPLY, and borrowing it without giving it back is an
    # undocumented contract change on exactly the kind of function this file's own header warns
    # about in capitals.
    It "restores the caller's REPLY after a successful read"
      preserved_ok() {
        inzsh_spec_salah_env || return 1
        {
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
          inzsh_spec_salah_entry || print -r -- no-entry
          local file=$REPLY
          local key=${_inzsh_salah_table[key]}

          REPLY=untouched-marker
          _inzsh_salah_cache_read "$key" "$file"
          [[ $REPLY == untouched-marker ]] || print -r -- "reply=$REPLY"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call preserved_ok
      The output should eq ''
    End

    It "restores the caller's REPLY after a read that misses"
      preserved_miss() {
        inzsh_spec_salah_env || return 1
        {
          REPLY=untouched-marker
          _inzsh_salah_cache_read 'a key nothing was written for' "$inzsh_spec_salah_cache/nothing-here"
          [[ $REPLY == untouched-marker ]] || print -r -- "reply=$REPLY"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call preserved_miss
      The output should eq ''
    End

    # `_inzsh_salah_cache_raw` is `_inzsh_salah_cache_parse`'s workspace, holding the same
    # coordinates `_inzsh_salah_table` and `_inzsh_salah_seed` already carry for the life of the
    # shell — not a new exposure, but a file headed COORDINATES NEVER LEAVE should not grow a
    # fourth place they sit once the one caller that needed them has copied them out.
    It 'clears the raw entry once a read has copied what it needs'
      cleared() {
        inzsh_spec_salah_env || return 1
        {
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
          inzsh_spec_salah_entry || print -r -- no-entry
          local file=$REPLY
          local key=${_inzsh_salah_table[key]}

          _inzsh_salah_cache_read "$key" "$file"
          (( ${#_inzsh_salah_cache_raw} == 0 )) || print -r -- "left=${#_inzsh_salah_cache_raw}"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call cleared
      The output should eq ''
    End

    It 'clears the raw entry once a health check has copied what it needs'
      cleared_health() {
        inzsh_spec_salah_env || return 1
        {
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
          _inzsh_salah_cache_health $inzsh_spec_salah_now
          (( ${#_inzsh_salah_cache_raw} == 0 )) || print -r -- "left=${#_inzsh_salah_cache_raw}"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call cleared_health
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'diagnostic health — issue #229'
    # `inzsh doctor` reports where the position came from; this is the other half, the state of
    # the TABLE computed from it. Read-only throughout: every example below either writes an
    # entry by hand or leaves the cache untouched, and none of them expects
    # `_inzsh_salah_cache_health` to compute or write anything itself.
    #
    # NO DIGEST HERE, AND THAT IS THE POINT. An earlier version of this function hashed the
    # recipe and exposed it as `_inzsh_salah_cache_health_recipe`; a review of the doctor row
    # that hash fed found the coordinate space at any precision a person types is smaller than
    # the 32-bit hash space, so the hash was a slow but complete encoding of the position rather
    # than a redaction of it. `_inzsh_salah_cache_health` now answers in a single status word and
    # nothing else — there is no coordinate for any example below to leak, so none of them test
    # for one; the leak-proof examples live in `doctor_spec.sh`, against the actual printed row.
    #
    # Every example is wrapped `{ … } always { cleanup }` — the `always` block runs whether the
    # body returns early or falls through, so a failed setup assertion cannot leak the scratch
    # directory the way an ordinary early `return` would.

    It 'reports none when no position is known'
      no_position() {
        inzsh_spec_salah_env || return 1
        {
          typeset -g INZSH_SALAH_LAT= INZSH_SALAH_LON= INZSH_SALAH_AUTOLOCATE=0
          _inzsh_salah_cache_health $inzsh_spec_salah_now
          [[ $REPLY == none ]] || print -r -- "reply=$REPLY"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call no_position
      The output should eq ''
    End

    It 'reports missing when the directory is fine and nothing has been cached yet'
      missing() {
        inzsh_spec_salah_env || return 1
        {
          _inzsh_salah_cache_health $inzsh_spec_salah_now
          [[ $REPLY == missing ]] || print -r -- "reply=$REPLY"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call missing
      The output should eq ''
    End

    It 'reports current when the entry matches today and matches the recipe in force'
      current() {
        inzsh_spec_salah_env || return 1
        {
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
          _inzsh_salah_cache_health $inzsh_spec_salah_now
          [[ $REPLY == current ]] || print -r -- "reply=$REPLY"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call current
      The output should eq ''
    End

    It 'reports stale when the entry was computed under the same recipe for another day'
      stale() {
        inzsh_spec_salah_env || return 1
        {
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
          inzsh_spec_salah_entry || print -r -- no-entry
          local file=$REPLY
          local seed=${_inzsh_salah_table[key]#*|}
          _inzsh_salah_table[key]="2026-5-29|$seed"
          _inzsh_salah_table[day]='2026-5-29'
          _inzsh_salah_cache_write "$file" || print -r -- write-failed

          _inzsh_salah_cache_health $inzsh_spec_salah_now
          [[ $REPLY == stale ]] || print -r -- "reply=$REPLY"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call stale
      The output should eq ''
    End

    # Issue #229 review, finding I1. The entry PATH is a hash of the seed, so a real recipe
    # change moves the file rather than leaving a conflicting one behind at the old path — the
    # only way to reach this path with a key naming a different seed is a hand edit or a 32-bit
    # collision, and either way it is not an entry this recipe wrote. `unreadable` is the honest
    # word: the same one an entry that does not parse at all gets, rather than a `mismatch` that
    # would name a cause reachable in practice.
    It 'folds a key naming a different seed at this path into unreadable, not a distinct state'
      collision() {
        inzsh_spec_salah_env || return 1
        {
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
          inzsh_spec_salah_entry || print -r -- no-entry
          local file=$REPLY
          local day=${_inzsh_salah_table[key]%%|*}
          _inzsh_salah_table[key]="$day|10.0000|20.0000|+0000|OTHER asr:1"
          _inzsh_salah_cache_write "$file" || print -r -- write-failed

          _inzsh_salah_cache_health $inzsh_spec_salah_now
          [[ $REPLY == unreadable ]] || print -r -- "reply=$REPLY"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call collision
      The output should eq ''
    End

    Describe 'an entry that cannot be trusted, reported as unreadable rather than as a failure'
      # $1 what to do to the file; $2 the fault it stands for.
      Parameters
        'print -r -- junk > $file'                             'garbage'
        ': > $file'                                             'an empty file'
        'inzsh_spec_salah_edit "$file" "s/^isha	.*/isha	soon/"'  'a single corrupted slot'
      End

      It "reports unreadable for $2"
        # Issue #229 review, finding I4: the four ORIGINAL cases here (garbage, empty, a future
        # version, an unreadable file) all short-circuited before the slot-validation loop in
        # `_inzsh_salah_cache_parse` — the version check or the open check failed first, so
        # deleting the loop entirely left every one of them green. The future-version and
        # permission cases moved to their own dedicated examples below, each now asserting its
        # own more specific word, and this third case is new: a version and a key that are both
        # exactly right, with one slot corrupted, which is the only fault that loop alone catches.
        damaged() {
          inzsh_spec_salah_env || return 1
          {
            _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
            inzsh_spec_salah_entry || print -r -- no-entry
            local file=$REPLY

            eval "$1"

            _inzsh_salah_cache_health $inzsh_spec_salah_now
            [[ $REPLY == unreadable ]] || print -r -- "reply=$REPLY"
          } always {
            inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
          }
        }
        When call damaged "$1"
        The output should eq ''
      End
    End

    # Issue #229 review, finding I5: `denied` and `future` are actionable in a way a generic
    # `unreadable` is not — a permissions fix versus an upgrade — so each keeps its own word
    # rather than folding into the parse-failure catch-all above.
    It 'reports denied for a file that exists and cannot be read'
      denied() {
        inzsh_spec_salah_env || return 1
        {
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
          inzsh_spec_salah_entry || print -r -- no-entry
          local file=$REPLY
          chmod 000 "$file"

          _inzsh_salah_cache_health $inzsh_spec_salah_now
          [[ $REPLY == denied ]] || print -r -- "reply=$REPLY"
        } always {
          chmod 644 "$file" 2>/dev/null
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call denied
      The output should eq ''
    End

    It 'reports future for a format version this file did not write'
      future() {
        inzsh_spec_salah_env || return 1
        {
          _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
          inzsh_spec_salah_entry || print -r -- no-entry
          local file=$REPLY
          inzsh_spec_salah_edit "$file" 's/^version.*/version	9/'

          _inzsh_salah_cache_health $inzsh_spec_salah_now
          [[ $REPLY == future ]] || print -r -- "reply=$REPLY"
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call future
      The output should eq ''
    End

    # Review finding N-6. `0` and a leading-zero `01` are both NUMBERS, so the naive `<->` range
    # this used to check with called each of them "future" — a version this file has never
    # written and, worse, that nothing could ever have written, since versions start at 1. Both
    # are exactly as untrustworthy as a version field with no digits in it, and now read that way.
    Describe 'does not call a version that could never have been written future'
      Parameters
        0  zero
        01 leading-zero
      End

      It "reports unreadable, not future, for version $1"
        low_version() {
          inzsh_spec_salah_env || return 1
          {
            _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
            inzsh_spec_salah_entry || print -r -- no-entry
            local file=$REPLY
            inzsh_spec_salah_edit "$file" "s/^version.*/version	$1/"

            _inzsh_salah_cache_health $inzsh_spec_salah_now
            [[ $REPLY == unreadable ]] || print -r -- "reply=$REPLY"
          } always {
            inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
          }
        }
        When call low_version "$1"
        The output should eq ''
      End
    End

    # Issue #229 review, finding I2. A cache directory that is a stray file, does not exist, or
    # cannot be looked inside is not the same fact as "the directory is fine and this recipe has
    # never been cached" — the reader needs to know the segment is recomputing every shell for a
    # reason that has nothing to do with today's recipe. `nodir` names that reason on its own.
    Describe 'a cache directory that cannot be used, reported as nodir rather than as missing'
      It 'reports nodir when the directory does not exist at all'
        absent() {
          local scratch
          scratch=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-salah-spec-XXXXXX") || return 1
          {
            inzsh_spec_salah_env || print -r -- setup-failed
            typeset -g INZSH_SALAH_CACHE_DIR=$scratch/never-created

            _inzsh_salah_cache_health $inzsh_spec_salah_now
            [[ $REPLY == nodir ]] || print -r -- "reply=$REPLY"
          } always {
            inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
            inzsh_spec_salah_clean "$scratch"
          }
        }
        When call absent
        The output should eq ''
      End

      It 'reports nodir when a file sits where the directory should be'
        is_a_file() {
          inzsh_spec_salah_env || return 1
          {
            : > "$inzsh_spec_salah_cache/a-file"
            typeset -g INZSH_SALAH_CACHE_DIR=$inzsh_spec_salah_cache/a-file

            _inzsh_salah_cache_health $inzsh_spec_salah_now
            [[ $REPLY == nodir ]] || print -r -- "reply=$REPLY"
          } always {
            inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
          }
        }
        When call is_a_file
        The output should eq ''
      End

      It 'reports nodir, not the valid entry inside, when the directory cannot be searched'
        mode_000() {
          inzsh_spec_salah_env || return 1
          {
            _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
            chmod 000 "$inzsh_spec_salah_cache"

            _inzsh_salah_cache_health $inzsh_spec_salah_now
            [[ $REPLY == nodir ]] || print -r -- "reply=$REPLY"
          } always {
            chmod 755 "$inzsh_spec_salah_cache" 2>/dev/null
            inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
          }
        }
        When call mode_000
        The output should eq ''
      End

      # Review finding N-5. `chmod 000` fails BOTH `-r` and `-x` at once, so it cannot tell a
      # probe that dropped one of the two conjuncts from a correct one — either half alone would
      # still pass that example. `chmod 111` and `chmod 444` each hold one half up and take the
      # other away, and both must still read `nodir`.
      It 'reports nodir when the directory can be searched but not read'
        mode_111() {
          inzsh_spec_salah_env || return 1
          {
            _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
            chmod 111 "$inzsh_spec_salah_cache"

            _inzsh_salah_cache_health $inzsh_spec_salah_now
            [[ $REPLY == nodir ]] || print -r -- "reply=$REPLY"
          } always {
            chmod 755 "$inzsh_spec_salah_cache" 2>/dev/null
            inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
          }
        }
        When call mode_111
        The output should eq ''
      End

      It 'reports nodir when the directory can be read but not searched'
        mode_444() {
          inzsh_spec_salah_env || return 1
          {
            _inzsh_salah_cache_refresh $inzsh_spec_salah_now || print -r -- refresh-failed
            chmod 444 "$inzsh_spec_salah_cache"

            _inzsh_salah_cache_health $inzsh_spec_salah_now
            [[ $REPLY == nodir ]] || print -r -- "reply=$REPLY"
          } always {
            chmod 755 "$inzsh_spec_salah_cache" 2>/dev/null
            inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
          }
        }
        When call mode_444
        The output should eq ''
      End
    End

    # Issue #229 review, finding I3. `_inzsh_salah_cache_path`, which the first version of this
    # function called, `mkdir -p`s a missing directory — the ordinary behaviour for the render
    # path, and exactly wrong for a diagnostic that is supposed to describe the machine without
    # changing it. `_inzsh_salah_cache_dir_probe` is the read-only sibling this function uses
    # instead, and this is the regression test for the side effect it replaced.
    It 'never creates the cache directory it is only reporting on'
      readonly_probe() {
        local scratch
        scratch=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-salah-spec-XXXXXX") || return 1
        {
          inzsh_spec_salah_env || print -r -- setup-failed
          local target=$scratch/never-created
          typeset -g INZSH_SALAH_CACHE_DIR=$target

          _inzsh_salah_cache_health $inzsh_spec_salah_now
          if [[ -e $target ]]; then
            print -r -- "created: $REPLY"
          fi
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
          inzsh_spec_salah_clean "$scratch"
        }
      }
      When call readonly_probe
      The output should eq ''
    End

    It 'never returns failure, whatever it finds'
      resilient() {
        inzsh_spec_salah_env || return 1
        {
          local -a bad=()
          _inzsh_salah_cache_health $inzsh_spec_salah_now || bad+=no-position
          typeset -g INZSH_SALAH_LAT= INZSH_SALAH_LON=
          _inzsh_salah_cache_health $inzsh_spec_salah_now || bad+=missing
          print -rl -- $bad
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call resilient
      The output should eq ''
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/salah/cache.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sources silently in a single-byte locale, on its own'
      # `lib/salah/` is sourced by a spec, a bundle and the entry point in different orders. A
      # file that needed a sibling at SOURCE time would break the one that loaded it first.
      alone() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          source "$1/lib/salah/cache.zsh"
          print -r -- "refresh=${+functions[_inzsh_salah_cache_refresh]}" \
            "table=${#_inzsh_salah_table}" "knobs=${#_inzsh_salah_cache_knobs}"
        ' inzsh-salah-cache-alone "$SHELLSPEC_PROJECT_ROOT" < /dev/null
      }
      When call alone
      The output should eq 'refresh=1 table=0 knobs=3'
      The stderr should eq ''
    End

    It 'refuses to answer rather than erroring when the arithmetic is not loaded'
      # Sourced alone, every entry point here is a no-op with a status. A function that assumed a
      # sibling would be a `command not found` on somebody's first prompt.
      unloaded() {
        zsh -f -c '
          source "$1/lib/salah/cache.zsh"
          local -a bad=()
          _inzsh_salah_cache_refresh 1780315200 && bad+=refresh
          _inzsh_salah_compute_table 1780315200 21.4225 39.8262 && bad+=compute
          _inzsh_salah_slots && bad+=slots
          _inzsh_salah_recipe && bad+=recipe
          print -r -- "${bad[*]}"
        ' inzsh-salah-cache-guard "$SHELLSPEC_PROJECT_ROOT" < /dev/null
      }
      When call unloaded
      The output should eq ''
      The stderr should eq ''
    End

    # `_inzsh_salah_cache_health` is the one entry point above that is a diagnostic rather than
    # part of the render path, and its contract is the opposite of its neighbours': it must
    # NEVER report failure, standalone load included. `_inzsh_salah_location` missing is exactly
    # the "no position" case it already reports for a configured shell, so the honest answer here
    # is the same word, not a status-1 refusal.
    It 'reports none, at status 0, when sourced alone without the location it depends on'
      standalone() {
        zsh -f -c '
          source "$1/lib/salah/cache.zsh"
          _inzsh_salah_cache_health 1780315200
          print -r -- "status=$? reply=$REPLY"
        ' inzsh-salah-cache-health-standalone "$SHELLSPEC_PROJECT_ROOT" < /dev/null
      }
      When call standalone
      The output should eq 'status=0 reply=none'
      The stderr should eq ''
    End

    It 'names nothing from the engine'
      # `lib/salah/` imports nothing from `lib/core/`. The dependency points one way on paper, and
      # this is what keeps it pointing there: a `_inzsh_config_get` borrowed for convenience would
      # make the cache depend on the prompt.
      unattached() {
        setopt local_options extended_glob
        local line prefix
        local -a bad=()
        while IFS= read -r line; do
          [[ ${line##[[:space:]]#} == \#* ]] && continue
          for prefix in _inzsh_config_ _inzsh_layout_ _inzsh_render_ _inzsh_seg_ _inzsh_token \
                        _inzsh_width _inzsh_truncate _inzsh_detect_ _inzsh_hook \
                        _inzsh_segment_; do
            [[ $line == *$prefix* ]] && bad+="$prefix: $line"
          done
        done < "$SHELLSPEC_PROJECT_ROOT/lib/salah/cache.zsh"
        print -rl -- $bad
      }
      When call unattached
      The output should eq ''
    End

    It 'reads the clock in exactly one place, as a default nobody has to take'
      # `EPOCHSECONDS` anywhere else here would mean a fixture could not pin what "now" is, and
      # every example above would be checking the sun's position at the moment the suite ran.
      clockless() {
        setopt local_options extended_glob
        local line
        local -a found=()
        while IFS= read -r line; do
          [[ ${line##[[:space:]]#} == \#* ]] && continue
          [[ $line == *EPOCHSECONDS* || $line == *EPOCHREALTIME* ]] && found+="$line"
        done < "$SHELLSPEC_PROJECT_ROOT/lib/salah/cache.zsh"
        print -rl -- "${#found}" "${found[@]}"
      }
      When call clockless
      The lines of output should eq 2
      The line 1 of output should eq '1'
      The line 2 of output should include 'local now=${1:-${EPOCHSECONDS-}}'
    End

    It 'names no `.claude` path and no absolute path from this machine'
      neutral() {
        local line
        local -a bad=()
        while IFS= read -r line; do
          [[ $line == *'.claude'* || $line == *'/Users/'* || $line == *'/home/'* ]] && bad+=$line
        done < "$SHELLSPEC_PROJECT_ROOT/lib/salah/cache.zsh"
        print -rl -- $bad
      }
      When call neutral
      The output should eq ''
    End
  End
End
