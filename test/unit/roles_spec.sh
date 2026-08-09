Include lib/core/tokens.zsh

# The role checklist. Every semantic alias in the design system's colors.css that a prompt can
# use, written out by hand so a dropped or renamed role fails here rather than at draw time.
# Deliberately excluded: --surface-card (web chrome, no prompt analogue) and --accent-wash
# (rgba() alpha — a terminal cell has nothing to composite against).
#
# ONE ENTRY IS NOT A DS ALIAS. `surface-deep` is the engine's own, and it is on this list because
# the list is what the role LAYER must carry rather than what colors.css names — see the note
# above the tables in `lib/core/tokens.zsh` for why a prompt needs a surface the DS never had to.
# It maps to palette keys the DS does ship, so the `dangling` example below holds it to the same
# rule as every other role, which is the property that matters.
inzsh_spec_roles=(
  surface surface-soft surface-deep
  text-strong text-body text-muted
  accent on-accent
  positive positive-text on-positive positive-wash positive-edge
  info info-text on-info info-wash info-edge
  negative negative-text on-negative negative-wash negative-edge
  caution caution-text on-caution caution-wash caution-edge
  neutral neutral-text on-neutral neutral-wash neutral-edge
  inactive-fill inactive-text inactive-edge
  focus-ring hairline
)

# No hex literals live in this file. A resolved role is asserted against the palette entry its
# mapping table names — the second-copy carve-out belongs to the palette spec alone.
Describe 'role layer'
  Describe 'mapping tables'
    Parameters
      light _inzsh_roles_light
      dark  _inzsh_roles_dark
    End

    It "the $1 table carries every role on the checklist"
      missing() {
        local -A table=("${(@Pkv)1}")
        local role; local -a gone=()
        for role in $inzsh_spec_roles; do
          [[ -n ${table[$role]+set} ]] || gone+=$role
        done
        print -r -- "${gone[*]}"
      }
      When call missing "$2"
      The output should eq ''
    End

    It "the $1 table carries nothing the checklist does not name"
      extra() {
        local -A table=("${(@Pkv)1}")
        local role; local -a unexpected=()
        for role in ${(ko)table}; do
          (( ${inzsh_spec_roles[(Ie)$role]} )) || unexpected+=$role
        done
        print -r -- "${unexpected[*]}"
      }
      When call extra "$2"
      The output should eq ''
    End

    It "the $1 table holds exactly the expected number of entries"
      count() {
        local -A table=("${(@Pkv)1}")
        print -r -- "${#table} ${#inzsh_spec_roles}"
      }
      When call count "$2"
      The output should eq '38 38'
    End

    It "the $1 table maps every role to a palette key, never to a value"
      dangling() {
        local -A table=("${(@Pkv)1}")
        local role; local -a bad=()
        for role in ${(ko)table}; do
          [[ -n ${_inzsh_palette[${table[$role]}]+set} ]] || bad+="$role=${table[$role]}"
        done
        print -r -- "${bad[*]}"
      }
      When call dangling "$2"
      The output should eq ''
    End
  End

  Describe 'resolution'
    It 'defaults to the dark register — the sharp preset is the default'
      register() { print -r -- "$_inzsh_register"; }
      When call register
      The output should eq 'dark'
    End

    It 'exposes the resolved roles as an associative array'
      kind() { print -r -- "${(t)_inzsh_role}"; }
      When call kind
      The output should start with 'association'
    End

    Parameters
      light _inzsh_roles_light
      dark  _inzsh_roles_dark
    End

    It "resolves the $1 register to exactly the palette entries its table names"
      resolved() {
        local -A table=("${(@Pkv)2}")
        local role; local -a wrong=() unexpected=()
        _inzsh_register=$1
        _inzsh_tokens_resolve
        for role in ${(ko)table}; do
          [[ ${_inzsh_role[$role]} == ${_inzsh_palette[${table[$role]}]} ]] || wrong+=$role
        done
        for role in ${(ko)_inzsh_role}; do
          [[ -n ${table[$role]+set} ]] || unexpected+=$role
        done
        print -r -- "${#_inzsh_role} ${#wrong} ${#unexpected}"
      }
      When call resolved "$1" "$2"
      The output should eq '38 0 0'
    End
  End

  Describe 'register semantics'
    # Both registers are drawn from the same design system, so the two must actually differ
    # where the DS says they do — a table copied from the wrong block would still pass every
    # structural check above.
    It 'moves surface, text and state roles when the register changes'
      shifted() {
        local -A light=() dark=()
        local role; local -a same=()
        _inzsh_register=light; _inzsh_tokens_resolve; light=("${(@kv)_inzsh_role}")
        _inzsh_register=dark;  _inzsh_tokens_resolve; dark=("${(@kv)_inzsh_role}")
        for role in positive negative on-accent surface surface-deep text-body hairline; do
          [[ ${light[$role]} != ${dark[$role]} ]] || same+=$role
        done
        print -r -- "${same[*]}"
      }
      When call shifted
      The output should eq ''
    End

    It 'keeps accent identical in both registers — one brand colour, not two'
      accent() {
        local light dark
        _inzsh_register=light; _inzsh_tokens_resolve; light=${_inzsh_role[accent]}
        _inzsh_register=dark;  _inzsh_tokens_resolve; dark=${_inzsh_role[accent]}
        [[ $light == $dark && $dark == ${_inzsh_palette[caramel]} ]] && print -r -- 'identical'
      }
      When call accent
      The output should eq 'identical'
    End

    It 'falls back to dark for any unrecognised register — config never breaks the render'
      fallback() {
        local -A expected=()
        local candidate role; local -a bad=()
        _inzsh_register=dark; _inzsh_tokens_resolve; expected=("${(@kv)_inzsh_role}")
        for candidate in chartreuse Light 'light ' '' 0; do
          _inzsh_register=$candidate
          _inzsh_tokens_resolve
          for role in ${(ko)expected}; do
            [[ ${_inzsh_role[$role]} == ${expected[$role]} ]] || bad+="${candidate:-empty}:$role"
          done
        done
        print -r -- "${bad[*]}"
      }
      When call fallback
      The output should eq ''
    End

    It 'keeps a chosen register across re-sourcing — the default applies only when unset'
      reload() {
        _inzsh_register=light
        source "$SHELLSPEC_PROJECT_ROOT/lib/core/tokens.zsh"
        source "$SHELLSPEC_PROJECT_ROOT/lib/core/tokens.zsh"
        [[ ${_inzsh_role[surface]} == ${_inzsh_palette[cream]} ]] || print -r -- 'resolved dark'
        print -r -- "$_inzsh_register"
      }
      When call reload
      The output should eq 'light'
    End
  End
End
