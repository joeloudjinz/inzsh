Include lib/core/config.zsh
Include lib/core/render.zsh
Include tools/perf.zsh

# The configuration layer. Two claims are under test here and everything else serves them:
#
#   nothing a user can type stops the prompt drawing — every knob validates, and every value
#   that fails validation falls back to a registered default rather than reaching the renderer
#
#   the precedence rule is one rule — per-segment override → role → default — and it holds for
#   any knob, not just for colour, including the subtlety that an empty override is no override
#
# `render.zsh` and `tools/perf.zsh` are included because two of the guards delegate to them;
# the examples that pin what happens when they are ABSENT run in a fresh `zsh -f` instead, where
# they genuinely have not been loaded. No hex appears here — this layer never sees a colour.

# Verdict helpers. Predicates are asserted through their printed verdict rather than through a
# status, so a failure names the case that broke instead of printing `1`.
inzsh_spec_check() {
  local verdict=invalid
  _inzsh_config_check "$1" "$2" && verdict=valid
  print -r -- $verdict
}

inzsh_spec_guard() {
  local verdict=fails
  _inzsh_config_guard "$@" && verdict=passes
  print -r -- $verdict
}

# Every way a mode can be written wrong, plus the three that are right. The sweeps below run
# each one through the whole config path; a value added here and not handled shows up as a
# fallback that did not happen.
inzsh_spec_modes=(alternate ramp flat Alternate RAMP 'ramp ' ' flat' alternat chartreuse 0 -)

# Slow enough to blow any sane budget, with no subprocess and no `sleep`: about twenty
# thousand turns of an empty arithmetic loop.
inzsh_spec_slow() {
  local -i i
  for (( i = 0; i < 20000; i++ )); do :; done
}

