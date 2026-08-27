Include lib/core/config.zsh
Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/retval.zsh
Include lib/segments/git.zsh
Include lib/segments/ssh.zsh
Include lib/segments/jobs.zsh

# The glyph knobs — `INZSH_GLYPH_<MARK>`, one family over every key of the token layer's glyph
# table. Issue #176: every fixed visual choice becomes a knob, and the marks were the largest
# block of fixed choices left — the separators, the truncation ellipsis, the input marker and
# the design system's state set, all chosen at transcription time and changeable by nobody.
#
# The mechanism under test is the TABLE, deliberately: an override lands in `_inzsh_glyph`
# during `_inzsh_glyphs_resolve` and every reader — the separator chooser, the marker, a
# segment — keeps reading the table it always read. No per-segment glyph knob exists, so no
# segment can drift away from the one home marks live in.
#
# The rule the hostile group pins is the ticket's own: a knob may change what the prompt LOOKS
# like, never WHETHER it draws. A value that could break the string the renderer just measured —
# a `%` opens a prompt escape, a control character breaks the row — is refused whole, and the
# table's own mark stands.

# Resolve with `$1` assigned to the named knob, and print the table entry for key `$2` in
# brackets — so an empty entry is a visible result rather than a blank line.
inzsh_spec_glyph_with() {
  emulate -L zsh

  local var=$1 value=$2 key=$3
  typeset -g "$var"="$value"
  _inzsh_glyphs_resolve
  print -r -- "[${_inzsh_glyph[$key]}]"
  unset "$var"
  _inzsh_glyphs_resolve
}

