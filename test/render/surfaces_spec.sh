Include lib/core/render.zsh

# Surface assignment. These examples pin ROLE NAMES and nothing else — the machinery never
# touches colour, so this file never loads the token layer and carries no hex, the same rule
# that holds everywhere outside it.
#
# Two blocks. The first pins what each mode produces. The second is the invariant gate: every
# mode, every length, every hostile importance vector, run through `_inzsh_surfaces_valid`.
#
# A `Parameters` block applies to every example in its group and to nested groups, so each one
# below sits in a leaf group of its own. An example that takes no parameters lives outside
# them, where it runs once.

# Assign under an explicit mode and print the roles as one line, so an assertion reads like the
# sequence it pins. $1 mode, $2 segment count, $3 a space-separated importance vector ('' for
# none). `local` keeps the mode out of the next example.
inzsh_spec_assign() {
  local INZSH_SURFACE_MODE=$1
  _inzsh_surface_assign "$2" ${=3}
  print -r -- "${reply[*]}"
}

# The hostile matrix, one entry per way a configuration could try to force two equal
# neighbours. The sweep in the second block runs every one of them through every mode at every
# length; the count is asserted alongside the failures, so adding a vector here and forgetting
# to widen the gate cannot pass silently.
inzsh_spec_vectors=(
  ''                  # no importances at all — every segment takes the default
  '1 1 1 1 1 1 1'     # all-equal, most important
  '2 2 2 2 2 2 2'     # all-equal, the default importance
  '3 3 3 3 3 3 3'     # all-equal, least important
  '1 2 3 1 2 3 1'     # ascending, wrapping past the end of the ramp
  '3 2 1 3 2 1 3'     # descending, wrapping the other way
  '2 2 1 3 3 1 2'     # arbitrary, pinned so that a failure reproduces
  '1 1 2 2 3 3 1'     # an equal pair at every step of the cycle
  '0 x 4 -1 2.5 9 z'  # every importance unparseable — all default to 2, so all collide
  '1'                 # one importance for many segments — the rest are missing
)