Describe 'the knob registry'
  Describe 'the validator grammar'
    # Five forms and nothing else. $1 the spec, $2 the value, $3 the verdict.
    #
    # A value is a string and never a pattern: `INZSH_SURFACE_MODE='*'` matches no mode, it is
    # simply not one. The glob-shaped cases below are what keeps the enum comparison exact.
    Parameters
      any        x            valid
      any        'a b'        valid
      any        0            valid
      any        ''           invalid
      bool       true         valid
      bool       false        valid
      bool       TRUE         valid
      bool       Off          valid
      bool       yes          valid
      bool       1            valid
      bool       0            valid
      bool       maybe        invalid
      bool       ''           invalid
      int        0            valid
      int        7            valid
      int        -7           valid
      int        +7           valid
      int        007          valid
      int        2.5          invalid
      int        x            invalid
      int        '1 2'        invalid
      int        ''           invalid
      int:1:3    1            valid
      int:1:3    2            valid
      int:1:3    3            valid
      int:1:3    0            invalid
      int:1:3    4            invalid
      int:1:3    -1           invalid
      int:1:3    two          invalid
      int:1:     999999       valid
      int:1:     0            invalid
      int::10    -50          valid
      int::10    10           valid
      int::10    11           invalid
      int::      -3           valid
      'enum:a|b|c' a          valid
      'enum:a|b|c' c          valid
      'enum:a|b|c' B          invalid
      'enum:a|b|c' ab         invalid
      'enum:a|b|c' 'a b'      invalid
      'enum:a|b|c' ''         invalid
      'enum:a|b|c' '*'        invalid
      'enum:a|b|c' '?'        invalid
      'enum:a|b|c' 'a|b'      invalid
      enum:solo  solo         valid
      enum:solo  'sol?'       invalid
      enum:solo  'solo*'      invalid
      bogus      anything     invalid
      ''         anything     invalid
    End

    It "reads '$2' as $3 under the $1 spec"
      When call inzsh_spec_check "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe 'what may be registered'
    # $1 the knob, $2 the spec, $3 the default, $4 whether the registry takes it. The three
    # refusals are all theme bugs rather than user ones, which is why they fail loudly here
    # instead of degrading the way a user's value does.
    #
    # The rows with an empty default are the ones that matter for the spec check: an empty
    # default is legal and skips the default's own validation, so a bogus spec has to be
    # caught on its own terms rather than by a default that happens to fail against it.
    Parameters
      INZSH_OK        any                  x         accepted
      INZSH_OK_2      'enum:alternate|ramp' ramp     accepted
      INZSH_RANGE     int:1:9              5         accepted
      INZSH_EMPTY     'enum:truecolor|256' ''        accepted
      inzsh_lower     any                  x         refused
      NOTINZSH        any                  x         refused
      'INZSH_SPACE X' any                  x         refused
      INZSH_BAD_SPEC  bogus                x         refused
      INZSH_BAD_SPEC  'int:low:high'       1         refused
      INZSH_BAD_SPEC  ''                   x         refused
      INZSH_BAD_DEF   int:1:3              4         refused
      INZSH_BAD_DEF   'enum:a|b'           c         refused
      INZSH_NO_DEF    bogus                ''        refused
      INZSH_NO_DEF    'int:low:high'       ''        refused
      INZSH_NO_DEF    'enum:'              ''        refused
    End

    It "$4 $1 with spec '$2' and default '$3'"
      registered() {
        local verdict=refused
        _inzsh_config_register "$1" "$2" "$3" && verdict=accepted
        print -r -- $verdict
      }
      When call registered "$1" "$2" "$3"
      The output should eq "$4"
    End

    It 'leaves the registry untouched when it refuses'
      untouched() {
        _inzsh_config_register INZSH_REJECTED int:1:3 99
        local seen=${_inzsh_config_defaults[INZSH_REJECTED]+default}
        seen+=${_inzsh_config_validators[INZSH_REJECTED]+validator}
        print -r -- "[$seen]"
      }
      When call untouched
      The output should eq '[]'
    End

    # Plugin managers source a theme twice. Registration has to land on the same registry the
    # second time, and a later registration with different arguments has to win outright rather
    # than leave a knob half-updated.
    It 'is idempotent, and a later registration replaces the earlier one'
      twice() {
        local before after
        _inzsh_config_register INZSH_TWICE int:1:3 2
        before="${_inzsh_config_validators[INZSH_TWICE]} ${_inzsh_config_defaults[INZSH_TWICE]}"
        _inzsh_config_register INZSH_TWICE int:1:3 2
        after="${_inzsh_config_validators[INZSH_TWICE]} ${_inzsh_config_defaults[INZSH_TWICE]}"
        [[ $before == $after ]] || { print -r -- 'not idempotent'; return }
        _inzsh_config_register INZSH_TWICE 'enum:x|y' y
        local now=${_inzsh_config_validators[INZSH_TWICE]}
        now+=" ${_inzsh_config_defaults[INZSH_TWICE]}"
        print -r -- "$before / $now"
      }
      When call twice
      The output should eq 'int:1:3 2 / enum:x|y y'
    End
  End

  Describe 'the knobs the tree already reads'
    # Seeded from what `detect.zsh` and `render.zsh` validate by hand today, so the registry
    # and the inline reads cannot disagree about what is legal.
    Parameters
      INZSH_SURFACE_MODE 'enum:alternate|ramp|flat' alternate
      INZSH_COLOR_DEPTH  'enum:truecolor|256|8'     ''
    End

    It "registers $1 with the $2 spec"
      seeded() {
        print -r -- "${_inzsh_config_validators[$1]} / ${_inzsh_config_defaults[$1]}"
      }
      When call seeded "$1"
      The output should eq "$2 / $3"
    End
  End

  Describe 'validating through the registry'
    It 'validates a knob against its registered spec'
      routed() {
        local -a wrong=()
        _inzsh_config_validate INZSH_SURFACE_MODE ramp  || wrong+=ramp
        _inzsh_config_validate INZSH_SURFACE_MODE RAMP  && wrong+=RAMP
        _inzsh_config_validate INZSH_COLOR_DEPTH 256    || wrong+=256
        _inzsh_config_validate INZSH_COLOR_DEPTH 16     && wrong+=16
        print -r -- "${wrong[*]}"
      }
      When call routed
      The output should eq ''
    End

    # A knob nobody declared has no opinion. The config layer is not a gate on the whole
    # namespace — it only enforces what it was told.
    It 'accepts any non-empty value for a knob that was never registered'
      unregistered() {
        local -a wrong=()
        _inzsh_config_validate INZSH_NOT_REGISTERED anything || wrong+=value
        _inzsh_config_validate INZSH_NOT_REGISTERED ''       && wrong+=empty
        print -r -- "${wrong[*]}"
      }
      When call unregistered
      The output should eq ''
    End
  End
