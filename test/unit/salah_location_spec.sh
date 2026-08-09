Include lib/salah/calc.zsh
Include lib/salah/cache.zsh
Include lib/salah/location.zsh

# Where you are — `lib/salah/location.zsh`. Two numbers, and the only place in this repository
# where anything can leave the machine.
#
# The file has two halves and they are tested at very different distances.
#
#   THE CONFIGURED PATH is pure: two variables, two range checks, no file and no process. It is
#   the default, it is what the documentation tells people to use, and most of the examples below
#   are about it.
#
#   THE LOOKUP is off by default and unreachable from anything that draws a prompt. What is tested
#   here is everything around the transfer — permission, the URL grammar, the TTL, the parse, the
#   write, and the fallback when it fails — plus one example that actually runs `curl` against a
#   port nothing is listening on, which is the failure a user will really meet.
#
# NO EXAMPLE HERE MAKES A NETWORK REQUEST THAT COULD SUCCEED. The one that runs a client points it
# at `127.0.0.1` on a port nothing serves, under a one-second ceiling, so the suite is offline in
# the only sense that matters: it does not depend on anything outside the machine and cannot be
# slow because something else is.
#
# EVERY EXAMPLE OWNS ITS OWN CACHE DIRECTORY, so nothing is ever written to the real
# `$XDG_CACHE_HOME` and no example can read what another one wrote.

typeset -gi inzsh_spec_salah_now=1780315200

inzsh_spec_salah_dir() {
  emulate -L zsh

  typeset -g REPLY=
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-salah-loc-XXXXXX") || return 1
  typeset -g REPLY=$dir

  return 0
}

inzsh_spec_salah_clean() {
  emulate -L zsh

  local target=${1-}
  [[ ${target:t} == inzsh-salah-loc-* ]] || return 1
  rm -rf -- "$target" 2>/dev/null

  return 0
}

# The fixture environment: a scratch directory, nothing configured, the lookup off. Every example
# starts from the shipped defaults and changes exactly what it is about.
inzsh_spec_salah_env() {
  emulate -L zsh

  inzsh_spec_salah_dir || return 1
  typeset -g inzsh_spec_salah_cache=$REPLY

  typeset -g INZSH_SALAH_CACHE_DIR=$inzsh_spec_salah_cache
  typeset -g INZSH_SALAH_LAT= INZSH_SALAH_LON=
  typeset -g INZSH_SALAH_AUTOLOCATE=0
  typeset -g INZSH_SALAH_AUTOLOCATE_TTL=
  typeset -g INZSH_SALAH_AUTOLOCATE_TIMEOUT=
  typeset -g INZSH_SALAH_AUTOLOCATE_URL=

  return 0
}

# `<lat> <lon>` and the provenance, or `none`, for whatever is configured right now.
inzsh_spec_salah_where() {
  emulate -L zsh

  if _inzsh_salah_location "${1-}"; then
    print -r -- "$REPLY $_inzsh_salah_location_source"
  else
    print -r -- "none $_inzsh_salah_location_source"
  fi

  return 0
}

# A body in a scratch file, parsed, reported as `<lat> <lon>` or `no`.
inzsh_spec_salah_parse() {
  emulate -L zsh

  inzsh_spec_salah_env || return 1
  local file=$inzsh_spec_salah_cache/body
  print -r -- "$1" > "$file"

  if _inzsh_salah_locate_parse "$file"; then
    print -r -- "$REPLY"
  else
    print -r -- no
  fi

  inzsh_spec_salah_clean "$inzsh_spec_salah_cache"

  return 0
}

