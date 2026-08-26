Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/date.zsh

# The calendar segment — `lib/segments/date.zsh`. What it registers, what it writes into
# `_inzsh_segment_text[DATE]` for a PINNED instant, and — the example that matters most in this
# milestone — that it ships HIDDEN.
#
# Every example that asserts a string pins the epoch, the zone AND the locale. The epoch for the
# same reason the clock spec pins one: a segment that reads its own clock can only be tested
# against itself. The locale because this format spells the weekday and the month out, and their
# spelling belongs to the C library — `LC_ALL=C` is the one setting every machine that runs this
# suite agrees on.
#
# No palette value reaches this file. The one example that pins colour pins it through
# `_inzsh_role[text-muted]`.

# The instants these examples use.
#
#   0           1970-01-01 Thursday, a single-digit day
#   1785121585  2026-07-27 Monday
#   1704067199  2023-12-31 Sunday, one second before a year rolls over
#   1785142800  2026-07-27 Monday, later the same day — the date must not move

# Build for a pinned instant, in a pinned zone and a pinned locale, and print what the segment
# wrote — in brackets, so an empty entry is a visible result rather than a blank line.
inzsh_spec_date() {
  emulate -L zsh

  local -x TZ=UTC LC_ALL=C
  _inzsh_segment_text=()
  _inzsh_segment_date_build "$@"
  print -r -- "[${_inzsh_segment_text[DATE]-'(no entry)'}]"
}

# The same, with `INZSH_DATE_FORMAT` set to $1 for the call and nothing else changed.
inzsh_spec_date_format() {
  emulate -L zsh

  local INZSH_DATE_FORMAT=$1
  shift
  inzsh_spec_date "$@"
}

# The segment as the renderer draws it, on a right prompt of its own.
inzsh_spec_date_drawn() {
  emulate -L zsh

  local -x TZ=UTC LC_ALL=C
  _inzsh_segment_text=()
  _inzsh_segment_date_build "$@"
  _inzsh_left=()
  _inzsh_right=(DATE)
  _inzsh_render_build right "${_inzsh_right[@]}"
  typeset -g inzsh_spec_drawn=$REPLY

  return 0
}

# The non-comment lines of the segment source, in `inzsh_spec_lines`, for the structural groups.
# Comments are skipped because the prose in the file names `date`, `$(` and `\u` precisely in
# order to say that none of the three is used.
inzsh_spec_date_lines() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga inzsh_spec_lines
  inzsh_spec_lines=()

  local line bare
  while IFS= read -r line; do
    bare=${line##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    inzsh_spec_lines+=$line
  done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/date.zsh"

  return 0
}

