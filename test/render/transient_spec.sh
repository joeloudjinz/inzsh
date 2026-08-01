# The transient prompt — `lib/core/transient.zsh`. What the prompt becomes once the command it
# introduced has been handed over, and what installing it does to a shell that already had a
# `zle-line-finish` of its own.
#
# Nothing here is `Include`d. Every example runs in a fresh `zsh -f -i -c`, because what is under
# test is what INSTALLING does: the widget table, the hook array, and two prompt parameters. A
# spec that installed a line-finish widget into its own runner would be testing a shell that
# already had one, and would be sourcing work in progress into a live shell besides.
#
# WHAT THIS FILE CANNOT SEE. `zle-line-finish` only fires inside a real line editor, and a line
# editor needs a terminal. So the wiring is asserted here — who is bound, in what order, and
# what the collapse does to the parameters — and the FIRING is asserted on a pty in
# `test/ui/test_transient.py`. Neither half is sufficient and both are cheap.

# Run `$1` with the render core and the transient layer loaded. Arguments after the body reach
# it as `$1`, `$2`… so a swept example passes a value rather than pasting one into a script.
inzsh_spec_transient() {
  local body=$1
  shift
  zsh -f -i -c '
    local root=$1 body=$2
    shift 2
    unset -m "INZSH_*"

    local file
    for file in config detect tokens-256 tokens layout engine render transient; do
      source $root/lib/core/$file.zsh
    done

    # The visible text of a prompt fragment, in REPLY: the colour escapes taken back off and
    # nothing else touched.
    inzsh_transient_text_of() {
      setopt local_options extended_glob
      local out=${1//\%[FK]\{[^\}]#\}/}
      typeset -g REPLY=${out//\%[fk]/}
    }

    eval "$body"
  ' inzsh-transient "$SHELLSPEC_PROJECT_ROOT" "$body" "$@"
}

Describe 'the transient prompt'
  # -------------------------------------------------------------------------------------------
  Describe 'installing'
    # THE RULE THIS FILE EXISTS FOR. `zle-line-finish` is not ours. Other plugins bind it, and a
    # theme that overwrites the binding breaks whichever of them loaded first — silently, and in
    # a way its author will never see. Install saves what it found; the widget calls it.
    It 'wraps a foreign zle-line-finish rather than replacing it'
      wraps() {
        inzsh_spec_transient '
          alien() { : }
          zle -N zle-line-finish alien
          _inzsh_transient_install
          print -r -- "bound=${widgets[zle-line-finish]} saved=$_inzsh_transient_prev"
        '
      }
      When call wraps
      The output should eq 'bound=user:_inzsh_transient_line_finish saved=user:alien'
      The stderr should eq ''
    End

    It 'gives the foreign widget back on uninstall'
      restores() {
        inzsh_spec_transient '
          alien() { : }
          zle -N zle-line-finish alien
          _inzsh_transient_install
          _inzsh_transient_uninstall
          print -r -- "bound=${widgets[zle-line-finish]} saved=<$_inzsh_transient_prev>"
        '
      }
      When call restores
      The output should eq 'bound=user:alien saved=<>'
      The stderr should eq ''
    End

    # Where there was no widget, uninstall must leave no widget — restoring "nothing" as an
    # empty binding would be a quieter kind of damage, and the next plugin to look would find a
    # `zle-line-finish` that does nothing rather than none at all.
    It 'leaves no widget behind where it found none'
      pristine() {
        inzsh_spec_transient '
          _inzsh_transient_install
          _inzsh_transient_uninstall
          print -r -- "bound=${widgets[zle-line-finish]-none}"
        '
      }
      When call pristine
      The output should eq 'bound=none'
      The stderr should eq ''
    End

    # Idempotent the honest way: a second install finds our own widget bound and returns before
    # saving anything, so it cannot record us as our own predecessor — which is the recursion
    # that would otherwise arrive the first time somebody sourced the theme twice.
    It 'installs once however many times it is asked'
      twice() {
        inzsh_spec_transient '
          alien() { : }
          zle -N zle-line-finish alien
          _inzsh_transient_install; _inzsh_transient_install; _inzsh_transient_install
          _inzsh_transient_uninstall
          print -r -- "bound=${widgets[zle-line-finish]} hooks=${#precmd_functions}"
        '
      }
      When call twice
      The output should eq 'bound=user:alien hooks=0'
      The stderr should eq ''
    End

    # A plugin that bound `zle-line-finish` AFTER us owns it now. Restoring over the top would
    # do to them precisely what this file exists not to do, so uninstall touches the binding
    # only while it is still ours.
    It 'leaves a binding alone once somebody else has taken it'
      overtaken() {
        inzsh_spec_transient '
          _inzsh_transient_install
          latecomer() { : }
          zle -N zle-line-finish latecomer
          _inzsh_transient_uninstall
          print -r -- "bound=${widgets[zle-line-finish]}"
        '
      }
      When call overtaken
      The output should eq 'bound=user:latecomer'
      The stderr should eq ''
    End

    # The precmd side of the install, registered through `add-zsh-hook` like everything else in
    # this tree — never by assigning `precmd_functions`, which would discard every registration
    # already in the user's shell.
    It 'registers its precmd through add-zsh-hook and leaves foreign hooks in place'
      hooked() {
        inzsh_spec_transient '
          autoload -Uz add-zsh-hook
          other() { : }
          add-zsh-hook precmd other
          _inzsh_transient_install
          local during=${precmd_functions[*]}
          _inzsh_transient_uninstall
          print -r -- "during=\"$during\" after=\"${precmd_functions[*]}\""
        '
      }
      When call hooked
      The output should eq 'during="other _inzsh_transient_precmd" after="other"'
      The stderr should eq ''
    End

    It 'uninstalls cleanly when there is nothing to uninstall'
      idle() {
        inzsh_spec_transient '
          _inzsh_transient_uninstall; _inzsh_transient_uninstall
          print -r -- "status=$? bound=${widgets[zle-line-finish]-none}"
        '
      }
      When call idle
      The output should eq 'status=0 bound=none'
      The stderr should eq ''
    End

    # The second lock, after the entry point's own. A shell with no prompt has nothing to
    # collapse, and a widget registered there is a widget that will never fire.
    It 'registers nothing in a non-interactive shell'
      inert() {
        zsh -f -c '
          local before=$PROMPT
          source "$1/lib/core/transient.zsh"
          _inzsh_transient_install
          local -a leaked=()
          [[ $PROMPT == $before ]]   || leaked+=PROMPT
          (( ${+precmd_functions} )) && leaked+=precmd:${precmd_functions[*]}
          [[ -z ${widgets[zle-line-finish]-} ]] || leaked+=widget
          print -r -- "${leaked[*]}"
        ' inzsh-transient-inert "$SHELLSPEC_PROJECT_ROOT"
      }
      When call inert
      The output should eq ''
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  Describe 'the widget'
    # THE ORDER IS THE CONTRACT. The foreign widget runs first, and it sees the prompt the user
    # was actually looking at — a highlighter or a history plugin that reads `PROMPT` must not
    # be handed our collapsed stand-in. Collapsing afterwards makes us the last word on the
    # prompt without taking anything away from whoever was there before.
    #
    # `zle` is stubbed AFTER the install, so the real builtin does the binding and the stub only
    # records the redraw. There is no line editor in a `zsh -c`, and `zle .reset-prompt` is the
    # one thing in this file that genuinely needs one.
    It 'runs the foreign widget first, and on the prompt the user was looking at'
      order() {
        inzsh_spec_transient '
          typeset -g trace= seen=
          alien() { trace+=alien; seen=$PROMPT }
          zle -N zle-line-finish alien
          _inzsh_transient_install
          typeset -g PROMPT=FULL RPROMPT=RIGHT
          zle() { trace+=" zle:$*" }
          _inzsh_transient_line_finish
          inzsh_transient_text_of "$PROMPT"
          local collapsed=collapsed
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] || collapsed="now=<$REPLY>"
          print -r -- "trace=<$trace> seen=<$seen> $collapsed right=<$RPROMPT>"
        '
      }
      When call order
      The output should eq 'trace=<alien zle:.reset-prompt> seen=<FULL> collapsed right=<>'
      The stderr should eq ''
    End

    # Switching the feature off may not take the foreign widget down with it. The knob is read
    # after the dispatch for exactly this reason.
    It 'still runs the foreign widget when the feature is switched off'
      disabled() {
        inzsh_spec_transient '
          typeset -g trace=
          alien() { trace+=alien }
          zle -N zle-line-finish alien
          _inzsh_transient_install
          typeset -g PROMPT=FULL
          zle() { trace+=" zle:$*" }
          INZSH_TRANSIENT=0
          _inzsh_transient_line_finish
          print -r -- "trace=<$trace> prompt=<$PROMPT>"
        '
      }
      When call disabled
      The output should eq 'trace=<alien> prompt=<FULL>'
      The stderr should eq ''
    End

    # A widget that has been removed since we saved it is not an error — a plugin may have
    # uninstalled itself between our install and this keystroke — and a saved name that is our
    # own is the one case that must never be called.
    It 'calls a predecessor that no longer exists, and itself, without complaint'
      hostile() {
        inzsh_spec_transient '
          typeset -g _inzsh_transient_prev=user:vanished
          _inzsh_transient_dispatch
          print -r -- "gone=$?"
          typeset -g _inzsh_transient_prev=user:_inzsh_transient_line_finish
          _inzsh_transient_dispatch
          print -r -- "self=$?"
          typeset -g _inzsh_transient_prev=
          _inzsh_transient_dispatch
          print -r -- "none=$?"
        '
      }
      When call hostile
      The output should eq 'gone=0
self=0
none=0'
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  Describe 'the collapsed form'
    # Tiny on purpose: the whole feature is a transcript you can skim, and anything larger is a
    # smaller version of the problem it was added to solve.
    It 'is the marker and nothing else by default'
      minimal() {
        inzsh_spec_transient '
          _inzsh_transient_text
          inzsh_transient_text_of "$REPLY"
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] && print -r -- marker-only ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call minimal
      The output should eq 'marker-only'
      The stderr should eq ''
    End

    # The same mark and the same status colouring as the second line of the two-line shape, so a
    # collapsed prompt reads as the prompt it came from rather than as something that appeared.
    It 'is the very marker the live prompt was drawn with'
      shared() {
        inzsh_spec_transient '
          typeset -g _inzsh_last_status=1
          _inzsh_render_marker
          local live=$REPLY
          _inzsh_transient_text
          [[ $REPLY == "$live " ]] && print -r -- same || print -r -- "got=<$REPLY> live=<$live>"
        '
      }
      When call shared
      The output should eq 'same'
      The stderr should eq ''
    End

    It 'puts the directory in front of the marker when asked for it'
      with_dir() {
        inzsh_spec_transient '
          INZSH_TRANSIENT_FORMAT=dir
          _inzsh_transient_text
          inzsh_transient_text_of "$REPLY"
          [[ $REPLY == "%~ ${_inzsh_glyph[prompt]} " ]] && print -r -- dir-then-marker ||
            print -r -- "got=<$REPLY>"
        '
      }
      When call with_dir
      The output should eq 'dir-then-marker'
      The stderr should eq ''
    End

    # A collapsed prompt with no marker in it is a transcript with no punctuation between a
    # command and its output, which is the state this feature replaced.
    It 'degrades to one ASCII column with no render core in the shell'
      alone() {
        zsh -f -i -c '
          source "$1/lib/core/transient.zsh"
          _inzsh_transient_text
          print -r -- "<$REPLY>"
        ' inzsh-transient-alone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call alone
      The output should eq '<> >'
      The stderr should eq ''
    End
  End

  Describe 'an INZSH_TRANSIENT_FORMAT the theme cannot read'
    Parameters
      'DIR'
      'directory'
      'full'
      'marker dir'
      ''
    End

    It "falls back to the marker for '$1'"
      unreadable() {
        inzsh_spec_transient '
          INZSH_TRANSIENT_FORMAT=$1
          _inzsh_transient_text
          inzsh_transient_text_of "$REPLY"
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] && print -r -- marker-only ||
            print -r -- "got=<$REPLY>"
        ' "$1"
      }
      When call unreadable "$1"
      The output should eq 'marker-only'
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  Describe 'collapsing and coming back'
    # It must collapse whichever shape is active. A two-row prompt that collapses to two rows
    # defeats the point, and the two-row shape is the default one.
    It 'collapses a two-row prompt to a single row'
      shapes() {
        inzsh_spec_transient '
          typeset -gA _inzsh_segment_defaults _inzsh_segment_text
          _inzsh_segment_defaults=(ALFA 1 CHARLIE -1)
          _inzsh_segment_text=(ALFA alfa CHARLIE charlie)
          typeset -g COLUMNS=80
          _inzsh_render
          local -a before=("${(f)PROMPT}")
          _inzsh_transient_collapse
          local -a after=("${(f)PROMPT}")
          print -r -- "${#before} then ${#after}"
        '
      }
      When call shapes
      The output should eq '2 then 1'
      The stderr should eq ''
    End

    It 'collapses a one-row prompt too'
      one_row() {
        inzsh_spec_transient '
          typeset -gA _inzsh_segment_defaults _inzsh_segment_text
          _inzsh_segment_defaults=(ALFA 1 CHARLIE -1)
          _inzsh_segment_text=(ALFA alfa CHARLIE charlie)
          typeset -g COLUMNS=80 INZSH_PROMPT_LINES=1
          _inzsh_render
          _inzsh_transient_collapse
          inzsh_transient_text_of "$PROMPT"
          local -a wrong=()
          [[ $REPLY == "${_inzsh_glyph[prompt]} " ]] || wrong+=prompt:$REPLY
          [[ -z $RPROMPT ]]                          || wrong+=rprompt:$RPROMPT
          print -r -- "${wrong[*]}"
        '
      }
      When call one_row
      The output should eq ''
      The stderr should eq ''
    End

    # The right prompt is live status — a clock, a countdown to the next prayer — and a live
    # value is a lie the moment it stops being redrawn. A wrong time in the transcript is worse
    # than no time in it.
    It 'clears the right prompt rather than collapsing it'
      cleared() {
        inzsh_spec_transient '
          typeset -g PROMPT=FULL RPROMPT=12:34
          _inzsh_transient_collapse
          print -r -- "<$RPROMPT>"
        '
      }
      When call cleared
      The output should eq '<>'
      The stderr should eq ''
    End

    It 'puts both parameters back on the next precmd'
      restored() {
        inzsh_spec_transient '
          typeset -g PROMPT=FULL RPROMPT=RIGHT
          _inzsh_transient_collapse
          _inzsh_transient_precmd
          print -r -- "$PROMPT|$RPROMPT"
        '
      }
      When call restored
      The output should eq 'FULL|RIGHT'
      The stderr should eq ''
    End

    # An associative array cannot hold the difference between `RPROMPT=` and no `RPROMPT` at
    # all, and that difference is the whole promise: restoring an unset variable as an empty one
    # is not a restoration, it is a quieter kind of damage.
    It 'puts back an unset parameter as unset'
      unset_case() {
        inzsh_spec_transient '
          unset PROMPT RPROMPT
          _inzsh_transient_collapse
          _inzsh_transient_precmd
          print -r -- "prompt=${+PROMPT} rprompt=${+RPROMPT}"
        '
      }
      When call unset_case
      The output should eq 'prompt=0 rprompt=0'
      The stderr should eq ''
    End

    # In a fully loaded theme `_inzsh_render` assigns both parameters before this hook runs, so
    # the restore must stand aside. One comparison covers both cases and neither can clobber the
    # other.
    It 'stands aside when something has already drawn a fresh prompt'
      fresh() {
        inzsh_spec_transient '
          typeset -g PROMPT=FULL RPROMPT=RIGHT
          _inzsh_transient_collapse
          typeset -g PROMPT=REDRAWN RPROMPT=NEW
          _inzsh_transient_precmd
          print -r -- "$PROMPT|$RPROMPT"
        '
      }
      When call fresh
      The output should eq 'REDRAWN|NEW'
      The stderr should eq ''
    End

    # A second collapse before a restore must not overwrite the user's originals with the
    # theme's own.
    It 'saves the originals once, however often it collapses'
      resaved() {
        inzsh_spec_transient '
          typeset -g PROMPT=FULL RPROMPT=RIGHT
          _inzsh_transient_collapse
          _inzsh_transient_collapse
          _inzsh_transient_precmd
          print -r -- "$PROMPT|$RPROMPT"
        '
      }
      When call resaved
      The output should eq 'FULL|RIGHT'
      The stderr should eq ''
    End

    # precmd functions run in a row, each seeing the status the previous one returned, so a hook
    # that swallows the exit status hides the user's failed command from every hook behind it.
    It 'carries the exit status through to the next precmd function'
      carried() {
        inzsh_spec_transient '
          false
          _inzsh_transient_precmd
          print -r -- "carried=$?"
          typeset -g PROMPT=FULL
          _inzsh_transient_collapse
          false
          _inzsh_transient_precmd
          print -r -- "restoring=$?"
        '
      }
      When call carried
      The output should eq 'carried=1
restoring=1'
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  Describe 'INZSH_TRANSIENT'
    # On by default. The feature exists because the alternative is a scrollback nobody can skim,
    # and a default of off would ship the cost of the prompt to everyone and the benefit to
    # whoever read the reference.
    It 'is on when nothing is set'
      default_on() {
        inzsh_spec_transient '
          _inzsh_transient_enabled && print -r -- on || print -r -- off
        '
      }
      When call default_on
      The output should eq 'on'
      The stderr should eq ''
    End

    Parameters
      '0'      off
      'false'  off
      'FALSE'  off
      'no'     off
      'Off'    off
      '1'      on
      'true'   on
      'yes'    on
      'ON'     on
      'maybe'  on
      ''       on
      '2'      on
    End

    It "reads '$1' as $2"
      vocabulary() {
        inzsh_spec_transient '
          INZSH_TRANSIENT=$1
          _inzsh_transient_enabled && print -r -- on || print -r -- off
        ' "$1"
      }
      When call vocabulary "$1"
      The output should eq "$2"
      The stderr should eq ''
    End
  End

  # -------------------------------------------------------------------------------------------
  Describe 'the registry'
    # Both knobs are declared beside the code that reads them, which is what gives them a
    # default to fall back to and a vocabulary to be listed by.
    It 'declares both of its knobs with the shipped defaults'
      declared() {
        inzsh_spec_transient '
          local -a wrong=()
          [[ ${_inzsh_config_validators[INZSH_TRANSIENT]} == bool ]] || wrong+=transient-spec
          [[ ${_inzsh_config_defaults[INZSH_TRANSIENT]} == 1 ]]      || wrong+=transient-default
          [[ ${_inzsh_config_validators[INZSH_TRANSIENT_FORMAT]} == enum:* ]] ||
            wrong+=format-spec
          [[ ${_inzsh_config_defaults[INZSH_TRANSIENT_FORMAT]} ==
             $_inzsh_transient_format_default ]] || wrong+=format-default
          print -r -- "${wrong[*]}"
        '
      }
      When call declared
      The output should eq ''
      The stderr should eq ''
    End
  End
End
