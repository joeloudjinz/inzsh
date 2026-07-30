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
    (alternate|ramp|flat) typeset -g _inzsh_surface_mode_resolved=$want ;;
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
#   _inzsh_segment_importance  SEGMENT → 1..3, what `ramp` reads. 2 by default, the middle of the
#                              ramp; `alternate` and `flat` ignore it.
typeset -gA _inzsh_segment_text
typeset -gA _inzsh_segment_fg_role
typeset -gA _inzsh_segment_importance

# The visible width of the last build, in columns. Tracked as the string is assembled rather than
# measured off the finished one: the result is escape-laden and its width cannot be recovered from
# it. Declared here so a caller reading it before the first build gets 0 rather than an error.
typeset -g _inzsh_render_width=0

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
_inzsh_render_surfaces() {
  emulate -L zsh

  _inzsh_surface_assign "$@"

  # WHICH invariant applies is a property of the SEPARATOR and not of the surface mode. A filled
  # boundary is only visible while the two blocks differ; `divider` has no filled boundary at
  # all, so equal neighbours there are as harmless as they are under `flat`. The style is
  # therefore resolved here and a `divider` prompt is put to the invariant AS `flat` — the
  # exemption `_inzsh_surfaces_valid` already grants, asked for the reason it already grants it,
  # rather than a second exemption bolted onto the predicate. Two copies of a rule is one copy
  # too many, and the copy that drifts is always the one further from the sentence.
  _inzsh_sep_style
  local mode=$_inzsh_surface_mode_resolved
  [[ $_inzsh_sep_style_resolved == divider ]] && mode=flat

  _inzsh_surfaces_valid "$mode" "${reply[@]}" && return 0

  local INZSH_SURFACE_MODE=alternate
  _inzsh_surface_assign "$1"

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
# A block is `<pad><text><pad>`, one column of padding either side, so a block is
# `_inzsh_width` of its text plus 2. A side of n visible segments draws n separators, not n-1:
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
  # whatever the user's shell says right now, and the next prompt is when it takes effect.
  _inzsh_separators

  _inzsh_render_surfaces $n "${importances[@]}"
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
      _inzsh_seg_color "${visible[i]}" fg "${_inzsh_segment_fg_role[${visible[i]}]:-text-body}" \
        text-body
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
      drawn+="${fill[i]}${face[i]} ${texts[i]} "
      if (( i < n )); then
        drawn+="${fill[i+1]}${ink[i]}${glyph}"
      else
        drawn+="%k${ink[i]}${glyph}"
      fi
      if (( measure )); then
        _inzsh_width "${texts[i]}"
        _inzsh_width_add used $REPLY
        _inzsh_width_add used $(( 2 + sep ))
      fi
    done
  else
    for (( i = 1; i <= n; i++ )); do
      if (( i == 1 )); then
        drawn+="%k${ink[1]}${glyph}"
      else
        drawn+="${fill[i-1]}${ink[i]}${glyph}"
      fi
      drawn+="${fill[i]}${face[i]} ${texts[i]} "
      if (( measure )); then
        _inzsh_width "${texts[i]}"
        _inzsh_width_add used $REPLY
        _inzsh_width_add used $(( 2 + sep ))
      fi
    done
  fi

  # Close both channels. A prompt that leaves a background open colours the line the user types.
  drawn+='%f%k'

  typeset -g REPLY=$drawn
  typeset -g _inzsh_render_width=$used

  return 0
}

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
  fi

  # A prompt is the one thing that may never come back empty. Every segment can legitimately
  # be absent at once — a clean directory at a narrow width with nothing to report — and a
  # blank PROMPT reads as a broken shell rather than a calm one. `%#` is zsh's own marker and
  # costs one column.
  [[ -n $left ]] && left+=' '
  typeset -g PROMPT=${left:-'%# '}
  typeset -g RPROMPT=$right

  return 0
}