Describe 'the calendar segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers a rank default, a foreground role and an importance'
      registered() {
        local -a got=()
        got+=rank=${_inzsh_segment_defaults[DATE]-}
        got+=role=${_inzsh_segment_fg_role[DATE]-}
        got+=importance=${_inzsh_segment_importance[DATE]-}
        print -r -- "${got[*]}"
      }
      When call registered
      The output should eq 'rank=0 role=text-muted importance=3'
    End

    # THE DEFINING PROPERTY OF THIS MILESTONE. Rank 0 is what the engine reads as hidden, and a
    # segment that shipped visible would be the bug. Asserted through the SPLIT rather than
    # against the number, because "0 means hidden" is the engine's sentence and this is the
    # engine saying it: neither side gets the segment, and it lands in `_inzsh_hidden`.
    It 'ships hidden — the engine puts it on neither side of the prompt'
      hidden() {
        _inzsh_rank_split DATE
        print -rn -- "left=[${_inzsh_left[*]}] right=[${_inzsh_right[*]}] "
        print -r  -- "hidden=[${_inzsh_hidden[*]}]"
      }
      When call hidden
      The output should eq 'left=[] right=[] hidden=[DATE]'
    End

    # And the other half: hidden is a DEFAULT, not a decision. One variable brings it out, on
    # either side, which is the whole interface this segment ships with.
    It 'comes out on whichever side the user ranks it'
      ranked() {
        local INZSH_DATE_RANK=15
        _inzsh_rank_split DATE
        local onleft="left=[${_inzsh_left[*]}]"
        INZSH_DATE_RANK=-15
        _inzsh_rank_split DATE
        print -r -- "$onleft right=[${_inzsh_right[*]}]"
      }
      When call ranked
      The output should eq 'left=[DATE] right=[DATE]'
    End

    It 'registers once however many times it is sourced'
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/date.zsh"
          source "$1/lib/segments/date.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${#_inzsh_segment_fg_role}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_defaults[DATE]}"
        ' inzsh-date-twice "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 1 1 0'
      The stderr should eq ''
    End

    It 'draws nothing at load — sourcing registers and returns'
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local before="${PROMPT-unset}|${RPROMPT-unset}"
          source "$1/lib/segments/date.zsh"
          local after="${PROMPT-unset}|${RPROMPT-unset}"
          local prompt=changed
          [[ $before == $after ]] && prompt=same
          print -r -- "texts=${#_inzsh_segment_text} prompt=$prompt"
        ' inzsh-date-load "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'texts=0 prompt=same'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the pinned instant'
    Describe 'the default format spells the day out'
      Parameters
        0          '[Thursday, 1 January 1970]'
        1785121585 '[Monday, 27 July 2026]'
        1704067199 '[Sunday, 31 December 2023]'
        1785142800 '[Monday, 27 July 2026]'
      End

      It "renders epoch $1 as $2"
        When call inzsh_spec_date "$1"
        The output should eq "$2"
      End
    End

    It 'writes the day unpadded, which is the one thing %-d is there for'
      # The default carries `%-d` rather than `%d`, and the difference only shows on the first
      # nine days of a month. Pinned here so a build whose `strftime` handles the flag
      # differently says so on the machine it is running on rather than on somebody's prompt.
      unpadded() {
        local INZSH_DATE_FORMAT
        inzsh_spec_date 0
        inzsh_spec_date_format '%-d' 0
        inzsh_spec_date_format '%d' 0
      }
      When call unpadded
      The output should eq '[Thursday, 1 January 1970]
[1]
[01]'
    End

    It 'follows the epoch it was given and not the clock on the wall'
      injected() {
        local INZSH_DATE_FORMAT='%Y-%m-%d'
        inzsh_spec_date 0
        inzsh_spec_date 1785121585
      }
      When call injected
      The output should eq '[1970-01-01]
[2026-07-27]'
    End

    It 'renders the same instant identically however often it is asked'
      stable() {
        local -i i
        for (( i = 1; i <= 3; i++ )); do
          inzsh_spec_date 1785121585
        done
      }
      When call stable
      The output should eq '[Monday, 27 July 2026]
