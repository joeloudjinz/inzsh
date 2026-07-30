Include lib/core/detect.zsh

# Colour depth detection. Every example forces the environment it is about — `COLORTERM` and
# `TERM` are declared `local` inside the helper, so zsh re-reads terminfo for the duration of
# the call and restores the caller's terminal on return. Nothing here depends on the terminal
# the suite happens to run in.
#
# The three answers are the only three answers: `truecolor`, `256`, `8`. A fourth value, or an
# empty one, is a failure however it was arrived at. Each parameterised Describe holds exactly
# one example, so a table row means what it looks like it means.
inzsh_spec_depths=(truecolor 256 8)

Describe 'colour depth detection'
  Describe 'at source time'
    It 'leaves a depth behind just by being sourced'
      sourced() { print -r -- "$_inzsh_color_depth"; }
      When call sourced
      The output should be present
    End

    It 'answers with one of the three depths and nothing else'
      known() {
        (( ${inzsh_spec_depths[(Ie)$_inzsh_color_depth]} )) && print -r -- 'known'
      }
      When call known
      The output should eq 'known'
    End

    # The file is one link in a chain — detect, then the fallback tables, then the token
    # layer — but each link has to stand on its own for a bundle, a partial source or a spec
    # to work. `zsh -f` because this spec file has already loaded it.
    It 'is independently sourceable — no other file of ours has to be loaded first'
      standalone() {
        zsh -f -c '
          source "$1/lib/core/detect.zsh" || print -r -- "non-zero exit"
          print -r -- "$_inzsh_color_depth"
        ' inzsh-detect-standalone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call standalone
      The output should be present
    End
  End

  # Truecolor is advertised rather than discovered: terminfo has no widely-populated 24-bit
  # capability, so this variable is the whole signal. Both spellings, either case.
  Describe 'a COLORTERM that advertises truecolor'
    Parameters
      truecolor
      24bit
      TrueColor
      24BIT
    End

    It "reads COLORTERM=$1 as truecolor"
      advertised() {
        local COLORTERM=$1 TERM=linux
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call advertised "$1"
      The output should eq 'truecolor'
    End
  End

  # Set-but-not-a-truecolor-claim has to fall through to terminfo, not be treated as a claim.
  # `TERM=linux` underneath makes the fall-through visible: a wrong answer here is `truecolor`,
  # not a near miss.
  Describe 'a COLORTERM that advertises nothing'
    Parameters
      ''
      yes
      1
      truecolor-ish
      '24 bit'
      256color
    End

    It "falls through to terminfo for COLORTERM='$1'"
      through() {
        local COLORTERM=$1 TERM=linux
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call through "$1"
      The output should eq '8'
    End
  End

  Describe 'a COLORTERM that is not set at all'
    It 'falls through to terminfo rather than reading the empty value as a claim'
      unset_colorterm() {
        local TERM=linux
        unset COLORTERM
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call unset_colorterm
      The output should eq '8'
    End
  End

  # zsh repopulates `$terminfo` when `TERM` is assigned, so a local assignment is a real
  # capability change for the length of the call — no subshell needed, and no `tput`.
  #
  # `linux` is the kernel console: a known terminal that genuinely has eight colours, and the
  # case that proves the floor is reached by detection rather than by giving up.
  Describe 'terminfo'
    Parameters
      xterm-256color        256
      screen-256color       256
      tmux-256color         256
      linux                 8
      xterm                 8
      vt100                 8
    End

    # A minimal terminfo database (slim containers) may simply lack an entry — tmux-256color
    # postdates debian buster's, for one. A missing entry proves nothing about detection, so
    # those rows skip rather than lie in either direction.
    has_no_entry() {
      local TERM=$1
      zmodload zsh/terminfo 2>/dev/null
      [[ -z ${terminfo[colors]:-} ]]
    }

    It "reads TERM=$1 as depth $2"
      Skip if "terminfo has no entry for $1" has_no_entry "$1"
      capability() {
        local TERM=$1 COLORTERM=
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call capability "$1"
      The output should eq "$2"
    End
  End

  Describe 'a terminal it cannot look up'
    # An unknown TERM leaves `$terminfo` empty rather than erroring. The empty string must not
    # reach an arithmetic comparison, and the missing answer must degrade down, never up.
    It 'never guesses upward'
      unknown() {
        local TERM COLORTERM=
        local -a wrong=()
        for TERM in no-such-terminal-here '' xterm-256color-typo dumb; do
          _inzsh_detect_color_depth
          [[ $_inzsh_color_depth == 8 ]] || wrong+="${TERM:-empty}=$_inzsh_color_depth"
        done
        print -r -- "${wrong[*]}"
      }
      When call unknown
      The output should eq ''
    End
  End

  # $1 the override, $2 the environment it has to beat, $3 the depth that environment would
  # otherwise produce. Every row is a real disagreement, and the helper asserts the
  # disagreement first — an override that matched detection by accident would prove nothing.
  Describe 'the INZSH_COLOR_DEPTH override'
    Parameters
      truecolor linux          8
      256       linux          8
      8         xterm-256color 256
      truecolor xterm-256color 256
      256       xterm-256color 256
    End

    It "honours INZSH_COLOR_DEPTH=$1 over TERM=$2"
      forced() {
        local TERM=$2 COLORTERM= INZSH_COLOR_DEPTH=
        _inzsh_detect_color_depth
        [[ $_inzsh_color_depth == $3 ]] || print -r -- "the environment did not say $3"
        INZSH_COLOR_DEPTH=$1
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call forced "$1" "$2" "$3"
      The output should eq "$1"
    End
  End

  # A typo must not flatten the palette. Anything outside the three known values is ignored
  # and detection answers instead — here `COLORTERM=truecolor`, so an obeyed typo shows up as
  # anything other than `truecolor`. `24bit` is a valid COLORTERM and an invalid override; the
  # two vocabularies are not the same vocabulary.
  Describe 'an unrecognised INZSH_COLOR_DEPTH'
    Parameters
      banana
      16
      ''
      'truecolor '
      ' truecolor'
      TRUECOLOR
      24bit
      0
      '8 '
      true
    End

    It "ignores INZSH_COLOR_DEPTH='$1' and detects instead"
      invalid() {
        local COLORTERM=truecolor TERM=linux INZSH_COLOR_DEPTH=$1
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call invalid "$1"
      The output should eq 'truecolor'
    End
  End

  Describe 'recomputation'
    It 'reads the override fresh — clearing it hands the answer back to detection'
      released() {
        local TERM=linux COLORTERM= INZSH_COLOR_DEPTH=truecolor
        _inzsh_detect_color_depth
        local held=$_inzsh_color_depth
        unset INZSH_COLOR_DEPTH
        _inzsh_detect_color_depth
        print -r -- "$held $_inzsh_color_depth"
      }
      When call released
      The output should eq 'truecolor 8'
    End

    # An existing `_inzsh_color_depth` is a previous answer, not a preference. Only the
    # override survives a recompute; a stale value must not.
    It 'overwrites a stale depth rather than respecting it'
      stale() {
        local TERM=linux COLORTERM=
        typeset -g _inzsh_color_depth=truecolor
        _inzsh_detect_color_depth
        print -r -- "$_inzsh_color_depth"
      }
      When call stale
      The output should eq '8'
    End

    It 'tracks the environment across repeated calls in both directions'
      tracked() {
        local TERM COLORTERM=
        local -a seen=()
        for TERM in linux xterm-256color linux; do
          _inzsh_detect_color_depth
          seen+=$_inzsh_color_depth
        done
        print -r -- "${seen[*]}"
      }
      When call tracked
      The output should eq '8 256 8'
    End

    It 'reports success whichever rung of the ladder answers'
      statuses() {
        local TERM COLORTERM INZSH_COLOR_DEPTH
        local -a bad=()
        TERM=linux COLORTERM= INZSH_COLOR_DEPTH=256
        _inzsh_detect_color_depth || bad+=override
        TERM=linux COLORTERM=truecolor INZSH_COLOR_DEPTH=
        _inzsh_detect_color_depth || bad+=colorterm
        TERM=xterm-256color COLORTERM= INZSH_COLOR_DEPTH=
        _inzsh_detect_color_depth || bad+=terminfo
        TERM=no-such-terminal-here COLORTERM= INZSH_COLOR_DEPTH=
        _inzsh_detect_color_depth || bad+=floor
        print -r -- "${bad[*]}"
      }
      When call statuses
      The output should eq ''
    End
  End

End

# Locale is READ here and never set. Every example assigns the three environment variables and
# asserts what detection made of them; `local` restores the caller's environment on return, so
# nothing below depends on the locale the suite happens to run in. What a C locale does to the
# CODE that consumes this flag needs a fresh parse, and so needs a subshell — that is
# `test/unit/locale_spec.sh`, not this file.
#
# Two answers only: 1 and 0. There is no `unknown` here, because there is no unknown — an
# environment that names no locale is a single-byte environment, which is a fact and not a gap.
inzsh_spec_multibyte=(1 0)

Describe 'multibyte detection'
  Describe 'at source time'
    It 'answers 1 or 0 and nothing else, just by being sourced'
      sourced() {
        (( ${inzsh_spec_multibyte[(Ie)$_inzsh_multibyte]} )) && print -r -- 'known'
      }
      When call sourced
      The output should eq 'known'
    End
  End

  # The codeset, however the system spells it. Case is not fixed by any standard — `UTF-8` and
  # `utf8` are both common, and both turn up capitalised — so the match is case-insensitive on
  # both spellings.
  Describe 'a locale that names a UTF-8 codeset'
    Parameters
      en_US.UTF-8
      en_US.utf8
      C.UTF-8
      ar_SA.UTF-8
      en_US.Utf-8
      ja_JP.UTF-8@calendar
    End

    It "reads LC_ALL=$1 as multibyte"
      utf8() {
        local LC_ALL=$1 LC_CTYPE= LANG= INZSH_MULTIBYTE=
        _inzsh_detect_multibyte
        print -r -- "$_inzsh_multibyte"
      }
      When call utf8 "$1"
      The output should eq '1'
    End
  End

  # Single-byte, and the unrecognised case with it. `C` and `POSIX` are the ones that provoked
  # the bug this detector exists for; the rest are here so that "not UTF-8" is not quietly read
  # as "not sure".
  Describe 'a locale that names anything else'
    Parameters
      C
      POSIX
      ''
      en_US
      en_US.ISO8859-1
      de_DE@euro
      ru_RU.KOI8-R
    End

    It "reads LC_ALL='$1' as single-byte"
      single() {
        local LC_ALL=$1 LC_CTYPE= LANG= INZSH_MULTIBYTE=
        _inzsh_detect_multibyte
        print -r -- "$_inzsh_multibyte"
      }
      When call single "$1"
      The output should eq '0'
    End
  End

  # zsh's own order, and the reason it is not alphabetical: `LC_ALL` is the override every
  # locale-aware program honours first, `LC_CTYPE` is the category that actually governs
  # character handling, and `LANG` is the fallback for both. Empty counts as unset at every
  # step — setlocale ignores an empty string, so reading one as a real setting would answer a
  # question the system never asked. $1 LC_ALL, $2 LC_CTYPE, $3 LANG, $4 the answer.
  Describe 'the precedence of the three locale variables'
    Parameters
      en_US.UTF-8 C           C           1
      C           en_US.UTF-8 en_US.UTF-8 0
      ''          en_US.UTF-8 C           1
      ''          C           en_US.UTF-8 0
      ''          ''          en_US.UTF-8 1
      ''          ''          C           0
      ''          ''          ''          0
    End

    It "resolves LC_ALL='$1' LC_CTYPE='$2' LANG='$3' to $4"
      precedence() {
        local LC_ALL=$1 LC_CTYPE=$2 LANG=$3 INZSH_MULTIBYTE=
        _inzsh_detect_multibyte
        print -r -- "$_inzsh_multibyte"
      }
      When call precedence "$1" "$2" "$3"
      The output should eq "$4"
    End
  End

  Describe 'a locale environment that is not set at all'
    It 'treats absent variables the same as empty ones rather than erroring'
      absent() {
        local INZSH_MULTIBYTE=
        unset LC_ALL LC_CTYPE LANG
        _inzsh_detect_multibyte
        print -r -- "$_inzsh_multibyte"
      }
      When call absent
      The output should eq '0'
    End
  End

  # $1 the override, $2 the locale it has to beat, $3 what that locale would otherwise say.
  # Every row is a real disagreement, asserted as one before the override is applied.
  Describe 'the INZSH_MULTIBYTE override'
    Parameters
      1 C           0
      0 en_US.UTF-8 1
    End

    It "honours INZSH_MULTIBYTE=$1 over LC_ALL=$2"
      forced() {
        local LC_ALL=$2 LC_CTYPE= LANG= INZSH_MULTIBYTE=
        _inzsh_detect_multibyte
        [[ $_inzsh_multibyte == $3 ]] || print -r -- "the locale did not say $3"
        INZSH_MULTIBYTE=$1
        _inzsh_detect_multibyte
        print -r -- "$_inzsh_multibyte"
      }
      When call forced "$1" "$2" "$3"
      The output should eq "$1"
    End
  End

  # An unrecognised override is ignored, not obeyed and not half-obeyed. `C` underneath, so an
  # obeyed typo shows up as `0` rather than as a near miss. `true`, `yes` and `on` are the
  # spellings a user is most likely to reach for, and none of them is the vocabulary.
  Describe 'an unrecognised INZSH_MULTIBYTE'
    Parameters
      true
      yes
      on
      ''
      '1 '
      ' 0'
      01
      2
      -1
      utf8
    End

    It "ignores INZSH_MULTIBYTE='$1' and detects instead"
      invalid() {
        local LC_ALL=en_US.UTF-8 LC_CTYPE= LANG= INZSH_MULTIBYTE=$1
        _inzsh_detect_multibyte
        print -r -- "$_inzsh_multibyte"
      }
      When call invalid "$1"
      The output should eq '1'
    End
  End

  Describe 'recomputation'
    It 'tracks the environment across repeated calls in both directions'
      tracked() {
        local LC_ALL LC_CTYPE= LANG= INZSH_MULTIBYTE=
        local -a seen=()
        for LC_ALL in C en_US.UTF-8 C; do
          _inzsh_detect_multibyte
          seen+=$_inzsh_multibyte
        done
        print -r -- "${seen[*]}"
      }
      When call tracked
      The output should eq '0 1 0'
    End

    # A previous answer is not a preference. Only the override survives a recompute.
    It 'overwrites a stale answer rather than respecting it'
      stale() {
        local LC_ALL=C LC_CTYPE= LANG= INZSH_MULTIBYTE=
        typeset -g _inzsh_multibyte=1
        _inzsh_detect_multibyte
        print -r -- "$_inzsh_multibyte"
      }
      When call stale
      The output should eq '0'
    End

    It 'reports success whichever rung answers'
      statuses() {
        local LC_ALL LC_CTYPE= LANG= INZSH_MULTIBYTE
        local -a bad=()
        LC_ALL=C INZSH_MULTIBYTE=1
        _inzsh_detect_multibyte || bad+=override
        LC_ALL=en_US.UTF-8 INZSH_MULTIBYTE=
        _inzsh_detect_multibyte || bad+=utf8
        LC_ALL=C INZSH_MULTIBYTE=
        _inzsh_detect_multibyte || bad+=single
        print -r -- "${bad[*]}"
      }
      When call statuses
      The output should eq ''
    End
  End
End

# Three answers, and the third one is the point. A font is not visible from inside a shell: the
# glyphs are private-use code points, the terminal chooses what covers them, and the only tools
# that could look are forks. So `unknown` is a first-class answer here, and most of the world
# gets it.
inzsh_spec_nerd_font=(1 0 unknown)

Describe 'nerd font detection'
  Describe 'at source time'
    It 'answers 1, 0 or unknown and nothing else, just by being sourced'
      sourced() {
        (( ${inzsh_spec_nerd_font[(Ie)$_inzsh_nerd_font]} )) && print -r -- 'known'
      }
      When call sourced
      The output should eq 'known'
    End
  End

  # The only positive evidence available without a fork: a terminal that ships the symbol range
  # inside the application. The name is matched case-insensitively because the programs disagree
  # about capitalising themselves and neither spelling is wrong.
  Describe 'a terminal that bundles the symbols'
    Parameters
      ghostty
      Ghostty
      GHOSTTY
      wezterm
      WezTerm
    End

    It "reads TERM_PROGRAM=$1 as a Nerd Font"
      bundled() {
        local TERM_PROGRAM=$1 LC_TERMINAL= TERMINAL_EMULATOR= INZSH_NERD_FONT=
        _inzsh_detect_nerd_font
        print -r -- "$_inzsh_nerd_font"
      }
      When call bundled "$1"
      The output should eq '1'
    End
  End

  # Every one of these can draw the glyphs the moment a Nerd Font is installed and selected, and
  # none of them proves one is. `unknown` is the honest answer and 0 would be a claim. The
  # near-misses are here too: a name that merely CONTAINS a known one is a different program.
  Describe 'a terminal that proves nothing either way'
    Parameters
      iTerm.app
      Apple_Terminal
      vscode
      Hyper
      tmux
      ghostty-ish
      not-wezterm
      ''
    End

    It "reads TERM_PROGRAM='$1' as unknown"
      unproven() {
        local TERM_PROGRAM=$1 LC_TERMINAL= TERMINAL_EMULATOR= INZSH_NERD_FONT=
        _inzsh_detect_nerd_font
        print -r -- "$_inzsh_nerd_font"
      }
      When call unproven "$1"
      The output should eq 'unknown'
    End
  End

  # Three places a terminal writes its own name, and the fallback order matters because only one
  # of them survives ssh. $1 TERM_PROGRAM, $2 LC_TERMINAL, $3 TERMINAL_EMULATOR, $4 the answer.
  Describe 'where the terminal name is read from'
    Parameters
      ghostty   ''        ''                 1
      ''        ghostty   ''                 1
      ''        ''        ghostty            1
      iTerm.app ghostty   ''                 unknown
      ''        iTerm2    ghostty            unknown
      ''        ''        JetBrains-JediTerm unknown
      ''        ''        ''                 unknown
    End

    It "resolves TERM_PROGRAM='$1' LC_TERMINAL='$2' TERMINAL_EMULATOR='$3' to $4"
      named() {
        local TERM_PROGRAM=$1 LC_TERMINAL=$2 TERMINAL_EMULATOR=$3 INZSH_NERD_FONT=
        _inzsh_detect_nerd_font
        print -r -- "$_inzsh_nerd_font"
      }
      When call named "$1" "$2" "$3"
      The output should eq "$4"
    End
  End

  # $1 the override, $2 the terminal it has to beat, $3 what that terminal would otherwise say.
  Describe 'the INZSH_NERD_FONT override'
    Parameters
      0 ghostty   1
      1 iTerm.app unknown
      0 iTerm.app unknown
    End

    It "honours INZSH_NERD_FONT=$1 over TERM_PROGRAM=$2"
      forced() {
        local TERM_PROGRAM=$2 LC_TERMINAL= TERMINAL_EMULATOR= INZSH_NERD_FONT=
        _inzsh_detect_nerd_font
        [[ $_inzsh_nerd_font == $3 ]] || print -r -- "the terminal did not say $3"
        INZSH_NERD_FONT=$1
        _inzsh_detect_nerd_font
        print -r -- "$_inzsh_nerd_font"
      }
      When call forced "$1" "$2" "$3"
      The output should eq "$1"
    End
  End

  # `unknown` is an answer this detector gives and not a value a user may set: the override
  # exists to state a fact the environment cannot, and "I do not know" is not that.
  Describe 'an unrecognised INZSH_NERD_FONT'
    Parameters
      true
      yes
      unknown
      ''
      '1 '
      2
      nerd
    End

    It "ignores INZSH_NERD_FONT='$1' and detects instead"
      invalid() {
        local TERM_PROGRAM=ghostty LC_TERMINAL= TERMINAL_EMULATOR= INZSH_NERD_FONT=$1
        _inzsh_detect_nerd_font
        print -r -- "$_inzsh_nerd_font"
      }
      When call invalid "$1"
      The output should eq '1'
    End
  End

  Describe 'the honesty rule'
    # The one thing this detector must never do. A terminal it has no evidence about gets
    # `unknown`, and no environment short of the override may produce a 1.
    It 'never claims a font from a terminal it knows nothing about'
      claims() {
        local TERM_PROGRAM LC_TERMINAL= TERMINAL_EMULATOR= INZSH_NERD_FONT=
        local -a wrong=()
        for TERM_PROGRAM in iTerm.app Apple_Terminal vscode Hyper alacritty kitty foot ''; do
          _inzsh_detect_nerd_font
          [[ $_inzsh_nerd_font == unknown ]] || wrong+="${TERM_PROGRAM:-empty}=$_inzsh_nerd_font"
        done
        print -r -- "${wrong[*]}"
      }
      When call claims
      The output should eq ''
    End

    It 'reports success whichever rung answers'
      statuses() {
        local TERM_PROGRAM LC_TERMINAL= TERMINAL_EMULATOR= INZSH_NERD_FONT
        local -a bad=()
        TERM_PROGRAM=iTerm.app INZSH_NERD_FONT=1
        _inzsh_detect_nerd_font || bad+=override
        TERM_PROGRAM=ghostty INZSH_NERD_FONT=
        _inzsh_detect_nerd_font || bad+=bundled
        TERM_PROGRAM=iTerm.app INZSH_NERD_FONT=
        _inzsh_detect_nerd_font || bad+=unknown
        print -r -- "${bad[*]}"
      }
      When call statuses
      The output should eq ''
    End
  End
End

# `$TMUX` is set by the server in every pane and by nothing else, so the pane question has a
# real answer. The passthrough question mostly does not: it lives in tmux's own configuration,
# which cannot be read without running tmux. A neutral, obviously-fake socket line stands in for
# what the server would set.
inzsh_spec_tmux_env='/tmp/tmux-0/default,0,0'
inzsh_spec_tmux_rgb=(1 0 unknown)

# The rung that says yes needs a terminfo entry that advertises direct colour, and no database
# this suite can count on ships one — macOS has no `*-direct` entry at all. So rather than leave
# the most consequential rung to whichever machine happens to have the right ncurses, one entry
# is compiled here: `RGB` and `Tc` on top of `xterm`, into a private database the examples point
# `TERMINFO` at. `tic` is a fork, and a fork in a spec costs nothing — it is the library that may
# not make one. Where there is no compiler the examples skip, and the real `*-direct` rows below
# cover the same rung wherever the database does have them.
inzsh_spec_rgb_db=${SHELLSPEC_TMPBASE:-${TMPDIR:-/tmp}}/inzsh-rgb-terminfo
inzsh_spec_rgb_term=
if command -v tic > /dev/null 2>&1 && mkdir -p "$inzsh_spec_rgb_db" 2> /dev/null; then
  {
    print -r -- 'inzsh-rgb-probe|inzsh rgb capability probe,'
    print -r -- '  RGB, Tc, use=xterm,'
    print -r --
    print -r -- 'inzsh-wide-probe|inzsh wide but indirect colour probe,'
    print -r -- '  colors#32767, pairs#32767, use=xterm-256color,'
  } > "$inzsh_spec_rgb_db/entry.ti"
  tic -x -o "$inzsh_spec_rgb_db" "$inzsh_spec_rgb_db/entry.ti" > /dev/null 2>&1 &&
    inzsh_spec_rgb_term=inzsh-rgb-probe
fi

Describe 'tmux detection'
  Describe 'at source time'
    It 'leaves both answers behind, in their own vocabularies, just by being sourced'
      sourced() {
        local -a bad=()
        [[ $_inzsh_tmux == (1|0) ]] || bad+="pane=$_inzsh_tmux"
        (( ${inzsh_spec_tmux_rgb[(Ie)$_inzsh_tmux_rgb]} )) || bad+="rgb=$_inzsh_tmux_rgb"
        print -r -- "${bad[*]}"
      }
      When call sourced
      The output should eq ''
    End
  End

  Describe 'the pane itself'
    Parameters
      set   1
      empty 0
      unset 0
    End

    It "reads a $1 TMUX as pane=$2"
      pane() {
        local TERM=xterm-256color COLORTERM=
        local TMUX=$inzsh_spec_tmux_env
        case $1 in
          (empty) TMUX= ;;
          (unset) unset TMUX ;;
        esac
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux"
      }
      When call pane "$1"
      The output should eq "$2"
    End
  End

  # Outside a pane the passthrough question is about a multiplexer that is not there. `unknown`
  # rather than 0, because a 0 reads as a fault and there is no fault to report.
  Describe 'outside a pane'
    It 'reports the passthrough question as unanswered rather than as a failure'
      outside() {
        local TERM=xterm-256color COLORTERM=truecolor
        unset TMUX
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux $_inzsh_tmux_rgb"
      }
      When call outside
      The output should eq '0 unknown'
    End
  End

  # The capability itself, which is what tmux's own `terminal-features` line ends up meaning.
  # The compiled entry is `xterm` underneath, so it advertises eight colours as well as `RGB` —
  # which makes these two examples the precedence check too: the capability outranks the colour
  # count, and a pane that says both is passing 24-bit through rather than being too small for
  # it.
  Describe 'a pane whose terminfo carries the RGB capability'
    no_rgb_entry() {
      [[ -z $inzsh_spec_rgb_term ]]
    }

    It 'reads the capability as passthrough, over the eight colours in the same entry'
      Skip if 'no terminfo compiler to build an RGB entry' no_rgb_entry
      capable() {
        local -x TERMINFO=$inzsh_spec_rgb_db
        local TERM=$inzsh_spec_rgb_term COLORTERM= TMUX=$inzsh_spec_tmux_env
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux_rgb"
      }
      When call capable
      The output should eq '1'
    End

    # The same terminal, no multiplexer. The capability belongs to the terminal and the question
    # belongs to the pane, so without a pane there is still nothing to answer.
    It 'says nothing about passthrough when there is no pane to pass through'
      Skip if 'no terminfo compiler to build an RGB entry' no_rgb_entry
      unwrapped() {
        local -x TERMINFO=$inzsh_spec_rgb_db
        local TERM=$inzsh_spec_rgb_term COLORTERM=
        unset TMUX
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux $_inzsh_tmux_rgb"
      }
      When call unwrapped
      The output should eq '0 unknown'
    End
  End

  # Where the direct-colour line actually sits. A palette is a palette however large it is:
  # 32767 named colours is still an indexed one, and only an entry counting in the millions is
  # saying "any colour at all". The entry is compiled with no `RGB` on it precisely so that the
  # colour count is the only thing under test.
  Describe 'a pane with a large palette that is still a palette'
    no_wide_entry() {
      [[ -z $inzsh_spec_rgb_term ]]
    }

    It 'does not read 32767 indexed colours as direct colour'
      Skip if 'no terminfo compiler to build a wide entry' no_wide_entry
      wide() {
        local -x TERMINFO=$inzsh_spec_rgb_db
        local TERM=inzsh-wide-probe COLORTERM= TMUX=$inzsh_spec_tmux_env
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux_rgb"
      }
      When call wide
      The output should eq 'unknown'
    End
  End

  # A pane whose terminfo entry advertises fewer than 256 colours cannot be carrying 24-bit
  # anywhere, whatever the terminal outside it can do. The guard runs in a subshell: a `TERM`
  # zsh fails to look up leaves `$terminfo` empty for the rest of the process, and a guard must
  # not do that to the examples after it.
  Describe 'a pane too small for 24-bit'
    not_small() {
      ( TERM=$1
        zmodload zsh/terminfo 2>/dev/null
        local colors=${terminfo[colors]}
        [[ $colors == <-> ]] && (( colors < 256 )) && return 1
        return 0 )
    }

    Parameters
      screen
      linux
    End

    It "reads a TERM=$1 pane as no passthrough"
      Skip if "terminfo has no small-colour entry for $1" not_small "$1"
      small() {
        local TERM=$1 COLORTERM= TMUX=$inzsh_spec_tmux_env
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux_rgb"
      }
      When call small "$1"
      The output should eq '0'
    End
  End

  # The other end: a `*-direct` entry advertises its colours in the millions, which is how a
  # terminfo database says "direct colour" on every build. Those entries ship with ncurses but
  # not with every trimmed-down database, so the row skips rather than lies when it is absent.
  Describe 'a pane whose terminfo advertises direct colour'
    not_direct() {
      ( TERM=$1
        zmodload zsh/terminfo 2>/dev/null
        local colors=${terminfo[colors]}
        [[ $colors == <-> ]] && (( colors >= 16777216 )) && return 1
        return 0 )
    }

    Parameters
      tmux-direct
      screen-direct
      xterm-direct
    End

    It "reads a TERM=$1 pane as passthrough"
      Skip if "terminfo has no direct-colour entry for $1" not_direct "$1"
      direct() {
        local TERM=$1 COLORTERM= TMUX=$inzsh_spec_tmux_env
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux_rgb"
      }
      When call direct "$1"
      The output should eq '1'
    End
  End

  # The ordinary pane, and the answer this detector exists to be honest about. `tmux-256color`
  # says 256 and says nothing about whether tmux passes 24-bit through to the terminal outside
  # it; that lives in a `terminal-features` line nobody can read without running tmux.
  Describe 'an ordinary 256-colour pane'
    has_no_entry() {
      ( TERM=$1
        zmodload zsh/terminfo 2>/dev/null
        [[ -z ${terminfo[colors]:-} ]] )
    }

    Parameters
      tmux-256color
      screen-256color
    End

    It "reads a TERM=$1 pane as unanswerable"
      Skip if "terminfo has no entry for $1" has_no_entry "$1"
      ordinary() {
        local TERM=$1 COLORTERM= TMUX=$inzsh_spec_tmux_env
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux_rgb"
      }
      When call ordinary "$1"
      The output should eq 'unknown'
    End
  End

  # The rung that is deliberately missing. tmux hands the server's environment to new panes, so
  # a `COLORTERM` inside one is the OUTER terminal's advertisement — evidence about the terminal
  # and none at all about the multiplexer between them. Promoting it to a yes is how a tmux that
  # is quietly flattening colour would get a clean bill of health.
  Describe 'a COLORTERM that survived into the pane'
    no_pane_entry() {
      ( TERM=tmux-256color
        zmodload zsh/terminfo 2>/dev/null
        [[ -z ${terminfo[colors]:-} ]] )
    }

    Parameters
      truecolor
      24bit
      TrueColor
    End

    It "does not read COLORTERM=$1 as passthrough"
      Skip if 'terminfo has no entry for tmux-256color' no_pane_entry
      inherited() {
        local TERM=tmux-256color COLORTERM=$1 TMUX=$inzsh_spec_tmux_env
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux_rgb"
      }
      When call inherited "$1"
      The output should eq 'unknown'
    End
  End

  Describe 'a pane it cannot look up'
    # An unknown TERM leaves `$terminfo` empty. The missing capability must not reach an
    # arithmetic comparison, and a missing answer is `unknown` — never one of the two verdicts.
    It 'never turns a missing capability into a verdict'
      unlookupable() {
        local TERM COLORTERM= TMUX=$inzsh_spec_tmux_env
        local -a wrong=()
        for TERM in no-such-terminal-here '' xterm-256color-typo dumb; do
          _inzsh_detect_tmux
          [[ $_inzsh_tmux_rgb == unknown ]] || wrong+="${TERM:-empty}=$_inzsh_tmux_rgb"
        done
        print -r -- "${wrong[*]}"
      }
      When call unlookupable
      The output should eq ''
    End
  End

  Describe 'recomputation'
    It 'tracks the pane across repeated calls in both directions'
      tracked() {
        local TERM=xterm-256color COLORTERM= TMUX=
        local -a seen=()
        local value
        for value in "$inzsh_spec_tmux_env" '' "$inzsh_spec_tmux_env"; do
          TMUX=$value
          _inzsh_detect_tmux
          seen+=$_inzsh_tmux
        done
        print -r -- "${seen[*]}"
      }
      When call tracked
      The output should eq '1 0 1'
    End

    It 'overwrites both stale answers rather than respecting them'
      stale() {
        local TERM=xterm-256color COLORTERM=
        unset TMUX
        typeset -g _inzsh_tmux=1 _inzsh_tmux_rgb=1
        _inzsh_detect_tmux
        print -r -- "$_inzsh_tmux $_inzsh_tmux_rgb"
      }
      When call stale
      The output should eq '0 unknown'
    End

    It 'reports success in a pane and out of one'
      statuses() {
        local TERM=xterm-256color COLORTERM= TMUX
        local -a bad=()
        TMUX=$inzsh_spec_tmux_env
        _inzsh_detect_tmux || bad+=pane
        TMUX=
        _inzsh_detect_tmux || bad+=outside
        print -r -- "${bad[*]}"
      }
      When call statuses
      The output should eq ''
    End
  End
End

# Structural rather than behavioural, and about the whole file rather than one detector. This
# file is sourced on every shell start, so the cost that matters is a fork, and a fork is
# invisible in the result. Comment lines are skipped — the prose there names these commands
# precisely because it explains why we do not call them.
Describe 'the cost of detection'
  It 'detects without forking — no command substitution and no external lookup'
    forks() {
      setopt local_options extended_glob
      local line; local -a bad=()
      while IFS= read -r line; do
        [[ $line == [[:space:]]#\#* ]] && continue
        [[ $line == *'$('* || $line == *'`'* ]] && bad+=$line
        [[ $line == *(tput|locale|fc-list|fc-match|infocmp)* ]] && bad+=$line
      done < "$SHELLSPEC_PROJECT_ROOT/lib/core/detect.zsh"
      print -r -- "${#bad}"
    }
    When call forks
    The output should eq '0'
  End

  # Every capability resolved by the time the file finishes sourcing, with nothing else of ours
  # loaded first — a bundle, a partial source and a spec all depend on that. `zsh -f` because
  # this spec file has already loaded it.
  # The pipes are the assertion: an unresolved capability shows up as an empty field, and an
  # empty field is a `||`, a leading pipe or a trailing one.
  It 'resolves all five capabilities at source time and on its own'
    standalone() {
      zsh -f -c '
        source "$1/lib/core/detect.zsh" || print -r -- "non-zero exit"
        local -a answers=(
          "$_inzsh_color_depth" "$_inzsh_multibyte" "$_inzsh_nerd_font"
          "$_inzsh_tmux" "$_inzsh_tmux_rgb"
        )
        print -r -- "|${(j:|:)answers}|"
      ' inzsh-detect-standalone "$SHELLSPEC_PROJECT_ROOT"
    }
    When call standalone
    The output should not include 'non-zero exit'
    The output should not include '||'
  End
End
