Include lib/core/config.zsh
Include lib/core/detect.zsh
Include lib/core/tokens.zsh
Include lib/salah/calc.zsh
Include lib/salah/methods.zsh
Include lib/salah/cache.zsh
Include lib/salah/location.zsh
Include lib/core/doctor.zsh

# The doctor — `lib/core/doctor.zsh`. A thin formatter over the capability detection the theme
# already runs, printed as one pasteable block, because "paste the output of `inzsh doctor`" is
# what the bug template asks for. Nothing here detects anything new: every value below is one of
# `lib/core/detect.zsh`'s globals, re-asked at call time, plus the diagnostics other files wrote
# down for exactly this reader — the guard names in the config layer, the location provenance in
# `lib/salah/location.zsh`.
#
# Two properties are load-bearing and each has its own example:
#
#   THE BLOCK COVERS THE BUG TEMPLATE. `.github/ISSUE_TEMPLATE/bug.yml` asks for terminal, TERM,
#   zsh version, tmux and Nerd Font, and the issue adds colour depth and locale. A field the
#   block dropped is a field every bug report loses.
#
#   COORDINATES NEVER APPEAR. The output exists to be pasted into a public issue, and
#   CONTRIBUTING.md asks reporters not to include their position — so the doctor prints where a
#   location CAME FROM and never where it is.
#
# Detectors recompute from the environment on every call, so each example declares the
# environment it is about `local`, exactly as `detect_spec.sh` does.

inzsh_spec_doctor_env() {
  emulate -L zsh

  # A fixed, neutral terminal for every example that does not say otherwise.
  typeset -g TERM=xterm-256color COLORTERM=truecolor
  typeset -g LC_ALL=en_US.UTF-8
  unset TMUX TERM_PROGRAM TERM_PROGRAM_VERSION LC_TERMINAL TERMINAL_EMULATOR 2>/dev/null
  unset INZSH_COLOR_DEPTH INZSH_MULTIBYTE INZSH_NERD_FONT 2>/dev/null
  unset INZSH_SALAH_LAT INZSH_SALAH_LON INZSH_SALAH_AUTOLOCATE 2>/dev/null

  return 0
}

Describe 'the near-miss matcher (issue #228)'
  # Pure functions, no environment and no `inzsh doctor` — the two building blocks the block's
  # `ignored` rows read a suggestion from further down this file.

  Describe '_inzsh_doctor_distance'
    # $1 the pattern (may carry one `*`), $2 the candidate, $3 the expected distance. The
    # wildcard cases are the reason this is not plain Levenshtein: `*` matches a run of zero or
    # more characters of $2 for free, which is what lets a family PATTERN be compared directly
    # against a candidate name without knowing what the wildcard stands for.
    Parameters
      INZSH_SEPARATOR_STYLE INZSH_SEPARATOR_STYLE 0
      INZSH_SEPARATOR_STYL  INZSH_SEPARATOR_STYLE  1
      kitten                sitting                3
      ''                    ''                     0
      abc                   ''                     3
      'INZSH_*_RANK'        INZSH_GIT_RANK         0
      'INZSH_*_RANK'        INZSH_GIT_RANNK        1
      'INZSH_*_BG'          INZSH_MY_OWN_THING     2
      '*X'                  ''                     1
    End

    It "measures $1 against $2 as $3"
      measured() {
        _inzsh_doctor_distance "$1" "$2"
        print -r -- "$REPLY"
      }
      When call measured "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe '_inzsh_doctor_near_miss'
    It 'suggests the registered singleton a near-miss name is probably meant to be'
      When call _inzsh_doctor_near_miss INZSH_SEPARATOR_STYL
      The status should be success
      The variable REPLY should eq 'INZSH_SEPARATOR_STYLE'
    End

    # `INZSH_<SEGMENT>_RANK` is not a name this file can complete — nothing here knows which
    # segment `RANNK` was reaching for — so the family PATTERN itself is the suggestion, verbatim,
    # the same vocabulary `lib/core/config.zsh`'s own comments already use for the shape.
    It 'suggests the family pattern a near-miss segment knob is probably meant to be'
      When call _inzsh_doctor_near_miss INZSH_GIT_RANNK
      The status should be success
      The variable REPLY should eq 'INZSH_*_RANK'
    End

    # `INZSH_GLYPH_*` — `lib/core/tokens.zsh`'s family, registered once the token layer is
    # loaded, which this spec's own `Include` list already does — is the theme's other TRAILING
    # wildcard, the same shape as `INZSH_SALAH_OFFSET_*` below. Nothing about the cap or the
    # distance walk treats a trailing wildcard differently from a middle one, but it had no
    # example of its own until now.
    It 'suggests a trailing-wildcard family the same way as a middle one'
      When call _inzsh_doctor_near_miss INZSH_GLPH_SEP_LEFT
      The status should be success
      The variable REPLY should eq 'INZSH_GLYPH_*'
    End

    # The example the issue names directly. Measured on its own two rows up, `INZSH_*_BG` sits
    # only 2 from this name once the wildcard is credited for swallowing the middle of it — a
    # flat house threshold of 2 would have reported it. `_inzsh_doctor_cap` is what keeps a
    # three-letter discriminant from being read that generously, which is why this name stays
    # silent rather than becoming a false "probably".
    It 'refuses a name that only looks close once a family wildcard is credited too much'
      When call _inzsh_doctor_near_miss INZSH_MY_OWN_THING
      The status should be failure
      The variable REPLY should eq ''
    End

    It 'refuses an empty name'
      When call _inzsh_doctor_near_miss ''
      The status should be failure
      The variable REPLY should eq ''
    End

    # The cap is not only a family concern. `INZSH_PS2` is discriminated by `PS2` alone, three
    # characters same as `_BG` — and the theme SHIPS an `ssh` segment, so a user turning it off
    # with `INZSH_SSH=0` is doing a wholly ordinary thing, not typing `INZSH_PS2` badly. Without
    # `_inzsh_doctor_cap` applying to plain names too, all three of these read as "probably
    # INZSH_PS2" at the flat threshold; capped at 1, none of them clear it.
    Parameters
      INZSH_SSH
      INZSH_ZSH
      INZSH_OS
    End

    It "does not read $1 as a near miss of a short registered name"
      When call _inzsh_doctor_near_miss "$1"
      The status should be failure
      The variable REPLY should eq ''
    End

    # Pins the threshold itself. Both examples are one mutation of `2` away from flipping: at 1,
    # the transposition below stops reporting; at 3, the truncated name below starts to.
    It 'reports a transposition sitting exactly at the threshold'
      When call _inzsh_doctor_near_miss INZSH_SEPARATOR_SYTLE
      The status should be success
      The variable REPLY should eq 'INZSH_SEPARATOR_STYLE'
    End

    It 'stays silent one edit past the threshold'
      When call _inzsh_doctor_near_miss INZSH_SEPARATOR_ST
      The status should be failure
      The variable REPLY should eq ''
    End

    # Every example above runs against the names `config.zsh` and `tokens.zsh` register directly
    # — this file's own `Include` list never sources `lib/salah/methods.zsh` and never calls
    # `_inzsh_config_absorb_all`, so `INZSH_SALAH_*` and the one TRAILING-wildcard family,
    # `INZSH_SALAH_OFFSET_*`, are otherwise untouched by any near-miss example in this suite. A
    # `zsh -f` of its own, sourced the way `tools/doctor.zsh` — the real `make doctor` launcher —
    # sources it, so this is the registry a reporter's near miss is actually matched against.
    It 'matches a near miss against the salah knobs and the trailing-wildcard family'
      salah() {
        zsh -f -c '
          source "$1/lib/core/config.zsh"
          source "$1/lib/core/detect.zsh"
          source "$1/lib/salah/calc.zsh"
          source "$1/lib/salah/methods.zsh"
          source "$1/lib/salah/cache.zsh"
          source "$1/lib/salah/location.zsh"
          source "$1/lib/core/doctor.zsh"
          _inzsh_config_absorb_all
          _inzsh_doctor_near_miss INZSH_SALAH_MEHTOD
          print -r -- "singleton: $REPLY"
          _inzsh_doctor_near_miss INZSH_SALAH_OFSET_FAJR
          print -r -- "family: $REPLY"
        ' inzsh-doctor-near-miss-salah "$SHELLSPEC_PROJECT_ROOT"
      }
      When call salah
      The line 1 should eq 'singleton: INZSH_SALAH_METHOD'
      The line 2 should eq 'family: INZSH_SALAH_OFFSET_*'
      The stderr should eq ''
    End
  End
