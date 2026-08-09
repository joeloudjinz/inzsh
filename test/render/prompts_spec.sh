# The secondary prompts and the terminal title — `lib/core/prompts.zsh`.
#
# Nothing here is `Include`d. Every example runs in a fresh `zsh` of its own, because what is
# under test is what INSTALLING does to a shell: `PS2`, `SPROMPT`, two hook arrays and a
# sequence written to stdout. A spec that installed a PS2 into its own runner would be testing
# a shell that already had one, and would be sourcing work in progress into a live shell
# besides.
#
# The four properties the file exists for, in the order they matter:
#
#   readable    `PS2` says WHY the shell is waiting and `SPROMPT` says which word is wrong,
#               both with a glyph and only then a colour, and both expand with nothing left over
#   reversible  install saves what it found and uninstall puts it back byte for byte, including
#               the difference between an empty variable and an absent one
#   silent      the title writes nothing into a script, nothing into a terminal that mishandles
#               OSC, and nothing when it is switched off
#   zero width  what it does write is wrapped so a prompt containing it still measures right

# An interactive zsh with no startup files, on a terminal that accepts OSC.
#
# `TERM` is PINNED rather than inherited, and that is the whole reason this helper exists: CI
# runs with no terminal at all, and `dumb` is one of the two values the title layer is required
# to refuse. An inherited `TERM` would turn every emission example green for the wrong reason.
#
# Inside the script, `$1` is the project root, `$2` an ESC and `$3` a BEL, and anything the
# caller adds follows. The two bytes are passed in rather than spelled inside each script,
# because a `$'\e'` cannot be written inside the single-quoted body of an example without
# closing it.
inzsh_spec_prompts() {
  local script=$1
  shift
  TERM=xterm-256color zsh -f -i -c "$script" inzsh-prompts \
    "$SHELLSPEC_PROJECT_ROOT" $'\e' $'\a' "$@"
}

# The same shell without `-i` — a script, an `ssh host command`, an editor's `zsh -c`. Same
# arguments, and the theme must do nothing at all in it.
inzsh_spec_script() {
  local script=$1
  shift
  TERM=xterm-256color zsh -f -c "$script" inzsh-prompts-script \
    "$SHELLSPEC_PROJECT_ROOT" $'\e' $'\a' "$@"
}

# The same again with one `INZSH_` knob set: `inzsh_spec_env <name> <value> <script> [args…]`.
# The value goes through `env` as a single argument, so a format with spaces in it arrives
# whole, and an empty value arrives SET AND EMPTY — which is the case half of these knobs are
# about.
inzsh_spec_env() {
  local knob=$1 value=$2 script=$3
  shift 3
  env "$knob=$value" TERM=xterm-256color zsh -f -i -c "$script" inzsh-prompts-env \
    "$SHELLSPEC_PROJECT_ROOT" $'\e' $'\a' "$@"
}

