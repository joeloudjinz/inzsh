# InZsh — render core. At M1 this file carries the surface-assignment machinery only; the
# renderer proper grows here at M2. Nothing below draws anything. It answers one question —
# "which surface does segment i sit on?" — and answers it in ROLE NAMES. Colour is resolved
# downstream by the token layer, so this file loads nothing and holds no hex. Separator glyphs
# are not its business either; they live in the token layer.
#
# Why surfaces are assigned centrally rather than per segment: a filled prompt is a run of
# abutting blocks, and a block is only legible because it differs from the block beside it.
# That is a property of the SEQUENCE, not of any one segment, so no segment can decide it on
# its own. The engine asks once, for the whole visible run, and gets back one role per segment.
#
# The invariant: in a filled mode, no two adjacent segments share a surface role.
# `_inzsh_surfaces_valid` is that sentence written down as code; the surfaces spec gates every
# mode, every length and every hostile importance vector against it. No configuration may break
# it — an unrecognised mode falls back rather than erroring, and `ramp` repairs a collision
# rather than rejecting it.
#
# Three modes:
#   alternate  the default. Two raised surfaces, strictly alternating. Visibility here is
#              structural — the invariant holds by construction, with no further rule — which
#              is exactly why it is also the fallback.
#   ramp       importance drives the surface: 1 (most important) sits highest, 3 lowest. Equal
#              neighbours are pulled apart afterwards by the collision rule below.
#   flat       one surface throughout. There is no filled powerline to make legible, so equal
#              neighbours are expected and the invariant does not apply.

# The ramp's ordering, and the bump order the collision rule walks: surface-soft → hairline →
# surface → surface-soft. Index 1..3 is also the importance mapping, so `ramp` reads an
# importance as a subscript directly. The first two entries are the two raised surfaces that
# `alternate` swings between.
typeset -ga _inzsh_surface_cycle
_inzsh_surface_cycle=(surface-soft hairline surface)

# Resolve INZSH_SURFACE_MODE into `_inzsh_surface_mode_resolved`. Unset, empty, misspelled,
# wrong case, padded with a stray space — all of it lands on `alternate`. A prompt with an
# unreadable mode name in the config still draws, and draws legibly.
_inzsh_surface_mode() {
  emulate -L zsh

  case ${INZSH_SURFACE_MODE-} in
    (alternate|ramp|flat) typeset -g _inzsh_surface_mode_resolved=${INZSH_SURFACE_MODE} ;;
    (*)                   typeset -g _inzsh_surface_mode_resolved=alternate ;;
  esac
}

# Assign a surface role to each of $1 visible segments; args 2.. are the per-segment importances
# that `ramp` reads (integers 1-3, 1 = most important). Missing or unparseable importances are
# 2 — the middle of the ramp, the least surprising place for a segment that never asked.
# `alternate` and `flat` ignore them entirely; they are positional.
#
# The answer comes back in `reply` as an array of $1 role names, zsh's usual channel for a
# function returning a list. A segment count that is not a positive integer yields an empty
# assignment and status 0: nothing to draw is not an error.
#
# The mode is resolved here rather than passed in, so a caller cannot draw with a mode the
# config no longer says. Parameter operations only — this runs on the render path, no forks.
_inzsh_surface_assign() {
  emulate -L zsh

  _inzsh_surface_mode

  typeset -ga reply
  reply=()

  local -i n=0
  [[ $1 == <-> ]] && n=$1
  (( n > 0 )) || return 0
  shift

  local -a importances=("$@")
  local -i i idx

  case $_inzsh_surface_mode_resolved in
    (flat)
      # One surface for every segment. Deliberately equal neighbours.
      for (( i = 1; i <= n; i++ )); do
        reply+=${_inzsh_surface_cycle[3]}
      done
      ;;

    (ramp)
      # Importance first, ignoring neighbours entirely.
      for (( i = 1; i <= n; i++ )); do
        idx=2
        [[ ${importances[i]-} == (1|2|3) ]] && idx=${importances[i]}
        reply+=${_inzsh_surface_cycle[idx]}
      done
      # Then the collision rule, left to right: where a pair came out equal, the RIGHT one
      # bumps to the next role in the cycle until the pair differs. Left-anchored on purpose —
      # position 1 keeps the importance it was given, and each bump is judged against a
      # neighbour that is already settled, so one pass is enough. A bump always lands on a
      # different cycle entry, so the inner loop cannot spin: at most two turns and the pair
      # differs.
      for (( i = 2; i <= n; i++ )); do
        while [[ ${reply[i]} == ${reply[i-1]} ]]; do
          idx=${_inzsh_surface_cycle[(Ie)${reply[i]}]}
          reply[i]=${_inzsh_surface_cycle[idx % ${#_inzsh_surface_cycle} + 1]}
        done
      done
      ;;

    (*)
      # alternate — odd positions raised, even positions on the hairline surface. Index 1 is
      # surface-soft, so the first segment is always the most raised one.
      for (( i = 1; i <= n; i++ )); do
        reply+=${_inzsh_surface_cycle[2 - (i % 2)]}
      done
      ;;
  esac

  return 0
}

# The invariant, as a predicate: $1 is the mode, $2.. a candidate assignment. Status 0 iff the
# sequence may be drawn.
#
# `flat` skips the check — with no filled blocks there is no boundary to lose, so equal
# neighbours there are the design and not a defect. Every other mode is a filled mode and must
# have no two adjacent entries equal. An unrecognised mode is treated as filled: the strict
# reading is the safe one, and it matches the fallback `_inzsh_surface_mode` would have picked.
_inzsh_surfaces_valid() {
  emulate -L zsh

  local mode=$1
  shift
  [[ $mode == flat ]] && return 0

  local -i i
  for (( i = 2; i <= $#; i++ )); do
    [[ ${@[i]} != ${@[i-1]} ]] || return 1
  done

  return 0
}
