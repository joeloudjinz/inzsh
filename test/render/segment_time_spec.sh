Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/time.zsh

# The clock segment — `lib/segments/time.zsh`. What it registers, and what it writes into
# `_inzsh_segment_text[TIME]` for a PINNED instant.
#
# Every example that asserts a string pins the epoch and the zone. That is the whole reason
# `_inzsh_segment_time_build` takes an argument at all: a clock that reads itself can only be
# tested against itself, and an example that compared the segment to a second reading of the same
# clock would pass while rendering the wrong minute, the wrong zone or the wrong century.
#
# `TZ=UTC` rather than the runner's zone, and formats made of digits rather than of names, so the
# expectations below say the same thing on every machine that runs them.
#
# No palette value reaches this file. The one example that pins colour pins it through
# `_inzsh_role[text-muted]`.

# The instants these examples use. A round one, a mid-minute one, a second before a year rolls
# over, and one exactly on the hour.
#
#   0           1970-01-01 00:00:00 UTC
#   1785121585  2026-07-27 03:06:25 UTC
#   1704067199  2023-12-31 23:59:59 UTC
#   1785142800  2026-07-27 09:00:00 UTC

# Build for a pinned instant in a pinned zone and print what the segment wrote, in brackets so
# that an empty entry — the absent case — is a visible result rather than a blank line.
inzsh_spec_time() {
  emulate -L zsh

  local -x TZ=UTC
  _inzsh_segment_text=()
  _inzsh_segment_time_build "$@"
  print -r -- "[${_inzsh_segment_text[TIME]-'(no entry)'}]"
}

# The same, with `INZSH_TIME_FORMAT` set to $1 for the call and nothing else changed.
inzsh_spec_time_format() {
  emulate -L zsh

  local INZSH_TIME_FORMAT=$1
  shift
  inzsh_spec_time "$@"
}

# The segment as the renderer draws it, on a right prompt of its own.
inzsh_spec_time_drawn() {
  emulate -L zsh

  local -x TZ=UTC
  _inzsh_segment_text=()
  _inzsh_segment_time_build "$@"
  _inzsh_left=()
  _inzsh_right=(TIME)
  _inzsh_render_build right
  typeset -g inzsh_spec_drawn=$REPLY

  return 0
}

# The non-comment lines of the segment source, in `inzsh_spec_lines`, for the structural groups.
# Comments are skipped because the prose in the file names `date` and `$(` precisely in order to
# say that neither is used.
inzsh_spec_time_lines() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga inzsh_spec_lines
  inzsh_spec_lines=()

  local line bare
  while IFS= read -r line; do
    bare=${line##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    inzsh_spec_lines+=$line
  done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/time.zsh"

  return 0
}

Describe 'the clock segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers a rank default, a foreground role and an importance'
      registered() {
        local -a got=()
        got+=rank=${_inzsh_segment_defaults[TIME]-}
        got+=role=${_inzsh_segment_fg_role[TIME]-}
        got+=importance=${_inzsh_segment_importance[TIME]-}
        print -r -- "${got[*]}"
      }
      When call registered
      The output should eq 'rank=-2 role=text-muted importance=3'
    End

    It 'is read by the engine as the second segment from the right edge'
      # -1 is the rightmost, so -2 sits one place inward, and the render order for the two of them
      # is most-negative-first. The rank is a DEFAULT: a user's `INZSH_TIME_RANK` outranks it.
      ranked() {
        _inzsh_rank_of TIME
        local shipped=$REPLY
        local INZSH_RETVAL_RANK=-1
        _inzsh_rank_split TIME RETVAL
        local order="right=${_inzsh_right[*]}"
        local INZSH_TIME_RANK=2
        _inzsh_rank_split TIME
        print -r -- "$shipped $order moved=${_inzsh_left[*]}"
      }
      When call ranked
      The output should eq '-2 right=TIME RETVAL moved=TIME'
    End

    It 'registers once however many times it is sourced'
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/time.zsh"
          source "$1/lib/segments/time.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${#_inzsh_segment_fg_role}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_defaults[TIME]}"
        ' inzsh-time-twice "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 1 1 -2'
      The stderr should eq ''
    End

    It 'draws nothing at load — sourcing registers and returns'
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local before="${PROMPT-unset}|${RPROMPT-unset}"
          source "$1/lib/segments/time.zsh"
          local after="${PROMPT-unset}|${RPROMPT-unset}"
          local prompt=changed
          [[ $before == $after ]] && prompt=same
          print -r -- "texts=${#_inzsh_segment_text} prompt=$prompt"
        ' inzsh-time-load "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'texts=0 prompt=same'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the pinned instant'
    Describe 'the default format is hours and minutes, 24-hour, zero-padded'
      Parameters
        0          '[00:00]'
        1785121585 '[03:06]'
        1704067199 '[23:59]'
        1785142800 '[09:00]'
      End

      It "renders epoch $1 as $2"
        When call inzsh_spec_time "$1"
        The output should eq "$2"
      End
    End

    It 'follows the epoch it was given and not the clock on the wall'
      # The seam, stated as a property: two calls a second apart in real time, pinned to instants
      # a year apart, differ by a year. A build that read `$EPOCHSECONDS` regardless would return
      # the same string twice.
      injected() {
        local INZSH_TIME_FORMAT='%Y-%m-%d %H:%M'
        inzsh_spec_time 0
        inzsh_spec_time 1785121585
      }
      When call injected
      The output should eq '[1970-01-01 00:00]