[Monday, 27 July 2026]
[Monday, 27 July 2026]'
    End

    It 'defaults to the live clock when no instant is given'
      # The only example that touches the real time, and it is careful about it: the live clock
      # is read either side of the call and the answer must be one of the two, so a run that
      # crosses midnight is right rather than flaky.
      live() {
        local -x TZ=UTC LC_ALL=C
        local before after
        strftime -s before '%A, %-d %B %Y' $EPOCHSECONDS
        _inzsh_segment_date_build
        local drawn=${_inzsh_segment_text[DATE]}
        strftime -s after '%A, %-d %B %Y' $EPOCHSECONDS
        [[ $drawn == $before || $drawn == $after ]] && print -r -- today || print -r -- "$drawn"
      }
      When call live
      The output should eq 'today'
    End

    It 'takes the foreground role it registered'
      # Asserted through `_inzsh_role`, never as a value: the claim is that the segment took the
      # muted role, and a palette change cannot fail it.
      muted() {
        inzsh_spec_date_drawn 1785121585
        local -a missing=()
        [[ $inzsh_spec_drawn == *"%F{${_inzsh_role[text-muted]}}"* ]] || missing+=role
        [[ $inzsh_spec_drawn == *' Monday, 27 July 2026 '* ]]         || missing+=text
        print -r -- "${missing[*]}"
      }
      When call muted
      The output should eq ''
    End

    It 'emits no colour of its own'
      uncoloured() {
        local INZSH_DATE_FORMAT='%Y-%m-%d'
        _inzsh_segment_date_build 1785121585
        local -a found=()
        [[ ${_inzsh_segment_text[DATE]} == *'%'[FKfk]* ]] && found+=escape
        print -r -- "${found[*]}"
      }
      When call uncoloured
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'INZSH_DATE_FORMAT'
    Describe 'a format the C library understands is used as it stands'
      Parameters
        '%Y-%m-%d'      '[2026-07-27]'
        '%d/%m/%Y'      '[27/07/2026]'
        '%B'            '[July]'
        '%A'            '[Monday]'
        'week %V'       '[week 31]'
        '%a %d %b %Y'   '[Mon 27 Jul 2026]'
      End

      It "renders the format '$1' as $2"
        When call inzsh_spec_date_format "$1" 1785121585
        The output should eq "$2"
      End
    End

    Describe 'a format that produces nothing usable falls back to the default'
      # `%n` is the hostile one and the reason the check exists at all: it renders a NEWLINE, and
      # a newline in a fragment breaks the row the renderer just measured. An empty setting is
      # the same case by the other route — `INZSH_DATE_FORMAT=` left in a zshrc means "no
      # opinion", exactly as an empty value does everywhere else in the theme.
      Parameters
        ''
        '%n'
        '%t'
      End

      It "falls back for a format of '$1'"
        When call inzsh_spec_date_format "$1" 1785121585
        The output should eq '[Monday, 27 July 2026]'
      End
    End

    It 'refuses a format there is nothing to render from'
      # The renderer asked directly, which is the only way to reach its two rejections
      # independently of the build's fallback ladder. An empty format renders nothing and says
      # so; a control character in the result is rejected with the same status, so the caller
      # has one branch and not two.
      refused() {
        local -a bad=()
        REPLY=untouched
        _inzsh_date_render '' 1785121585 && bad+=empty-format-accepted
        [[ -z $REPLY ]] || bad+=empty-format-left:$REPLY
        REPLY=untouched
        _inzsh_date_render '%n' 1785121585 && bad+=newline-accepted
        [[ -z $REPLY ]] || bad+=newline-left:$REPLY
        _inzsh_date_render '%Y' 1785121585 || bad+=good-format-refused
        [[ $REPLY == 2026 ]] || bad+=good-format-said:$REPLY
        print -rl -- $bad
      }
      When call refused
      The output should eq ''
    End

    It 'never lets a control character into the fragment, whatever the format says'
      controlled() {
        local -x TZ=UTC LC_ALL=C
        local INZSH_DATE_FORMAT; local -a bad=()
        for INZSH_DATE_FORMAT in '%n' '%t' '%n%t' '%Y%n%m' '' '%Y-%m-%d'; do
          _inzsh_segment_date_build 1785121585
          [[ ${_inzsh_segment_text[DATE]} == *[[:cntrl:]]* ]] &&
            bad+=${INZSH_DATE_FORMAT:-empty}
          [[ -n ${_inzsh_segment_text[DATE]} ]] || bad+=absent:${INZSH_DATE_FORMAT:-empty}
        done
        print -r -- "${bad[*]}"
      }
      When call controlled
      The output should eq ''
    End

    It 'doubles a per cent in the rendered output, so prompt expansion cannot read it'
      escaped() {
        local INZSH_DATE_FORMAT='%d%% %m'
        inzsh_spec_date 1785121585
        _inzsh_segment_date_build 1785121585
        _inzsh_width "${_inzsh_segment_text[DATE]}"
        print -r -- "columns=$REPLY"
      }
      When call escaped
      The output should eq '[27%% 07]
columns=6'
    End

    It 'reads the knob at build time, so a change takes effect at the next prompt'
      relive() {
        local INZSH_DATE_FORMAT='%Y'
        inzsh_spec_date 1785121585
        INZSH_DATE_FORMAT='%m'
        inzsh_spec_date 1785121585
      }
      When call relive
      The output should eq '[2026]