Describe 'the secondary prompts'
  Describe 'the continuation prompt'
    # `%_` is the point of the whole thing: the parser state is what turns "the shell is still
    # waiting" into "the shell is waiting for a closing quote". A PS2 without it is a `>`.
    It 'carries the parser state, a colour and a marker, and expands with nothing left over'
      ps2() {
        inzsh_spec_prompts '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          _inzsh_prompts_ps2
          local raw=$REPLY expanded=${(%%)REPLY}
          local -a wrong=()
          [[ $raw == *%_* ]]                     || wrong+=no-parser-state
          [[ $raw == *%F\{?*\}*%f* ]]            || wrong+=no-colour
          [[ $raw == *%F\{\}* ]]                 && wrong+=empty-colour
          [[ $raw == *$_inzsh_prompts_marker* ]] || wrong+=no-marker
          [[ $raw == *" " ]]                     || wrong+=no-trailing-space
          [[ $expanded != *%* ]]                 || wrong+=left-over-escape
          print -r -- "${wrong[*]}"
        '
      }
      When call ps2
      The output should eq ''
    End
  End

  Describe 'the correction prompt'
    # zsh reads one key here and accepts four of them. A prompt that offers two of the four
    # choices it will act on teaches the wrong thing, so all four are asserted by name.
    It 'names both words, both glyphs and all four choices, and expands with nothing left over'
      sprompt() {
        inzsh_spec_prompts '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          _inzsh_prompts_sprompt
          local raw=$REPLY expanded=${(%%)REPLY}
          local -a wrong=() key
          [[ $raw == *%R* ]]                    || wrong+=no-typed-word
          [[ $raw == *%r* ]]                    || wrong+=no-correction
          [[ $raw == *$_inzsh_prompts_wrong* ]] || wrong+=no-wrong-glyph
          [[ $raw == *$_inzsh_prompts_right* ]] || wrong+=no-right-glyph
          for key in y n a e; do
            [[ $raw == *$key* ]] || wrong+=no-choice-$key
          done
          [[ $raw == *%F\{\}* ]]                && wrong+=empty-colour
          [[ $raw == *" " ]]                    || wrong+=no-trailing-space
          [[ $expanded != *%* ]]                || wrong+=left-over-escape
          print -r -- "${wrong[*]}"
        '
      }
      When call sprompt
      The output should eq ''
    End

    # Colour is never the only signal. Stripped of every SGR sequence the string still has to
    # say which word was typed and which is the suggestion — and it is the ✕/✓ pair, not the
    # red/green pair, that a monochrome terminal keeps.
    It 'still distinguishes the two words with no colour at all'
      monochrome() {
        inzsh_spec_prompts '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          setopt extended_glob
          _inzsh_prompts_sprompt
          local visible=${${(%%)REPLY}//$2\[[0-9;]#m/}
          local -a wrong=()
          [[ $visible == *$_inzsh_prompts_wrong* ]] || wrong+=no-wrong-glyph
          [[ $visible == *$_inzsh_prompts_right* ]] || wrong+=no-right-glyph
          [[ $visible == *$2* ]]                    && wrong+=colour-left-behind
          print -r -- "${wrong[*]}"
        '
      }
      When call monochrome
      The output should eq ''
    End
  End

  Describe 'the user override'
    # $1 a label, $2 the knob, $3 the builder, $4 the replacement.
    Parameters
      ps2     INZSH_PS2     _inzsh_prompts_ps2     '%_ still waiting > '
      sprompt INZSH_SPROMPT _inzsh_prompts_sprompt 'correct %R to %r? '
    End

    # Any non-empty value wins verbatim. Not validated, not decorated, not measured: a user who
    # replaces the whole string has said everything there is to say about it. Bracketed on
    # output because the trailing space is part of the value and part of the point.
    It "$2 replaces the theme's $1 exactly"
      override() {
        inzsh_spec_env "$1" "$2" '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          '"$3"'
          print -r -- "[$REPLY]"
        '
      }
      When call override "$2" "$4" "$3"
      The output should eq "[$4]"
    End

    # Set but empty counts as unset. An `INZSH_PS2=` left behind in a zshrc must fall through
    # to the theme's own rather than blank the prompt — the house rule, stated once per knob.
    It "$2= falls through to the theme's $1 rather than blanking it"
      empty() {
        inzsh_spec_env "$1" '' '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          '"$2"'
          local overridden=$REPLY
          unset "$4"
          '"$2"'
          [[ -n $REPLY && $overridden == $REPLY ]] && print -r -- same || print -r -- "$REPLY"
        ' "$1"
      }
      When call empty "$2" "$3"
      The output should eq 'same'
    End
  End

  # A bundle loaded without the token layer, a partial source, a role table that never
  # resolved. `%F{}` is not a colour — zsh prints it — so no role means no colour, same text.
  Describe 'a shell with no roles resolved'
    It 'drops the colour rather than emitting an empty one'
      uncoloured() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          _inzsh_prompts_ps2;     local ps2=$REPLY
          _inzsh_prompts_sprompt; local sprompt=$REPLY
          local -a wrong=()
          [[ $ps2$sprompt == *%F* ]]                && wrong+=colour-without-a-role
          [[ $ps2 == *%_* ]]                        || wrong+=no-parser-state
          [[ $sprompt == *%R*%r* ]]                 || wrong+=no-words
          [[ $sprompt == *$_inzsh_prompts_wrong* ]] || wrong+=no-glyph
          print -r -- "${wrong[*]}"
        '
      }
      When call uncoloured
      The output should eq ''
    End
  End

  Describe 'install'
    It 'assigns exactly what the two builders say'
      assigned() {
        inzsh_spec_prompts '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          _inzsh_prompts_install
          _inzsh_prompts_ps2;     local ps2=$REPLY
          _inzsh_prompts_sprompt; local sprompt=$REPLY
          local -a wrong=()
          [[ $PS2 == $ps2 ]]         || wrong+=PS2
          [[ $SPROMPT == $sprompt ]] || wrong+=SPROMPT
          print -r -- "${wrong[*]}"
        '
      }
      When call assigned
      The output should eq ''
    End

    # A reload, a second plugin manager, a bundle and a checkout of the same theme all add up
    # to a second install. It must land where the first did — and, more importantly, the
    # ORIGINALS must survive it: a save that ran twice would save the theme's own PS2 over the
    # user's and leave nothing to go back to.
    It 'is idempotent, and a second install cannot swallow the originals'
      twice() {
        inzsh_spec_prompts '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          PS2="mine> "; SPROMPT="mine? "
          _inzsh_prompts_install
          local first="$PS2|$SPROMPT"
          _inzsh_prompts_install; _inzsh_prompts_install
          local second="$PS2|$SPROMPT"
          _inzsh_prompts_uninstall
          local -a wrong=()
          [[ $first == $second ]]    || wrong+=stacked
          [[ $PS2 == "mine> " ]]     || wrong+=PS2:$PS2
          [[ $SPROMPT == "mine? " ]] || wrong+=SPROMPT:$SPROMPT
          print -r -- "${wrong[*]}"
        '
      }
      When call twice
      The output should eq ''
    End

    # Byte for byte, and the values are chosen to be hostile: a per cent, a backslash, a quote
    # and a trailing space are all things a naive save-and-restore mangles.
    It 'restores the values it found exactly, escapes and trailing spaces included'
      exact() {
        inzsh_spec_prompts '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/prompts.zsh"
          PS2="%_ 100%% \\ ${4}q${4} > "
          SPROMPT="fix %R? "
          local before="$(typeset -p PS2 SPROMPT)"
          _inzsh_prompts_install
          _inzsh_prompts_uninstall
          local after="$(typeset -p PS2 SPROMPT)"
          [[ $before == $after ]] && print -r -- same || print -r -- "$before // $after"
        ' "'"
      }
      When call exact
      The output should eq 'same'
    End

    # The case the saved array exists for. An associative array cannot hold "absent", so the
    # difference between `SPROMPT=` and no SPROMPT at all is carried in a companion key — and
    # restoring an unset variable as an empty one is not a restoration, it is quieter damage.
    #
    # Both ways round, because the two variables are restored by two separate branches and a
    # spec that only ever unsets one of them cannot see the other one go wrong.
    Describe 'absence'
      Parameters
        PS2     SPROMPT
        SPROMPT PS2
      End

      It "restores an absent $1 as absent and an empty $2 as empty"
        absence() {
          inzsh_spec_prompts '
            source "$1/lib/core/tokens.zsh"
            source "$1/lib/core/prompts.zsh"
            unset "$4"
            typeset -g "$5"=
            _inzsh_prompts_install
            local -a wrong=()
            # `${(P)+name}` is the indirect form of `${+name}`. `typeset -p` cannot answer
            # this question: PS2 and SPROMPT are special parameters, and it reports success
            # for one that has been unset.
            (( ${(P)+4} && ${(P)+5} )) || wrong+=install-left-one-unset
            _inzsh_prompts_uninstall
            (( ${(P)+4} ))             && wrong+=$4-resurrected
            (( ${(P)+5} ))             || wrong+=$5-lost
            [[ -z ${(P)5} ]]           || wrong+=$5-not-empty
            print -r -- "${wrong[*]}"
          ' "$1" "$2"
        }
        When call absence "$1" "$2"
        The output should eq ''
      End
    End

    # Uninstall from a shell that never installed is a no-op, and a second uninstall must not
    # restore a snapshot that is no longer current — hence the forget at the end of it.
    It 'uninstalls cleanly when there is nothing to uninstall'
      idle() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          PS2="untouched> "
          _inzsh_prompts_uninstall
          local first=$?
          _inzsh_prompts_install
          _inzsh_prompts_uninstall
          PS2="changed> "
          _inzsh_prompts_uninstall
          print -r -- "$first [$PS2]"
        '
      }
      When call idle
      The output should eq '0 [changed> ]'
    End

    Describe 'a non-interactive shell'
      It 'assigns nothing, registers nothing and prints nothing'
        inert() {
          inzsh_spec_script '
            local before="$PS2|$SPROMPT"
            source "$1/lib/core/prompts.zsh"
            _inzsh_prompts_install
            _inzsh_title_install
            local -a leaked=()
            [[ "$PS2|$SPROMPT" == $before ]] || leaked+=prompts
            (( ${+precmd_functions} ))       && leaked+=precmd:${precmd_functions[*]}
            (( ${+preexec_functions} ))      && leaked+=preexec:${preexec_functions[*]}
            print -r -- "${leaked[*]}"
          '
        }
        When call inert
        The output should eq ''
        The stderr should eq ''
      End
    End

    # The user's environment is theirs. Snapshot every parameter with `typeset -p` and every
    # option with `setopt` either side of the whole lifecycle — source, install both halves,
    # run both hooks, uninstall both halves — and compare line by line. `PS2` and `SPROMPT` are
    # NOT filtered out of the comparison: they are the point of it.
    #
    # Snapshots go to files rather than to variables, so that holding one cannot itself perturb
    # the next; `$snap` is assigned before either and never changes, so it reads identically in
    # both.
    Describe 'purity'
      It 'leaves parameters and options exactly as it found them'
        untouched() {
          inzsh_spec_prompts '
            : ${+functions[_inzsh_title_precmd]}
            snap=${TMPDIR:-/tmp}/inzsh-prompts-purity.$$
            mkdir -p $snap
            {
              typeset -p >| $snap/before
              setopt     >| $snap/before-opts

              source "$1/lib/core/prompts.zsh"
              _inzsh_prompts_install
              _inzsh_title_install
              _inzsh_title_precmd  >/dev/null
              _inzsh_title_preexec "make test" >/dev/null
              _inzsh_title_uninstall
              _inzsh_prompts_uninstall

              typeset -p >| $snap/after
              setopt     >| $snap/after-opts

              local -a before=("${(f)$(<$snap/before)}") after=("${(f)$(<$snap/after)}")
              local line; local -a touched=()
              (( ${#before} > 1 && ${#after} > 1 )) || touched+=snapshot-empty
              for line in $after; do
                (( ${before[(Ie)$line]} )) || touched+=${${line%%=*}##* }
              done
              for line in $before; do
                (( ${after[(Ie)$line]} )) || touched+=${${line%%=*}##* }
              done
              touched=(${(ou)touched})
              # RANDOM and SECONDS move between any two snapshots on their own. REPLY is zshs
              # conventional return channel and every function in this tree writes it. The two
              # hook arrays are add-zsh-hooks to create, not ours to delete — what we owe is
              # that they end up EMPTY, and that is asserted rather than filtered.
              touched=(${touched:#(_inzsh_*|REPLY|RANDOM|SECONDS)})
              touched=(${touched:#(precmd_functions|preexec_functions)})
              (( ${#precmd_functions} ))  && touched+=precmd-left-registered
              (( ${#preexec_functions} )) && touched+=preexec-left-registered
              [[ $(<$snap/before-opts) == $(<$snap/after-opts) ]] || touched+=setopt
              print -r -- "${touched[*]}"
            } always {
              rm -rf $snap
            }
          '
        }
        When call untouched
        The output should eq ''
        The stderr should eq ''
      End
    End
  End
End

Describe 'the terminal title'
  Describe 'the text'
    It 'is the directory at a prompt and the directory and the command while one runs'
      shape() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          cd /
          _inzsh_title_text;             local idle=$REPLY
          _inzsh_title_text "make test"; local busy=$REPLY
          print -r -- "[$idle][$busy]"
        '
      }
      When call shape
      The output should eq '[/][/ make test]'
    End

    # `%d` is `%~`, not `$PWD`: a home directory spelled out in full is noise in a tab.
    It 'collapses the home directory to a tilde'
      collapsed() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          cd "${TMPDIR:-/tmp}"
          HOME=$PWD
          _inzsh_title_text
          print -r -- "$REPLY"
        '
      }
      When call collapsed
      The output should eq '~'
    End

    Describe 'the format'
      # $1 the format, $2 the running command, $3 what it must produce with the cwd at `/`.
      Parameters
        '%d'          ''      '/'
        '%c'          'vim x' 'vim x'
        '%c @ %d'     'vim x' 'vim x @ /'
        '100%% of %d' ''      '100% of /'
        'in %z %d'    ''      'in %z /'
        'trailing %'  ''      'trailing %'
        ''            ''      '/'
        '   '         ''      '/'
        '%c'          ''      '/'
      End

      # A tiny grammar with no room to be wrong in: two placeholders, a literal per cent, and
      # anything else kept as it was written. The last three rows are the fallback — an empty
      # format, a whitespace-only one, and one that produced nothing at all — because a title
      # is not a place to report a configuration error.
      It "reads [$1] with command [$2] as [$3]"
        formatted() {
          inzsh_spec_env INZSH_TITLE_FORMAT "$1" '
            source "$1/lib/core/prompts.zsh"
            cd /
            _inzsh_title_text "$4"
            print -r -- "[$REPLY]"
          ' "$2"
        }
        When call formatted "$1" "$2"
        The output should eq "[$3]"
      End
    End

    # A command line with a newline in it, a filename with an ESC in it, and the OSC string is
    # over — everything after the first BEL would be read by the terminal as a fresh command.
    # Flattening control characters to spaces is what stops a title from being an injection.
    It 'flattens control characters, so nothing in a command can end the title early'
      hostile() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          cd /
          _inzsh_title_text "echo one${3}${2}]0;stolen${3}two"
          local -a wrong=()
          [[ $REPLY == *$2* ]]     && wrong+=escape-survived
          [[ $REPLY == *$3* ]]     && wrong+=bell-survived
          [[ $REPLY == *stolen* ]] || wrong+=text-dropped
          print -r -- "${wrong[*]}"
        '
      }
      When call hostile
      The output should eq ''
    End

    # A `find` invocation three screens long must not become a three-screen title. The marker
    # is part of the budget, not added on top of it.
    It 'truncates a long command to the cap, marker included'
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      truncated() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          cd /
          _inzsh_title_text "${(l:400::x:)}"
          local -a wrong=()
          (( ${#REPLY} == _inzsh_title_max_chars )) || wrong+=length:${#REPLY}
          [[ $REPLY == *$_inzsh_title_ellipsis ]]   || wrong+=no-marker
          _inzsh_title_text "short"
          [[ $REPLY == *$_inzsh_title_ellipsis ]]   && wrong+=marker-when-it-fits
          print -r -- "${wrong[*]}"
        '
      }
      When call truncated
      The output should eq ''
    End
  End

  Describe 'the sequence'
    # Two forms of one thing: REPLY is the prompt-safe form, wrapped so it measures zero
    # columns, and what reaches the terminal is that form's prompt expansion — the markers
    # gone, the bytes kept. A `%{` in a tab title would be the bug this shape prevents.
    It 'wraps the sequence for a prompt and emits its expansion for the terminal'
      wrapped() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          local out="$(_inzsh_title_set "a title"; print -rn -- "|$REPLY")"
          local emitted=${out%%\|*} reply=${out#*\|}
          local -a wrong=()
          [[ $reply == %\{*%\} ]]            || wrong+=not-wrapped
          [[ $emitted == "$2]0;a title$3" ]] || wrong+=emitted
          [[ $emitted == ${(%%)reply} ]]     || wrong+=not-the-expansion
          [[ $emitted != *%* ]]              || wrong+=marker-reached-the-terminal
          print -r -- "${wrong[*]}"
        '
      }
      When call wrapped
      The output should eq ''
    End

    # The wrapped form is a prompt string, so a per cent in it is an instruction to whoever
    # expands it. Doubled going in, single coming out — a directory called `100%` neither eats
    # the character after it nor turns into a `%D{...}`.
    It 'doubles a per cent in the wrapper and delivers a single one to the terminal'
      percent() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          local out="$(_inzsh_title_set "100% D{x}"; print -rn -- "|$REPLY")"
          local emitted=${out%%\|*} reply=${out#*\|}
          local -a wrong=()
          [[ $reply == *"100%% D{x}"* ]]        || wrong+=not-doubled
          [[ $emitted == "$2]0;100% D{x}$3" ]]  || wrong+=emitted
          print -r -- "${wrong[*]}"
        '
      }
      When call percent
      The output should eq ''
    End

    It 'writes nothing at all in a non-interactive shell'
      script() {
        inzsh_spec_script '
          source "$1/lib/core/prompts.zsh"
          _inzsh_title_set "a title"
          print -rn -- "[$REPLY]"
        '
      }
      When call script
      The output should eq '[]'
      The stderr should eq ''
    End

    Describe 'a terminal that mishandles OSC'
      Parameters
        dumb
        linux
        ''
      End

      # `dumb` is what an editor's shell buffer and a plain pipe report; `linux` is the kernel
      # console. Neither swallows an OSC string, so both would show the raw bytes across the
      # line the user is typing. An absent TERM is not a terminal we can address at all.
      It "writes nothing under TERM=$1"
        refused() {
          TERM=$1 zsh -f -i -c '
            source "$1/lib/core/prompts.zsh"
            _inzsh_title_set "a title"
            print -rn -- "[$REPLY]"
          ' inzsh-prompts-term "$SHELLSPEC_PROJECT_ROOT"
        }
        When call refused "$1"
        The output should eq '[]'
        The stderr should eq ''
      End
    End

    Describe 'the switch'
      # $1 the INZSH_TITLE value, $2 whether anything is written.
      Parameters
        1     written
        0     silent
        true  written
        false silent
        'ON'  written
        'Off' silent
        yes   written
        no    silent
        maybe written
        ''    written
      End

      # Default on, and every unreadable value is on too: a typo may not switch a feature off
      # without saying so, and a title that failed to appear is not a thing anybody debugs.
      It "INZSH_TITLE=$1 is $2"
        switched() {
          inzsh_spec_env INZSH_TITLE "$1" '
            source "$1/lib/core/prompts.zsh"
            _inzsh_title_set "a title" >/dev/null
            [[ -n $REPLY ]] && print -r -- written || print -r -- silent
          '
        }
        When call switched "$1"
        The output should eq "$2"
      End
    End
  End

  Describe 'the hooks'
    # The regression the add-zsh-hook rule exists to prevent: a foreign hook is registered on
    # both arrays first, and installing must leave it in place, installing twice must register
    # once, and uninstalling must take ours away and leave theirs.
    It 'registers once on each array and leaves a foreign hook alone'
      registration() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          autoload -Uz add-zsh-hook
          alien() { : }
          add-zsh-hook precmd alien; add-zsh-hook preexec alien
          _inzsh_title_install; _inzsh_title_install
          local during="${precmd_functions[*]}/${preexec_functions[*]}"
          _inzsh_title_uninstall
          print -r -- "$during | ${precmd_functions[*]}/${preexec_functions[*]}"
        '
      }
      When call registration
      The output should eq 'alien _inzsh_title_precmd/alien _inzsh_title_preexec | alien/alien'
    End

    # precmd functions run in a row, each one seeing the status the previous one RETURNED. A
    # hook that swallows the exit status hides the user's failed command from every hook behind
    # it — including a segment somebody else wrote. Ours carries it through.
    It 'carries the exit status through to a hook registered behind it'
      carried() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          typeset -g seen=
          behind() { seen=$? }
          false
          _inzsh_title_precmd >/dev/null
          behind
          print -r -- "seen=$seen"
        '
      }
      When call carried
      The output should eq 'seen=1'
    End

    # End to end, through the two hooks rather than the two builders: preexec paints the
    # command, precmd paints it back out again.
    It 'paints the command while it runs and the directory once it is done'
      lifecycle() {
        inzsh_spec_prompts '
          source "$1/lib/core/prompts.zsh"
          cd /
          local out="$(_inzsh_title_preexec "make test"; _inzsh_title_precmd)"
          [[ $out == "$2]0;/ make test$3$2]0;/$3" ]] && print -r -- paired || print -r -- "$out"
        '
      }
      When call lifecycle
      The output should eq 'paired'
    End
  End
End
