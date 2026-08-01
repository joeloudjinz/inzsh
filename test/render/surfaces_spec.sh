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
# The two expectations that outrun a line. Assembled rather than wrapped: a `Parameters` entry
# is one line by construction, so the only place to break a long one is here.
inzsh_spec_alternate_7='surface-deep neutral-wash surface-deep neutral-wash surface-deep'
inzsh_spec_alternate_7+=' neutral-wash surface-deep'
inzsh_spec_ramp_7='surface-deep neutral-wash surface neutral-wash surface surface-deep'
inzsh_spec_ramp_7+=' neutral-wash'

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
      hue
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
      # always opens on surface-deep and every boundary is a change of colour.
      Parameters
        1 'surface-deep'
        2 'surface-deep neutral-wash'
        3 'surface-deep neutral-wash surface-deep'
        4 'surface-deep neutral-wash surface-deep neutral-wash'
        5 'surface-deep neutral-wash surface-deep neutral-wash surface-deep'
        6 'surface-deep neutral-wash surface-deep neutral-wash surface-deep neutral-wash'
        7 "$inzsh_spec_alternate_7"
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
      The output should eq 'surface-deep neutral-wash surface-deep neutral-wash'
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
      # Importance maps straight onto the cycle: 1 raised, 2 neutral-wash, 3 base. $1 segments,
      # $2 the importance vector, $3 what comes back when no pair collides.
      Parameters
        1 '3'            'surface'
        3 '1 2 3'        'surface-deep neutral-wash surface'
        3 '3 2 1'        'surface neutral-wash surface-deep'
        6 '1 2 3 1 2 3'  'surface-deep neutral-wash surface surface-deep neutral-wash surface'
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
        2 '1'         'surface-deep neutral-wash'
        3 '1'         'surface-deep neutral-wash surface'
        4 '0 x 4 -1'  'neutral-wash surface neutral-wash surface'
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
          # back as the neutral-wash surface and anything else shows up immediately.
          _inzsh_surface_assign 2 1 "$candidate"
          [[ ${reply[*]} == 'surface-deep neutral-wash' ]] || bad+=${candidate:-empty}
        done
        print -r -- "${bad[*]}"
      }
      When call outsiders
      The output should eq ''
    End

    Describe 'the collision rule'
      # An adjacent pair that resolved equal bumps the RIGHT one along the cycle
      # (surface-deep → neutral-wash → surface → surface-deep) until the pair differs. Left to
      # right, so position 1 always keeps the importance it was given and every bump is judged
      # against a neighbour that has already settled.
      Parameters
        2 '1 1'            'surface-deep neutral-wash'
        2 '2 2'            'neutral-wash surface'
        2 '3 3'            'surface surface-deep'
        3 '1 1 1'          'surface-deep neutral-wash surface-deep'
        3 '2 2 2'          'neutral-wash surface neutral-wash'
        3 '3 3 3'          'surface surface-deep surface'
        5 '1 2 2 3 3'      'surface-deep neutral-wash surface surface-deep surface'
        7 '1 1 2 2 3 3 1'  "$inzsh_spec_ramp_7"
      End

      It "bumps the right of each equal pair in ($2) at n=$1"
        When call inzsh_spec_assign ramp "$1" "$2"
        The output should eq "$3"
      End
    End
  End

  Describe 'hue'
    # `_inzsh_surface_assign` stays POSITIONAL under `hue` — it is handed a count and a set of
    # importances and knows no segment names, so it cannot be the place a declaration is read.
    # What it answers is the assignment `_inzsh_render_hues` falls back on, and that assignment
    # is deliberately `alternate`'s: the one that holds the invariant with no further rule.
    Describe 'the positional fallback'
      Parameters
        1 'surface-deep'
        2 'surface-deep neutral-wash'
        5 'surface-deep neutral-wash surface-deep neutral-wash surface-deep'
      End

      It "falls back on the alternating assignment at n=$1"
        When call inzsh_spec_assign hue "$1" ''
        The output should eq "$2"
      End
    End

    It 'ignores importances, exactly as alternate does'
      When call inzsh_spec_assign hue 4 '1 3 1 3'
      The output should eq 'surface-deep neutral-wash surface-deep neutral-wash'
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
      alternate 'surface-deep'                        passes
      alternate 'surface-deep neutral-wash'               passes
      alternate 'surface-deep neutral-wash surface-deep'  passes
      alternate 'surface-deep surface-deep'           fails
      alternate 'surface-deep neutral-wash neutral-wash'      fails
      ramp      'surface-deep neutral-wash surface'       passes
      ramp      'surface surface-deep surface'        passes
      ramp      'neutral-wash neutral-wash'                   fails
      ramp      'surface surface surface-deep'        fails
      flat      'surface surface surface'             passes
      flat      'surface-deep surface-deep'           passes
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
      alternate ramp flat hue
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