Describe 'the glyph knob family'
  # ------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'is registered as a family, validator and default'
      registered() {
        # The key holds a literal `*`, which a literal subscript would read as a backslashed
        # character — a variable subscript is taken verbatim.
        local key='INZSH_GLYPH_*'
        print -r -- "${_inzsh_config_family_validators[$key]-missing}"
        print -r -- "[${_inzsh_config_family_defaults[$key]-missing}]"
      }
      When call registered
      The line 1 of output should eq 'any'
      The line 2 of output should eq '[]'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'an override reaches the table'
    # One example per naming rule: a plain key, and a key whose dashes become underscores.
    Describe 'by the key, uppercased, dashes as underscores'
      Parameters
        INZSH_GLYPH_ERROR           E   error
        INZSH_GLYPH_OK              Y   ok
        INZSH_GLYPH_ELLIPSIS        ..  ellipsis
        INZSH_GLYPH_PROMPT          :   prompt
        INZSH_GLYPH_SEP_LEFT        /   sep-left
        INZSH_GLYPH_SEP_RIGHT_ROUND '<' sep-right-round
      End

      It "reads $1 into the $3 entry"
        When call inzsh_spec_glyph_with "$1" "$2" "$3"
        The output should eq "[$2]"
      End
    End

    It 'leaves every other entry exactly as the tables resolve it'
      others() {
        local INZSH_GLYPH_ERROR=E
        _inzsh_glyphs_resolve
        local key; local -a moved=()
        for key in ${(ko)_inzsh_glyph_utf8}; do
          [[ $key == error ]] && continue
          [[ ${_inzsh_glyph[$key]} == ${_inzsh_glyph_utf8[$key]} ||
             ${_inzsh_glyph[$key]} == ${_inzsh_glyph_ascii[$key]} ]] || moved+=$key
        done
        print -r -- "${moved[*]}"
      }
      When call others
      The output should eq ''
    End

    It 'wins over the ASCII degradation — the user reported their own screen'
      # `INZSH_MULTIBYTE=0` selects the ASCII register, and an explicit glyph on top of it is a
      # statement about the same screen. Refusing it would make the two knobs fight.
      reported() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          typeset -g _inzsh_multibyte=0
          typeset -g INZSH_GLYPH_ERROR=@
          _inzsh_glyphs_resolve
          print -r -- "${_inzsh_glyph[error]} ${_inzsh_glyph[ok]}"
        ' inzsh-glyph-reported "$SHELLSPEC_PROJECT_ROOT"
      }
      When call reported
      The output should eq "@ ${_inzsh_glyph_ascii[ok]}"
      The stderr should eq ''
    End

    It 'applies without a config layer at all'
      # The token layer stays independently sourceable, and the knob is read the way
      # `_inzsh_seg_color` reads its colour overrides: the family answers `any`, so the raw
      # parameter IS the registry's answer.
      alone() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          typeset -g INZSH_GLYPH_DOT=,
          _inzsh_glyphs_resolve
          print -r -- "${_inzsh_glyph[dot]} config=${+functions[_inzsh_config_get]}"
        ' inzsh-glyph-alone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call alone
      The output should eq ', config=0'
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'hostile values'
    # Refused whole, never sanitised: a mark the theme had to edit is a mark the user did not
    # set, and the honest fallback is the table's own.
    Describe 'a value that could break the drawn row falls back'
      Parameters
        '%'          percent-opens-an-escape
        '%F{red}x'   escape-laden
        '100%'       trailing-percent
        $'a\nb'      newline
        $'\t'        tab
        $'\e[31m'    raw-csi
      End

      It "refuses ($2) and keeps the table's own mark"
        When call inzsh_spec_glyph_with INZSH_GLYPH_ERROR "$1" error
        The output should eq "[${_inzsh_glyph[error]}]"
      End
    End

    It 'reads set-but-empty as unset, like every other knob'
      When call inzsh_spec_glyph_with INZSH_GLYPH_ERROR '' error
      The output should eq "[${_inzsh_glyph[error]}]"
    End

    It 'never resolves a key to an empty mark, whatever the override was'
      # The glyphs spec's own invariant, held under fire: colour is never the only signal, so
      # no override may leave a signal blank.
      blank() {
        local INZSH_GLYPH_ERROR=$'\n' INZSH_GLYPH_OK='%'
        _inzsh_glyphs_resolve
        local key; local -a empty=()
        for key in ${(ko)_inzsh_glyph}; do
          [[ -n ${_inzsh_glyph[$key]} ]] || empty+=$key
        done
        print -r -- "${empty[*]}"
      }
      When call blank
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'what the renderer draws'
    It 'draws an overridden separator on the built ribbon'
      separator() {
        local INZSH_GLYPH_SEP_LEFT=+
        _inzsh_glyphs_resolve
        _inzsh_segment_text=(A one B two)
        _inzsh_left=(A B)
        _inzsh_right=()
        _inzsh_render_build left "${_inzsh_left[@]}"
        local built=$REPLY
        setopt local_options extended_glob
        built=${built//(%[KF]\{[^\}]#\}|%[fk])/}
        print -r -- "[$built]"
      }
      When call separator
      The output should eq '[ one + two +]'
    End

    It 'takes effect at the next draw, with no re-source'
      # The end-to-end claim: `_inzsh_render` re-resolves the table before it builds, so a knob
      # typed at one prompt has moved the marker by the next. In `zsh -f -i` because the real
      # entry point no-ops in a non-interactive shell — the same harness `prompt_shape_spec`
      # uses, and for the same reason.
      live() {
        zsh -f -i -c '
          local root=$1 file
          unset -m "INZSH_*"
          for file in config detect tokens-256 tokens layout engine rows render; do
            source $root/lib/core/$file.zsh
          done
          typeset -g COLUMNS=80
          _inzsh_render
          local before=$PROMPT
          typeset -g INZSH_GLYPH_PROMPT=:
          _inzsh_render
          local after=$PROMPT
          unset INZSH_GLYPH_PROMPT
          _inzsh_render
          local restored=$PROMPT
          local -a wrong=()
          [[ $after == *:* ]]        || wrong+=unmoved
          [[ $before != *:* ]]       || wrong+=pre-moved
          [[ $restored == $before ]] || wrong+=stuck
          print -r -- "${wrong[*]}"
        ' inzsh-glyph-live "$SHELLSPEC_PROJECT_ROOT"
      }
      When call live
      The output should eq ''
      The stderr should eq ''
    End

    It 'reaches the state marks the segments carry, at the next build'
      # The reason the mechanism is the TABLE: a segment's mark moves with the knob because the
      # segment re-reads the table it always read, at build time — no per-segment glyph knob
      # exists, and none may. One example per source-time copy that used to be fixed.
      segments() {
        local INZSH_GLYPH_ERROR=E INZSH_GLYPH_WARN=W INZSH_GLYPH_AHEAD='^' INZSH_GLYPH_INFO=J
        _inzsh_glyphs_resolve

        local -a wrong=()
        _inzsh_segment_text=()

        _inzsh_segment_retval_build 1
        [[ ${_inzsh_segment_text[RETVAL]} == 'E 1' ]] || wrong+=retval:${_inzsh_segment_text[RETVAL]}

        local -A pinned=(repo 1 branch main dirty 2 ahead 1)
        _inzsh_segment_git_build pinned
        [[ ${_inzsh_segment_text[GIT]} == 'W main ^1' ]] || wrong+=git:${_inzsh_segment_text[GIT]}

        _inzsh_segment_ssh_build somewhere
        [[ ${_inzsh_segment_text[SSH]} == 'W ssh' ]] || wrong+=ssh:${_inzsh_segment_text[SSH]}

        _inzsh_segment_jobs_build 2 0
        [[ ${_inzsh_segment_text[JOBS]} == 'J 2' ]] || wrong+=jobs:${_inzsh_segment_text[JOBS]}

        print -r -- "${wrong[*]}"
      }
      When call segments
      The output should eq ''
    End

    It 'lets go of an override at the next build, back to the theme"s own mark'
      restored() {
        local INZSH_GLYPH_ERROR=E
        _inzsh_glyphs_resolve
        _inzsh_segment_retval_build 1
        local overridden=${_inzsh_segment_text[RETVAL]}
        unset INZSH_GLYPH_ERROR
        _inzsh_glyphs_resolve
        _inzsh_segment_retval_build 1
        local after=${_inzsh_segment_text[RETVAL]}
        local -a wrong=()
        [[ $overridden == 'E 1' ]]                    || wrong+=set:$overridden
        [[ $after == "${_inzsh_glyph[error]} 1" ]]    || wrong+=unset:$after
        print -r -- "${wrong[*]}"
      }
      When call restored
      The output should eq ''
    End

    It 'reaches the truncation marker the path shortens with'
      ellipsis() {
        local INZSH_GLYPH_ELLIPSIS='..'
        _inzsh_glyphs_resolve
        _inzsh_truncate_path /aaa/bbb/ccc 8
        local path=$REPLY
        _inzsh_truncate_text abcdef 5
        local text=$REPLY
        unset INZSH_GLYPH_ELLIPSIS
        _inzsh_glyphs_resolve
        print -r -- "$path $text"
      }
      When call ellipsis
      The output should eq '../ccc abc..'
    End

    It 'reaches the kicker between the prayer and its time'
      # In its own shell because the salah segment carries real state; the table is the same
      # fixture day `segment_salah_spec` pins, reduced to the one moment this claim needs.
      kicker() {
        zsh -f -c '
          local root=$1
          source $root/lib/core/tokens.zsh
          source $root/lib/salah/calc.zsh
          source $root/lib/segments/salah.zsh
          local -x TZ=UTC
          local -A table=(fajr 1780284600 sunrise 1780290000 dhuhr 1780315200
                          asr 1780327800 maghrib 1780340400 isha 1780345800)
          typeset -g INZSH_GLYPH_DOT=,
          _inzsh_glyphs_resolve
          typeset -gA _inzsh_segment_text
          _inzsh_segment_text=()
          _inzsh_segment_salah_build 1780336800 table
          print -r -- "${_inzsh_segment_text[SALAH]}"
        ' inzsh-glyph-kicker "$SHELLSPEC_PROJECT_ROOT"
      }
      When call kicker
      The output should eq 'Maghrib , 19:00'
      The stderr should eq ''
    End

    It 'measures an override wider than one column rather than trusting the old width'
      # The width invariant survives because nothing about it is assumed: the separator is
      # measured off the glyph actually drawn, so a two-column override costs two columns in
      # the tracked total instead of overflowing the row.
      measured() {
        local INZSH_GLYPH_SEP_LEFT='=='
        _inzsh_glyphs_resolve
        _inzsh_segment_text=(A one B two)
        _inzsh_left=(A B)
        _inzsh_right=()
        _inzsh_render_build left "${_inzsh_left[@]}"
        local -i tracked=$_inzsh_render_width
        _inzsh_width "$REPLY"
        [[ $tracked == $REPLY ]] && print -r -- "agree" || print -r -- "tracked=$tracked measured=$REPLY"
      }
      When call measured
      The output should eq 'agree'
    End
  End
End