End

Describe 'reading configuration'
  Describe 'the fallback ladder'
    # $1 what the user's variable holds, $2 what comes back. Everything unusable lands on the
    # registered default: unset, empty, misspelled, wrong case, padded with a stray space.
    Parameters
      flat       flat
      ramp       ramp
      alternate  alternate
      ''         alternate
      Flat       alternate
      'ramp '    alternate
      chartreuse alternate
      0          alternate
    End

    It "gives '$2' when INZSH_SURFACE_MODE holds '$1'"
      ladder() {
        typeset -g INZSH_SURFACE_MODE=$1
        _inzsh_config_get INZSH_SURFACE_MODE
        print -r -- "$REPLY"
      }
      When call ladder "$1"
      The output should eq "$2"
    End

    It 'gives the default when the variable is not set at all'
      unset_knob() {
        unset INZSH_SURFACE_MODE
        _inzsh_config_get INZSH_SURFACE_MODE
        print -r -- "$REPLY"
      }
      When call unset_knob
      The output should eq 'alternate'
    End

    # An empty default is a real answer for a knob whose absence means something — nothing set
    # for the colour depth is the instruction to trust detection.
    It 'gives the empty default for a knob whose absence is meaningful'
      depth() {
        local -a seen=()
        typeset -g INZSH_COLOR_DEPTH=256; _inzsh_config_get INZSH_COLOR_DEPTH; seen+="[$REPLY]"
        typeset -g INZSH_COLOR_DEPTH=16;  _inzsh_config_get INZSH_COLOR_DEPTH; seen+="[$REPLY]"
        unset INZSH_COLOR_DEPTH;          _inzsh_config_get INZSH_COLOR_DEPTH; seen+="[$REPLY]"
        print -r -- "${seen[*]}"
      }
      When call depth
      The output should eq '[256] [] []'
    End

    It 'never comes back empty for a knob that has a default'
      populated() {
        local candidate; local -a empty=()
        for candidate in "${inzsh_spec_modes[@]}" ; do
          typeset -g INZSH_SURFACE_MODE=$candidate
          _inzsh_config_get INZSH_SURFACE_MODE
          [[ -n $REPLY ]] || empty+=${candidate:-none}
        done
        print -r -- "checked=${#inzsh_spec_modes} empty=${empty[*]}"
      }
      When call populated
      The output should eq 'checked=11 empty='
    End

    # No status a prompt could usefully react to. A read that could fail is a read every caller
    # has to guard, and one of them will forget.
    It 'always succeeds, whatever it was asked for'
      statuses() {
        local -a failed=()
        _inzsh_config_get INZSH_SURFACE_MODE   || failed+=known
        _inzsh_config_get INZSH_NEVER_HEARD_OF || failed+=unknown
        _inzsh_config_get ''                   || failed+=empty
        print -r -- "${failed[*]}"
      }
      When call statuses
      The output should eq ''
    End
  End

  # The point of reading at render time: a variable changed at a prompt takes effect at the
  # next one, with no re-source and no new shell. Nothing here caches.
  It 'reads the live variable on every call, in both directions'
    live() {
      local mode; local -a seen=()
      for mode in flat ramp chartreuse '' alternate flat; do
        typeset -g INZSH_SURFACE_MODE=$mode
        _inzsh_config_get INZSH_SURFACE_MODE
        seen+=$REPLY
      done
      print -r -- "${seen[*]}"
    }
    When call live
    The output should eq 'flat ramp alternate alternate alternate flat'
  End
End