Describe 'where you are'
  # --------------------------------------------------------------------------------------------
  Describe 'the configured position'
    Describe 'is used when both halves are a position'
      # $1 latitude, $2 longitude, $3 what comes back.
      Parameters
        21.4225  39.8262  '21.4225 39.8262 config'
        0        0        '0 0 config'
        -33.86   151.20   '-33.86 151.20 config'
        90       180      '90 180 config'
        -90      -180     '-90 -180 config'
      End

      It "reads ($1, $2) as $3"
        configured() {
          inzsh_spec_salah_env || return 1
          typeset -g INZSH_SALAH_LAT=$1 INZSH_SALAH_LON=$2
          inzsh_spec_salah_where
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call configured "$1" "$2"
        The output should eq "$3"
      End
    End

    Describe 'and anything that is not a position is treated as unset'
      # It cannot invent a location, so a typo hides the segment rather than moving somebody. No
      # default coordinates, no guess from `$TZ`, no "near enough".
      Parameters
        banana   39.8262
        21.4225  banana
        ''       39.8262
        21.4225  ''
        91       39.8262
        -91      39.8262
        21.4225  181
        21.4225  -181
        '21,4225'  39.8262
        '1e2'    39.8262
        '0x15'   39.8262
        ' 21.4225 '  39.8262
      End

      It "refuses ($1, $2)"
        rejected() {
          inzsh_spec_salah_env || return 1
          typeset -g INZSH_SALAH_LAT=$1 INZSH_SALAH_LON=$2
          inzsh_spec_salah_where
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call rejected "$1" "$2"
        The output should eq 'none '
        The stderr should eq ''
      End
    End

    It 'reads no file and starts no process to answer'
      # The path everybody is on. `_inzsh_salah_cache_dir` is stood in with a spy that would
      # create nothing and report being asked; a configured position must never reach it.
      untouched() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262

        local saved=$functions[_inzsh_salah_cache_dir]
        typeset -g inzsh_spec_asked=0
        _inzsh_salah_cache_dir() { inzsh_spec_asked=1; typeset -g REPLY=; return 1 }

        _inzsh_salah_location $inzsh_spec_salah_now
        local answer=$REPLY
        functions[_inzsh_salah_cache_dir]=$saved

        print -r -- "$answer asked=$inzsh_spec_asked"
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call untouched
      The output should eq '21.4225 39.8262 asked=0'
    End

    It 'beats a looked-up position, even while the lookup is switched on'
      # A configured pair is a STATEMENT and a looked-up one is an inference, so setting the
      # coordinates by hand after turning the lookup on does the obvious thing.
      preferred() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_AUTOLOCATE=1
        _inzsh_salah_location_write 31.63 -7.99 $inzsh_spec_salah_now
        local -a seen=()
        seen+="$(inzsh_spec_salah_where $inzsh_spec_salah_now)"
        typeset -g INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
        seen+="$(inzsh_spec_salah_where $inzsh_spec_salah_now)"
        print -rl -- $seen
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call preferred
      The lines of output should eq 2
      The line 1 of output should eq '31.63 -7.99 cache'
      The line 2 of output should eq '21.4225 39.8262 config'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the lookup, as a permission'
    Describe 'is off unless it is switched on in so many words'
      # Anything unreadable is OFF. A typo may not switch a network call on, which is the
      # opposite of the theme's usual "fall back to the default" — because here the default IS
      # off, and an unreadable value falling back to it is the same rule, not an exception.
      Parameters
        ''        off
        0         off
        no        off
        false     off
        chartreuse off
        2         off
        1         on
        yes       on
        TRUE      on
        On        on
      End

      It "reads '$1' as $2"
        permitted() {
          inzsh_spec_salah_env || return 1
          typeset -g INZSH_SALAH_AUTOLOCATE=$1
          _inzsh_salah_autolocate_on && print -r -- on || print -r -- off
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call permitted "$1"
        The output should eq "$2"
      End
    End

    It 'is off by default, which is the whole point of it'
      shipped() {
        inzsh_spec_salah_env || return 1
        local -i i
        local -a bad=()
        for (( i = 1; i <= ${#_inzsh_salah_location_knobs}; i += 3 )); do
          [[ ${_inzsh_salah_location_knobs[i]} == INZSH_SALAH_AUTOLOCATE ]] || continue
          local spec=${_inzsh_salah_location_knobs[i+1]}
          local shipped=${_inzsh_salah_location_knobs[i+2]}
          [[ $spec == bool ]] || bad+="spec=$spec"
          [[ $shipped == 0 ]] || bad+="default=$shipped"
        done
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call shipped
      The output should eq ''
    End

    It 'refuses to fetch at all while it is off'
      # The permission is checked first, before a URL is read or a directory is made, so an
      # unconfigured machine cannot be made to resolve a hostname by a stray call.
      forbidden() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_AUTOLOCATE=0
        local -a bad=()
        _inzsh_salah_locate_fetch $inzsh_spec_salah_now && bad+=fetched
        _inzsh_salah_locate_refresh $inzsh_spec_salah_now && bad+=refreshed
        local -a files=("$inzsh_spec_salah_cache"/**/*(N))
        (( ${#files} )) && bad+="wrote=${#files}"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call forbidden
      The output should eq ''
      The stderr should eq ''
    End

    It 'ignores a cached position entirely while it is off'
      # A file left behind by a machine that once had the lookup on must not keep answering after
      # it is switched off. The permission governs the READ as well as the request.
      ignored() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_AUTOLOCATE=1
        _inzsh_salah_location_write 31.63 -7.99 $inzsh_spec_salah_now
        local -a seen=()
        seen+="$(inzsh_spec_salah_where $inzsh_spec_salah_now)"
        typeset -g INZSH_SALAH_AUTOLOCATE=0
        seen+="$(inzsh_spec_salah_where $inzsh_spec_salah_now)"
        print -rl -- $seen
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call ignored
      The lines of output should eq 2
      The line 1 of output should eq '31.63 -7.99 cache'
      The line 2 of output should eq 'none '
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the stored position'
    It 'round trips through a file written the way the day cache writes one'
      trip() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_AUTOLOCATE=1
        local -a bad=()
        _inzsh_salah_location_write 21.4225 39.8262 $inzsh_spec_salah_now || bad+=write
        _inzsh_salah_location_read $inzsh_spec_salah_now || bad+=read
        [[ $REPLY == '21.4225 39.8262' ]] || bad+="got=$REPLY"
        (( _inzsh_salah_location_age == 0 )) || bad+="age=$_inzsh_salah_location_age"
        local -a leftovers=("$inzsh_spec_salah_cache"/*.tmp(N))
        (( ${#leftovers} )) && bad+="temporaries=${#leftovers}"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call trip
      The output should eq ''
    End

    It 'reports its age, in seconds, against the instant it is asked about'
      aged() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_salah_now - 7200 ))
        _inzsh_salah_location_read $inzsh_spec_salah_now
        print -r -- "$_inzsh_salah_location_age"
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call aged
      The output should eq '7200'
    End

    It 'never expires, however old it is'
      # THE fallback the whole feature runs on. A TTL says when a refresh is due, not when an
      # answer stops being usable: a laptop offline for a year is still almost certainly in the
      # same city, and a prayer segment that vanished because a lookup failed would be worse than
      # a stale one.
      kept() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_AUTOLOCATE=1 INZSH_SALAH_AUTOLOCATE_TTL=300
        _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_salah_now - 365 * 86400 ))
        inzsh_spec_salah_where $inzsh_spec_salah_now
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call kept
      The output should eq '21.4225 39.8262 cache'
    End

    Describe 'is a miss when the file says anything unusable'
      # The file outlives the shell that wrote it, can be truncated, and can be edited. `0 0` is a
      # real place in the Gulf of Guinea, so a coordinate that does not parse is nothing rather
      # than zero.
      #
      # $1 is the file, written as `key=value` fields separated by `%` — shellspec reads a
      # Parameters row as ONE PHYSICAL LINE, so an entry cannot be spelled out here as the several
      # lines it really is. A value with no `=` in it is written to the file verbatim.
      Parameters
        'junk'                                 'garbage'
        ''                                     'an empty file'
        'version=1'                            'no position at all'
        'version=9%lat=21.4225%lon=39.8262'    'a future format'
        'version=1%lat=banana%lon=39.8262'     'a latitude that is not a number'
        'version=1%lat=91%lon=39.8262'         'a latitude off the globe'
        'version=1%lat=21.4225%lon=-181'       'a longitude off the globe'
        'version=1%lon=39.8262'                'half a position'
      End

      It "refuses $2"
        damaged() {
          inzsh_spec_salah_env || return 1
          typeset -g INZSH_SALAH_AUTOLOCATE=1
          local file=$inzsh_spec_salah_cache/location tab=$'\t' field
          : > "$file"
          if [[ $1 == *=* ]]; then
            for field in ${(s:%:)1}; do
              print -r -- "${field%%=*}$tab${field#*=}" >> "$file"
            done
          else
            print -r -- "$1" > "$file"
          fi

          local -a bad=()
          _inzsh_salah_location_read $inzsh_spec_salah_now && bad+=accepted
          [[ -n $REPLY ]] && bad+="left=$REPLY"
          print -rl -- $bad
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call damaged "$1"
        The output should eq ''
        The stderr should eq ''
      End
    End

    It 'refuses to write a position that is not one'
      unwritten() {
        inzsh_spec_salah_env || return 1
        local -a bad=()
        _inzsh_salah_location_write 91 39.8262 $inzsh_spec_salah_now && bad+=latitude
        _inzsh_salah_location_write 21.4225 banana $inzsh_spec_salah_now && bad+=longitude
        _inzsh_salah_location_write 21.4225 39.8262 later && bad+=stamp
        local -a files=("$inzsh_spec_salah_cache"/*(N))
        (( ${#files} )) && bad+="wrote=${#files}"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call unwritten
      The output should eq ''
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the refresh'
    It 'does nothing while the stored position is younger than the TTL'
      # `_inzsh_salah_locate_fetch` is stood in with a spy, so "did not ask" is asserted rather
      # than inferred from a timing.
      fresh() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_AUTOLOCATE=1 INZSH_SALAH_AUTOLOCATE_TTL=3600
        _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_salah_now - 60 ))

        local saved=$functions[_inzsh_salah_locate_fetch]
        typeset -g inzsh_spec_fetched=0
        _inzsh_salah_locate_fetch() { inzsh_spec_fetched=1; return 1 }
        _inzsh_salah_locate_refresh $inzsh_spec_salah_now
        local -i rc=$?
        functions[_inzsh_salah_locate_fetch]=$saved

        print -r -- "rc=$rc fetched=$inzsh_spec_fetched"
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call fresh
      The output should eq 'rc=0 fetched=0'
    End

    Describe 'asks again once it is due, or was never asked at all'
      # $1 how old the stored position is, in seconds, or `none` for no file.
      Parameters
        none
        3601
        86400
      End

      It "asks when the stored position is ($1)"
        due() {
          inzsh_spec_salah_env || return 1
          typeset -g INZSH_SALAH_AUTOLOCATE=1 INZSH_SALAH_AUTOLOCATE_TTL=3600
          [[ $1 == none ]] ||
            _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_salah_now - $1 ))

          local saved=$functions[_inzsh_salah_locate_fetch]
          typeset -g inzsh_spec_fetched=0
          _inzsh_salah_locate_fetch() { inzsh_spec_fetched=1; return 1 }
          _inzsh_salah_locate_refresh $inzsh_spec_salah_now
          functions[_inzsh_salah_locate_fetch]=$saved

          print -r -- "fetched=$inzsh_spec_fetched"
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call due "$1"
        The output should eq 'fetched=1'
      End
    End

    It 'leaves the last good position in place when the lookup fails'
      # The fallback, end to end and with a real client: the URL points at a port on this machine
      # that nothing is listening on, under a one-second ceiling. Whatever the client does about
      # it, the previously stored position is still readable afterwards and nothing is left in the
      # directory but the entry itself.
      resilient() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_AUTOLOCATE=1 INZSH_SALAH_AUTOLOCATE_TTL=300
        typeset -g INZSH_SALAH_AUTOLOCATE_TIMEOUT=1
        typeset -g INZSH_SALAH_AUTOLOCATE_URL='http://127.0.0.1:9/inzsh-spec-nothing-here'
        _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_salah_now - 86400 ))

        local -a bad=()
        _inzsh_salah_locate_refresh $inzsh_spec_salah_now && bad+=reported-success
        _inzsh_salah_location_read $inzsh_spec_salah_now || bad+=lost-the-position
        [[ $REPLY == '21.4225 39.8262' ]] || bad+="got=$REPLY"
        local -a leftovers=("$inzsh_spec_salah_cache"/*.raw(N) "$inzsh_spec_salah_cache"/*.tmp(N))
        (( ${#leftovers} )) && bad+="leftovers=${#leftovers}"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call resilient
      The output should eq ''
      The stderr should eq ''
    End

    It 'writes nothing at all when there was nothing stored and the lookup failed'
      # With the lookup on, no coordinates set and nothing ever cached, the segment is absent —
      # which is the truthful rendering of not knowing where you are.
      empty_handed() {
        inzsh_spec_salah_env || return 1
        typeset -g INZSH_SALAH_AUTOLOCATE=1 INZSH_SALAH_AUTOLOCATE_TIMEOUT=1
        typeset -g INZSH_SALAH_AUTOLOCATE_URL='http://127.0.0.1:9/inzsh-spec-nothing-here'

        local -a bad=()
        _inzsh_salah_locate_refresh $inzsh_spec_salah_now && bad+=reported-success
        [[ -e $inzsh_spec_salah_cache/location ]] && bad+=wrote-a-position
        local answer=$(inzsh_spec_salah_where $inzsh_spec_salah_now)
        [[ ${answer% } == none ]] || bad+="answer=$answer"
        print -rl -- $bad
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call empty_handed
      The output should eq ''
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the endpoint'
    Describe 'accepts only a URL a client will treat as one'
      # The value reaches an external command's argument list, so a knob that could name a
      # `file://` path or a scheme a client invents its own meaning for is a knob that does more
      # than it says. $1 what is set; $2 what is used.
      Parameters
        ''                              'default'
        'https://example.invalid/where' 'https://example.invalid/where'
        'http://127.0.0.1:8080/'        'http://127.0.0.1:8080/'
        'file:///etc/passwd'            'default'
        'ftp://example.invalid/'        'default'
        'example.invalid'               'default'
        'https://'                      'default'
        '-o/tmp/inzsh-spec'             'default'
      End

      It "reads '$1' as $2"
        urled() {
          inzsh_spec_salah_env || return 1
          typeset -g INZSH_SALAH_AUTOLOCATE_URL=$1
          _inzsh_salah_autolocate_url
          local shown=$REPLY
          [[ $shown == $_inzsh_salah_autolocate_url_default ]] && shown=default
          print -r -- "$shown"
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call urled "$1"
        The output should eq "$2"
      End
    End

    It 'ships a default that is HTTPS and needs no key'
      # Documented in `docs/configuration.md`, and pinned here so it cannot change without the
      # page changing with it.
      shipped() {
        print -r -- "$_inzsh_salah_autolocate_url_default"
      }
      When call shipped
      The output should eq 'https://ipapi.co/json/'
    End

    Describe 'bounds the request and the interval, falling back to the shipped numbers'
      # $1 what is set; $2 the TTL and the timeout that come out.
      Parameters
        ''      '86400 5'
        '0'     '86400 5'
        '299'   '86400 5'
        '61'    '86400 5'
        '300'   '300 5'
        '3600'  '3600 5'
        'lots'  '86400 5'
      End

      It "reads a TTL of '$1' as ${2%% *}"
        bounded() {
          inzsh_spec_salah_env || return 1
          typeset -g INZSH_SALAH_AUTOLOCATE_TTL=$1
          _inzsh_salah_autolocate_ttl
          local ttl=$REPLY
          _inzsh_salah_autolocate_timeout
          print -r -- "$ttl $REPLY"
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call bounded "$1"
        The output should eq "$2"
      End
    End

    Describe 'bounds the ceiling on the request itself'
      Parameters
        ''    5
        0     5
        61    5
        -1    5
        1     1
        60    60
        soon  5
      End

      It "reads a timeout of '$1' as $2"
        ceiling() {
          inzsh_spec_salah_env || return 1
          typeset -g INZSH_SALAH_AUTOLOCATE_TIMEOUT=$1
          _inzsh_salah_autolocate_timeout
          print -r -- "$REPLY"
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
        When call ceiling "$1"
        The output should eq "$2"
      End
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'reading an answer'
    # Not a JSON parser and not pretending to be one: it looks for a pair of numbers under two
    # spellings and takes them. Anything else — an error page, an HTML redirect, a rate-limit
    # notice — matches nothing and is a failure, which is the treatment it deserves.
    Describe 'takes a position out of a body that carries one'
      Parameters
        '{"city": "Placeholder", "latitude": 21.4225, "longitude": 39.8262}'  '21.4225 39.8262'
        '{"latitude":21.4225,"longitude":39.8262}'                           '21.4225 39.8262'
        '{ "latitude" : -33.86 , "longitude" : 151.20 }'                     '-33.86 151.20'
        '{"status":"success","lat":31.63,"lon":-7.99}'                       '31.63 -7.99'
        '{"latitude": 21, "longitude": 39}'                                  '21 39'
      End

      It "reads $2"
        When call inzsh_spec_salah_parse "$1"
        The output should eq "$2"
      End
    End

    Describe 'and refuses a body that does not'
      Parameters
        '<html><body>429 Too Many Requests</body></html>'
        '{"error": true, "reason": "quota exceeded"}'
        '{"latitude": 21.4225}'
        '{"latitude": "north", "longitude": "east"}'
        '{"latitude": 210.5, "longitude": 39.8262}'
        ''
        'not json at all'
      End

      It "refuses it"
        When call inzsh_spec_salah_parse "$1"
        The output should eq 'no'
      End
    End

    It 'refuses a body that is not there'
      absent() {
        inzsh_spec_salah_env || return 1
        _inzsh_salah_locate_parse "$inzsh_spec_salah_cache/nothing" && print -r -- accepted
        inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
      }
      When call absent
      The output should eq ''
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/salah/location.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sources silently in a single-byte locale, on its own'
      alone() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          source "$1/lib/salah/location.zsh"
          print -r -- "located=${+functions[_inzsh_salah_location]}" \
            "knobs=${#_inzsh_salah_location_knobs}"
        ' inzsh-salah-loc-alone "$SHELLSPEC_PROJECT_ROOT" < /dev/null
      }
      When call alone
      The output should eq 'located=1 knobs=18'
      The stderr should eq ''
    End

    It 'refuses to answer rather than erroring when the arithmetic is not loaded'
      # Range checking belongs to `lib/salah/calc.zsh`, and without it a coordinate reaching
      # `(( ))` is a fatal error in the middle of a hook. Refusing is the safe answer.
      unloaded() {
        zsh -f -c '
          source "$1/lib/salah/location.zsh"
          INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
          local -a bad=()
          _inzsh_salah_location 1780315200 && bad+=located
          _inzsh_salah_position_ok 21.4225 39.8262 && bad+=validated
          print -r -- "${bad[*]}"
        ' inzsh-salah-loc-guard "$SHELLSPEC_PROJECT_ROOT" < /dev/null
      }
      When call unloaded
      The output should eq ''
      The stderr should eq ''
    End

    It 'names nothing from the engine'
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
        done < "$SHELLSPEC_PROJECT_ROOT/lib/salah/location.zsh"
        print -rl -- $bad
      }
      When call unattached
      The output should eq ''
    End

    It 'holds every restated default equal to the one it declares'
      # Three numbers written twice: once as the fallback this file uses when the config layer is
      # not loaded, and once in the table the registry absorbs. A disagreement between them is
      # invisible — both values are plausible, and which you get depends on how much was sourced.
      agree() {
        local -a bad=()
        local -i i
        local -A declared=()
        for (( i = 1; i <= ${#_inzsh_salah_location_knobs}; i += 3 )); do
          declared[${_inzsh_salah_location_knobs[i]}]=${_inzsh_salah_location_knobs[i+2]}
        done
        [[ ${declared[INZSH_SALAH_AUTOLOCATE_TTL]} == $_inzsh_salah_autolocate_ttl_default ]] ||
          bad+=ttl
        [[ ${declared[INZSH_SALAH_AUTOLOCATE_TIMEOUT]} ==
           $_inzsh_salah_autolocate_timeout_default ]] || bad+=timeout
        [[ ${declared[INZSH_SALAH_AUTOLOCATE_URL]} == $_inzsh_salah_autolocate_url_default ]] ||
          bad+=url
        print -rl -- $bad
      }
      When call agree
      The output should eq ''
    End

    It 'names no `.claude` path and no absolute path from this machine'
      neutral() {
        local line
        local -a bad=()
        while IFS= read -r line; do
          [[ $line == *'.claude'* || $line == *'/Users/'* || $line == *'/home/'* ]] && bad+=$line
        done < "$SHELLSPEC_PROJECT_ROOT/lib/salah/location.zsh"
        print -rl -- $bad
      }
      When call neutral
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'unreachable from anything that draws a prompt'
    # THE guarantee the whole design rests on, and it is stronger than a timeout because it does
    # not depend on the timeout working. The lookup is reached from exactly one place outside
    # this file — the `inzsh locate` command in `lib/core/doctor.zsh`, which a PERSON types —
    # and from nothing that renders: not the segment, not the cache, not a hook, not the entry
    # point.

    It 'is named by no file outside `lib/salah/location.zsh` and its one public face'
      contained() {
        setopt local_options extended_glob
        local root=$SHELLSPEC_PROJECT_ROOT
        local file line
        local -a bad=()
        for file in $root/lib/**/*.zsh $root/inzsh.zsh-theme $root/presets/*.zsh(N); do
          [[ ${file#$root/} == lib/salah/location.zsh ]] && continue
          # The command layer is the documented exception: `inzsh locate` exists to be the one
          # attended way to run the lookup, so the name appearing there is the feature.
          [[ ${file#$root/} == lib/core/doctor.zsh ]] && continue
          while IFS= read -r line; do
            [[ ${line##[[:space:]]#} == \#* ]] && continue
            [[ $line == *_inzsh_salah_locate_* ]] && bad+="${file#$root/}: $line"
          done < $file
        done
        print -rl -- $bad
      }
      When call contained
      The output should eq ''
    End

    It 'is reached from one function inside it, and that one from nowhere'
      # Read out of the loaded bodies rather than the text, so a call written any way at all is
      # counted. `_inzsh_salah_locate_refresh` may name the fetch; nothing may name the refresh.
      counted() {
        local name
        local -a callers_of_fetch=() callers_of_refresh=()
        for name in ${(k)functions[(I)_inzsh_salah_*]}; do
          [[ $name == _inzsh_salah_locate_fetch ]] ||
            [[ ${functions[$name]} != *_inzsh_salah_locate_fetch* ]] || callers_of_fetch+=$name
          [[ $name == _inzsh_salah_locate_refresh ]] ||
            [[ ${functions[$name]} != *_inzsh_salah_locate_refresh* ]] ||
              callers_of_refresh+=$name
        done
        print -r -- "fetch=${callers_of_fetch[*]} refresh=${callers_of_refresh[*]}"
      }
      When call counted
      The output should eq 'fetch=_inzsh_salah_locate_refresh refresh='
    End

    It 'is the only place a client is named at all'
      # One `curl`, one `wget`, in one function. A second one anywhere would be a second network
      # call, and the claim at the top of the file would stop being true.
      single() {
        setopt local_options extended_glob
        local root=$SHELLSPEC_PROJECT_ROOT
        local file line bare word
        local -a bad=()
        for file in $root/lib/**/*.zsh $root/inzsh.zsh-theme; do
          while IFS= read -r line; do
            bare=${line##[[:space:]]#}
            [[ $bare == \#* ]] && continue
            for word in curl wget nc ssh openssl; do
              [[ $bare == *[[:space:]]${word}[[:space:]]* || $bare == ${word}[[:space:]]* ]] &&
                bad+="${file#$root/}: $bare"
            done
          done < $file
        done
        print -rl -- $bad
      }
      When call single
      The lines of output should eq 2
      The output should include 'lib/salah/location.zsh: command curl'
      The output should include 'lib/salah/location.zsh: command wget'
    End
  End
End