End
# --------------------------------------------------------------------------------------------
# Issue #229. The table row lives beside the location row and shares its cache fixture with
# `salah_cache_spec.sh` — `inzsh_spec_salah_env`, `inzsh_spec_salah_dir`, `inzsh_spec_salah_clean`
# and the pinned `inzsh_spec_salah_now` all live in `test/spec_helper.sh` now, loaded into every
# spec, so nothing here reads or writes the real `$XDG_CACHE_HOME` and nothing here restates a
# fixture instant a sibling suite already owns.
#
# `_inzsh_doctor` TAKES THE SAME INJECTED CLOCK EVERY SALAH FUNCTION DOES. An earlier version of
# these examples captured `$EPOCHSECONDS` at setup and relied on it still being the same second
# by the time `inzsh doctor` read the wall clock a moment later — true almost always, and false
# for one example a run at the wrong instant near a Riyadh midnight, which is exactly what
# CLAUDE.md's "never against the real time" rule exists to rule out. `inzsh doctor
# $inzsh_spec_salah_now` below is pinned exactly as every `_inzsh_salah_cache_health` call in
# `salah_cache_spec.sh` is.

# The doctor environment plus a resolved position (Mecca) and a scratch cache directory,
# composed from the shared salah fixture and this file's own terminal fixture.
inzsh_spec_doctor_salah_env() {
  emulate -L zsh

  inzsh_spec_doctor_env
  inzsh_spec_salah_env

  return 0
}

# Writes a valid entry at the path the current configuration's recipe hashes to, under a chosen
# key, in REPLY as the file path. `$1`, when given, is the key to store; empty or omitted stores
# today's real key. The caller decides whether that is today's real key or one built to look
# stale — the twelve moments underneath it only have to parse, never to mean anything, since the
# doctor never reads them.
inzsh_spec_doctor_cache_write() {
  emulate -L zsh

  typeset -g REPLY=

  _inzsh_salah_cache_keys $inzsh_spec_salah_now "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON" ||
    return 1
  local key=${1:-$_inzsh_salah_key}
  _inzsh_salah_cache_path "$_inzsh_salah_seed" || return 1
  local file=$REPLY

  _inzsh_salah_compute_table $inzsh_spec_salah_now "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON" ||
    return 1
  _inzsh_salah_table[key]=$key
  _inzsh_salah_table[day]=${key%%\|*}

  _inzsh_salah_cache_write "$file" || return 1

  typeset -g REPLY=$file

  return 0
}