Describe 'precedence'
  # override → role → default, the same three levels the colour resolver uses, generalised to
  # any knob. Each example moves exactly one level so a failure names which one broke.
  Describe 'the three levels'
    # $1 the per-segment override, $2 the role value, $3 the user's global setting, $4 the
    # resolved answer.
    Parameters
      ramp  flat  alternate ramp       # the override wins over everything
      ''    flat  alternate flat       # no override — the role wins over the global setting
      ''    ''    flat      flat       # no role — the global setting stands in as the default
      ''    ''    ''        alternate  # nothing set anywhere — the registered default
      ''    ''    nonsense  alternate  # an unusable global setting is no setting
    End

    It "resolves override='$1' role='$2' global='$3' to $4"
      levels() {
        typeset -g INZSH_DIR_SURFACE_MODE=$1
        typeset -g INZSH_SURFACE_MODE=$3
        _inzsh_config_resolve DIR SURFACE_MODE "$2"
        print -r -- "$REPLY"
      }
      When call levels "$1" "$2" "$3"
      The output should eq "$4"
    End
  End

  Describe 'emptiness is no opinion, at every level'
    # An `INZSH_DIR_SURFACE_MODE=` left behind in a zshrc must fall through rather than blank
    # the setting — the same rule `_inzsh_seg_color` follows for an empty colour override.
    It 'treats an override that is set but empty as unset'
      blank() {
        typeset -g INZSH_DIR_SURFACE_MODE=
        _inzsh_config_resolve DIR SURFACE_MODE ramp
        print -r -- "$REPLY"
      }
      When call blank
      The output should eq 'ramp'
    End

    It 'treats an empty role value as unset'
      no_role() {
        typeset -g INZSH_SURFACE_MODE=flat
        _inzsh_config_resolve DIR SURFACE_MODE ''
        print -r -- "$REPLY"
      }
      When call no_role
      The output should eq 'flat'
    End
  End

  Describe 'validation applies at every level'
    # $1 the override, $2 the role, $3 what survives. A mistyped override falls through exactly
    # as an unset one does — the level below is still there, so there is nothing to report.
    Parameters
      chartreuse ramp ramp
      RAMP       flat flat
      'flat '    ramp ramp
      chartreuse ''   alternate
      chartreuse RAMP alternate
    End

    It "drops override='$1' and role='$2' to $3 when they do not validate"
      invalid() {
        typeset -g INZSH_DIR_SURFACE_MODE=$1
        unset INZSH_SURFACE_MODE
        _inzsh_config_resolve DIR SURFACE_MODE "$2"
        print -r -- "$REPLY"
      }
      When call invalid "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe 'the shape of the answer'
    It 'keeps overrides on different segments out of each other'
      independent() {
        typeset -g INZSH_DIR_SURFACE_MODE=ramp
        local dir host
        _inzsh_config_resolve DIR SURFACE_MODE flat  && dir=$REPLY
        _inzsh_config_resolve HOST SURFACE_MODE flat && host=$REPLY
        print -r -- "$dir $host"
      }
      When call independent
      The output should eq 'ramp flat'
    End

    It 'reads the segment name case-insensitively, as the colour resolver does'
      lowercased() {
        typeset -g INZSH_DIR_SURFACE_MODE=ramp
        _inzsh_config_resolve dir surface_mode flat
        print -r -- "$REPLY"
      }
      When call lowercased
      The output should eq 'ramp'
    End

    # A knob with nothing behind it must not come back as a plausible-looking empty answer —
    # the caller is told, the same way the colour resolver tells it.
    It 'yields an empty result and a failing status when no level has anything to say'
      nothing() {
        _inzsh_config_resolve DIR NO_SUCH_KNOB
        print -r -- "status=$? reply=[$REPLY]"
      }
      When call nothing
      The output should eq 'status=1 reply=[]'
    End

    It 'still answers for an unregistered knob when a level supplies a value'
      unregistered() {
        typeset -g INZSH_DIR_NO_SUCH_KNOB=anything
        _inzsh_config_resolve DIR NO_SUCH_KNOB
        print -r -- "status=$? reply=[$REPLY]"
      }
      When call unregistered
      The output should eq 'status=0 reply=[anything]'
    End
  End
