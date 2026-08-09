Include lib/core/tokens.zsh

# The transcription checklist. Every solid-hex token in the design system's colors.css that a
# terminal can render, written out by hand so a dropped or renamed ramp fails here rather
# than at draw time. Deliberately excluded: the two rgba() highlight-wash tokens (no alpha
# in a terminal cell) and the web-only utility tokens (board-bg, badge-aa-*, surface-card).
inzsh_spec_tokens=(
  cream cream-soft cream-bright cream-muted cream-deep
  choc choc-soft choc-ink
  navy navy-soft navy-deep
  caramel caramel-bright
  sage sage-bright ink-blue ink-blue-bright
  sage-deep sage-wash sage-wash-dark sage-edge sage-edge-dark
  ink-blue-wash ink-blue-wash-dark ink-blue-edge ink-blue-edge-dark
  madder madder-bright madder-wash madder-wash-dark madder-edge madder-edge-dark
  ochre ochre-bright ochre-wash ochre-wash-dark ochre-edge ochre-edge-dark
  putty-wash putty-line putty-text putty-fill putty-hair
  slate-wash slate-line slate-text slate-fill slate-hair
  hair-light hair-dark
)

Describe 'token layer'
  It 'exposes the palette as an associative array'
    kind() { print -r -- "${(t)_inzsh_palette}"; }
    When call kind
    The output should start with 'association'
  End

  It 'carries every expected DS token'
    missing() {
      local name; local -a gone=()
      for name in $inzsh_spec_tokens; do
        [[ -n ${_inzsh_palette[$name]} ]] || gone+=$name
      done
      print -r -- "${gone[*]}"
    }
    When call missing
    The output should eq ''
  End

  It 'carries nothing the checklist does not name'
    extra() {
      local name; local -a unexpected=()
      for name in ${(ko)_inzsh_palette}; do
        (( ${inzsh_spec_tokens[(Ie)$name]} )) || unexpected+=$name
      done
      print -r -- "${unexpected[*]}"
    }
    When call extra
    The output should eq ''
  End

  It 'holds exactly the expected number of entries'
    count() { print -r -- "${#_inzsh_palette} ${#inzsh_spec_tokens}"; }
    When call count
    The output should eq '50 50'
  End

  It 'stores every value as an uppercase six-digit hex with a leading hash'
    malformed() {
      local name value; local -a bad=()
      for name in ${(ko)_inzsh_palette}; do
        value=${_inzsh_palette[$name]}
        [[ $value =~ '^#[0-9A-F]{6}$' ]] || bad+="$name=$value"
      done
      print -r -- "${bad[*]}"
    }
    When call malformed
    The output should eq ''
  End

  # The one place a literal hex belongs outside lib/core/tokens.zsh: pinning the
  # transcription needs a second, independent copy of the DS value to compare against.
  Describe 'spot-checks against the design-system source'
    Parameters
      cream           '#F3EAD2'
      navy-soft       '#2A3350'
      caramel         '#B07A3C'
      sage-deep       '#4F6B4C'
      madder-bright   '#E0A5AF'
      ochre           '#7A6119'
      ink-blue-bright '#8F9BC4'
      slate-hair      '#414965'
      hair-light      '#E4D8BE'
    End

    It "transcribes $1 verbatim"
      value() { print -r -- "${_inzsh_palette[$1]}"; }
      When call value "$1"
      The output should eq "$2"
    End
  End

  It 'keeps the navy and chocolate ramps distinct at truecolor'
    # These six famously flatten into each other once quantised to 256; at this depth the
    # token layer must still hand back six different values.
    spread() {
      local name; local -a values=()
      for name in navy navy-soft navy-deep choc choc-soft choc-ink; do
        values+=${_inzsh_palette[$name]}
      done
      local -a distinct=(${(u)values})
      print -r -- "${#values} ${#distinct}"
    }
    When call spread
    The output should eq '6 6'
  End
End
