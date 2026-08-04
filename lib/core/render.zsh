# InZsh — render core. Two halves, in this order:
#
#   surfaces   which surface does segment i sit on? Answered in ROLE NAMES, never in colour.
#   assembly   the prompt string for one side, from the sorted rank arrays. Answered in REPLY.
#
# The first half loads nothing and knows nothing about colour, glyphs or segments; the second
# half is the only place in the tree that puts those three together. No hex lives here either
# way — the token layer resolves every value, and this file asks it by role.
#
# ---------------------------------------------------------------------------------------------
# Surfaces
# ---------------------------------------------------------------------------------------------
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
# Four modes. The first three assign by ELEVATION — how far a block sits from the base surface
# — and differ only in the rule that picks a level. The fourth changes the axis.
#   alternate  the default. The two ends of the surface ramp, strictly alternating. Visibility
#              here is structural — the invariant holds by construction, with no further rule —
#              which is exactly why it is also the fallback.
#   ramp       importance drives the surface: 1 (most important) sits furthest from the base
#              surface, 3 on it. Equal neighbours are pulled apart afterwards by the collision
#              rule below.
#   flat       one surface throughout. There is no filled powerline to make legible, so equal
#              neighbours are expected and the invariant does not apply.
#   hue        each segment carries its OWN background, declared rather than assigned — see
#              `_inzsh_render_hues`. Elevation stops being the thing that tells two blocks
#              apart and colour starts; the positional assignment stays underneath as the
#              answer for a segment that declared nothing.

# The ramp's ordering, and the bump order the collision rule walks: surface-deep → neutral-wash
# → surface → surface-deep. Index 1..3 is also the importance mapping, so `ramp` reads an
# importance as a subscript directly. The first two entries are the pair `alternate` swings
# between, and they are the two the whole file is arranged around.
#
# WHY THESE TWO. A filled boundary IS the colour change, so the separator's own contrast is the
# contrast between the blocks either side of it — and the DS's two raised surfaces, `surface-soft`
# and `hairline`, are #2A3350 and #333C58 in the dark register: nine points a channel, 1.14:1, a
# boundary you have to look for. `surface-deep` (the far end of the ramp — `lib/core/tokens.zsh`
# says why the DS has no name for it) against `neutral-wash` (its neutral chip tint, and a prompt
# block is exactly a chip) gives 1.32:1 in light and 1.41:1 in dark, and every foreground role a
# segment can register still clears WCAG AA on both of them — which `hairline` did not: at
# #333C58 the info ink lands at 3.97:1.
typeset -ga _inzsh_surface_cycle
_inzsh_surface_cycle=(surface-deep neutral-wash surface)