[2026-07-27 03:06]'
    End

    It 'renders the same instant identically however often it is asked'
      stable() {
        local -a seen=()
        local -i i
        for (( i = 1; i <= 3; i++ )); do
          inzsh_spec_time 1785121585
        done
      }
      When call stable
      The output should eq '[03:06]
[03:06]
[03:06]'
    End

    It 'defaults to the live clock when no instant is given'
      # The only example that touches the real time, and it is careful about it: the live clock is
      # read either side of the call and the answer must be one of the two, so a run that crosses
      # a minute boundary is right rather than flaky.
      live() {
        local -x TZ=UTC
        local before after
        strftime -s before '%H:%M' $EPOCHSECONDS
        _inzsh_segment_time_build
        local drawn=${_inzsh_segment_text[TIME]}
        strftime -s after '%H:%M' $EPOCHSECONDS
        [[ $drawn == $before || $drawn == $after ]] && print -r -- now || print -r -- "$drawn"
      }
      When call live
      The output should eq 'now'
    End

    It 'takes the foreground role it registered'
      # Asserted through `_inzsh_role`, never as a value: the claim is that the segment took the
      # muted role, and a palette change cannot fail it.
      muted() {
        inzsh_spec_time_drawn 1785121585
        local -a missing=()
        [[ $inzsh_spec_drawn == *"%F{${_inzsh_role[text-muted]}}"* ]] || missing+=role
        [[ $inzsh_spec_drawn == *' 03:06 '* ]]                       || missing+=text
        print -r -- "${missing[*]}"
      }
      When call muted
      The output should eq ''
    End

    It 'emits no colour of its own'
      uncoloured() {
        local INZSH_TIME_FORMAT='%H:%M:%S'
        _inzsh_segment_time_build 1785121585
        local -a found=()
        [[ ${_inzsh_segment_text[TIME]} == *'%'[FKfk]* ]] && found+=escape
        print -r -- "${found[*]}"
      }
      When call uncoloured
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'INZSH_TIME_FORMAT'
    # A `strftime` format, and validation is deliberately loose: the set of conversions belongs to
    # the C library and differs between platforms, so the format is TRIED and judged on what came
    # back rather than parsed here.
    Describe 'a format the C library understands is used as it stands'
      Parameters
        '%H:%M'      '[03:06]'
        '%H:%M:%S'   '[03:06:25]'
        '%d/%m'      '[27/07]'
        '%Y-%m-%d'   '[2026-07-27]'
        '%s'         '[1785121585]'
        'at %H%Mh'   '[at 0306h]'
      End

      It "renders the format '$1' as $2"
        When call inzsh_spec_time_format "$1" 1785121585
        The output should eq "$2"
      End
    End

    Describe 'a format that produces nothing usable falls back to the default'
      # `%n` is the hostile one and the reason the check exists at all: it renders a NEWLINE, and
      # a newline in a fragment breaks the row the renderer just measured. An empty setting is the
      # same case by the other route — an `INZSH_TIME_FORMAT=` left behind in a zshrc means "no
      # opinion", exactly as an empty value does everywhere else in the theme.
      Parameters
        ''
        '%n'
        '%t'
      End

      It "falls back for a format of '$1'"
        When call inzsh_spec_time_format "$1" 1785121585
        The output should eq '[03:06]'
      End
    End

    It 'never lets a control character into the fragment, whatever the format says'
      # The property behind the group above, swept rather than enumerated: nothing this knob can
      # be set to may put a newline, a tab or an escape into the row.
      controlled() {
        local -x TZ=UTC
        local INZSH_TIME_FORMAT; local -a bad=()
        for INZSH_TIME_FORMAT in '%n' '%t' '%n%t' '%H%n%M' '' '%H:%M'; do
          _inzsh_segment_time_build 1785121585
          [[ ${_inzsh_segment_text[TIME]} == *[[:cntrl:]]* ]] &&
            bad+=${INZSH_TIME_FORMAT:-empty}
          [[ -n ${_inzsh_segment_text[TIME]} ]] || bad+=absent:${INZSH_TIME_FORMAT:-empty}
        done
        print -r -- "${bad[*]}"
      }
      When call controlled
      The output should eq ''
    End

    It 'doubles a per cent in the rendered output, so prompt expansion cannot read it'
      # The fragment is spliced into PROMPT and prompt expansion runs over it. A single `%` there
      # is the start of an escape the user never wrote — `%d` would expand to a directory.
      # Doubled, it reaches the screen as one per cent, and `_inzsh_width` already counts `%%`
      # as one column.
      escaped() {
        local INZSH_TIME_FORMAT='%H%% %M'
        inzsh_spec_time 1785121585
        _inzsh_segment_time_build 1785121585
        _inzsh_width "${_inzsh_segment_text[TIME]}"
        print -r -- "columns=$REPLY"
      }
      When call escaped
      The output should eq '[03%% 06]