Describe 'the inzsh command'
  It 'refuses a subcommand it has never heard of, and says what it does know'
    unknown() { inzsh frobnicate; }
    When call unknown
    The status should be failure
    The stderr should include 'usage'
    The stderr should include 'doctor'
    The stderr should include 'locate'
    The stderr should include 'preset'
  End

  It 'prints the same usage when called bare'
    bare() { inzsh; }
    When call bare
    The status should be failure
    The stderr should include 'usage'
  End
End

Describe 'inzsh doctor'
  It 'covers every field the bug template asks for'
    block() { inzsh_spec_doctor_env; inzsh doctor; }
    When call block
    The output should include 'zsh'
    The output should include 'terminal'
    The output should include 'TERM'
    The output should include 'colour depth'
    The output should include 'locale'
    The output should include 'nerd font'
    The output should include 'tmux'
    The status should be success
  End

  It 'reports the running zsh version'
    version() { inzsh_spec_doctor_env; inzsh doctor; }
    When call version
    The output should include "$ZSH_VERSION"
  End

  It 'reports the TERM in force when it is asked, not when it was loaded'
    term_now() {
      inzsh_spec_doctor_env
      local TERM=vt100 COLORTERM=
      inzsh doctor
    }
    When call term_now
    The output should include 'vt100'
  End

  It 'names the terminal program when the environment names one'
    program() {
      inzsh_spec_doctor_env
      local TERM_PROGRAM=Ghostty TERM_PROGRAM_VERSION=1.2.0
      inzsh doctor
    }
    When call program
    The output should include 'Ghostty 1.2.0'
  End

  It 'admits it cannot name the terminal when nothing does'
    anonymous() { inzsh_spec_doctor_env; inzsh doctor; }
    When call anonymous
    The output should include 'terminal      unknown'
  End

  It 'reports the detected colour depth'
    depth() { inzsh_spec_doctor_env; inzsh doctor; }
    When call depth
    The output should include 'colour depth  truecolor'
  End

  # The bug reader's first question about any surprising value: did the user set it, or did
  # detection? A valid override is obeyed by the detector, so the doctor says whose answer it is.
  It 'marks a colour depth that came from the override rather than from detection'
    overridden() {
      inzsh_spec_doctor_env
      local INZSH_COLOR_DEPTH=8
      inzsh doctor
    }
    When call overridden
    The output should include 'colour depth  8 (INZSH_COLOR_DEPTH)'
  End

  # The row says what was DETECTED and credits the override only when one was obeyed. The
  # unreadable value is not silently forgotten either — it is listed below as ignored, which is
  # the other half of the same honesty and is what issue #210 added.
  It 'does not blame the override for a value detection produced'
    ignored() {
      inzsh_spec_doctor_env
      local INZSH_COLOR_DEPTH=chartreuse
      inzsh doctor
    }
    When call ignored
    The output should include 'colour depth  truecolor'
    The output should not include 'truecolor (INZSH_COLOR_DEPTH)'
    The output should include 'ignored       INZSH_COLOR_DEPTH=chartreuse'
  End

  It 'reports the locale and whether multibyte glyphs are safe'
    utf8() { inzsh_spec_doctor_env; inzsh doctor; }
    When call utf8
    The output should include 'locale        en_US.UTF-8 (multibyte: yes)'
  End

  It 'reads a C locale as single-byte'
    single() {
      inzsh_spec_doctor_env
      local LC_ALL=C
      inzsh doctor
    }
    When call single
    The output should include 'locale        C (multibyte: no)'
  End

  It 'reports an undetectable Nerd Font as unknown, with the note that policy owes the reader'
    unknown_font() { inzsh_spec_doctor_env; inzsh doctor; }
    When call unknown_font
    The output should include 'nerd font     unknown'
    The output should include 'INZSH_NERD_FONT=0'
  End

  It 'reports tmux as absent outside a pane'
    no_pane() { inzsh_spec_doctor_env; inzsh doctor; }
    When call no_pane
    The output should include 'tmux          no'
    The output should include 'tmux rgb      unknown'
  End

  It 'reports the pane and warns when passthrough is not proven'
    pane() {
      inzsh_spec_doctor_env
      local TMUX=/tmp/tmux-1000/default,1,0
      inzsh doctor
    }
    When call pane
    The output should include 'tmux          yes'
    The output should include 'RGB passthrough'
  End

  It 'lists the registered invariants, straight out of the registry'
    guards() { inzsh_spec_doctor_env; inzsh doctor; }
    When call guards
    The output should include 'exit-code-capture'
    The output should include 'render-budget'
    The output should include 'separator-visibility'
  End

  # Issue #210. A value that fails its validator is dropped and never reported — the rule that
  # keeps a typo from stopping the prompt drawing — and the cost is that a near miss is
  # indistinguishable from a knob that does nothing: `INZSH_SEPARATOR_STYLE=rounded` is silent,
  # and the word is `round`. The registry holds every validator, so the block can answer it.
  #
  # Two properties, and the second is the one that keeps the section honest: what is listed is
  # SET, INVALID and therefore ignored — and nothing is said at all when everything is valid. A
  # clean shell does not grow a section telling it so.
  Describe 'values that are set and ignored'
    It 'names a near miss and the vocabulary it should have used'
      near_miss() {
        inzsh_spec_doctor_env
        local INZSH_SEPARATOR_STYLE=rounded
        inzsh doctor
      }
      When call near_miss
      The output should include 'ignored'
      The output should include 'INZSH_SEPARATOR_STYLE=rounded'
      The output should include 'arrow · round · divider'
    End

    # The vocabulary is rendered from the registered spec rather than restated here, so every
    # shape of validator has to come out as words. One example per shape that ships.
    Describe 'the vocabulary'
      Parameters
        INZSH_PRESET        wark    'sharp · warm'
        INZSH_SURFACE_MODE  chart   'alternate · ramp · flat · hue'
        INZSH_DIR_RANK      leftish 'whole number'
        INZSH_DIR_MINCOLS   -5      '0 or more'
        INZSH_TITLE         maybe   '1 or 0'
      End

      It "says $1=$2 accepts $3"
        accepts() {
          inzsh_spec_doctor_env
          typeset -g "$1"="$2"
          inzsh doctor
        }
        When call accepts "$1" "$2"
        The output should include "ignored"
        The output should include "$1=$2"
        The output should include "$3"
      End
    End

    # The section exists for the near miss, so silence is as load-bearing as the listing. A
    # `zsh -f` of its own, because the shell running the suite may carry knobs of its own.
    It 'says nothing at all when every value that is set is valid'
      clean() {
        zsh -f -c '
          TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
          source "$1/lib/core/config.zsh"
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/doctor.zsh"
          INZSH_SEPARATOR_STYLE=round
          INZSH_DIR_RANK=-3
          inzsh doctor
        ' inzsh-doctor-clean "$SHELLSPEC_PROJECT_ROOT"
      }
      When call clean
      The output should not include 'ignored'
      The stderr should eq ''
    End

    # Set-but-empty is UNSET at every level of this theme — an `INZSH_DIR_BG=` left in a zshrc
    # falls through to the role rather than blanking the segment — so it is not an ignored value
    # and must not be listed as one. `INZSH_NOT_A_KNOB` is quiet for a different reason since
    # issue #228: the registry has heard of nothing close enough to it, not because nothing here
    # can ever tell a typo from a variable that was never ours — see the near-miss examples below.
    It 'lists neither an empty value nor a name the registry never heard of'
      quiet() {
        zsh -f -c '
          TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
          source "$1/lib/core/config.zsh"
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/doctor.zsh"
          INZSH_SEPARATOR_STYLE=
          INZSH_DIR_BG=
          INZSH_NOT_A_KNOB=banana
          inzsh doctor
        ' inzsh-doctor-quiet "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should not include 'ignored'
      The stderr should eq ''
    End

    It 'lists every ignored value, one row each, in a fixed order'
      several() {
        zsh -f -c '
          TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
          source "$1/lib/core/config.zsh"
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/doctor.zsh"
          INZSH_SURFACE_MODE=chartreuse
          INZSH_PRESET=wark
          INZSH_DIR_MINCOLS=-5
          inzsh doctor | grep -c ignored
          _inzsh_doctor_ignored
          print -r -- "${reply[*]}"
        ' inzsh-doctor-several "$SHELLSPEC_PROJECT_ROOT"
      }
      When call several
      The line 1 should eq '3'
      The line 2 should eq 'INZSH_DIR_MINCOLS INZSH_PRESET INZSH_SURFACE_MODE'
    End

    # The block is pasted into an issue, so one hostile value may not break its shape. A newline
    # would end the row early, a control character would move the cursor, and a value long enough
    # to be a config file in its own right would push the block off the screen.
    It 'keeps one row per value whatever the value holds'
      hostile() {
        zsh -f -c '
          TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
          source "$1/lib/core/config.zsh"
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/doctor.zsh"
          INZSH_SURFACE_MODE=$'\''one\ntwo\tthree'\''
          INZSH_PRESET=%F{red}aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
          local -a rows=(${(f)"$(inzsh doctor)"})
          local -a ignored=(${(M)rows:#*ignored*})
          local -a wrong=()
          (( ${#ignored} == 2 )) || wrong+=rows:${#ignored}
          local row
          for row in $ignored; do
            [[ $row == *[[:cntrl:]]* ]] && wrong+=control
            (( ${#row} > 100 )) && wrong+=long:${#row}
          done
          [[ ${ignored[2]} == *aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa* ]] && wrong+=unclipped
          print -r -- "${wrong[*]}"
        ' inzsh-doctor-hostile "$SHELLSPEC_PROJECT_ROOT"
      }
      When call hostile
      The output should eq ''
      The stderr should eq ''
    End

    # Issue #228. `_inzsh_doctor_ignored` above only ever sees a name the registry recognises;
    # this is the other half — a name it does NOT recognise, close enough to one it does that it
    # is almost certainly the same slipped key. Printed as the same `ignored` row shape, straight
    # after the ones above, because a reader pasting this block is asking one question of both:
    # "what did I set here that did nothing?"
    Describe 'a near miss for a name the registry has never heard of'
      It 'names the singleton it is probably a typo of'
        singleton_typo() {
          inzsh_spec_doctor_env
          local INZSH_SEPARATOR_STYL=round
          inzsh doctor
        }
        When call singleton_typo
        The output should include 'ignored'
        The output should include 'INZSH_SEPARATOR_STYL=round - probably INZSH_SEPARATOR_STYLE'
      End

      # The shape offered for a mistyped family member is the pattern itself, not a guessed
      # segment name — nothing here knows which segment `RANNK` was reaching for.
      It 'names the family shape a mistyped segment knob is probably one of'
        family_typo() {
          inzsh_spec_doctor_env
          local INZSH_GIT_RANNK=3
          inzsh doctor
        }
        When call family_typo
        The output should include 'ignored'
        The output should include 'INZSH_GIT_RANNK=3 - probably INZSH_*_RANK'
      End

      # The example the issue itself asks to stay silent for — a name that is not close to
      # anything registered, however plausible it looks as a knob.
      It 'stays silent for a name that is not close to anything registered'
        unrelated() {
          inzsh_spec_doctor_env
          local INZSH_MY_OWN_THING=banana
          inzsh doctor
        }
        When call unrelated
        The output should not include 'ignored'
      End

      # The same "set-but-empty is unset" rule `_inzsh_doctor_ignored` keeps: a near miss on an
      # empty value is still nothing set, and must not grow a row of its own.
      It 'skips a near miss whose value is empty'
        blank() {
          zsh -f -c '
            TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
            source "$1/lib/core/config.zsh"
            source "$1/lib/core/detect.zsh"
            source "$1/lib/core/doctor.zsh"
            INZSH_SEPARATOR_STYL=
            inzsh doctor
          ' inzsh-doctor-near-miss-blank "$SHELLSPEC_PROJECT_ROOT"
        }
        When call blank
        The output should not include 'ignored'
        The stderr should eq ''
      End

      # A registered name is never a near miss, of itself or of anything else — that question is
      # `_inzsh_doctor_ignored`'s, and the two lists are read from the same walk but never
      # overlap: `_inzsh_config_spec_of` gates one in exactly where it gates the other out.
      It 'never lists a registered name as a near miss'
        registered() {
          zsh -f -c '
            TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
            source "$1/lib/core/config.zsh"
            source "$1/lib/core/detect.zsh"
            source "$1/lib/core/doctor.zsh"
            INZSH_SEPARATOR_STYLE=round
            _inzsh_doctor_near_misses
            print -r -- "${reply[*]}"
          ' inzsh-doctor-near-miss-registered "$SHELLSPEC_PROJECT_ROOT"
        }
        When call registered
        The output should eq ''
        The stderr should eq ''
      End

      # The house rule this whole file keeps: a diagnostic that can fail is one nobody can run in
      # the broken environment it exists for.
      It 'returns success even though nothing here is a valid knob'
        odd() {
          zsh -f -c '
            TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
            source "$1/lib/core/config.zsh"
            source "$1/lib/core/detect.zsh"
            source "$1/lib/core/doctor.zsh"
            INZSH_SEPARATOR_STYL=round
            INZSH_GIT_RANNK=abc
            _inzsh_doctor_near_misses
            print $?
          ' inzsh-doctor-near-miss-status "$SHELLSPEC_PROJECT_ROOT"
        }
        When call odd
        The output should eq '0'
        The stderr should eq ''
      End
    End
  End

  It 'reports where the location came from when coordinates are configured'
    provenance() {
      inzsh_spec_doctor_env
      local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
      inzsh doctor
    }
    When call provenance
    The output should include 'location: config'
  End

  # The output exists to be pasted into a public issue, and CONTRIBUTING.md asks reporters not
  # to include their coordinates. Provenance is the diagnostic; the position itself never leaves.
  It 'never prints the coordinates themselves'
    private() {
      inzsh_spec_doctor_env
      local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
      inzsh doctor
    }
    When call private
    The output should not include '21.4225'
    The output should not include '39.8262'
  End

  It 'reports no location as none rather than as silence'
    nowhere() { inzsh_spec_doctor_env; inzsh doctor; }
    When call nowhere
    The output should include 'location: none'
  End

  # Issue #229. The table row: whether an entry is cached, readable and current — and, in every
  # one of those states, never the coordinates or a hash of them the recipe was built from. Every
  # example is wrapped `{ … } always { cleanup }`, and every call to `inzsh doctor` is pinned to
  # `$inzsh_spec_salah_now` — see the fixture comment above for why neither is optional.
  Describe 'the prayer table'
    It 'reports no table when no position is known'
      no_position() { inzsh_spec_doctor_env; inzsh doctor $inzsh_spec_salah_now; }
      When call no_position
      The output should include 'table: none (no position)'
    End

    It 'reports the table as not cached yet when nothing has ever been written for the recipe'
      not_cached() {
        inzsh_spec_doctor_salah_env || return 1
        {
          inzsh doctor $inzsh_spec_salah_now
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call not_cached
      The output should include 'table: not cached yet (method MWL, asr standard)'
      The status should be success
    End

    It 'reports a table that covers today as current'
      current() {
        inzsh_spec_doctor_salah_env || return 1
        {
          inzsh_spec_doctor_cache_write || print -r -- no-entry
          inzsh doctor $inzsh_spec_salah_now
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call current
      The output should include 'table: current, covers today (method MWL, asr standard)'
    End

    It 'reports a table computed under the same recipe for a day that is not today as stale'
      stale() {
        inzsh_spec_doctor_salah_env || return 1
        {
          _inzsh_salah_cache_keys $inzsh_spec_salah_now "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON"
          # Same seed as today's, a day three days earlier — the ordinary case of a shell that
          # has not opened since.
          local stale_key="2026-5-29|${_inzsh_salah_seed}"
          inzsh_spec_doctor_cache_write "$stale_key" || print -r -- no-entry
          inzsh doctor $inzsh_spec_salah_now
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call stale
      The output should include 'table: stale, computed for a day that is not today'
    End

    It 'reports denied for an entry it cannot read'
      denied() {
        inzsh_spec_doctor_salah_env || return 1
        {
          inzsh_spec_doctor_cache_write || print -r -- no-entry
          local file=$REPLY
          chmod 000 "$file"
          inzsh doctor $inzsh_spec_salah_now
        } always {
          chmod 644 "$file" 2>/dev/null
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call denied
      The output should include 'table: unreadable, permission denied (method MWL, asr standard)'
      The status should be success
    End

    It 'reports future for an entry written by a format version this one does not know'
      future() {
        inzsh_spec_doctor_salah_env || return 1
        {
          inzsh_spec_doctor_cache_write || print -r -- no-entry
          local file=$REPLY
          local content=$(<"$file")
          content=${content/version$'\t'1/version$'\t'9}
          print -r -- "$content" > "$file"
          inzsh doctor $inzsh_spec_salah_now
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call future
      The output should include 'table: unreadable, written by a newer InZsh (method MWL, asr standard)'
      The status should be success
    End

    It 'reports an empty entry file as unreadable rather than failing'
      # A full filesystem or an interrupted write can leave nothing behind at all — no version
      # to reject, no slot to fail — and the doctor still owes a row rather than a crash.
      empty() {
        inzsh_spec_doctor_salah_env || return 1
        {
          inzsh_spec_doctor_cache_write || print -r -- no-entry
          local file=$REPLY
          : > "$file"
          inzsh doctor $inzsh_spec_salah_now
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call empty
      The output should include 'table: unreadable (method MWL, asr standard)'
      The status should be success
    End

    # Issue #229 review, finding I2. A directory that does not exist, is a stray file, or cannot
    # be searched must not read as "not cached" — that word means the directory is fine and only
    # the recipe has never been written, which is a different fact from "the segment is
    # recomputing every shell and this is why".
    It 'reports no cache directory rather than not cached when the directory cannot be used'
      nodir() {
        inzsh_spec_doctor_salah_env || return 1
        {
          typeset -g INZSH_SALAH_CACHE_DIR=$inzsh_spec_salah_cache/never-created
          inzsh doctor $inzsh_spec_salah_now
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call nodir
      The output should include 'table: no cache directory (recomputed every shell)'
    End

    # Issue #229 review, finding I3. `inzsh doctor` had zero filesystem side effects before this
    # row existed and still must have none — the regression test for the `mkdir -p` an earlier
    # version of `_inzsh_salah_cache_health` triggered by reusing the write-capable path builder.
    It 'never creates the cache directory it only reports on'
      readonly_probe() {
        inzsh_spec_doctor_env
        local scratch
        scratch=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-salah-spec-XXXXXX") || return 1
        {
          typeset -gx TZ=Asia/Riyadh
          typeset -g INZSH_SALAH_CACHE_DIR=$scratch/never-created
          typeset -g INZSH_SALAH_LAT=$inzsh_spec_salah_lat INZSH_SALAH_LON=$inzsh_spec_salah_lon
          typeset -g INZSH_SALAH_AUTOLOCATE=0

          inzsh doctor $inzsh_spec_salah_now >/dev/null
          if [[ -e $INZSH_SALAH_CACHE_DIR ]]; then
            print -r -- created
          fi
        } always {
          inzsh_spec_salah_clean "$scratch"
        }
      }
      When call readonly_probe
      The output should eq ''
    End

    # The whole point of the row, and the review's central finding (C1): a hash of the recipe is
    # a slow but complete encoding of the position it was built from, not a redaction of it, and
    # is checked for here on the same footing as the raw coordinates — a `[0-9a-f]{8}` word next
    # to `table:` would be exactly what that finding was about. Checked across several states, so
    # a future word choice cannot reintroduce a leak that only the untested branch would show.
    It 'never prints the coordinates or a digest of them in any state of the table'
      leakproof() {
        inzsh_spec_doctor_salah_env || return 1
        {
          setopt local_options extended_glob
          local -a bad=()
          local block

          block=$(inzsh doctor $inzsh_spec_salah_now 2>&1)
          [[ $block == *21.4225* || $block == *39.8262* ]] && bad+=not-cached
          [[ $block == *'table: '*[0-9a-f](#c8)* ]]         && bad+=digest-shaped-not-cached

          inzsh_spec_doctor_cache_write >/dev/null
          block=$(inzsh doctor $inzsh_spec_salah_now 2>&1)
          [[ $block == *21.4225* || $block == *39.8262* ]] && bad+=current
          [[ $block == *'table: '*[0-9a-f](#c8)* ]]         && bad+=digest-shaped-current

          _inzsh_salah_cache_keys $inzsh_spec_salah_now "$INZSH_SALAH_LAT" "$INZSH_SALAH_LON"
          local other_key="$_inzsh_salah_day|10.0000|20.0000|+0000|OTHER asr:1"
          inzsh_spec_doctor_cache_write "$other_key" >/dev/null
          block=$(inzsh doctor $inzsh_spec_salah_now 2>&1)
          [[ $block == *21.4225* || $block == *39.8262* ]] && bad+=collision
          [[ $block == *'table: '*[0-9a-f](#c8)* ]]         && bad+=digest-shaped-collision

          print -rl -- $bad
        } always {
          inzsh_spec_salah_clean "$inzsh_spec_salah_cache"
        }
      }
      When call leakproof
      The output should eq ''
    End
  End

  # The command ships with the theme, so it has to work from a partial load — a bundle that
  # stopped early, a spec that included three files. Without the salah library the location line
  # is omitted rather than invented; everything the bug template needs is still there.
  It 'stands on config, detect and itself alone'
    standalone() {
      zsh -f -c '
        TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
        source "$1/lib/core/config.zsh"
        source "$1/lib/core/detect.zsh"
        source "$1/lib/core/doctor.zsh"
        inzsh doctor
      ' inzsh-doctor-standalone "$SHELLSPEC_PROJECT_ROOT"
    }
    When call standalone
    The output should include 'colour depth  truecolor'
    The output should not include 'location'
    The stderr should eq ''
  End
End

Describe 'inzsh locate'
  # The lookup's public face — issue #186. `INZSH_SALAH_AUTOLOCATE` permits the one network call
  # in the theme, and this command is the only shipped way to make it: typed by a person, never
  # reached from a hook or the render path. Every example here keeps the suite offline the way
  # `salah_location_spec.sh` does — the only endpoint ever contacted is a port on 127.0.0.1 that
  # nothing serves, under a one-second ceiling.

  inzsh_spec_locate_now=1780315200

  inzsh_spec_locate_env() {
    emulate -L zsh

    typeset -g inzsh_spec_locate_cache=
    inzsh_spec_locate_cache=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-locate-XXXXXX") || return 1

    typeset -g INZSH_SALAH_CACHE_DIR=$inzsh_spec_locate_cache
    typeset -g INZSH_SALAH_LAT= INZSH_SALAH_LON=
    typeset -g INZSH_SALAH_AUTOLOCATE=1
    typeset -g INZSH_SALAH_AUTOLOCATE_TTL=
    typeset -g INZSH_SALAH_AUTOLOCATE_TIMEOUT=1
    typeset -g INZSH_SALAH_AUTOLOCATE_URL='http://127.0.0.1:1/'

    return 0
  }

  inzsh_spec_locate_clean() {
    emulate -L zsh

    [[ ${inzsh_spec_locate_cache:t} == inzsh-locate-* ]] || return 0
    rm -rf -- "$inzsh_spec_locate_cache" 2>/dev/null

    return 0
  }

  It 'refuses while the knob is off, and says which knob permits it'
    off() {
      inzsh_spec_locate_env
      local INZSH_SALAH_AUTOLOCATE=0
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call off
    The status should be failure
    The stderr should include 'INZSH_SALAH_AUTOLOCATE'
  End

  # A typo may not switch a network call on — the same rule the knob itself keeps.
  It 'reads an unreadable knob as off'
    typo() {
      inzsh_spec_locate_env
      local INZSH_SALAH_AUTOLOCATE=banana
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call typo
    The status should be failure
    The stderr should include 'INZSH_SALAH_AUTOLOCATE'
  End

  It 'leaves a current position alone and says how to insist'
    current() {
      inzsh_spec_locate_env
      _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_locate_now - 300 )) || return 1
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call current
    The status should be success
    The output should include 'current'
    The output should include '--force'
  End

  It 'reports a failed lookup and keeps the previous position'
    kept() {
      inzsh_spec_locate_env
      local INZSH_SALAH_AUTOLOCATE_TTL=300
      _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_locate_now - 86400 )) || return 1
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call kept
    The status should be failure
    The stderr should include 'kept'
  End

  It 'says so when the lookup fails and nothing was ever stored'
    nothing() {
      inzsh_spec_locate_env
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call nothing
    The status should be failure
    The stderr should include 'no position'
  End

  It 'looks a current position up anyway under --force'
    forced() {
      inzsh_spec_locate_env
      _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_locate_now - 300 )) || return 1
      inzsh locate --force $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call forced
    The status should be failure
    The stderr should include 'kept'
  End
End

Describe 'inzsh preset'
  # Issue #211. `INZSH_PRESET` is read when the theme loads — correctly, since `PS2`, `SPROMPT`
  # and the title are built once from the register resolved then — so setting it at a prompt does
  # nothing, and the only live switch was sourcing a preset file by its full path, which differs
  # between an in-place install and a bundle.
  #
  # The register table in `lib/core/tokens.zsh` is what this reuses, so the command reads no file
  # and works identically from a bundle with no `presets/` directory anywhere near it.
  #
  # Every example starts from the register it is NOT switching to, so each is a real switch
  # rather than a command agreeing with where the shell already was.

  Describe 'reporting'
    It 'names the register in force and the ones there are'
      report() {
        _inzsh_register=dark
        inzsh preset
      }
      When call report
      The line 1 should eq 'preset: sharp'
      The line 2 should eq 'available: sharp · warm'
      The status should be success
    End

    # The REGISTER is the truth, not the knob: somebody who sourced `presets/inzsh-warm.zsh` by
    # hand moved one and not the other, and the report has to describe the prompt being drawn.
    It 'reads the name back from the register rather than from the knob'
      sourced_by_hand() {
        _inzsh_register=light
        unset INZSH_PRESET
        inzsh preset
      }
      When call sourced_by_hand
      The line 1 should eq 'preset: warm'
      The status should be success
    End

    # Empty is unset at every level of this theme, so an argument that expanded to nothing is a
    # report rather than a refusal.
    It 'reports when the argument expanded to nothing'
      empty() {
        _inzsh_register=dark
        inzsh preset ''
      }
      When call empty
      The line 1 should eq 'preset: sharp'
      The status should be success
    End
  End

  Describe 'switching'
    # $1 what is typed, $2 the register before, $3 the register after, $4 the name reported.
    Parameters
      warm   dark  light warm
      sharp  light dark  sharp
      WARM   dark  light warm
      ' Warm ' dark light warm
    End

    It "switches the register to $3 for '$1'"
      switched() {
        _inzsh_register=$2
        _inzsh_tokens_resolve
        inzsh preset "$1"
        print -r -- "$_inzsh_register"
      }
      When call switched "$1" "$2"
      The line 1 should eq "preset: $4"
      The line 2 should eq "$3"
      The status should be success
    End
  End

  Describe 'what switching touches'
    It 'rebuilds every role from the register it switched to'
      roles() {
        _inzsh_register=dark
        _inzsh_tokens_resolve
        inzsh preset warm >/dev/null
        local named=_inzsh_roles_light
        local -A table=("${(@Pkv)named}")
        local role; local -a wrong=()
        for role in ${(ko)table}; do
          [[ ${_inzsh_role[$role]} == ${_inzsh_palette[${table[$role]}]} ]] || wrong+=$role
        done
        print -r -- "${#_inzsh_role} ${#wrong}"
      }
      When call roles
      The output should eq '38 0'
    End

    # The knob is the applier's own input, and a shell whose knob disagreed with the register it
    # is drawing would lie to everything that reads it back — the doctor, a re-source, the next
    # report. Written as the canonical name, whatever spelling was typed.
    It 'leaves the knob agreeing with the register'
      knob() {
        _inzsh_register=dark
        inzsh preset ' WARM ' >/dev/null
        print -r -- "${INZSH_PRESET}"
      }
      When call knob
      The output should eq 'warm'
    End

    # The reason the knob is read at load time in the first place: the secondary prompts are
    # built ONCE, from the roles resolved at install. A switch that moved the ribbon and left the
    # continuation prompt in the old register would be the half-done knob the load-time rule
    # exists to avoid. An interactive shell, because installing them is what it is about.
    It 'rebuilds the secondary prompts it owns'
      secondary() {
        TERM=xterm-256color zsh -f -i -c '
          source "$1/lib/core/config.zsh"
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          source "$1/lib/core/doctor.zsh"
          _inzsh_register=dark
          _inzsh_tokens_resolve
          _inzsh_prompts_install
          local before=$PS2 before_sprompt=$SPROMPT
          inzsh preset warm >/dev/null
          local -a wrong=()
          [[ $PS2 != $before ]]                    || wrong+=ps2-kept-the-old-register
          [[ $SPROMPT != $before_sprompt ]]        || wrong+=sprompt-kept-the-old-register
          [[ $PS2 == *${_inzsh_role[accent]}* ]]   || wrong+=ps2-not-from-the-new-roles
          print -r -- "${wrong[*]}"
        ' inzsh-preset-secondary "$SHELLSPEC_PROJECT_ROOT"
      }
      When call secondary
      The output should eq ''
      The stderr should eq ''
    End

    # And the other side of owning them: a shell where the theme never installed the secondary
    # prompts has somebody else's `PS2` in it, and that is none of our business.
    It 'leaves a PS2 the theme never installed alone'
      foreign() {
        TERM=xterm-256color zsh -f -i -c '
          source "$1/lib/core/config.zsh"
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          source "$1/lib/core/doctor.zsh"
          _inzsh_register=dark
          PS2="mine> "
          inzsh preset warm >/dev/null
          print -r -- "$PS2"
        ' inzsh-preset-foreign "$SHELLSPEC_PROJECT_ROOT"
      }
      When call foreign
      The output should eq 'mine> '
      The stderr should eq ''
    End
  End

  Describe 'a name it does not know'
    # Every one of these is a plausible thing to type — a register's own name, a preset file's
    # name, a typo — and every one leaves the register exactly as it was found. The refusal names
    # what there is, because the whole point of the command is that the vocabulary is small and
    # nobody should have to go and look it up.
    Parameters
      light
      dark
      inzsh-warm
      chartreuse
      0
    End

    It "refuses '$1' and leaves the register alone"
      refused() {
        _inzsh_register=dark
        _inzsh_tokens_resolve
        inzsh preset "$1"
        local -i rc=$?
        print -r -- "$_inzsh_register"
        return $rc
      }
      When call refused "$1"
      The status should be failure
      The output should eq 'dark'
      The stderr should include "$1"
      The stderr should include 'sharp · warm'
    End
  End

  It 'refuses more than one name at a time'
    two() {
      _inzsh_register=dark
      inzsh preset warm sharp
      local -i rc=$?
      print -r -- "$_inzsh_register"
      return $rc
    }
    When call two
    The status should be failure
    The output should eq 'dark'
    The stderr should include 'sharp · warm'
  End

  # The command ships with the theme, so it has to be honest about a partial load. Without the
  # token layer there is no register to switch and no table to read one from, and saying so is
  # the whole of what it can do.
  It 'says so when the token layer is not loaded'
    standalone() {
      zsh -f -c '
        source "$1/lib/core/config.zsh"
        source "$1/lib/core/doctor.zsh"
        inzsh preset warm
      ' inzsh-preset-standalone "$SHELLSPEC_PROJECT_ROOT"
    }
    When call standalone
    The status should be failure
    The stderr should include 'token layer'
    The output should eq ''
  End
End

Describe 'make doctor'
  # The Makefile target runs the same `inzsh doctor` the shipped command defines, through the
  # harness launcher — never by re-implementing the block in make.
  It 'wires the harness to the same code path as the shipped command'
    harness() { zsh -f "$SHELLSPEC_PROJECT_ROOT/tools/doctor.zsh"; }
    When call harness
    The output should include 'InZsh doctor'
    The output should include 'colour depth'
    The output should include 'zsh'
    The status should be success
  End
End

Describe 'the house rule, kept anyway'
  # Not on the render path — nothing calls the near-miss matcher per prompt — but issue #228
  # says outright that it keeps the rule regardless: parameter operations and arithmetic only.
  # `$((` is taken out of the way first, the same way `salah_calc_spec.sh` clears it for its own
  # forkless check, so the arithmetic-expansion opener is never mistaken for a command one.
  It 'never starts a subprocess'
    forkless() {
      setopt local_options extended_glob
      local line bare
      local -a bad=()
      while IFS= read -r line; do
        [[ ${line##[[:space:]]#} == \#* ]] && continue
        bare=${line//\$\(\(/}
        [[ $bare == *'$('* || $bare == *'`'* ]] && bad+=$line
      done < "$SHELLSPEC_PROJECT_ROOT/lib/core/doctor.zsh"
      # The offending lines themselves, not only their count — stderr, so a failing count in the
      # assertion below still leaves the actual `$(` or backtick visible in the run's own output
      # rather than sending whoever is chasing it back to grep the file by hand.
      (( ${#bad} )) && print -ru2 -- "${bad[@]}"
      print -r -- "${#bad}"
    }
    When call forkless
    The output should eq '0'
  End
End