# Resolve INZSH_SURFACE_MODE into `_inzsh_surface_mode_resolved`. Unset, empty, misspelled,
# wrong case, padded with a stray space — all of it lands on `alternate`. A prompt with an
# unreadable mode name in the config still draws, and draws legibly.
#
# `lib/core/config.zsh` owns the knob and its answer is preferred, exactly as in
# `_inzsh_sep_style` below and for the same reason: it is the one that knows about registered
# defaults. The `case` repeats the enum rather than trusting whatever came back, because this
# file is independently sourceable.
_inzsh_surface_mode() {
  emulate -L zsh

  local want=${INZSH_SURFACE_MODE-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_SURFACE_MODE
    want=$REPLY
  fi

  typeset -g _inzsh_surface_mode_resolved=alternate
  case $want in
    (alternate|ramp|flat|hue) typeset -g _inzsh_surface_mode_resolved=$want ;;
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
      # alternate — odd positions on the cycle's first surface, even on its second. Index 1 is
      # surface-deep, so a prompt always opens on the far end of the ramp.
      #
      # `hue` lands here too, and deliberately: this is the assignment it falls back on for every
      # segment that declared no background of its own, and it is the one assignment that holds
      # the adjacency invariant with no further rule. A mode that decorates a positional
      # assignment wants the SAFEST positional assignment under it.
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

# ---------------------------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------------------------
#
# WHY THE ENTRY POINT BELOW IS NOT CALLED `_inzsh_render`.
#
# `lib/core/hooks.zsh` dispatches on that exact NAME — `(( ${+functions[_inzsh_render]} )) &&
# _inzsh_render` runs before every prompt — and the dispatch is live today. There are no segments
# until M3, so `_inzsh_segment_text` is empty, both sides build to nothing, and a function of that
# name would draw an EMPTY prompt over the user's real one from the moment this file is sourced.
# So the assembly is written, tested and shipped under a name the hook does not know, and nothing
# in this file assigns PROMPT or RPROMPT. Going live is one deliberate step at M3: fill the maps
# from real segments, define `_inzsh_render` over `_inzsh_render_build`, and assign there.
#
# The seam this half is built on: it FETCHES NOTHING. Text, foreground role and importance all
# arrive in associations the caller has already filled, so the builder is arithmetic, parameter
# expansion and string concatenation — no forks, no command substitution, no segment reaching out
# for its own data at draw time.

# The injected state. Three associations, keyed by the segment name exactly as it appears in
# `_inzsh_left` / `_inzsh_right`. Declared here and populated by nobody: segments fill them at M3.
# Declared without an assignment on purpose — `typeset -gA` over an existing association keeps
# what is in it, so re-sourcing the theme never empties a map a segment already wrote.
#
#   _inzsh_segment_text        SEGMENT → the prompt FRAGMENT to draw. Not plain text: a segment
#                              may carry `%F{…}` runs of its own — a status block draws three
#                              colours in one segment — and `_inzsh_width` measures around them.
#                              A segment with NO entry, or an empty one, is ABSENT: no block, and
#                              no separator either. Empty means unset here as it does everywhere.
#   _inzsh_segment_fg_role     SEGMENT → the semantic role its text takes. `text-body` by default.
#   _inzsh_segment_bg_role     SEGMENT → the background ROLE it asks for, read only by `hue` —
#                              see `_inzsh_render_hues`. Nothing by default, which means "give me
#                              whatever the position was going to give me".
#   _inzsh_segment_importance  SEGMENT → 1..3, what `ramp` reads. 2 by default, the middle of the
#                              ramp; `alternate`, `flat` and `hue` ignore it.
#   _inzsh_segment_priority    SEGMENT → the survival order, lower kept longer. Read through
#                              `_inzsh_priority_of`, which lets `INZSH_<SEG>_PRIORITY` override it.
typeset -gA _inzsh_segment_text
typeset -gA _inzsh_segment_fg_role
typeset -gA _inzsh_segment_bg_role
typeset -gA _inzsh_segment_importance
typeset -gA _inzsh_segment_priority

# What `dir` books when the row is fitted, rather than the width it currently happens to be. It is
# the one segment that shortens instead of vanishing, so what it truly needs is the ellipsis, one
# path component and the padding around them — everything past that is negotiable, and the
# truncation pass negotiates it. Four columns of CONTENT: the padding is added where the booking
# is made, from the resolved `INZSH_SEGMENT_PAD`, the same way every other block's is.
typeset -gi _inzsh_dir_reserved=4

# The visible width of the last build, in columns. Tracked as the string is assembled rather than
# measured off the finished one: the result is escape-laden and its width cannot be recovered from
# it. Declared here so a caller reading it before the first build gets 0 rather than an error.
typeset -g _inzsh_render_width=0

# The terminal width the prompt currently in `PROMPT` was built for. Written by `_inzsh_render`
# and read by `lib/core/resize.zsh`, which redraws on SIGWINCH only while this and `$COLUMNS`
# disagree — a window whose height changed emits the same signal and moves nothing the prompt
# draws. Declared here so a reader before the first draw gets 0, which no real terminal is, so the
# first resize after a load always redraws.
typeset -g _inzsh_render_cols=0

# ---------------------------------------------------------------------------------------------
# Separators
#
# The glyphs themselves live in `lib/core/tokens.zsh` — every mark the theme draws does, and the
# byte-spelling and the locale fallback live there with them. What is left here is the CHOOSING:
# which pair of them a side is drawn with.
#
# Three styles, and `INZSH_SEPARATOR_STYLE` picks one:
#
#   arrow    the default. The filled powerline wedges, U+E0B0 and its mirror U+E0B2.
#   round    the same ribbon with rounded caps, U+E0B4 and U+E0B6.
#   divider  a thin rule between blocks, U+2502, and no filled boundary at all.
#
# `arrow` and `round` are FILLED styles: the boundary IS the colour change, so a separator is
# only visible while the two blocks it sits between differ, and the surface invariant is the
# whole reason they do. `divider` draws its own boundary in its own ink and needs no such help,
# so it is exempt for exactly the reason `flat` is — see `_inzsh_render_surfaces`.
#
# NERD FONTS. The powerline glyphs live in the Unicode private-use area: only a Nerd Font draws
# them, and `_inzsh_nerd_font` answers 1, 0 or `unknown`. The decision here is that 0 resolves
# the style to `divider`, while 1 AND `unknown` draw the powerline.
#
# The asymmetry is deliberate and it follows `lib/core/detect.zsh`, which never INFERS a 0.
# Nothing inside a shell can prove a font is absent — the tools that could look are forks, on a
# machine that is not necessarily the one drawing the pixels — so the only way a 0 arrives is
# `INZSH_NERD_FONT=0`, a user reporting what is on their own screen. Honouring that is honouring
# a statement rather than a guess. `unknown`, by contrast, is most terminals, and degrading all
# of them would take the theme's own look away from the majority who do have the font, on the
# strength of a question this repo deliberately refuses to answer. What to tell the `unknown`
# user is `doctor`'s business: the policy is detect-and-WARN, and a warning is a diagnostic
# rather than a downgrade.
typeset -ga _inzsh_sep_styles
_inzsh_sep_styles=(arrow round divider)

# The pair the last resolve chose, one per side, and the style it chose them for. Declared with
# the ASCII values so that a caller reading them before the first resolve gets a drawable
# boundary rather than nothing; `_inzsh_separators` runs at the foot of this section and again
# on every build.
typeset -g _inzsh_sep_left='|'
typeset -g _inzsh_sep_right='|'
typeset -g _inzsh_sep_style_resolved=arrow

# Resolve INZSH_SEPARATOR_STYLE into `_inzsh_sep_style_resolved`. Unset, empty, misspelled, wrong
# case, padded with a stray space — all of it lands on `arrow`, exactly as `_inzsh_surface_mode`
# lands on `alternate`.
#
# `lib/core/config.zsh` owns the knob and validates it, and its answer is preferred because it is
# the one that knows about registered defaults. The `case` below repeats the enum rather than
# trusting whatever came back: this file is independently sourceable, and a config layer that
# never loaded — or one from an older bundle that never registered the knob — would otherwise
# hand back whatever the variable happened to hold.
_inzsh_sep_style() {
  emulate -L zsh

  local want=${INZSH_SEPARATOR_STYLE-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_SEPARATOR_STYLE
    want=$REPLY
  fi

  typeset -g _inzsh_sep_style_resolved=arrow
  case $want in
    (arrow|round|divider) _inzsh_sep_style_resolved=$want ;;
  esac

  # A style whose glyphs the terminal cannot draw is not the style that gets drawn.
  [[ ${_inzsh_nerd_font-unknown} == 0 ]] && _inzsh_sep_style_resolved=divider

  return 0
}

# `_inzsh_sep_left` and `_inzsh_sep_right` for the resolved style, read from the token layer's
# glyph table. Parameter operations only — this runs once per build, on the render path.
#
# The ASCII defaults are assigned FIRST, and they are what a render core sourced without a token
# layer draws: a prompt with plain boundaries beats a prompt with none. The rounded pair keeps
# its mirror even there, which is the one property that style exists for.
_inzsh_separators() {
  emulate -L zsh

  _inzsh_sep_style

  local lkey=sep-left rkey=sep-right
  typeset -g _inzsh_sep_left='|'
  typeset -g _inzsh_sep_right='|'

  case $_inzsh_sep_style_resolved in
    (round)
      lkey=sep-left-round
      rkey=sep-right-round
      _inzsh_sep_left=')'
      _inzsh_sep_right='('
      ;;
    (divider)
      # One glyph, both sides. A thin rule has no point to face, so it does not mirror — which
      # is itself the difference between a rule and a wedge.
      lkey=divider
      rkey=divider
      ;;
  esac

  [[ ${(t)_inzsh_glyph} == association* ]] || return 0
  [[ -n ${_inzsh_glyph[$lkey]} ]] && _inzsh_sep_left=${_inzsh_glyph[$lkey]}
  [[ -n ${_inzsh_glyph[$rkey]} ]] && _inzsh_sep_right=${_inzsh_glyph[$rkey]}

  return 0
}

_inzsh_separators

# ---------------------------------------------------------------------------------------------
# The padding — how many columns of air sit either side of a block's text. One by default, which
# is the block shape the theme shipped with; `0` packs the row and `4` spreads it. Bounded above
# because padding is LITERAL SPACES, the one thing in a prompt that can push a row past the edge
# of the terminal: a bound the validator states is a wrap nobody can configure into existence,
# which is the same argument `_inzsh_render_gap` makes about the gap.
typeset -g _inzsh_render_pad_resolved=1

# Resolve INZSH_SEGMENT_PAD into `_inzsh_render_pad_resolved`. Unset, empty, out of bounds,
# unparseable — all of it lands on 1, exactly as `_inzsh_surface_mode` lands on `alternate` and
# for the same reason. The pattern repeats the validator rather than trusting what came back,
# because this file is independently sourceable; the arithmetic assignment normalises `+3` and
# `03` to the number they name.
_inzsh_render_pad() {
  emulate -L zsh

  local want=${INZSH_SEGMENT_PAD-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_SEGMENT_PAD
    want=$REPLY
  fi

  typeset -g _inzsh_render_pad_resolved=1
  if [[ $want == (|+)<-> ]] && (( want <= 4 )); then
    (( _inzsh_render_pad_resolved = want ))
  fi

  return 0
}

# `%K{value}` or `%F{value}` for channel $1 (`K` or `F`) and colour $2, in REPLY. An EMPTY value
# resets the channel instead — `%k` / `%f`. That case is real: `_inzsh_seg_color` answers empty
# when neither the role nor its fallback exists, and `%K{}` reaches the screen as literal braces.
# A missing role must cost colour, never legibility.
_inzsh_render_escape() {
  emulate -L zsh

  if [[ -n $2 ]]; then
    typeset -g REPLY="%$1{$2}"
  else
    typeset -g REPLY="%${(L)1}"
  fi

  return 0
}

# The surface assignment for $1 visible segments, importances in $2.., in `reply` — with the
# invariant enforced rather than assumed.
#
# `_inzsh_surface_assign` resolves the mode itself, so the check here is on the ASSIGNMENT and not
# on the knob: `_inzsh_config_guarded INZSH_SURFACE_MODE …` would re-read the knob and could only
# vouch for the name, never for the sequence it produced. What must hold is that no two adjacent
# blocks share a surface, and only the sequence can answer that.
#
# A mode that produced an invalid one is dropped for `alternate`, which holds the invariant by
# construction. If alternate is invalid too — `_inzsh_surface_cycle` clobbered, a bundle half
# sourced — the assignment is drawn as it stands: a prompt whose separators are hard to see is a
# worse prompt, and no prompt at all is not a prompt. Always status 0.
# WHICH invariant applies is a property of the SEPARATOR and not of the surface mode, so the mode
# an assignment is judged under is not always the mode it was drawn with. A filled boundary is
# only visible while the two blocks differ; `divider` has no filled boundary at all, so equal
# neighbours there are as harmless as they are under `flat`. A `divider` prompt is therefore put
# to the invariant AS `flat` — the exemption `_inzsh_surfaces_valid` already grants, asked for the
# reason it already grants it, rather than a second exemption bolted onto the predicate.
#
# The answer is in REPLY. Written once and asked twice — by `_inzsh_render_surfaces` and by
# `_inzsh_render_hues` — because two copies of a rule is one copy too many, and the copy that
# drifts is always the one further from the sentence.
#
# The mode is READ rather than re-resolved: `_inzsh_surface_mode_resolved` is the mode the
# assignment in hand was actually drawn with, and that is the one its adjacency has to be judged
# under. Re-reading the knob here would judge an assignment against a mode that did not produce
# it — which is exactly the confusion `_inzsh_render_surfaces` avoids by checking the sequence
# rather than the knob.
_inzsh_render_fill_mode() {
  emulate -L zsh

  _inzsh_sep_style

  typeset -g REPLY=$_inzsh_surface_mode_resolved
  [[ $_inzsh_sep_style_resolved == divider ]] && typeset -g REPLY=flat

  return 0
}

_inzsh_render_surfaces() {
  emulate -L zsh

  _inzsh_surface_assign "$@"

  _inzsh_render_fill_mode
  _inzsh_surfaces_valid "$REPLY" "${reply[@]}" && return 0

  local INZSH_SURFACE_MODE=alternate
  _inzsh_surface_assign "$1"

  return 0
}

# `_inzsh_render_hues <segment>…` — the backgrounds actually drawn, in `reply`, given the
# positional assignment already in `reply` and the visible segments in drawn order. Outside `hue`
# the positional assignment is the answer and this returns it untouched.
#
# WHAT THE MODE IS FOR. `alternate`, `ramp` and `flat` are POSITIONAL: the renderer owns every
# background, which is what makes the adjacency invariant hold by construction. A segment that
# could claim a fill under those would be a second place surfaces are decided, and the first thing
# to put a hole in the one property the render core is arranged around. `hue` is the mode that
# hands that decision over — `_inzsh_segment_bg_role` is read here and nowhere else, and outside
# this mode the way to pin one block is `INZSH_<SEGMENT>_BG`, which has always worked and still
# does.
#
# HOW THE INVARIANT SURVIVES A COLOUR THAT WAS CHOSEN RATHER THAN ASSIGNED. It stops being
# automatic the moment two segments may name the same role, so it is enforced rather than argued,
# left to right, one settled neighbour at a time:
#
#   1. a segment takes the background it declared, or the positional one if it declared none;
#   2. where that repeats the background already settled on its LEFT, the declaration is given up
#      and the positional surface taken instead — a segment's colour is worth less than the
#      boundary beside it, and the positional one is the assignment the invariant was built for;
#   3. where the positional surface repeats too, it walks the cycle until it does not, which is
#      the bump `ramp` already uses and terminates for the same reason: a bump always lands on a
#      different entry, and there are three.
#
# Left-anchored on purpose: position 1 always keeps what it asked for, and every later decision is
# judged against a neighbour that has already settled, so one pass is enough.
# `_inzsh_surfaces_valid` is then asked over the finished sequence — the rule above should make
# that a formality, and it is asked anyway because the predicate is the invariant and this
# function is only an argument about it. Where it says no, every declaration is dropped and the
# positional assignment stands, which came out of `_inzsh_render_surfaces` valid.
#
# Parameter operations only: this runs on the render path, once per side, no forks.
_inzsh_render_hues() {
  emulate -L zsh

  local -a surfaces=("${reply[@]}")

  # Resolved here rather than read, because this is a stage of its own and whether the map is
  # consulted at all is the CONFIG's answer — the same re-read every knob in this file gets, so
  # `INZSH_SURFACE_MODE=hue` typed at a prompt takes effect at the next one.
  _inzsh_surface_mode
  [[ $_inzsh_surface_mode_resolved == hue ]] || return 0

  _inzsh_render_fill_mode
  local mode=$REPLY

  [[ ${(t)_inzsh_segment_bg_role} == association* ]] || return 0

  local -i n=${#surfaces}
  local -a drawn=()
  local -i i idx turns
  local want

  for (( i = 1; i <= n; i++ )); do
    want=${_inzsh_segment_bg_role[${@[i]}]:-${surfaces[i]}}

    if (( i > 1 )) && [[ $mode != flat && $want == ${drawn[i-1]} ]]; then
      # The bump is bounded by the cycle's own length rather than trusting it to terminate: a
      # clobbered or half-sourced `_inzsh_surface_cycle` would otherwise divide by zero
      # mid-render. Running out of turns leaves the pair equal, the predicate below says so,
      # and the positional assignment stands.
      want=${surfaces[i]}
      turns=${#_inzsh_surface_cycle}
      while (( turns-- > 0 )) && [[ $want == ${drawn[i-1]} ]]; do
        idx=${_inzsh_surface_cycle[(Ie)$want]}
        want=${_inzsh_surface_cycle[idx % ${#_inzsh_surface_cycle} + 1]}
      done
    fi

    drawn+=$want
  done

  _inzsh_surfaces_valid "$mode" "${drawn[@]}" || return 0

  typeset -ga reply
  reply=("${drawn[@]}")

  return 0
}

# `_inzsh_render_build <side>` — the assembled prompt string for `left` or `right`, in REPLY, with
# its visible width in `_inzsh_render_width`. `reply` is clobbered; read it before building.
#
# The order comes from `_inzsh_left` / `_inzsh_right`, which `_inzsh_rank_split` has already
# sorted. This function never re-sorts, never re-ranks and never writes either array.
#
# An empty side, a side with nothing visible, and a side name that is neither `left` nor `right`
# all yield an empty REPLY, a width of 0 and status 0 — nothing to draw is not an error, the same
# rule the sorter and the surface assigner follow. Nothing is emitted in that case, not even a
# reset escape: an "empty" prompt that still writes `%f%k` is an empty prompt with an escape in
# it.
#
# A block is `<pad><text><pad>`, `INZSH_SEGMENT_PAD` columns of padding either side (one by
# default), so a block is `_inzsh_width` of its text plus twice the resolved padding. A side of
# n visible segments draws n separators, not n-1:
# the extra one is the cap the ribbon ends (left) or starts (right) with, over the terminal's own
# background.
#
# CHAINING. A separator is one cell carrying two colours. The wedge's ink — its FOREGROUND — fills
# the flat-edge side of the cell and the cell's own BACKGROUND shows through the pointed side, so
# the ribbon reads as continuous when the ink is the block on the flat side and the background is
# the block on the point side. The two sides therefore run OPPOSITE WAYS, because their ribbons
# open at opposite ends.
#
# The rule is about the two COLOURS and not about the shape between them, so it is the same rule
# for all three separator styles: `round` swaps a wedge for a semicircle with its mass on the
# same side, and `divider` draws a rule that needs no colour change at all but is chained
# identically so that a style is never a second code path. Only the glyph moves.
#
#   LEFT — starts at the left edge, ends in open terminal. The wedge points right (U+E0B0) and
#   each separator FOLLOWS its block. `>` below is that glyph:
#
#     [  A  ]>[  B  ]>[  C  ]>
#            fg=bgA  fg=bgB  fg=bgC
#            bg=bgB  bg=bgC  bg=term
#
#     between i and i+1:  foreground = bg[i]      background = bg[i+1]
#     after the last:     foreground = bg[n]      background = the terminal's own (`%k`)
#
#   RIGHT — ends at the right edge, OPENS on the left. The wedge points left (U+E0B2) and each
#   separator PRECEDES its block, so the cap is the FIRST one and not the last:
#
#     <[  A  ]<[  B  ]<[  C  ]
#     fg=bgA  fg=bgB  fg=bgC
#     bg=term bg=bgA  bg=bgB
#
#     between i and i+1:  foreground = bg[i+1]    background = bg[i]
#     before the first:   foreground = bg[1]      background = the terminal's own (`%k`)
#
#   Worked example, three right-prompt segments A B C in render order, one piece per line:
#
#     %k%F{bgA}<              cap: over the terminal's own background, inked with A's fill
#     %K{bgA}%F{fgA} A        A's block
#     %K{bgA}%F{bgB}<         the A|B boundary: sits on A's fill, inked with B's
#     %K{bgB}%F{fgB} B        B's block
#     %K{bgB}%F{bgC}<         the B|C boundary: sits on B's fill, inked with C's
#     %K{bgC}%F{fgC} C        C's block, hard against the right edge
#     %f%k                    both channels closed
#
#   Read as one rule: the ink is always the background of the block on the side the point faces
#   AWAY from, and the cell's background is always the block the point faces INTO. Left points
#   forward, right points backward; everything else is the same sentence.
#
# Degradation. `lib/core/layout.zsh` and `lib/core/tokens.zsh` are looked up at call time, never
# at source time, so this file stays independently sourceable and the dependency stays one-way.
# Without the token layer the blocks draw uncoloured rather than not at all; without the layout
# layer the width comes back 0, which every consumer already reads as "unknown", which every
# consumer already treats as "assume room".
_inzsh_render_build() {
  emulate -L zsh
  setopt extended_glob

  typeset -g REPLY=
  typeset -g _inzsh_render_width=0

  local -a order
  case $1 in
    (left)  order=("${_inzsh_left[@]}")  ;;
    (right) order=("${_inzsh_right[@]}") ;;
    (*)     return 0 ;;
  esac

  # Pass one: who is visible. Done before anything is assigned or drawn, which is what keeps a
  # segment that has no text from leaving a separator behind — it never enters the run, so there
  # is no boundary for one to sit on and no surface spent on it.
  local segment
  local -a visible texts importances
  for segment in "${order[@]}"; do
    [[ -n ${_inzsh_segment_text[$segment]-} ]] || continue
    visible+=("$segment")
    texts+=("${_inzsh_segment_text[$segment]}")
    importances+=("${_inzsh_segment_importance[$segment]:-2}")
  done

  local -i n=${#visible}
  (( n )) || return 0

  # The style is resolved before the surfaces are, because it decides which invariant they are
  # held to, and re-read on every build for the same reason the surface mode is: a knob is
  # whatever the user's shell says right now, and the next prompt is when it takes effect. The
  # padding follows the same rule; `${(l:pad:):-}` is `pad` spaces, and none at 0.
  _inzsh_separators
  _inzsh_render_pad
  local -i pad=$_inzsh_render_pad_resolved
  local air=${(l:pad:):-}

  _inzsh_render_surfaces $n "${importances[@]}"
  _inzsh_render_hues "${visible[@]}"
  local -a surfaces=("${reply[@]}")

  local -i colour=${+functions[_inzsh_seg_color]}
  local -i measure=${+functions[_inzsh_width]}

  # Pass two: resolve both channels per segment and cache the escapes. `_inzsh_seg_color` is the
  # one place the precedence lives, so `INZSH_<SEG>_BG` and `INZSH_<SEG>_FG` keep working here for
  # free rather than being re-derived. Three escapes per segment, because the background is needed
  # twice over — once to fill the block, once as the ink of a separator beside it.
  #
  # A name that cannot form a variable is asked nothing. `_inzsh_seg_color` reads
  # `INZSH_<NAME>_BG` through `${(P)…}`, and `${(P)}` on something that is not an identifier is a
  # fatal error mid-render — the same trap `_inzsh_mincols_of` guards in `lib/core/layout.zsh`.
  # A segment named that way is a theme bug, not a user one, and it costs its colour here rather
  # than costing the whole prompt.
  local -a fill ink face
  local bg fg
  local -i i
  for (( i = 1; i <= n; i++ )); do
    bg=''
    fg=''
    if (( colour )) && [[ ${visible[i]} == [A-Za-z_][A-Za-z0-9_]# ]]; then
      _inzsh_seg_color "${visible[i]}" bg "${surfaces[i]}" surface
      bg=$REPLY
      # THE FOREGROUND FOLLOWS THE FILL, and it does so without a second map. The design system
      # already pairs every fill with the ink that goes on it — `accent`/`on-accent`,
      # `negative`/`on-negative`, five slots per state — so the ink a block wants is `on-` its own
      # background, and where the role layer has no such twin the segment's own foreground is the
      # answer. That is exactly the distinction between the two kinds of background a block can
      # end up with: no SURFACE role has an `on-` twin, so a positional block keeps the ink it
      # registered and this line costs one hash miss; a segment that declared a FILL under `hue`
      # gives its ink up to that fill's, which is the only way `on-negative` ends up over madder
      # rather than over a surface it cannot be read on.
      _inzsh_seg_color "${visible[i]}" fg "on-${surfaces[i]}" \
        "${_inzsh_segment_fg_role[${visible[i]}]:-text-body}"
      fg=$REPLY
    fi
    _inzsh_render_escape K "$bg"; fill[i]=$REPLY
    _inzsh_render_escape F "$bg"; ink[i]=$REPLY
    _inzsh_render_escape F "$fg"; face[i]=$REPLY
  done

  local glyph=$_inzsh_sep_left
  [[ $1 == right ]] && glyph=$_inzsh_sep_right

  local -i sep=0
  if (( measure )); then
    _inzsh_width_raw "$glyph"
    sep=$REPLY
  fi

  # Pass three: draw, accumulating the width as the pieces go on.
  local drawn=''
  local -i used=0
  if [[ $1 == left ]]; then
    for (( i = 1; i <= n; i++ )); do
      drawn+="${fill[i]}${face[i]}${air}${texts[i]}${air}"
      if (( i < n )); then
        drawn+="${fill[i+1]}${ink[i]}${glyph}"
      else
        drawn+="%k${ink[i]}${glyph}"
      fi
      if (( measure )); then
        _inzsh_width "${texts[i]}"
        _inzsh_width_add used $REPLY
        _inzsh_width_add used $(( 2 * pad + sep ))
      fi
    done
  else
    for (( i = 1; i <= n; i++ )); do
      if (( i == 1 )); then
        drawn+="%k${ink[1]}${glyph}"
      else
        drawn+="${fill[i-1]}${ink[i]}${glyph}"
      fi
      drawn+="${fill[i]}${face[i]}${air}${texts[i]}${air}"
      if (( measure )); then
        _inzsh_width "${texts[i]}"
        _inzsh_width_add used $REPLY
        _inzsh_width_add used $(( 2 * pad + sep ))
      fi
    done
  fi

  # Close both channels. A prompt that leaves a background open colours the line the user types.
  drawn+='%f%k'

  typeset -g REPLY=$drawn
  typeset -g _inzsh_render_width=$used

  return 0
}

# ---------------------------------------------------------------------------------------------
# The shape — one line or two
#
# TWO LINES BY DEFAULT. The segment row is a ribbon of blocks and it grows with the repository,
# the virtualenv and the branch name; the line you type on should not move with it. So the
# segments take a row of their own and the input starts at column 1 of the next one, behind one
# short marker. A command is then always typed in the same place, and a pasted transcript wraps
# at the same column it was typed at. `INZSH_PROMPT_LINES=1` puts it all back on one row for
# anyone who would rather spend the row than the width.
#
# WHERE THE RIGHT PROMPT GOES, and why it is not `RPROMPT` here. zsh draws `RPROMPT` on the LAST
# line of a multi-line prompt — verified on a real terminal in `test/ui/test_prompt_shape.py` —
# which would put the clock and the prayer time beside the marker, on the line the user is
# typing into, where they would be overwritten by a long command line. They belong on the
# segment row. So in two-line mode the right side is PADDED INTO the first line and `RPROMPT` is
# left empty: the padding is `COLUMNS` minus two widths this file already tracked, so it costs
# one subtraction and no measuring pass. Where the two sides do not both fit — a narrow terminal,
# an unknown `COLUMNS` — the right side falls back to `RPROMPT` and lands beside the marker,
# because a right prompt in the wrong place is still better than one that vanished.
typeset -g _inzsh_prompt_lines_resolved=2

# Resolve INZSH_PROMPT_LINES into `_inzsh_prompt_lines_resolved`. Unset, empty, `3`, `two` — all
# of it lands on 2, exactly as `_inzsh_surface_mode` lands on `alternate` and for the same
# reason. The `case` repeats the enum rather than trusting what came back, because this file is
# independently sourceable.
_inzsh_render_lines() {
  emulate -L zsh

  local want=${INZSH_PROMPT_LINES-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_PROMPT_LINES
    want=$REPLY
  fi

  typeset -g _inzsh_prompt_lines_resolved=2
  case $want in
    (1|2) _inzsh_prompt_lines_resolved=$want ;;
  esac

  return 0
}

# ---------------------------------------------------------------------------------------------
# The padding, and the guard under it
#
# The padding is LITERAL SPACES, which makes it the one thing in the prompt that can push a row
# past the edge of the terminal. A row that overflows does not merely look wrong: it WRAPS, and a
# wrapped prompt is redrawn as several rows of the same ribbon, which is issue #190 as the user
# reported it. Two functions, because the answer is arrived at twice over — the arithmetic that
# proposes a gap, and the measurement that accepts or refuses the row it produced.

# `_inzsh_render_gap <cols> <left-width> <right-width>` → REPLY: how many columns of PADDING go
# between the two sides of the segment row, or 0 for "do not pad".
#
# One column is kept back at the right edge, which is where zsh puts `RPROMPT` itself — filling
# the last cell is the classic off-by-one that turns a two-row prompt into a three-row one on a
# terminal that wraps eagerly, and the marker row below already keeps the same column back for
# the cursor.
#
# Everything that is not a number is refused rather than coerced. `$COLUMNS` must be a positive
# integer — unknown means no arithmetic can right-align against it, the same reading
# `lib/core/layout.zsh` gives it — and both widths must be non-negative integers. A `local -i`
# would silently turn `abc` into 0 and pad the row to the full width of the terminal.
#
# A gap of 0 is not a failure. `_inzsh_render` has the degradation for it — the right side goes
# to `RPROMPT` and lands beside the marker on row two, which is a right prompt in the wrong place
# rather than one that vanished. Always status 0.
_inzsh_render_gap() {
  emulate -L zsh

  typeset -g REPLY=0

  [[ $1 == <1-> && $2 == <-> && $3 == <-> ]] || return 0

  local -i gap=$(( $1 - $2 - $3 - 1 ))
  (( gap >= 1 )) || return 0

  typeset -g REPLY=$gap

  return 0
}

# `_inzsh_render_row_fits <row> <cols>` — status 0 iff that row can be drawn on a terminal that
# wide without wrapping.
#
# THE ROW IS MEASURED, NOT ARGUED ABOUT. `left_width + gap + right_width <= cols - 1` is true by
# construction of the gap, so restating it would gate on the arithmetic's own opinion of itself
# and could never fire. What can be wrong is the arithmetic's INPUTS: `_inzsh_render_width` is
# accumulated as a side effect of assembly, it is 0 both for "nothing was drawn" and for "there
# was no `_inzsh_width` in this shell to measure with" — a render core sourced without the layout
# layer, which this file supports on purpose — and a separator or a block that stopped being
# accounted for would be invisible to every check made of the numbers. So the finished string is
# measured, once, and that is a different question from the one the gap answered.
#
# This is `_inzsh_surfaces_valid`'s relationship to `_inzsh_render_surfaces`, in the other half of
# the file: the predicate is the invariant, and the function that produced the candidate is only
# an argument about it.
#
# A guard that CANNOT answer says no. Without `_inzsh_width` there is no way to know how wide the
# row is, and "I could not check" has to read as "do not trust this" — the rule
# `lib/core/config.zsh` states for its own guards, for the same reason: refusing to vouch costs a
# fallback, vouching wrongly costs a wrapped prompt.
#
# It costs one measuring pass over the assembled row, which is 0.06 ms on a 160-column prompt —
# 2% of the warm render and a fifth of a percent of the house budget.
_inzsh_render_row_fits() {
  emulate -L zsh

  (( ${+functions[_inzsh_width]} )) || return 1
  [[ $2 == <1-> ]] || return 1

  _inzsh_width "$1"

  (( REPLY <= $2 - 1 ))
}

# `_inzsh_render_paint <role> <text>` → REPLY. One helper, for one reason: an unresolved role
# must never reach the prompt as `%F{}`, which is a broken escape zsh prints verbatim and
# exactly what a bundle loaded without the token layer would produce. No role, no colour, same
# text. `_inzsh_role` is read directly rather than through `_inzsh_seg_color`, which would
# invent `INZSH_MARKER_FG`-shaped knobs as a side effect of asking; the marker is already
# replaceable whole through `INZSH_PROMPT_MARKER`.
_inzsh_render_paint() {
  emulate -L zsh

  local color=${_inzsh_role[$1]-}
  if [[ -n $color ]]; then
    typeset -g REPLY="%F{$color}$2%f"
  else
    typeset -g REPLY=$2
  fi

  return 0
}

# The stand-in, for a render core sourced without a token layer. Assigned first and overwritten
# from the glyph table at call time, the same way `_inzsh_separators` treats its ASCII pair: a
# marker that cannot degrade to one ASCII column is a marker that breaks a single-byte locale.
typeset -g _inzsh_render_marker_ascii='>'

# The second line's marker, in REPLY, coloured and ready to concatenate.
#
# WHAT IT SIGNALS, and what it deliberately does not. The marker takes the `negative` role when
# the last command failed and `accent` when it did not — and it changes NOTHING ELSE. The glyph
# stays the same, and no number is drawn. That is the whole point: `lib/segments/retval.zsh`
# already carries the failure as a glyph and a status (`✕ 1`, `✕ SIGINT`), on the row above, and
# a second copy of it beside the cursor would be the same fact twice in a prompt whose stated
# goal is calm. So the marker REPEATS in colour what the retval block has already said in a
# glyph — the same relationship `_inzsh_prompts_sprompt` has between its glyphs and its colours —
# and the house rule that colour is never the only signal is kept by the block, not by the
# marker. A user who hides the retval segment has chosen not to be told; the marker is not the
# place to overrule that.
#
# `INZSH_PROMPT_MARKER` replaces the mark verbatim, with the same set-but-empty rule as
# `INZSH_PS2`: an `INZSH_PROMPT_MARKER=` left in a zshrc falls through to the theme's own rather
# than blanking the line you type on. The colouring still applies to whatever it holds.
_inzsh_render_marker() {
  emulate -L zsh

  local mark=$_inzsh_render_marker_ascii
  if [[ ${(t)_inzsh_glyph} == association* && -n ${_inzsh_glyph[prompt]} ]]; then
    mark=${_inzsh_glyph[prompt]}
  fi

  local override=${INZSH_PROMPT_MARKER-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_PROMPT_MARKER
    override=$REPLY
  fi
  [[ -n $override ]] && mark=$override

  # The capture in `lib/core/hooks.zsh`, never `$?` — by the time this runs, `$?` is the status
  # of whatever the render path did last, which is always 0 and always a lie. A capture that is
  # missing or unreadable reads as success: a marker must not claim a failure it cannot see.
  local -i last=0
  [[ ${_inzsh_last_status-0} == <-> ]] && last=${_inzsh_last_status-0}

  local role=accent
  (( last )) && role=negative

  _inzsh_render_paint "$role" "$mark"

  return 0
}

# The knobs this file reads, declared where they are read — the pattern `lib/segments/git.zsh`
# follows. Guarded, because this file is independently sourceable and the config layer may not
# be in the shell at all.
#
# `INZSH_PROMPT_MARKER` registers an EMPTY default for the reason `INZSH_PS2` does: there is no
# value that means "the theme's own", there is only not setting it.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_PROMPT_LINES  'enum:1|2'  2
  _inzsh_config_register INZSH_PROMPT_MARKER any         ''
  _inzsh_config_register INZSH_SEGMENT_PAD   'int:0:4'   1
fi

# ---------------------------------------------------------------------------------------
# The draw. This is the function `lib/core/hooks.zsh` dispatches to on every precmd — the name
# is the contract, and until this file defined one the dispatch was a deliberate no-op.
#
# Order matters and is not arbitrary:
#   1. every registered segment builds its own text, from state injected by its caller;
#   2. the width filter drops whoever does not fit THIS terminal, before ranks are read, so a
#      hidden segment never reaches the sorter and never spends a surface;
#   3. the rank sort decides side and order over exactly the survivors;
#   4. each side is assembled, and only then is a prompt parameter assigned.
#
# `_inzsh_rank_split` answers in `reply`, which `_inzsh_layout_filter` also uses, so the
# survivors are copied out before the split runs. Getting that wrong loses the filter's answer.
_inzsh_render() {
  emulate -L zsh
  setopt extended_glob

  [[ -o interactive ]] || return 0

  # The width this draw is for, published before anything is built. `lib/core/resize.zsh` reads
  # it to tell a resize that moved the prompt from one that did not, and a draw that is about to
  # happen is a draw for the width it is happening at.
  typeset -g _inzsh_render_cols=${COLUMNS:-0}

  # The glyph table, re-resolved before anything reads it, so the `INZSH_GLYPH_*` overrides are
  # whatever the user's shell says right now — the rule every knob in this tree follows, applied
  # to the one table every mark is read from. Guarded: this file is independently sourceable.
  (( ${+functions[_inzsh_glyphs_resolve]} )) && _inzsh_glyphs_resolve

  local segment builder
  for segment in ${(k)_inzsh_segment_defaults}; do
    builder=_inzsh_segment_${(L)segment}_build
    (( ${+functions[$builder]} )) && $builder
  done

  local -a candidates
  candidates=(${(ok)_inzsh_segment_defaults})
  _inzsh_layout_filter "${COLUMNS:-0}" "${candidates[@]}"

  local -a survivors
  survivors=("${reply[@]}")

  _inzsh_rank_split "${survivors[@]}"

  # What the terminal has room for. The filter above answered the user's explicit MINCOLS; this
  # answers the window. Blocks are measured as they will be DRAWN — the text plus the column of
  # padding either side, one separator between neighbours — and taken in priority order until the
  # side is full, so what survives is always a prefix of that order.
  #
  # PER SIDE, and after the rank split rather than before it, because the two sides do not always
  # share a row. When the gap will not hold them both the right side moves to `RPROMPT` and is
  # drawn beside the marker instead — it has somewhere else to go, and fitting the two together
  # would drop a block for failing to fit a row it was never going to be on. Each side is held to
  # the terminal on its own, which is the true constraint in the shape where they are apart and
  # still a necessary one in the shape where they are together.
  #
  # `dir` books only what it cannot give up rather than its full width, because it is the one
  # segment that shortens instead of vanishing. Reserving all of it would drop a block to make
  # room for a path that the pass below was about to truncate anyway, and the user would lose
  # their branch name to a directory name they were not going to be shown in full either way.
  #
  # One column is held back so the row is never flush against the right edge — the same spare the
  # truncation pass keeps, and for the same reason: a prompt that ends exactly on the last column
  # wraps on some terminals and not others.
  if (( ${+functions[_inzsh_layout_fit]} && ${+functions[_inzsh_width]} )); then
    _inzsh_separators
    _inzsh_render_pad
    _inzsh_width "$_inzsh_sep_left"
    local -i sep_width
    (( sep_width = REPLY + 1 ))

    local -i budget
    (( budget = ${COLUMNS:-0} - 1 ))

    local -a fit_args
    local side candidate
    local -i block
    for side in _inzsh_left _inzsh_right; do
      fit_args=()
      for candidate in ${(P)side}; do
        [[ -n ${_inzsh_segment_text[$candidate]-} ]] || continue
        _inzsh_width "${_inzsh_segment_text[$candidate]}"
        (( block = REPLY + 2 * _inzsh_render_pad_resolved ))
        [[ $candidate == DIR ]] &&
          (( block = _inzsh_dir_reserved + 2 * _inzsh_render_pad_resolved ))
        fit_args+=("$candidate" "$block")
      done

      (( ${#fit_args} )) || continue
      _inzsh_layout_fit "$budget" "$sep_width" "${fit_args[@]}"
      set -A $side "${reply[@]}"
    done
  fi

  _inzsh_render_build right
  local right=$REPLY
  local -i right_width=$_inzsh_render_width

  _inzsh_render_build left
  local left=$REPLY
  local -i left_width=$_inzsh_render_width

  # The path is the one segment that shortens instead of vanishing, so it absorbs whatever
  # overrun is left after everything else has taken its width. Measured rather than guessed: the
  # budget is the terminal minus the right prompt minus every other block on the left, and one
  # column spare so the cursor is never flush against the edge. Below one column there is no
  # useful path left, and the segment's own ladder answers empty — which is the honest result.
  #
  # Re-assembling the left side is the second and last pass. The numbers the ladder chooses are
  # placeholders until they are tuned on a real terminal.
  local -i cols=${COLUMNS:-0}
  if (( cols > 0 && left_width + right_width > cols )) &&
     [[ -n ${_inzsh_segment_text[DIR]-} ]]; then
    _inzsh_width "${_inzsh_segment_text[DIR]}"
    local -i dir_width=$REPLY
    local -i budget=$(( cols - right_width - (left_width - dir_width) - 1 ))
    (( budget < 0 )) && budget=0
    _inzsh_segment_dir_build "" "$budget"
    _inzsh_render_build left
    left=$REPLY
    left_width=$_inzsh_render_width
  fi

  # The shape, resolved per draw so that `INZSH_PROMPT_LINES=1` typed at a prompt takes effect
  # at the next one, with no re-source — the rule every other knob in this tree follows.
  _inzsh_render_lines

  # One line. Unchanged, and deliberately the shorter branch: a prompt is the one thing that may
  # never come back empty. Every segment can legitimately be absent at once — a clean directory
  # at a narrow width with nothing to report — and a blank PROMPT reads as a broken shell rather
  # than a calm one. `%#` is zsh's own marker and costs one column.
  if (( _inzsh_prompt_lines_resolved == 1 )); then
    [[ -n $left ]] && left+=' '
    typeset -g PROMPT=${left:-'%# '}
    typeset -g RPROMPT=$right
    return 0
  fi

  # Two lines. The segment row first, with the right side padded into it where both fit, then
  # the marker on a row of its own. `pad` is arithmetic over two widths this function already
  # holds, so placing the right side costs no second measuring pass.
  _inzsh_render_marker
  local marker=$REPLY

  local row=$left
  local rest=$right
  if [[ -n $right ]]; then
    # Proposed, then measured. The gap is arithmetic over two widths this function already holds,
    # so placing the right side costs no second measuring pass — and the row it produces is put
    # to `_inzsh_render_row_fits` before it is kept, because a row that overflows its terminal
    # wraps, and a wrapped prompt is redrawn as several rows of the same ribbon. Where the
    # measurement refuses, `rest` is left as it was and the right side goes to `RPROMPT`, which
    # is the degradation this branch already had for a gap that would not fit.
    _inzsh_render_gap "$cols" "$left_width" "$right_width"
    local -i pad=$REPLY

    if (( pad >= 1 )); then
      local padded=$left${(l:pad:):-}$right
      if _inzsh_render_row_fits "$padded" "$cols"; then
        row=$padded
        rest=
      fi
    fi
  fi

  # An empty segment row is not drawn at all. Two lines is a shape, not a quota: a row with
  # nothing on it is a blank line above the cursor, which is the noise this theme is against.
  if [[ -n $row ]]; then
    typeset -g PROMPT=$row$'\n'"$marker "
  else
    typeset -g PROMPT="$marker "
  fi
  typeset -g RPROMPT=$rest

  return 0
}
