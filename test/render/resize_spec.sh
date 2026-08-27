# The resize redraw — `lib/core/resize.zsh`. What taking the WINCH slot does to a shell that
# already had a handler in it, and what the handler does when it fires.
#
# Nothing here is `Include`d. Every example runs in a fresh `zsh -f -i -c`, because what is under
# test is what INSTALLING does: the one trap slot zsh has. A spec that installed a TRAPWINCH into
# its own runner would be testing a shell that already had one, and would be sourcing work in
# progress into a live shell besides.
#
# WHAT THIS FILE CANNOT SEE. A real SIGWINCH needs a real terminal that really changes size, and
# `zle .reset-prompt` needs a line editor to reset. So the wiring is asserted here — who is in
# the slot, what the handler decides, and what it hands to `zle` — and the FIRING is asserted on
# a pty in `test/ui/test_resize.py`. Neither half is sufficient and both are cheap.

# Run `$1` with the render core and the resize layer loaded.
inzsh_spec_resize() {
  local body=$1
  shift
  zsh -f -i -c '
    local root=$1 body=$2
    shift 2
    unset -m "INZSH_*"

    local file
    for file in config detect tokens-256 tokens layout engine rows render resize; do
      source $root/lib/core/$file.zsh
    done

    # A two-segment fixture, so a render has something to draw and a width to draw it at.
    typeset -gA _inzsh_segment_defaults _inzsh_segment_text
    _inzsh_segment_defaults=(LEFTA 1 RIGHTB -1)
    _inzsh_segment_text=(LEFTA left RIGHTB right)

    eval "$body"
  ' inzsh-resize "$SHELLSPEC_PROJECT_ROOT" "$body" "$@"
}