Describe 'surface modes'
  Describe 'mode resolution'
    Parameters
      alternate
      ramp
      flat
    End

    It "resolves the explicit $1 mode"
      resolve() {
        local INZSH_SURFACE_MODE=$1
        _inzsh_surface_mode
        print -r -- "$_inzsh_surface_mode_resolved"
      }
      When call resolve "$1"
      The output should eq "$1"
    End
  End

  Describe 'mode fallback'
    # alternate is the default because it is the only mode that guarantees separator
    # visibility without a further rule — the safe landing place for anything unreadable.
    It 'defaults to alternate when INZSH_SURFACE_MODE is unset'
      unconfigured() {
        unset INZSH_SURFACE_MODE
        _inzsh_surface_mode
        print -r -- "$_inzsh_surface_mode_resolved"
      }
      When call unconfigured
      The output should eq 'alternate'
    End

    It 'falls back to alternate for anything else — config never breaks the render'
      fallback() {
        local candidate INZSH_SURFACE_MODE; local -a bad=()
        for candidate in Alternate RAMP Flat 'ramp ' ' flat' alternat chartreuse '' 0 -; do
          INZSH_SURFACE_MODE=$candidate
          _inzsh_surface_mode
          [[ $_inzsh_surface_mode_resolved == alternate ]] || bad+=${candidate:-empty}
        done
        print -r -- "${bad[*]}"
      }
      When call fallback
      The output should eq ''
    End
  End

  Describe 'alternate'
    Describe 'the sequence'
      # The two raised surfaces, swinging. Index 1 is the more raised of the two, so a prompt
      # always opens on surface-soft and every boundary is a change of colour.
      Parameters
        1 'surface-soft'
        2 'surface-soft hairline'
        3 'surface-soft hairline surface-soft'
        4 'surface-soft hairline surface-soft hairline'
        5 'surface-soft hairline surface-soft hairline surface-soft'
        6 'surface-soft hairline surface-soft hairline surface-soft hairline'
        7 'surface-soft hairline surface-soft hairline surface-soft hairline surface-soft'
      End

      It "alternates strictly at n=$1"
        When call inzsh_spec_assign alternate "$1" ''
        The output should eq "$2"
      End
    End

    It 'never puts a segment on the base surface — both alternates are raised'
      raised() {
        local INZSH_SURFACE_MODE=alternate
        local -i n; local -a bad=()
        for (( n = 1; n <= 7; n++ )); do
          _inzsh_surface_assign $n
          (( ${#reply} == n )) || bad+="$n:length"
          (( ${reply[(I)surface]} )) && bad+="$n:base-surface"
        done
        print -r -- "${bad[*]}"
      }
      When call raised
      The output should eq ''
    End

    It 'ignores importances — the mode is positional, not weighted'
      When call inzsh_spec_assign alternate 4 '3 3 3 3'
      The output should eq 'surface-soft hairline surface-soft hairline'
    End
  End

  Describe 'flat'
    Describe 'the sequence'
      # One surface throughout: no filled blocks, so nothing to keep apart.
      Parameters
        1 'surface'
        2 'surface surface'
        3 'surface surface surface'
        4 'surface surface surface surface'
        5 'surface surface surface surface surface'
        6 'surface surface surface surface surface surface'
        7 'surface surface surface surface surface surface surface'
      End

      It "gives n=$1 identical entries"
        When call inzsh_spec_assign flat "$1" ''
        The output should eq "$2"
      End
    End

    It 'ignores importances too'
      When call inzsh_spec_assign flat 3 '1 2 3'
      The output should eq 'surface surface surface'
    End
  End

  Describe 'ramp'
    Describe 'importance alone'
      # Importance maps straight onto the cycle: 1 raised, 2 hairline, 3 base. $1 segments,
      # $2 the importance vector, $3 what comes back when no pair collides.
      Parameters
        1 '3'            'surface'
        3 '1 2 3'        'surface-soft hairline surface'
        3 '3 2 1'        'surface hairline surface-soft'
        6 '1 2 3 1 2 3'  'surface-soft hairline surface surface-soft hairline surface'
      End

      It "honours ($2) at n=$1 when nothing collides"
        When call inzsh_spec_assign ramp "$1" "$2"
        The output should eq "$3"
      End
    End

    Describe 'defaulted importances'
      # 2 is the middle of the ramp — the least surprising surface for a segment that never
      # asked for one, and where anything unreadable lands.
      Parameters
        2 '1'         'surface-soft hairline'
        3 '1'         'surface-soft hairline surface'
        4 '0 x 4 -1'  'hairline surface hairline surface'
      End

      It "fills in ($2) at n=$1 with the default importance"
        When call inzsh_spec_assign ramp "$1" "$2"
        The output should eq "$3"
      End
    End

    It 'reads every value outside 1..3 as the middle of the ramp'
      outsiders() {
        local INZSH_SURFACE_MODE=ramp
        local candidate; local -a bad=()
        for candidate in 0 4 -1 2.5 03 x '+2' 999 ''; do
          # Position 1 is pinned to the raised surface, so a second entry reading as 2 comes
          # back as the hairline surface and anything else shows up immediately.
          _inzsh_surface_assign 2 1 "$candidate"
          [[ ${reply[*]} == 'surface-soft hairline' ]] || bad+=${candidate:-empty}
        done
        print -r -- "${bad[*]}"
      }
      When call outsiders
      The output should eq ''
    End

    Describe 'the collision rule'
      # An adjacent pair that resolved equal bumps the RIGHT one along the cycle
      # (surface-soft → hairline → surface → surface-soft) until the pair differs. Left to
      # right, so position 1 always keeps the importance it was given and every bump is judged
      # against a neighbour that has already settled.
      Parameters
        2 '1 1'            'surface-soft hairline'
        2 '2 2'            'hairline surface'
        2 '3 3'            'surface surface-soft'
        3 '1 1 1'          'surface-soft hairline surface-soft'
        3 '2 2 2'          'hairline surface hairline'
        3 '3 3 3'          'surface surface-soft surface'
        5 '1 2 2 3 3'      'surface-soft hairline surface surface-soft surface'
        7 '1 1 2 2 3 3 1'  'surface-soft hairline surface hairline surface surface-soft hairline'
      End

      It "bumps the right of each equal pair in ($2) at n=$1"
        When call inzsh_spec_assign ramp "$1" "$2"
        The output should eq "$3"
      End
    End
  End

  Describe 'the shape of the answer'
    It 'hands the roles back in reply, as an array'
      kind() {
        local INZSH_SURFACE_MODE=alternate
        _inzsh_surface_assign 3
        print -r -- "${(t)reply} ${#reply}"
      }
      When call kind
      The output should eq 'array 3'
    End

    It 'yields an empty assignment for a segment count that is not a positive integer'
      degenerate() {
        local candidate INZSH_SURFACE_MODE; local -a bad=()
        for candidate in 0 -1 -7 x 2.5 '' ' '; do
          for INZSH_SURFACE_MODE in alternate ramp flat; do
            _inzsh_surface_assign "$candidate" 1 2 3
            (( ${#reply} )) && bad+="$INZSH_SURFACE_MODE:${candidate:-empty}"
          done
        done
        print -r -- "${bad[*]}"
      }
      When call degenerate
      The output should eq ''
    End
  End
End

# ------------------------------------------------------------------------------------------
# The invariant gate. Everything above says what a mode produces; this block says what no mode
# may ever produce. A filled block is legible only because it differs from the block beside it,
# so in a filled mode two equal neighbours are a separator that cannot be seen. No
# configuration may reach that state — the sweep is the proof, run over the whole hostile
# matrix declared at the top of this file.
Describe 'separator visibility'
  Describe 'the guard itself'
    # Hand-built sequences, valid and invalid, so that the sweep below cannot pass by way of a
    # guard that says yes to everything. $1 the mode, $2 the candidate, $3 the verdict.
    Parameters
      alternate 'surface-soft'                        passes
      alternate 'surface-soft hairline'               passes
      alternate 'surface-soft hairline surface-soft'  passes
      alternate 'surface-soft surface-soft'           fails
      alternate 'surface-soft hairline hairline'      fails
      ramp      'surface-soft hairline surface'       passes
      ramp      'surface surface-soft surface'        passes
      ramp      'hairline hairline'                   fails
      ramp      'surface surface surface-soft'        fails
      flat      'surface surface surface'             passes
      flat      'surface-soft surface-soft'           passes
    End

    It "$1: '$2' $3 validation"
      check() {
        local verdict=fails
        _inzsh_surfaces_valid "$1" ${=2} && verdict=passes
        print -r -- $verdict
      }
      When call check "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe 'no configuration breaks it'
    # mode × segment count × the ten hostile vectors. The counted total is asserted with the
    # failures, so a loop that quietly stopped running fails here rather than passing.
    Parameters:matrix
      alternate ramp flat
      1 2 3 4 5 6 7
    End

    It "$1 mode at n=$2 holds the invariant for every hostile vector"
      sweep() {
        local INZSH_SURFACE_MODE=$1
        local vector; local -i n=$2 checked=0; local -a broken=()
        for vector in "${inzsh_spec_vectors[@]}"; do
          _inzsh_surface_assign $n ${=vector}
          (( checked++ ))
          (( ${#reply} == n )) || broken+="${vector:-none}:length"
          _inzsh_surfaces_valid "$1" "${reply[@]}" || broken+="${vector:-none}:adjacent"
        done
        print -r -- "checked=$checked broken=${broken[*]}"
      }
      When call sweep "$1" "$2"
      The output should eq 'checked=10 broken='
    End
  End

  Describe 'the flat exemption'
    # flat is the one mode whose output repeats, and it repeats by design. Stating it both ways
    # keeps the exemption honest: the sequence a filled mode must reject is exactly the one
    # flat is meant to produce.
    It 'accepts under flat exactly what it rejects under a filled mode'
      exemption() {
        local INZSH_SURFACE_MODE=flat
        local -a bad=()
        _inzsh_surface_assign 4
        _inzsh_surfaces_valid flat "${reply[@]}"      || bad+=flat-rejected
        _inzsh_surfaces_valid alternate "${reply[@]}" && bad+=alternate-accepted
        _inzsh_surfaces_valid ramp "${reply[@]}"      && bad+=ramp-accepted
        print -r -- "segments=${#reply} broken=${bad[*]}"
      }
      When call exemption
      The output should eq 'segments=4 broken='
    End

    It 'treats an unrecognised mode as filled — the strict reading is the safe one'
      unknown() {
        local verdict=fails
        _inzsh_surfaces_valid chartreuse surface surface && verdict=passes
        print -r -- $verdict
      }
      When call unknown
      The output should eq 'fails'
    End
  End
End