[07]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'hostile input'
    Describe 'an epoch that is not an epoch falls back to the live clock'
      Parameters
        'zzz'
        ''
        '1.5'
        '2026-07-27'
        ' 100'
      End

      It "still draws a date for an epoch of '$1'"
        shaped() {
          setopt local_options extended_glob
          local -x TZ=UTC LC_ALL=C
          local INZSH_DATE_FORMAT='%Y-%m-%d'
          _inzsh_segment_text=()
          _inzsh_segment_date_build "$1"
          local text=${_inzsh_segment_text[DATE]}
          [[ $text == [0-9](#c4)-[0-9](#c2)-[0-9](#c2) ]] &&
            print -r -- date || print -r -- "[$text]"
        }
        When call shaped "$1"
        The output should eq 'date'
      End
    End

    It 'renders an epoch before the one it counts from'
      When call inzsh_spec_date_format '%Y-%m-%d' -100
      The output should eq '[1969-12-31]'
    End

    It 'is absent rather than broken when the datetime module is not there'
      unloaded() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/date.zsh"
          zmodload -u zsh/datetime
          _inzsh_segment_date_build
          print -r -- "live=$? [${_inzsh_segment_text[DATE]}]"
          _inzsh_segment_date_build 1785121585
          print -r -- "pinned=$? [${_inzsh_segment_text[DATE]}]"
        ' inzsh-date-unloaded "$SHELLSPEC_PROJECT_ROOT"
      }
      When call unloaded
      The output should eq 'live=0 []
pinned=0 []'
      The stderr should eq ''
    End

    It 'rewrites the entry on every build rather than accumulating'
      rewritten() {
        local INZSH_DATE_FORMAT='%Y'
        inzsh_spec_date 1785121585
        INZSH_DATE_FORMAT='%n'
        inzsh_spec_date 0
      }
      When call rewritten
      The output should eq '[2026]
[Thursday, 1 January 1970]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/segments/date.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sources silently in a single-byte locale'
      # The `\u` trap, asked the way it actually bites: a file carrying one parses fine in a
      # UTF-8 locale and fails with `character not in range` under `LC_ALL=C`, abandoning every
      # function below the escape.
      bytes() {
        LC_ALL=C zsh -f -c '
          source "$1/lib/segments/date.zsh"
          (( ${+functions[_inzsh_segment_date_build]} )) && print -r -- loaded
        ' inzsh-date-bytes "$SHELLSPEC_PROJECT_ROOT" </dev/null
      }
      When call bytes
      The output should eq 'loaded'
      The stderr should eq ''
    End

    It 'builds without forking — this runs before every prompt'
      forks() {
        inzsh_spec_date_lines
        local line; local -a bad=()
        (( ${#inzsh_spec_lines} > 10 )) || bad+=no-lines-scanned
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'$('* || $line == *'`'* || $line == *whence* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call forks
      The output should eq ''
    End

    It 'never calls date, ps or uptime — the instant comes from a module, not a process'
      # `zsh/datetime` contains the word and is the whole point, so the search is for each name
      # as a WORD rather than as a substring.
      processes() {
        inzsh_spec_date_lines
        local line name; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          for name in date ps uptime; do
            # `${name}` braced: `$name[` would be read as a SUBSCRIPT of the parameter.
            [[ " $line " == *[^a-zA-Z_]${name}[^a-zA-Z_]* ]] && bad+="$name: $line"
          done
        done
        print -rl -- $bad
      }
      When call processes
      The output should eq ''
    End

    It 'writes no \u escape — one would kill the file in a single-byte locale'
      escapes() {
        inzsh_spec_date_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'\u'* || $line == *'\U'* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call escapes
      The output should eq ''
    End

    It 'loads the module it depends on'
      moduled() {
        inzsh_spec_date_lines
        local line; local -a found=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'zmodload -i zsh/datetime'* ]] && found+=module
        done
        print -r -- "${found[*]}"
      }
      When call moduled
      The output should eq 'module'
    End

    It 'carries no hex — colour lives in the token layer and nowhere else'
      hexed() {
        setopt local_options extended_glob
        inzsh_spec_date_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'#'[0-9A-Fa-f](#c6)* ]] && bad+=$line
        done
        print -r -- "${#bad}"
      }
      When call hexed
      The output should eq '0'
    End
  End
End