End

Describe 'invariant guards'
  Describe 'the guard registry'
    It 'registers the three invariants of this milestone'
      names() {
        _inzsh_config_guard_names
        print -r -- "${reply[*]}"
      }
      When call names
      The output should eq 'exit-code-capture render-budget separator-visibility'
    End

    It 'takes a new invariant and answers through it'
      added() {
        _inzsh_config_guard_yes() { [[ $1 == yes ]] }
        _inzsh_config_guard_register house-rule _inzsh_config_guard_yes
        print -r -- "$(inzsh_spec_guard house-rule yes) $(inzsh_spec_guard house-rule no)"
      }
      When call added
      The output should eq 'passes fails'
    End

    # An invariant nobody registered cannot be vouched for, and a guard that cannot vouch says
    # no — the caller's answer to a failed guard is a safe fallback, which costs nothing.
    It 'fails an unknown invariant rather than waving it through'
      When call inzsh_spec_guard no-such-invariant anything
      The output should eq 'fails'
    End

    It 'fails an invariant whose function is registered but not loaded'
      missing() {
        _inzsh_config_guard_register phantom _inzsh_config_guard_not_defined
        inzsh_spec_guard phantom anything
      }
      When call missing
      The output should eq 'fails'
    End

    # Guards run where a prompt is being drawn. A diagnostic there is corruption on somebody's
    # screen, so every one of them answers with a status and nothing else.
    It 'says nothing on either stream, whatever the verdict'
      quiet() {
        _inzsh_config_guard separator-visibility ramp surface surface
        _inzsh_config_guard separator-visibility ramp surface hairline
        _inzsh_config_guard exit-code-capture 'x=1'
        _inzsh_config_guard render-budget 1 inzsh_spec_slow
        _inzsh_config_guard no-such-invariant
        return 0
      }
      When call quiet
      The output should eq ''
      The stderr should eq ''
    End
  End

  Describe 'separator visibility'
    # $1 the mode, $2 a candidate assignment, $3 the verdict. The invariant itself is pinned in
    # the surfaces spec; what is pinned here is that the guard asks the same question.
    Parameters
      alternate 'surface-soft hairline surface-soft' passes
      alternate 'surface-soft surface-soft'          fails
      ramp      'surface-soft hairline surface'      passes
      ramp      'hairline hairline'                  fails
      flat      'surface surface surface'            passes
      chartreuse 'surface surface'                   fails
    End

    It "$1: '$2' $3 the guard"
      When call inzsh_spec_guard separator-visibility "$1" ${=2}
      The output should eq "$3"
    End

    # The rule has one home. If the guard ever answered a question of its own, the two would
    # drift, and the copy that drifts is always the one in the guard.
    It 'agrees with _inzsh_surfaces_valid on every mode and every sequence'
      delegated() {
        local mode candidate; local -a disagreed=(); local -i checked=0
        local -a sequences=(
          'surface'
          'surface surface'
          'surface-soft hairline'
          'surface-soft hairline surface-soft'
          'surface-soft hairline hairline'
          'surface surface-soft surface'
          'hairline hairline hairline'
        )
        for mode in alternate ramp flat chartreuse; do
          for candidate in "${sequences[@]}"; do
            (( checked++ ))
            local direct=fails guarded=fails
            _inzsh_surfaces_valid "$mode" ${=candidate} && direct=passes
            _inzsh_config_guard separator-visibility "$mode" ${=candidate} && guarded=passes
            [[ $direct == $guarded ]] || disagreed+="$mode:$candidate"
          done
        done
        print -r -- "checked=$checked disagreed=${disagreed[*]}"
      }
      When call delegated
      The output should eq 'checked=28 disagreed='
    End

    # A partial source, an old bundle, a file that never loaded: the delegate may be missing,
    # and a guard with no way to check must not vouch. Run in `zsh -f`, where `render.zsh`
    # genuinely has not been sourced.
    It 'fails rather than errors when the delegate was never loaded'
      absent() {
        zsh -f -c '
          source "$1/lib/core/config.zsh"
          local verdict=fails
          _inzsh_config_guard separator-visibility alternate surface hairline && verdict=passes
          print -r -- "${+functions[_inzsh_surfaces_valid]} $verdict"
        ' inzsh-config-absent "$SHELLSPEC_PROJECT_ROOT"
      }
      When call absent
      The output should eq '0 fails'
      The stderr should eq ''
    End
  End

  Describe 'exit-code capture'
    # The contract is positional: `$?` and `$pipestatus` are read on the FIRST line of precmd,
    # because anything above that has already replaced them. The guard is input-driven — one
    # statement per argument — so the hook layer can compose it against what it installs, and
    # this spec can compose it against orderings nobody would write on purpose.
    #
    # $1 the ordering, one statement per word here for readability, $2 the verdict.
    Parameters
      'local:-i:code=$?'               passes
      'local:-a:st=($pipestatus)'      passes
      '#:the:hook x=$?'                passes
      'x=1 code=$?'                    fails
      'setopt:local_options code=$?'   fails
      'x=1'                            fails
      ''                               fails
    End

    It "reads ($1) as $2"
      ordering() {
        local -a statements=()
        local word
        for word in ${=1}; do statements+=${word//:/ }; done
        inzsh_spec_guard exit-code-capture "${statements[@]}"
      }
      When call ordering "$1"
      The output should eq "$2"
    End

    It 'skips blanks and comments, which run nothing and so destroy nothing'
      lenient() {
        inzsh_spec_guard exit-code-capture '' '   ' '# capture first, always' '  local -i c=$?'
      }
      When call lenient
      The output should eq 'passes'
    End

    It 'accepts both spellings of the capture and refuses a near miss'
      spellings() {
        local -a wrong=()
        _inzsh_config_guard exit-code-capture 'local -i c=$?'         || wrong+=status
        _inzsh_config_guard exit-code-capture 'local -a s=($pipestatus)' || wrong+=pipestatus
        _inzsh_config_guard exit-code-capture 'local -i c=$status'    && wrong+=near-miss
        print -r -- "${wrong[*]}"
      }
      When call spellings
      The output should eq ''
    End
  End

  Describe 'the render budget'
    # 30 ms warm, and `tools/perf.zsh` already owns the timing — the guard delegates rather
    # than growing a second clock.
    It 'passes a trivial render inside the house budget'
      When call inzsh_spec_guard render-budget '' :
      The output should eq 'passes'
    End

    It 'fails a render that overruns the budget it was given'
      When call inzsh_spec_guard render-budget 1 inzsh_spec_slow
      The output should eq 'fails'
      The stderr should eq ''
    End

    It 'reads a budget that is not a positive integer as the house budget'
      house() {
        local candidate; local -a wrong=()
        for candidate in '' 0 -5 x 2.5; do
          _inzsh_config_guard render-budget "$candidate" : || wrong+=${candidate:-empty}
        done
        print -r -- "$_inzsh_config_render_budget_ms ${wrong[*]}"
      }
      When call house
      The output should eq '30 '
    End

    It 'fails rather than errors with no command to time'
      When call inzsh_spec_guard render-budget 100
      The output should eq 'fails'
    End

    It 'fails rather than errors when the perf harness was never loaded'
      absent() {
        zsh -f -c '
          source "$1/lib/core/config.zsh"
          local verdict=fails
          _inzsh_config_guard render-budget 1000 : && verdict=passes
          print -r -- "${+functions[inzsh_perf_assert_budget]} $verdict"
        ' inzsh-config-perf "$SHELLSPEC_PROJECT_ROOT"
      }
      When call absent
      The output should eq '0 fails'
      The stderr should eq ''
    End
  End
End

Describe 'degrading under a hostile config'
  # The whole point, stated as behaviour: a configuration that would break an invariant comes
  # back as the registered default, not as an error and not as a broken prompt.
  Describe 'a guarded read'
    # $1 the user's setting, $2 a candidate assignment made under it, $3 the mode that survives.
    Parameters
      ramp  'surface-soft hairline surface' ramp       # holds — the setting stands
      ramp  'hairline hairline'             alternate  # breaks — degrade to the default
      flat  'surface surface surface'       flat       # flat is exempt, and stays
      flat  'surface-soft surface-soft'     flat
      chartreuse 'surface surface'          alternate  # unusable setting, and it breaks too
      ''    'hairline hairline'             alternate
    End

    It "resolves '$1' to $3 for the assignment '$2'"
      guarded() {
        typeset -g INZSH_SURFACE_MODE=$1
        _inzsh_config_guarded INZSH_SURFACE_MODE separator-visibility ${=2}
        print -r -- "$REPLY"
      }
      When call guarded "$1" "$2"
      The output should eq "$3"
    End
  End

  # The guard registry is open, so a guard nobody in this repo wrote can end up on the path. It
  # is a predicate by contract; the answer must not depend on its honouring that.
  It 'holds the answer across a guard that writes REPLY itself'
    clobbering() {
      _inzsh_config_guard_rude() { typeset -g REPLY=clobbered; return 0 }
      _inzsh_config_guard_register rude _inzsh_config_guard_rude
      typeset -g INZSH_SURFACE_MODE=ramp
      _inzsh_config_guarded INZSH_SURFACE_MODE rude
      print -r -- "$REPLY"
    }
    When call clobbering
    The output should eq 'ramp'
  End

  It 'always returns a usable value and a zero status, however hostile the setting'
    survivable() {
      local candidate; local -a bad=()
      for candidate in "${inzsh_spec_modes[@]}"; do
        typeset -g INZSH_SURFACE_MODE=$candidate
        _inzsh_config_guarded INZSH_SURFACE_MODE separator-visibility hairline hairline ||
          bad+="status:${candidate:-none}"
        [[ $REPLY == (alternate|ramp|flat) ]] || bad+="value:${candidate:-none}:$REPLY"
      done
      print -r -- "checked=${#inzsh_spec_modes} bad=${bad[*]}"
    }
    When call survivable
    The output should eq 'checked=11 bad='
  End

  # End to end, against the real surface machinery: set the mode, assign, guard, and if the
  # guard says no, re-assign under what came back. Every hostile mode has to land on a legible
  # prompt, which is the promise the whole layer exists to keep.
  It 'lands every hostile mode on an assignment that holds the invariant'
    end_to_end() {
      local candidate; local -i n; local -a broken=(); local -i checked=0
      for candidate in "${inzsh_spec_modes[@]}"; do
        for (( n = 1; n <= 5; n++ )); do
          (( checked++ ))
          typeset -g INZSH_SURFACE_MODE=$candidate
          _inzsh_surface_assign $n 2 2 2 2 2
          _inzsh_config_guarded INZSH_SURFACE_MODE separator-visibility "${reply[@]}"
          typeset -g INZSH_SURFACE_MODE=$REPLY
          _inzsh_surface_assign $n 2 2 2 2 2
          (( ${#reply} == n )) || broken+="${candidate:-none}:$n:length"
          _inzsh_config_guard separator-visibility "$REPLY" "${reply[@]}" ||
            broken+="${candidate:-none}:$n:adjacent"
        done
      done
      print -r -- "checked=$checked broken=${broken[*]}"
    }
    When call end_to_end
    The output should eq 'checked=55 broken='
  End
End

# Structural, the same gate the token layer carries: this file sits on the render path, and a
# fork there is a cost every prompt in the session pays. Comment lines are skipped — the prose
# above quotes zsh syntax.
Describe 'cost'
  It 'resolves without forking — no command substitution in the config layer'
    substitutions() {
      setopt local_options extended_glob
      local line; local -a bad=()
      while IFS= read -r line; do
        [[ $line == [[:space:]]#\#* ]] && continue
        [[ $line == *'$('* || $line == *'`'* ]] && bad+=$line
      done < "$SHELLSPEC_PROJECT_ROOT/lib/core/config.zsh"
      print -r -- "${#bad}"
    }
    When call substitutions
    The output should eq '0'
  End
End