# ------------------------------------------------------------------------------------------
# Declared backgrounds. `_inzsh_surface_assign` answers one role per POSITION; `hue` is the mode
# in which a segment may answer for itself instead, and `_inzsh_render_hues` is where the two
# meet. Everything here is role names — no colour, no token layer, no hex, the same rule the
# rest of this file keeps.

# Resolve declared backgrounds over a positional assignment. $1 the mode, $2 the positional
# roles as one word-split string, $3.. the visible segment names. `local` keeps both the mode
# and the map out of the next example.
inzsh_spec_hues() {
  local INZSH_SURFACE_MODE=$1
  local -a reply=(${=2})
  shift 2
  _inzsh_render_hues "$@"
  print -r -- "${reply[*]}"
}

Describe 'declared backgrounds'
  # The map is read in `hue` and in no other mode. That is not a restriction bolted on: a
  # positional mode is DEFINED by the renderer owning every background, which is what makes the
  # invariant hold by construction, and a segment that could claim a fill under `alternate` would
  # put a hole in exactly that. `INZSH_<SEGMENT>_BG` is the seam that works in every mode.
  Describe 'which modes read the map'
    Parameters
      hue        'negative neutral-wash'
      alternate  'surface-deep neutral-wash'
      ramp       'surface-deep neutral-wash'
      flat       'surface-deep neutral-wash'
      chartreuse 'surface-deep neutral-wash'
    End

    It "$1 answers '$2' for a segment that declared negative"
      declared() {
        local -A _inzsh_segment_bg_role=(ROOT negative)
        inzsh_spec_hues "$1" 'surface-deep neutral-wash' ROOT DIR
      }
      When call declared "$1"
      The output should eq "$2"
    End
  End

  Describe 'under hue'
    It 'gives a segment the background it declared and everyone else the positional one'
      mixed() {
        local -A _inzsh_segment_bg_role=(ROOT negative SALAH accent)
        inzsh_spec_hues hue 'surface-deep neutral-wash surface-deep neutral-wash' \
          ROOT DIR SALAH TIME
      }
      When call mixed
      The output should eq 'negative neutral-wash accent neutral-wash'
    End

    It 'leaves a run that declared nothing exactly as the position assigned it'
      untouched() {
        local -A _inzsh_segment_bg_role=()
        inzsh_spec_hues hue 'surface-deep neutral-wash surface-deep' A B C
      }
      When call untouched
      The output should eq 'surface-deep neutral-wash surface-deep'
    End

    It 'reads an empty declaration as no declaration — empty means unset here too'
      blank() {
        local -A _inzsh_segment_bg_role=(A '' B accent)
        inzsh_spec_hues hue 'surface-deep neutral-wash' A B
      }
      When call blank
      The output should eq 'surface-deep accent'
    End

    It 'answers nothing for an empty run'
      nothing() {
        local -A _inzsh_segment_bg_role=(A accent)
        inzsh_spec_hues hue ''
      }
      When call nothing
      The output should eq ''
    End
  End

  # THE RULE THAT KEEPS THE INVARIANT WHEN THE COLOUR WAS CHOSEN RATHER THAN ASSIGNED. Left to
  # right: a declaration that would repeat the background already settled on the left is given up
  # for the positional surface, and where that repeats too it walks the cycle until it does not.
  # Position 1 always keeps what it asked for.
  Describe 'the collision rule'
    # $1 the positional assignment, $2 the declarations as `NAME=role` pairs, $3 the answer.
    Parameters
      'surface-deep neutral-wash'              'A=accent B=accent'  'accent neutral-wash'
      'surface-deep neutral-wash surface-deep' 'A=accent B=accent C=accent' \
        'accent neutral-wash accent'
      'surface-deep neutral-wash'              'B=surface-deep'     'surface-deep neutral-wash'
      'surface-deep surface-deep'              'A=accent B=accent'  'accent surface-deep'
      'neutral-wash neutral-wash'              'B=neutral-wash'     'neutral-wash surface'
    End

    It "resolves ($2) over ($1) to ($3)"
      collide() {
        local -A _inzsh_segment_bg_role=()
        local pair
        local -a names=()
        for pair in ${=2}; do
          _inzsh_segment_bg_role[${pair%%=*}]=${pair#*=}
        done
        for pair in A B C D E F G; do names+=$pair; done
        inzsh_spec_hues hue "$1" "${names[@]}"
      }
      When call collide "$1" "$2"
      The output should eq "$3"
    End

    It 'never lets two adjacent blocks share a background, however hostile the map'
      # Every segment asking for the SAME fill is the worst a configuration can do, and the one
      # a positional mode could never produce. The sweep runs it at every length and puts the
      # answer to `_inzsh_surfaces_valid`, which is the invariant itself rather than a
      # restatement of it.
      hostile() {
        local -A _inzsh_segment_bg_role=()
        local INZSH_SURFACE_MODE=hue
        local role name
        local -i n checked=0
        local -a names broken=()
        for name in A B C D E F G; do _inzsh_segment_bg_role[$name]=accent; done
        for role in accent negative surface-deep neutral-wash surface positive; do
          for name in A B C D E F G; do _inzsh_segment_bg_role[$name]=$role; done
          for (( n = 1; n <= 7; n++ )); do
            names=(A B C D E F G)
            _inzsh_surface_assign $n
            _inzsh_render_hues "${names[@]:0:$n}"
            (( checked++ ))
            (( ${#reply} == n )) || broken+="$role:$n:length"
            _inzsh_surfaces_valid hue "${reply[@]}" || broken+="$role:$n:adjacent"
          done
        done
        print -r -- "checked=$checked broken=${broken[*]}"
      }
      When call hostile
      The output should eq 'checked=42 broken='
    End

    It 'lets equal neighbours stand where nothing filled is drawn'
      # The `flat` exemption, reached the way a real prompt reaches it: `INZSH_SEPARATOR_STYLE`
      # resolved to `divider` draws no filled boundary, so there is none to lose and a segment
      # keeps the colour it asked for even beside a twin.
      exempt() {
        local -A _inzsh_segment_bg_role=(A accent B accent)
        local INZSH_SEPARATOR_STYLE=divider
        inzsh_spec_hues hue 'surface-deep neutral-wash' A B
      }
      When call exempt
      The output should eq 'accent accent'
    End
  End

  Describe 'degrading rather than failing'
    It 'keeps the positional assignment when the map is not an association'
      wrong_shape() {
        local -a _inzsh_segment_bg_role=(accent accent)
        inzsh_spec_hues hue 'surface-deep neutral-wash' A B
      }
      When call wrong_shape
      The output should eq 'surface-deep neutral-wash'
    End

    It 'keeps the positional assignment when the cycle has been clobbered'
      # A bump with nowhere to go must not divide by zero mid-render, which is what an empty
      # `_inzsh_surface_cycle` would do to `idx % ${#_inzsh_surface_cycle}`. B declares the
      # surface its own position was going to give it, so neither repair can separate the pair:
      # the predicate says the sequence may not be drawn, and the positional assignment — which
      # came in valid — is what stands. Without that last check the answer would be the equal
      # pair, which is the one thing no filled mode may produce.
      clobbered() {
        local -a _inzsh_surface_cycle=()
        local -A _inzsh_segment_bg_role=(A neutral-wash B neutral-wash)
        inzsh_spec_hues hue 'surface-deep neutral-wash' A B
      }
      When call clobbered
      The output should eq 'surface-deep neutral-wash'
      The stderr should eq ''
    End

    It 'gives a declaration up for the positional surface before it reaches for the cycle'
      # The cheap repair first: B asked for A's colour, so it takes the surface the position was
      # going to give it, which differs — no walk needed, and B keeps the elevation it would have
      # had anyway.
      cheapest() {
        local -a _inzsh_surface_cycle=()
        local -A _inzsh_segment_bg_role=(A accent B accent)
        inzsh_spec_hues hue 'surface-deep neutral-wash' A B
      }
      When call cheapest
      The output should eq 'accent neutral-wash'
    End

    It 'asks nothing of a segment name that is not in the map'
      unknown() {
        local -A _inzsh_segment_bg_role=(A accent)
        inzsh_spec_hues hue 'surface-deep neutral-wash' A 'not a name'
      }
      When call unknown
      The output should eq 'accent neutral-wash'
    End
  End
End

# ------------------------------------------------------------------------------------------
# What the SHIPPED segments ask for. Everything above is about the machinery; this is about the
# defaults it is handed, which is the difference between a mode that works and a mode that looks
# deliberate the first time somebody switches it on.
#
# Loaded in a fresh `zsh -f` rather than `Include`d, because the claim is about the whole segment
# layer at once and half of it registers colour roles this file must not otherwise pull in.

# Every shipped segment's name, its declared background role and its registered foreground, one
# triple per line, with the whole library loaded.
inzsh_spec_shipped_roles() {
  zsh -f -c '
    local root=$1 file segment
    for file in $root/lib/core/*.zsh $root/lib/segments/*.zsh; do source $file; done
    for segment in ${(ko)_inzsh_segment_defaults}; do
      print -r -- "$segment ${_inzsh_segment_bg_role[$segment]:-<none>}" \
        "${_inzsh_segment_fg_role[$segment]:-<none>}"
    done
  ' inzsh-shipped-roles "$SHELLSPEC_PROJECT_ROOT"
}

Describe 'the backgrounds the shipped segments ask for'
  It 'gives every shipped segment one, so the mode needs no configuration to look deliberate'
    # The point of the example is the COUNT as much as the absence: a segment added later without
    # a background role would draw a positional surface in a mode where everything around it
    # carries a colour, which reads as the block that failed rather than as the quiet one.
    complete() {
      local line
      local -i seen=0
      local -a missing=()
      while IFS= read -r line; do
        (( seen++ ))
        [[ ${${=line}[2]} == '<none>' ]] && missing+=${${=line}[1]}
      done < <(inzsh_spec_shipped_roles)
      print -r -- "segments=$(( seen >= 13 )) missing=${missing[*]}"
    }
    When call complete
    The output should eq 'segments=1 missing='
  End

  It 'names only roles the token layer carries, in both registers'
    # A misspelled role is invisible until somebody switches the mode on: `_inzsh_seg_color`
    # falls through to `surface` and the block is simply the wrong colour, which no other example
    # in the tree would notice.
    real() {
      zsh -f -c '
        local root=$1 file segment role
        local -a bad=()
        for file in $root/lib/core/*.zsh $root/lib/segments/*.zsh; do source $file; done
        for segment in ${(ko)_inzsh_segment_bg_role}; do
          role=${_inzsh_segment_bg_role[$segment]}
          [[ -n ${_inzsh_roles_dark[$role]+set} ]]  || bad+=dark:$segment:$role
          [[ -n ${_inzsh_roles_light[$role]+set} ]] || bad+=light:$segment:$role
        done
        print -r -- "${bad[*]}"
      ' inzsh-shipped-real "$SHELLSPEC_PROJECT_ROOT"
    }
    When call real
    The output should eq ''
    The stderr should eq ''
  End

  It 'spends the accent exactly once'
    # One saturated colour, one block. Spend it twice and it stops meaning anything; spend it
    # nowhere and the theme has a brand colour it never draws.
    accent() {
      local line
      local -a claimants=()
      while IFS= read -r line; do
        [[ ${${=line}[2]} == accent ]] && claimants+=${${=line}[1]}
      done < <(inzsh_spec_shipped_roles)
      print -r -- "${claimants[*]}"
    }
    When call accent
    The output should eq 'SALAH'
  End

  It 'gives the root badge the negative fill it has always been asking for'
    warned() {
      local line
      local -a found=()
      while IFS= read -r line; do
        [[ ${${=line}[1]} == ROOT ]] && found=(${=line})
      done < <(inzsh_spec_shipped_roles)
      print -r -- "${found[2]} ${found[3]}"
    }
    When call warned
    The output should eq 'negative negative-text'
  End
End