Describe 'the resize redraw'
  # ---------------------------------------------------------------------------------------------
  Describe 'installing'
    # THE RULE THIS FILE EXISTS FOR. zsh has ONE WINCH handler. A user or another plugin may
    # already be in it, and a theme that overwrites the slot breaks them silently — the same rule
    # `lib/core/transient.zsh` keeps for `zle-line-finish`, arrived at from the other side.
    It 'wraps a foreign TRAPWINCH rather than replacing it'
      wraps() {
        inzsh_spec_resize '
          TRAPWINCH() { alien=1 }
          local before=${functions[TRAPWINCH]}
          _inzsh_resize_install
          local -a wrong=()
          [[ ${functions[TRAPWINCH]} == ${functions[_inzsh_resize_trap]} ]] || wrong+=slot
          [[ ${functions[_inzsh_resize_prev_winch]} == $before ]]           || wrong+=saved
          (( _inzsh_resize_prev_set == 1 ))                                 || wrong+=flag
          print -r -- "${wrong[*]}"
        '
      }
      When call wraps
      The output should eq ''
      The stderr should eq ''
    End

    # THE REGRESSION THIS FILE LEARNED. `emulate -L zsh` sets LOCAL_TRAPS as well as
    # LOCAL_OPTIONS, and under LOCAL_TRAPS a trap set inside a function is unset again the moment
    # that function returns — including a `TRAPWINCH` defined by assigning to `$functions`, which
    # zsh treats as setting a trap like any other. The install then reports success and there is
    # no trap in the shell. Nothing else in this file would have caught it: every other example
    # would pass for an install that worked only until it returned.
    It 'leaves the trap in the shell after the installer has returned'
      persists() {
        inzsh_spec_resize '
          _inzsh_resize_install
          print -r -- "installed=${+functions[TRAPWINCH]}"
        '
      }
      When call persists
      The output should eq 'installed=1'
      The stderr should eq ''
    End

    It 'gives the foreign handler back on uninstall, body for body'
      restores() {
        inzsh_spec_resize '
          TRAPWINCH() { alien=1 }
          local before=${functions[TRAPWINCH]}
          _inzsh_resize_install
          _inzsh_resize_uninstall
          local -a wrong=()
          [[ ${functions[TRAPWINCH]} == $before ]]                  || wrong+=slot
          (( ${+functions[_inzsh_resize_prev_winch]} ))              && wrong+=leftover
          [[ -z $_inzsh_resize_prev ]]                               || wrong+=saved
          (( _inzsh_resize_prev_set == 0 ))                          || wrong+=flag
          print -r -- "${wrong[*]}"
        '
      }
      When call restores
      The output should eq ''
      The stderr should eq ''
    End

    # Where there was no handler, uninstall must leave none. Restoring "nothing" as an empty
    # `TRAPWINCH` would be a quieter kind of damage: the next thing to look would find a handler
    # that does nothing rather than no handler at all.
    It 'leaves no trap behind where it found none'
      pristine() {
        inzsh_spec_resize '
          _inzsh_resize_install
          _inzsh_resize_uninstall
          print -r -- "trap=${+functions[TRAPWINCH]}"
        '
      }
      When call pristine
      The output should eq 'trap=0'
      The stderr should eq ''
    End

    # Idempotent the honest way: a second install finds our own body in the slot and returns
    # before saving anything, so it cannot record us as our own predecessor — which is the
    # recursion that would otherwise arrive the first time somebody sourced the theme twice.
    It 'installs once however many times it is asked'
      twice() {
        inzsh_spec_resize '
          TRAPWINCH() { alien=1 }
          local before=${functions[TRAPWINCH]}
          _inzsh_resize_install; _inzsh_resize_install; _inzsh_resize_install
          _inzsh_resize_uninstall
          print -r -- "back=$([[ ${functions[TRAPWINCH]} == $before ]] && print yes || print no)"
        '
      }
      When call twice
      The output should eq 'back=yes'
      The stderr should eq ''
    End

    # Something that took the slot AFTER us owns it now. Restoring over the top would do to them
    # precisely what this file exists not to do.
    It 'leaves the slot alone once somebody else has taken it'
      overtaken() {
        inzsh_spec_resize '
          _inzsh_resize_install
          TRAPWINCH() { latecomer=1 }
          local taken=${functions[TRAPWINCH]}
          _inzsh_resize_uninstall
          print -r -- "kept=$([[ ${functions[TRAPWINCH]} == $taken ]] && print yes || print no)"
        '
      }
      When call overtaken
      The output should eq 'kept=yes'
      The stderr should eq ''
    End

    It 'uninstalls cleanly when there is nothing to uninstall'
      idle() {
        inzsh_spec_resize '
          _inzsh_resize_uninstall; _inzsh_resize_uninstall
          print -r -- "status=$? trap=${+functions[TRAPWINCH]}"
        '
      }
      When call idle
      The output should eq 'status=0 trap=0'
      The stderr should eq ''
    End

    # The second lock, after the entry point's own. A shell with no prompt has nothing to redraw,
    # and a trap installed there fires in every script that sources a lib file directly.
    It 'installs nothing in a non-interactive shell'
      inert() {
        zsh -f -c '
          local before=$PROMPT
          source "$1/lib/core/resize.zsh"
          _inzsh_resize_install
          local -a leaked=()
          [[ $PROMPT == $before ]]           || leaked+=PROMPT
          (( ${+functions[TRAPWINCH]} ))     && leaked+=trap
          print -r -- "${leaked[*]}"
        ' inzsh-resize-inert "$SHELLSPEC_PROJECT_ROOT"
      }
      When call inert
      The output should eq ''
      The stderr should eq ''
    End

    # Sourcing installs nothing at all. The entry point decides when the theme goes live, and a
    # spec has to be able to load the file without a trap landing in the shell running it.
    It 'registers nothing at source time'
      quiet() {
        inzsh_spec_resize '
          local saved=${+functions[_inzsh_resize_prev_winch]}
          print -r -- "trap=${+functions[TRAPWINCH]} saved=$saved"
        '
      }
      When call quiet
      The output should eq 'trap=0 saved=0'
      The stderr should eq ''
    End
  End

  # ---------------------------------------------------------------------------------------------
  Describe 'the handler'
    # `zle` is stubbed AFTER the install, so the real builtin does nothing here and the stub
    # records what it was asked for. There is no line editor in a `zsh -c`, and `zle
    # .reset-prompt` is the one thing in this file that genuinely needs one. A stub that answers
    # 0 to the bare `zle` is standing in for "the line editor is on screen".

    # THE ORDER IS THE CONTRACT, and it is the same one the transient prompt keeps: a foreign
    # handler that redraws for its own reasons must see the terminal as the user left it, and
    # going last makes us the last word on the prompt without taking anything from whoever was
    # there before.
    It 'runs the foreign handler first, and before anything is redrawn'
      order() {
        inzsh_spec_resize '
          typeset -g trace=
          TRAPWINCH() { trace+=alien }
          _inzsh_resize_install
          zle() { trace+=" zle:$*"; return 0 }
          typeset -g COLUMNS=80
          _inzsh_render
          typeset -g COLUMNS=40
          _inzsh_resize_winch WINCH
          print -r -- "$trace"
        ' | tr -d '\033\r' | sed 's/\[[0-9]*[AJ]//g'
      }
      When call order
      The output should eq 'alien zle: zle:.reset-prompt'
      The stderr should eq ''
    End

    # THE ERASE, which is the fix for the staircase. `zle .reset-prompt` alone repaints from an
    # origin computed before the window moved, so it lands below the prompt already on screen
    # and leaves it there — one stale copy per signal. The handler therefore climbs to the
    # first row of the prompt and erases to the end of the screen before repainting.
    #
    # Asserted as the BYTES that go to the terminal, because that is what a terminal obeys:
    # `\e[<n>A` to climb when there is a row above, `\r` to the start, `\e[J` to erase.
    It 'erases the prompt on screen before it repaints'
      erases() {
        inzsh_spec_resize '
          _inzsh_resize_install
          zle() { return 0 }
          typeset -g COLUMNS=80
          _inzsh_render
          typeset -g COLUMNS=40
          _inzsh_resize_winch WINCH
        ' | cat -v
      }
      When call erases
      The output should eq '^[[1A^M^[[J'
      The stderr should eq ''
    End

    # The redraw itself: a narrower terminal must produce a narrower row, and the width the
    # prompt was built for has to follow it. Both are read off the parameters rather than off a
    # screen, which is what `test/ui/test_resize.py` is for.
    It 'rebuilds the prompt for the new width'
      rebuilds() {
        inzsh_spec_resize '
          _inzsh_resize_install
          zle() { return 0 }
          typeset -g COLUMNS=80
          _inzsh_render
          local wide=${(%%)PROMPT}
          typeset -g COLUMNS=40
          _inzsh_resize_winch WINCH
          local narrow=${(%%)PROMPT}
          print -r -- "cols=$_inzsh_render_cols shrank=$(( ${#narrow} < ${#wide} ))"
        ' | tr -d '\033\r' | sed 's/\[[0-9]*[AJ]//g'
      }
      When call rebuilds
      The output should eq 'cols=40 shrank=1'
      The stderr should eq ''
    End

    # The coalescing. A window dragged by its bottom edge signals every frame and moves nothing
    # the prompt draws, so the handler asks one question before it does any work.
    It 'redraws nothing when the width has not changed'
      unchanged() {
        inzsh_spec_resize '
          _inzsh_resize_install
          typeset -g trace=
          zle() { trace+=" zle:$*"; return 0 }
          typeset -g COLUMNS=80
          _inzsh_render
          local drawn=$PROMPT
          _inzsh_resize_winch WINCH
          print -r -- "same=$([[ $PROMPT == $drawn ]] && print yes || print no) trace=<$trace>"
        '
      }
      When call unchanged
      The output should eq 'same=yes trace=<>'
      The stderr should eq ''
    End

    # The knob, read per signal rather than at install, so switching it off takes effect at the
    # next resize with no re-source. And switching it off may not take the foreign handler down
    # with it — that is somebody else's registration, not part of our feature.
    It 'redraws nothing when INZSH_RESIZE is off, and still runs the foreign handler'
      disabled() {
        inzsh_spec_resize '
          typeset -g trace=
          TRAPWINCH() { trace+=alien }
          _inzsh_resize_install
          zle() { trace+=" zle:$*"; return 0 }
          typeset -g COLUMNS=80
          _inzsh_render
          typeset -g INZSH_RESIZE=0 COLUMNS=40
          _inzsh_resize_winch WINCH
          print -r -- "cols=$_inzsh_render_cols trace=<$trace>"
        '
      }
      When call disabled
      The output should eq 'cols=80 trace=<alien>'
      The stderr should eq ''
    End

    # No line editor, no reset. A resize that arrives during a long-running command has no prompt
    # on screen to fix and no widget context to fix it from — the prompt is still rebuilt, so the
    # next draw is right, and nothing is handed to a `zle` that would refuse it.
    It 'rebuilds but does not reset when the line editor is not on screen'
      offscreen() {
        inzsh_spec_resize '
          _inzsh_resize_install
          typeset -g trace=
          zle() { trace+=" zle:$*"; return 1 }
          typeset -g COLUMNS=80
          _inzsh_render
          typeset -g COLUMNS=40
          _inzsh_resize_winch WINCH
          print -r -- "cols=$_inzsh_render_cols trace=<$trace>"
        '
      }
      When call offscreen
      The output should eq 'cols=40 trace=< zle:>'
      The stderr should eq ''
    End

    # A predecessor that has since been removed is not an error — a plugin may have uninstalled
    # itself between our install and this signal — and the redraw still happens.
    It 'survives a predecessor that has since gone away'
      vanished() {
        inzsh_spec_resize '
          TRAPWINCH() { : }
          _inzsh_resize_install
          unfunction _inzsh_resize_prev_winch
          zle() { return 0 }
          typeset -g COLUMNS=80
          _inzsh_render
          typeset -g COLUMNS=40
          _inzsh_resize_winch WINCH
          print -r -- "status=$? cols=$_inzsh_render_cols"
        ' | tr -d '\033\r' | sed 's/\[[0-9]*[AJ]//g'
      }
      When call vanished
      The output should eq 'status=0 cols=40'
      The stderr should eq ''
    End
  End

  # ---------------------------------------------------------------------------------------------
  Describe 'the knob'
    It 'registers INZSH_RESIZE with the shipped default'
      registered() {
        inzsh_spec_resize '
          _inzsh_config_get INZSH_RESIZE
          print -r -- "spec=${_inzsh_config_validators[INZSH_RESIZE]} default=$REPLY"
        '
      }
      When call registered
      The output should eq 'spec=bool default=1'
      The stderr should eq ''
    End

    # The house boolean vocabulary, in any case, and an unreadable value means on — a typo may
    # not disable a feature silently.
    It 'reads the whole boolean vocabulary and falls back to on'
      vocabulary() {
        inzsh_spec_resize '
          local value
          local -a out=()
          for value in 0 false NO Off 1 true yes ON chartreuse ""; do
            typeset -g INZSH_RESIZE=$value
            _inzsh_resize_enabled && out+=on || out+=off
          done
          print -r -- "${out[*]}"
        '
      }
      When call vocabulary
      The output should eq 'off off off off on on on on on on'
      The stderr should eq ''
    End
  End
End