columns=6'
    End

    It 'reads the knob at build time, so a change takes effect at the next prompt'
      # Nothing is cached at source time. The knob is read on every build, which is what lets a
      # user set it at a prompt and see it on the next one with no re-source and no new shell.
      relive() {
        local INZSH_TIME_FORMAT='%H:%M'
        inzsh_spec_time 1785121585
        INZSH_TIME_FORMAT='%d/%m'
        inzsh_spec_time 1785121585
      }
      When call relive
      The output should eq '[03:06]
[27/07]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'hostile input'
    Describe 'an epoch that is not an epoch falls back to the live clock'
      # The argument is the theme's own to pass, so a bad one is a bug here rather than in a
      # user's config — and while it is being found, a prompt still draws a clock. The assertion
      # is on the SHAPE, since the answer is the real time.
      Parameters
        'zzz'
        ''
        '1.5'
        '2026-07-27'
        ' 100'
      End

      It "still draws a clock for an epoch of '$1'"
        shaped() {
          local -x TZ=UTC
          _inzsh_segment_text=()
          _inzsh_segment_time_build "$1"
          local text=${_inzsh_segment_text[TIME]}
          [[ $text == [0-9][0-9]:[0-9][0-9] ]] && print -r -- clock || print -r -- "[$text]"
        }
        When call shaped "$1"
        The output should eq 'clock'
      End
    End

    It 'renders an epoch before the one it counts from'
      When call inzsh_spec_time -100
      The output should eq '[23:58]'
    End

    It 'is absent rather than broken when the datetime module is not there'
      # `strftime` is a module builtin. Without it there is no clock to read, and a segment with
      # nothing to show writes nothing — it does not error, it does not leave a placeholder where
      # a time should be, and it does not write a word to stderr on its way past.
      #
      # Both routes in: with no argument there is no `$EPOCHSECONDS` either, and with a pinned
      # epoch the build gets as far as a `strftime` that is no longer there.
      unloaded() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/time.zsh"
          zmodload -u zsh/datetime
          _inzsh_segment_time_build
          print -r -- "live=$? [${_inzsh_segment_text[TIME]}]"
          _inzsh_segment_time_build 1785121585
          print -r -- "pinned=$? [${_inzsh_segment_text[TIME]}]"
        ' inzsh-time-unloaded "$SHELLSPEC_PROJECT_ROOT"
      }
      When call unloaded
      The output should eq 'live=0 []
pinned=0 []'
      The stderr should eq ''
    End

    It 'rewrites the entry on every build rather than accumulating'
      rewritten() {
        local INZSH_TIME_FORMAT='%H:%M'
        inzsh_spec_time 1785121585
        INZSH_TIME_FORMAT='%n'
        inzsh_spec_time 1785142800
      }
      When call rewritten
      The output should eq '[03:06]
[09:00]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/segments/time.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'builds without forking — this runs before every prompt'
      forks() {
        inzsh_spec_time_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'$('* || $line == *'`'* || $line == *whence* ]] && bad+=$line
        done
        print -r -- "${#bad}"
      }
      When call forks
      The output should eq '0'
    End

    It 'never calls date — the time comes from a module, not from a process'
      # `zsh/datetime` contains the word and is the whole point, so the search is for `date` as a
      # word rather than as a substring.
      dated() {
        inzsh_spec_time_lines
        local line; local -a bad=()
        (( ${#inzsh_spec_lines} > 10 )) || bad+=no-lines-scanned
        for line in "${inzsh_spec_lines[@]}"; do
          [[ " $line " == *[^a-zA-Z_]date[^a-zA-Z_]* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call dated
      The output should eq ''
    End

    It 'loads the module it depends on'
      moduled() {
        inzsh_spec_time_lines
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
        inzsh_spec_time_lines
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
