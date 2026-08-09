Include lib/core/config.zsh
Include lib/core/tokens.zsh

# `INZSH_PRESET` — the one knob that names a whole look rather than one detail of it.
#
# What is under test is the pair the knob is made of: the registry entry, which decides which
# names are names at all, and `_inzsh_preset_apply`, which turns one into a register. The two
# have to agree about the vocabulary — a value the validator blesses and the applier then fails
# to find would be a knob that accepts a word and does nothing with it, which is exactly the
# invisible failure the registry exists to end.
#
# The applier reads no file. That is the property the single-file bundle depends on and it is
# asserted rather than assumed: `test/render/bundle_spec.sh` runs the knob against a bundle with
# no `presets/` directory anywhere near it, and the example here that loads the token layer
# ALONE — no config layer, no repository — is the same claim at this level.
#
# No hex literals: a resolved role is compared to the palette entry its register's table names.

Describe 'the preset knob'
  Describe 'registration'
    It 'is declared with the preset names and no default'
      declared() {
        print -r -- "${_inzsh_config_validators[INZSH_PRESET]} [${_inzsh_config_defaults[INZSH_PRESET]}]"
      }
      When call declared
      The output should eq 'word:sharp|warm []'
    End

    # `word:` matches with case, spacing and punctuation ignored, so a name typed the way a
    # person types it is the name. Anything else — a register name, a typo, nothing at all —
    # reads as the empty default, which is the instruction to leave the built-in register alone.
    Parameters
      warm       warm
      sharp      sharp
      WARM       WARM
      ' warm '   ' warm '
      light      ''
      dark       ''
      chartreuse ''
      ''         ''
    End

    It "reads INZSH_PRESET='$1' as '$2'"
      through_registry() {
        typeset -g INZSH_PRESET=$1
        _inzsh_config_get INZSH_PRESET
        print -r -- "[$REPLY]"
      }
      When call through_registry "$1"
      The output should eq "[$2]"
    End
  End

  Describe 'applying'
    Describe 'a name it knows'
      # $1 the value set, $2 the register in place before it, $3 the one after, $4 its table.
      # Every case starts from the other register, so each is a real switch rather than a knob
      # agreeing with where the shell already was.
      Parameters
        warm  dark  light _inzsh_roles_light
        sharp light dark  _inzsh_roles_dark
        WARM  dark  light _inzsh_roles_light
        Warm  dark  light _inzsh_roles_light
      End

      It "switches the register to $3 for INZSH_PRESET='$1'"
        applied() {
          typeset -g INZSH_PRESET=$1
          _inzsh_register=$2
          _inzsh_tokens_resolve
          _inzsh_preset_apply
          print -r -- "$_inzsh_register"
        }
        When call applied "$1" "$2"
        The output should eq "$3"
      End

      It "rebuilds every role from the $3 table for INZSH_PRESET='$1'"
        rebuilt() {
          typeset -g INZSH_PRESET=$1
          _inzsh_register=$2
          _inzsh_tokens_resolve
          _inzsh_preset_apply
          local -A table=("${(@Pkv)3}")
          local role; local -a wrong=()
          for role in ${(ko)table}; do
            [[ ${_inzsh_role[$role]} == ${_inzsh_palette[${table[$role]}]} ]] || wrong+=$role
          done
          print -r -- "${#_inzsh_role} ${#wrong}"
        }
        When call rebuilt "$1" "$2" "$4"
        The output should eq '38 0'
      End
    End

    Describe 'a name it does not'
      # Every one of these is a plausible thing to type — the register's own name, a preset's
      # file name, a typo, a leftover empty assignment — and every one of them leaves the
      # register exactly as it was found. Validate, then fall back: the knob's whole contract.
      Parameters
        light
        dark
        inzsh-warm
        chartreuse
        0
        ''
      End

      It "leaves the register alone for INZSH_PRESET='$1'"
        untouched() {
          typeset -g INZSH_PRESET=$1
          _inzsh_register=light
          _inzsh_tokens_resolve
          _inzsh_preset_apply
          [[ ${_inzsh_role[surface]} == ${_inzsh_palette[cream]} ]] || print -r -- 'roles moved'
          print -r -- "$_inzsh_register"
        }
        When call untouched "$1"
        The output should eq 'light'
      End
    End

    It 'leaves the register alone when INZSH_PRESET was never set at all'
      unset_knob() {
        unset INZSH_PRESET
        _inzsh_register=light
        _inzsh_preset_apply
        print -r -- "$_inzsh_register"
      }
      When call unset_knob
      The output should eq 'light'
    End

    It 'says nothing on either stream and succeeds, whatever it was handed'
      quiet() {
        local value
        for value in warm sharp chartreuse '' light; do
          typeset -g INZSH_PRESET=$value
          _inzsh_preset_apply || print -r -- "failed on '$value'"
        done
      }
      When call quiet
      The output should eq ''
      The stderr should eq ''
      The status should be success
    End

    # The token layer is independently sourceable — that is stated at the head of the file and
    # it has to keep being true of the preset applier too. With no config layer in the shell the
    # knob is read raw, and an unknown name is still nothing more than an unknown name.
    It 'reads the variable directly when the config layer was never loaded'
      standalone() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          local -a wrong=()
          INZSH_PRESET=warm       _inzsh_preset_apply
          [[ $_inzsh_register == light ]] || wrong+=warm:$_inzsh_register
          INZSH_PRESET=chartreuse _inzsh_preset_apply
          [[ $_inzsh_register == light ]] || wrong+=unknown:$_inzsh_register
          INZSH_PRESET=sharp      _inzsh_preset_apply
          [[ $_inzsh_register == dark ]]  || wrong+=sharp:$_inzsh_register
          (( ${+functions[_inzsh_config_get]} )) && wrong+=config-loaded
          print -r -- "${wrong[*]}"
        ' inzsh-preset-standalone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call standalone
      The output should eq ''
      The stderr should eq ''
    End
  End
End
