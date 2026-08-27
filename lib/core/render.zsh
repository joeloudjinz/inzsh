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

# The drawn width of every row `_inzsh_render` kept, one entry per row, in the order the rows
# are drawn. `_inzsh_render_width` above is `_inzsh_render_build`'s own contract — one side, one
# build — and stays exactly that; it is not a meaningful answer for the whole prompt the moment
# there is more than one row, because it is left holding whichever build happened to run last.
# This array is what `lib/core/resize.zsh` sums a reflow height over instead (issue #223,
# `.claude/docs/DESIGN-prompt-rows.md` §5.3.1). Each entry is the width of the ASSEMBLED row —
# including its gap, where one was drawn — because that is the string that can wrap on screen,
# not one side of it. Declared here, empty, so a reader before the first render has nothing to
# sum rather than an unset-parameter error.
typeset -ga _inzsh_render_row_widths
_inzsh_render_row_widths=()

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

# `_inzsh_render_build <left|right> <segment>...` — the assembled prompt string for that side, in
# REPLY, with its visible width in `_inzsh_render_width`. `reply` is clobbered; read it before
# building.
#
# The segment list is INJECTED rather than read off a global, which is what lets a caller build a
# side without writing `_inzsh_left` / `_inzsh_right` first — the seam every segment already has,
# since none of them read their own state off a global either. `_inzsh_render`, today, still
# passes exactly what `_inzsh_rank_split` sorted into those two arrays, so nothing about the
# order changes: this function still never re-sorts, never re-ranks and never writes the arrays it
# used to read.
#
# The SIDE argument survives the change. It is not part of the list — it decides which way the
# separators chain and which edge the ribbon opens on, and that half of the contract is untouched.
# See the CHAINING block below for why left and right run opposite ways.
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

  local side=${1-}
  (( $# )) && shift
  case $side in
    (left|right) ;;
    (*)          return 0 ;;
  esac
  local -a order=("$@")

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
  [[ $side == right ]] && glyph=$_inzsh_sep_right

  local -i sep=0
  if (( measure )); then
    _inzsh_width_raw "$glyph"
    sep=$REPLY
  fi

  # Pass three: draw, accumulating the width as the pieces go on.
  local drawn=''
  local -i used=0
  if [[ $side == left ]]; then
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
# The shape — N rows, joined by newlines, plus the marker
#
# ONE ROW OF SEGMENTS BY DEFAULT, and a bare marker line below it — see `lib/core/rows.zsh` for
# how many rows there are and what sits on each one. The segment row is a ribbon of blocks and it
# grows with the repository, the virtualenv and the branch name; the line the marker sits on
# should not move with it, which is what `own` (the default) buys: input always starts at the
# same column. `INZSH_MARKER_ROW=inline` spends that row instead: the marker terminates the LAST
# drawn row and typing continues on it.
#
# WHERE THE RIGHT PROMPT GOES, and where it does not. zsh draws `RPROMPT` on the LAST line of a
# multi-line prompt — verified on a real terminal in `test/ui/test_prompt_shape.py` — so a real
# `RPROMPT` is only ever correct for the row that ends up being that last line, which is the last
# drawn row under `inline` and never under `own` (whose last physical line is the bare marker,
# not a segment row). Everywhere else the right side is PADDED IN with literal spaces and
# `RPROMPT` stays empty, which is what keeps the clock and the prayer time beside the segments
# they were placed with rather than beside the cursor.
#
# NOTHING RELOCATES ANY MORE. Where a row's two sides will not both fit, the OLD renderer moved
# the right side down to `RPROMPT`, beside the marker. This design removes that: a block that
# will not fit its row drops by priority, on that row, like every other block that does not fit —
# see `_inzsh_render_row` below. `RPROMPT` is not a fallback in this file any longer; it is only
# ever the mechanism zsh already uses to draw the last row's right side.
typeset -g _inzsh_prompt_lines_resolved=2

# Resolve the marker's placement into `_inzsh_prompt_lines_resolved` — kept in this shape, and
# under this name, because `lib/core/resize.zsh` still reads it, but only for the one fact it was
# always narrow enough to state correctly: whether the marker spends a bare physical line of its
# own (`own`) or terminates the last drawn row (`inline`). The ROW COUNT that used to ride along
# with it — "1 or 2 segment rows" — is `_inzsh_render_row_widths`'s job now (issue #223), and
# resize.zsh sums that separately rather than inferring it from this number. The mapping here is
# exact and loses nothing `resize.zsh` still uses this value for: `inline` is the old one-row
# shape, `own` the old two-row one, and `_inzsh_marker_row_resolved` already carries the whole of
# what is left to resolve, now that `INZSH_PROMPT_LINES` is gone — see `lib/core/rows.zsh`. This
# file restates only the fallback for the render core sourced without it, the same courtesy every
# guarded call in this file gives the layer under it.
_inzsh_render_lines() {
  emulate -L zsh

  typeset -g _inzsh_prompt_lines_resolved=2

  if (( ${+functions[_inzsh_marker_row_resolved]} )); then
    _inzsh_marker_row_resolved
    [[ $REPLY == inline ]] && _inzsh_prompt_lines_resolved=1
    return 0
  fi

  local want=${INZSH_MARKER_ROW-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_MARKER_ROW
    want=$REPLY
  fi
  [[ $want == inline ]] && _inzsh_prompt_lines_resolved=1

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
# A gap of 0 is not a failure. It means "these two, one immediately after the other, still fit
# with the one spare column kept" — a real, drawable answer, not a refusal — and it is what
# `_inzsh_render`'s join step falls through to bare when the LEFT side is empty (nothing to
# separate the right side FROM). Where the left side is not empty, 0 IS treated as "do not pad"
# there, because running two blocks together with no gap at all would look like one broken block:
# `_inzsh_render_row`'s own fit runs before this ever executes and drops right-hand content by
# priority so that case does not arise. Always status 0.
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

# The marker, in REPLY, coloured and ready to concatenate — on its own bare line under `own`,
# whatever line that ends up being over N drawn rows, or terminating the last drawn row under
# `inline`. Where it goes is `_inzsh_render`'s decision; this only resolves what it says.
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
#
# `INZSH_PROMPT_LINES` was registered here through v1.x, as the deprecated alias for
# `INZSH_MARKER_ROW` — `enum:1|2`, default `2`. `v2.0.0` retires it outright: the registration is
# gone, so a `.zshrc` that still sets it is no longer read by anything, exactly like any other
# name the registry has never heard of.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_PROMPT_MARKER any         ''
  _inzsh_config_register INZSH_SEGMENT_PAD   'int:0:4'   1
fi

# ---------------------------------------------------------------------------------------------
# Per-row fitting
#
# `_inzsh_layout_fit` already runs one priority walk for one side; a row needs it run for BOTH
# sides, and then — where the two together still will not fit — run again over the right side
# alone at a tighter budget, because that is the mechanism this design replaces `RPROMPT` with
# (see §4 of `.claude/docs/DESIGN-prompt-rows.md`, section "Fitting"). `dir` truncation is the
# last resort, unchanged in its own arithmetic from the single-row renderer this grew out of; it
# just reads the row it is asked about rather than the only one there used to be.

# `_inzsh_render_fit_args <segment>...` → `reply`: flattened `<name> <width>` pairs for
# `_inzsh_layout_fit`, one pass pulled out of the single-row renderer's own inline loop so it can
# run per side, per row, instead of twice in total. A segment with no text contributes nothing —
# there is no block to fit and no separator for one to sit beside — and `dir` is booked at its
# reserved floor rather than its current width, for the reason `_inzsh_dir_reserved` gives: it is
# the one segment that shortens instead of vanishing, and reserving its full width would drop a
# block to make room for a path the truncation pass was about to shorten anyway.
_inzsh_render_fit_args() {
  emulate -L zsh

  typeset -ga reply
  reply=()

  (( ${+functions[_inzsh_width]} )) || return 0

  _inzsh_render_pad
  local -i pad=$_inzsh_render_pad_resolved

  local candidate
  local -i block
  for candidate in "$@"; do
    [[ -n ${_inzsh_segment_text[$candidate]-} ]] || continue
    if [[ $candidate == DIR ]]; then
      (( block = _inzsh_dir_reserved + 2 * pad ))
    else
      _inzsh_width "${_inzsh_segment_text[$candidate]}"
      (( block = REPLY + 2 * pad ))
    fi
    reply+=("$candidate" "$block")
  done

  return 0
}

# `_inzsh_render_row <cols> <left-array-name> <right-array-name>` — fit and assemble ONE row
# against `<cols>`. The two array names are read with `${(P)}`, the idiom this tree already uses
# for a caller holding several rows of segment names rather than one pair of globals.
#
# Answers in `_inzsh_render_row_left` / `_inzsh_render_row_right` (the assembled strings, each
# ready to concatenate) and `_inzsh_render_row_left_width` / `_inzsh_render_row_right_width`
# (their measured widths) — nothing else. A caller that needs to know which segments survived
# reads the strings themselves; publishing the survivor lists too was tried and dropped; nothing
# ever read them, and an answer nobody reads is a second thing to keep correct for no reader.
#
# Three passes, in the order §4 of the design states:
#   1. `_inzsh_layout_fit`, per side, against `COLUMNS - 1` — unchanged in behaviour from the
#      single-row renderer, run twice per row instead of twice in total.
#   2. THE ROW'S OWN FIT. `_inzsh_render_gap` proposes a pad; where it will not hold — or where
#      the padded row still fails `_inzsh_render_row_fits`, the MEASURED guard rather than the
#      arithmetic's own opinion of itself — the right side drops by priority, at a budget one
#      column tighter than the gap needs, and the row is re-measured. NOTHING RELOCATES: a block
#      that will not fit is dropped, never moved to another row and never to `RPROMPT`, which is
#      the degradation this design removes (see the header comment above `_inzsh_render_lines`).
#      The walk always makes progress — a right side too wide for `cols - left - 2` is too wide
#      for the row it is being dropped for, so `_inzsh_layout_fit` sheds at least one block each
#      time through — so it terminates with the right side fitting or empty.
#   3. `dir` TRUNCATION absorbs whatever overrun the drop could not: it runs only when the two
#      widths still do not fit together, and only against the side `dir` is actually drawn on in
#      THIS row, which is what "budgeted against its own row" means once a row is not always row
#      one. The budget arithmetic itself is the single-row renderer's, unmoved.
_inzsh_render_row() {
  emulate -L zsh
  setopt extended_glob

  local -i cols=0
  [[ $1 == <-> ]] && cols=$1
  local left_name=$2 right_name=$3

  typeset -g _inzsh_render_row_left='' _inzsh_render_row_right=''
  typeset -gi _inzsh_render_row_left_width=0 _inzsh_render_row_right_width=0

  local -a left_list=("${(@P)left_name}")
  local -a right_list=("${(@P)right_name}")

  local -i budget=$(( cols - 1 ))
  local -i sep_width=0
  if (( ${+functions[_inzsh_width]} )); then
    _inzsh_separators
    _inzsh_width "$_inzsh_sep_left"
    (( sep_width = REPLY + 1 ))
  fi

  if (( ${+functions[_inzsh_layout_fit]} )); then
    _inzsh_render_fit_args "${left_list[@]}"
    _inzsh_layout_fit "$budget" "$sep_width" "${reply[@]}"
    left_list=("${reply[@]}")

    _inzsh_render_fit_args "${right_list[@]}"
    _inzsh_layout_fit "$budget" "$sep_width" "${reply[@]}"
    right_list=("${reply[@]}")
  fi

  _inzsh_render_build right "${right_list[@]}"
  local right_str=$REPLY
  local -i right_width=$_inzsh_render_width

  _inzsh_render_build left "${left_list[@]}"
  local left_str=$REPLY
  local -i left_width=$_inzsh_render_width

  # The row's own fit. `_inzsh_render_row_fits` — the measured guard, not the gap's own arithmetic
  # — is what actually stops the walk, because the arithmetic can only ever vouch for itself.
  while (( ${#right_list} )); do
    _inzsh_render_gap "$cols" "$left_width" "$right_width"
    if (( REPLY >= 1 )); then
      local candidate_row=$left_str${(l:REPLY:):-}$right_str
      _inzsh_render_row_fits "$candidate_row" "$cols" && break
    fi

    local -i right_budget=$(( cols - left_width - 2 ))
    (( right_budget < 0 )) && right_budget=0

    _inzsh_render_fit_args "${right_list[@]}"
    _inzsh_layout_fit "$right_budget" "$sep_width" "${reply[@]}"
    (( ${#reply} == ${#right_list} )) && break

    right_list=("${reply[@]}")
    _inzsh_render_build right "${right_list[@]}"
    right_str=$REPLY
    right_width=$_inzsh_render_width
  done

  # `dir` truncation, on whichever side of THIS row it survived to. Only one side can hold it —
  # claiming and deriving both place a segment once — so at most one of the two branches runs.
  if (( cols > 0 && left_width + right_width > cols )) &&
     [[ -n ${_inzsh_segment_text[DIR]-} ]]; then
    if (( ${left_list[(Ie)DIR]} )); then
      _inzsh_width "${_inzsh_segment_text[DIR]}"
      local -i dir_width=$REPLY
      local -i dir_budget=$(( cols - right_width - (left_width - dir_width) - 1 ))
      (( dir_budget < 0 )) && dir_budget=0
      _inzsh_segment_dir_build "" "$dir_budget"
      _inzsh_render_build left "${left_list[@]}"
      left_str=$REPLY
      left_width=$_inzsh_render_width
    elif (( ${right_list[(Ie)DIR]} )); then
      _inzsh_width "${_inzsh_segment_text[DIR]}"
      local -i dir_width=$REPLY
      local -i dir_budget=$(( cols - left_width - (right_width - dir_width) - 1 ))
      (( dir_budget < 0 )) && dir_budget=0
      _inzsh_segment_dir_build "" "$dir_budget"
      _inzsh_render_build right "${right_list[@]}"
      right_str=$REPLY
      right_width=$_inzsh_render_width
    fi
  fi

  typeset -g _inzsh_render_row_left=$left_str
  typeset -g _inzsh_render_row_right=$right_str
  typeset -gi _inzsh_render_row_left_width=$left_width
  typeset -gi _inzsh_render_row_right_width=$right_width

  return 0
}

# ---------------------------------------------------------------------------------------
# The draw. This is the function `lib/core/hooks.zsh` dispatches to on every precmd — the name
# is the contract, and until this file defined one the dispatch was a deliberate no-op.
#
# Order matters and is not arbitrary:
#   1. the rows are resolved FIRST, over every registered segment, before a single one of them
#      builds any text — `_inzsh_rows_resolve` decides membership from rank and `MINCOLS` alone
#      (see `lib/core/rows.zsh`), so it needs nothing this step would otherwise have to build
#      just to throw away. A segment that lands nowhere is touched by nothing below: not built,
#      not measured, not read a second time by anything in this file.
#   2. only the segments that landed on some row build their own text, from state injected by
#      their caller — in registration order, for the same determinism the old single-row split
#      always had;
#   3. each row is fitted and assembled independently by `_inzsh_render_row`, above;
#   4. the marker is placed per `_inzsh_marker_row_resolved` and the rows are joined by
#      newlines, and only then is a prompt parameter assigned.
#
# `_inzsh_hidden` keeps meaning what it always has — "switched off by rank, at every width" — but
# is now computed from `_inzsh_rows_hidden`, `lib/core/rows.zsh`'s own record of the candidates
# its rank-zero drop removed, rather than recomputed here. Asking `_inzsh_rank_of` again for a
# segment `_inzsh_rows_resolve` already asked would be the exact re-read `_inzsh_rank_split_pairs`
# exists to rule out, paid here instead of there.
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

  local -i cols=${COLUMNS:-0}
  local -a candidates=(${(ok)_inzsh_segment_defaults})
  local -i row_count=0

  if (( ${+functions[_inzsh_rows_resolve]} )); then
    _inzsh_rows_resolve "$cols" "${candidates[@]}"
    row_count=$_inzsh_row_count
    _inzsh_hidden+=("${_inzsh_rows_hidden[@]}")
  else
    # Degradation for a render core sourced without `lib/core/rows.zsh` — everything derives onto
    # one row, exactly the split this file always did before rows existed, so the render core
    # stays independently sourceable the way every other feature in it does when the layer under
    # it is missing.
    typeset -ga _inzsh_row1_left _inzsh_row1_right
    local segment
    local -A ranks=()
    local -a visible=() hidden_now=()
    for segment in "${candidates[@]}"; do
      _inzsh_rank_of "$segment"
      if (( REPLY == 0 )); then
        hidden_now+=("$segment")
        continue
      fi
      ranks[$segment]=$REPLY
      visible+=("$segment")
    done

    local -a survivors=("${visible[@]}")
    (( ${+functions[_inzsh_layout_filter]} )) && {
      _inzsh_layout_filter "$cols" "${visible[@]}"
      survivors=("${reply[@]}")
    }

    local -a pairs=()
    for segment in "${survivors[@]}"; do
      pairs+=("${ranks[$segment]}" "$segment")
    done
    _inzsh_rank_split_pairs "${pairs[@]}"
    _inzsh_hidden+=("${hidden_now[@]}")

    _inzsh_row1_left=("${_inzsh_left[@]}")
    _inzsh_row1_right=("${_inzsh_right[@]}")
    (( ${#_inzsh_row1_left} || ${#_inzsh_row1_right} )) && row_count=1
  fi
  typeset -gi _inzsh_row_count=$row_count

  # `_inzsh_left` / `_inzsh_right` stay what they have always been: row one's membership BY
  # RANK, not what survived the fit. A segment a hook installs after `lib/core/hooks.zsh` — see
  # `lib/segments/duration.zsh`'s own precmd — asks `${_inzsh_right[(Ie)DURATION]}` to learn
  # whether it was PLACED on a side at all, before it has any text to be measured with; reading
  # the post-fit list here would answer that question with "no" on the very first command, when
  # there is nothing yet to fit.
  typeset -ga _inzsh_left _inzsh_right
  _inzsh_left=("${_inzsh_row1_left[@]}")
  _inzsh_right=("${_inzsh_row1_right[@]}")

  # Build only what will actually be drawn — the "switched off costs nothing" promise the
  # single-row renderer always kept (issue #185), extended over every row rather than just the
  # one there used to be.
  local -A drawn_set=()
  local -i n
  local ln rn seg builder
  local -a row_names
  for (( n = 1; n <= row_count; n++ )); do
    ln="_inzsh_row${n}_left"
    rn="_inzsh_row${n}_right"
    row_names=("${(@P)ln}" "${(@P)rn}")
    for seg in "${row_names[@]}"; do
      drawn_set[$seg]=1
    done
  done

  for seg in "${candidates[@]}"; do
    (( ${+drawn_set[$seg]} )) || continue
    builder=_inzsh_segment_${(L)seg}_build
    (( ${+functions[$builder]} )) && $builder
  done

  # The shape, resolved per draw so that `INZSH_MARKER_ROW` typed at a prompt takes effect at the
  # next one, with no re-source, the rule every other knob in this tree follows.
  _inzsh_render_lines
  local -i inline_marker=$(( _inzsh_prompt_lines_resolved == 1 ))

  _inzsh_render_marker
  local marker=$REPLY

  # Fit and assemble every resolved row. `lib/core/rows.zsh` only knows that NAMES were assigned
  # to a row — it fetches no segment text — so whether a row actually drew anything is a fact
  # this file discovers only now, from the strings `_inzsh_render_row` handed back. A row whose
  # every segment turned out to have no text, or dropped out of the fit entirely, is EMPTY and is
  # not kept: "two lines is a shape, not a quota" generalises to "N rows is a shape", and an empty
  # row in the middle would be a blank line between two others.
  local -a eff_left=() eff_right=() eff_left_w=() eff_right_w=()
  for (( n = 1; n <= row_count; n++ )); do
    ln="_inzsh_row${n}_left"
    rn="_inzsh_row${n}_right"
    _inzsh_render_row "$cols" "$ln" "$rn"

    [[ -z $_inzsh_render_row_left && -z $_inzsh_render_row_right ]] && continue

    eff_left+=("$_inzsh_render_row_left")
    eff_right+=("$_inzsh_render_row_right")
    eff_left_w+=("$_inzsh_render_row_left_width")
    eff_right_w+=("$_inzsh_render_row_right_width")
  done

  # Join the drawn rows, and place the marker. Under `inline` the LAST drawn row never gets its
  # right side padded in at all — zsh already draws a real `RPROMPT` on the last line of a
  # multi-line prompt, which is exactly where that row's right side is going regardless of what
  # this file does with a literal space — so it is finished below instead, with the marker and
  # `RPROMPT` rather than a pad. Every other row, and every row under `own`, is padded in here,
  # proposed then measured exactly as the single-row renderer always did it.
  local -i eff_count=${#eff_left} i pad
  local -a physical_rows=() row_widths=()
  local last_left='' last_right='' row_str padded
  local -i row_width
  for (( i = 1; i <= eff_count; i++ )); do
    if (( inline_marker && i == eff_count )); then
      last_left=${eff_left[i]}
      last_right=${eff_right[i]}
      continue
    fi

    row_str=${eff_left[i]}
    if [[ -n ${eff_right[i]} ]]; then
      if [[ -z ${eff_left[i]} ]]; then
        # A right-only row — legitimate under "override is per side" (§2.3) — has nothing to
        # pad AWAY FROM. `_inzsh_render_gap` demands a gap of at least 1 because with content on
        # BOTH sides a gap of 0 would run them together; with no left at all there is no
        # collision to avoid, and `_inzsh_render_row`'s own per-side fit already bounded this
        # string to `cols - 1` before handing it back, so it is measured and used bare rather
        # than dropped for a margin nothing needed.
        _inzsh_render_row_fits "${eff_right[i]}" "$cols" && row_str=${eff_right[i]}
      else
        _inzsh_render_gap "$cols" "${eff_left_w[i]}" "${eff_right_w[i]}"
        pad=$REPLY
        if (( pad >= 1 )); then
          padded=${eff_left[i]}${(l:pad:):-}${eff_right[i]}
          _inzsh_render_row_fits "$padded" "$cols" && row_str=$padded
        fi
      fi
    fi

    # A row that could not be safely assembled — the arithmetic above refusing to vouch for it,
    # a case `test/render/prompt_shape_spec.sh`'s "accounting under-reports" example exercises
    # directly — is not appended EMPTY. `physical_rows` is the newline-joined shape of the whole
    # prompt, and an empty entry in it is a blank line between two others, not a row with
    # nothing on it. `${(f)PROMPT}` will not show you this bug: zsh drops an empty field from a
    # `(f)` split, so a consecutive `$'\n\n'` in the raw string reads back as one fewer line than
    # it draws. Count newline BYTES in the raw string, or read it on a real grid, to catch this.
    #
    # `row_widths` still gets an entry when the row was dropped: 0 is exactly the reflow height
    # a row with nothing on screen contributes, which is what `lib/core/resize.zsh` needs it to
    # be. Measured off the finished string rather than summed from `eff_left_w` / `eff_right_w`
    # — the same reason `_inzsh_render_row_fits` measures rather than trusts the gap's own
    # arithmetic: those two can under-report, and this number is the one the climb depends on.
    row_width=0
    if [[ -n $row_str ]]; then
      physical_rows+=("$row_str")
      if (( ${+functions[_inzsh_width]} )); then
        _inzsh_width "$row_str"
        row_width=$REPLY
      fi
    fi
    row_widths+=("$row_width")
  done

  # The marker. Under `own` it always gets a bare line of its own, below every drawn row — the
  # only physical line `RPROMPT` is ever assigned on, since it is never the last line under
  # `inline` and never a segment row under `own`. Under `inline` it terminates the row held back
  # above, with a single space either side of it, and `RPROMPT` is that row's right side, placed
  # exactly where zsh would put it anyway.
  #
  # A PROMPT MAY NEVER COME BACK EMPTY. With nothing drawn at all — every segment absent, which is
  # legitimate — the marker is the whole prompt, under both settings; `physical_rows` is empty in
  # that case and this is the only row either branch below adds.
  if (( inline_marker )); then
    local marker_row="${marker} "
    [[ -n $last_left ]] && marker_row="${last_left} ${marker} "
    physical_rows+=("$marker_row")
    typeset -g RPROMPT=$last_right

    # The row held back above is still a drawn row — the last configured segment row, only
    # carrying the marker instead of a bare line of its own — so `row_widths` gets an entry for
    # it here that the loop's `continue` skipped. `RPROMPT` is not measured into it: zsh
    # right-aligns it itself and drops it rather than wrapping it, so unlike the literal padding
    # every other row's right side is drawn with, it is not text of ours that can push this line
    # past the terminal's edge. `eff_count` guards the case where nothing was drawn at all —
    # the loop never ran, so there is no row here to record either.
    if (( eff_count > 0 )); then
      row_width=0
      if (( ${+functions[_inzsh_width]} )); then
        _inzsh_width "$marker_row"
        row_width=$REPLY
      fi
      row_widths+=("$row_width")
    fi
  else
    physical_rows+=("$marker ")
    typeset -g RPROMPT=
  fi

  typeset -g PROMPT="${(F)physical_rows}"

  typeset -ga _inzsh_render_row_widths
  _inzsh_render_row_widths=("${row_widths[@]}")

  return 0
}
