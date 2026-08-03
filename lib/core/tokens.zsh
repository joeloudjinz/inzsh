# InZsh — token layer. The single transcription point for colour in this repo, and — since the
# glyph table at the foot of it — for every mark the theme draws as well.
#
# Source:     the Joe Inz design system's tokens/colors.css, transcribed 2026-07-29.
# Rule:       hex values exist here and nowhere else — not in presets, not in segments, not
#             in tests. Everything downstream reads semantic roles, never these ramp names.
#             `tokens-256.zsh` is the one sibling: the same keys at 256 and 8 colours, which
#             is still the token layer and still not hex.
# On change:  when the design system moves, re-pull ds-colors.css, re-transcribe this file,
#             and re-run the colour audit. Nothing else in the tree gets edited for a
#             palette change.
#
# Values are stored ready for zsh's truecolor form — `%F{$_inzsh_palette[cream]}` — so the
# leading `#` is part of the value and hex digits are uppercase.
#
# Not transcribed, deliberately:
#   --highlight-wash / --highlight-wash-dark — rgba() with alpha. A terminal cell has no
#     alpha channel; there is nothing to composite against, so an alpha wash is not
#     representable. The DS already ships pre-mixed solid `-wash` tints for this purpose.
#   --board-bg, --badge-aa-bg, --badge-aa-fg, and --surface-card's #FFFFFF — web-app
#     chrome (canvas behind cards, contrast badges). No prompt analogue.
#   The var()-only semantic aliases (--surface, --text-body, --positive, …) carry no hex of
#     their own; they are roles and get their own mapping in the role layer below.
#
# The palette is pure data. The role layer under it is pure parameter work — one function,
# run once at the end of this file, so sourcing yields a ready `_inzsh_role`. Below it sits
# the per-segment resolver every segment calls at draw time, and below that the glyph table,
# which follows exactly the same shape: two source tables, one resolve, one ready map.

typeset -gA _inzsh_palette
_inzsh_palette=(
  # --- Base ramps ---
  cream               '#F3EAD2'  # --cream         primary light background
  cream-soft          '#F7F1E1'  # --cream-soft    softer light surface
  cream-bright        '#FFFDF6'  # --cream-bright  near-white highlight for glows
  cream-muted         '#C9BFA6'  # --cream-muted   muted cream — dark-mode secondary text
  cream-deep          '#EEE2C6'  # --cream-deep    deeper cream for subtle light gradients

  choc                '#3A281E'  # --choc          chocolate — primary ink on light
  choc-soft           '#6B5A4C'  # --choc-soft     muted chocolate — secondary text on light
  choc-ink            '#241B14'  # --choc-ink      deepest brown — headings

  navy                '#191F33'  # --navy          navy — primary dark background
  navy-soft           '#2A3350'  # --navy-soft     raised navy surface
  navy-deep           '#12172A'  # --navy-deep     deepest navy for gradient ends

  caramel             '#B07A3C'  # --caramel        the single saturated accent, both modes
  caramel-bright      '#C68A45'  # --caramel-bright brighter caramel for glows

  # --- Muted semantics (restrained, warm) ---
  sage                '#5E7A5B'  # --sage             positive / affirmative
  sage-bright         '#8FAE8B'  # --sage-bright      lighter sage for dark mode
  ink-blue            '#41507A'  # --ink-blue         info / link, derived from navy
  ink-blue-bright     '#8F9BC4'  # --ink-blue-bright  lighter ink-blue for dark mode

  # --- State ramps (additive) ---
  # Solid opaque hex only. X = light-mode value, X-bright = dark-mode lift;
  # -wash = pre-mixed solid tint (not alpha), -edge = >=3:1 border/ring value.
  sage-deep           '#4F6B4C'  # --sage-deep  positive TEXT on cream — raw sage is
                                 #              AA-large only
  sage-wash           '#E8E2C9'  # --sage-wash
  sage-wash-dark      '#2B3440'  # --sage-wash-dark
  sage-edge           '#748A6D'  # --sage-edge
  sage-edge-dark      '#6E8572'  # --sage-edge-dark
  ink-blue-wash       '#E5DECB'  # --ink-blue-wash
  ink-blue-wash-dark  '#2C334A'  # --ink-blue-wash-dark
  ink-blue-edge       '#7D8497'  # --ink-blue-edge
  ink-blue-edge-dark  '#747EA3'  # --ink-blue-edge-dark

  madder              '#7A443A'  # --madder  negative / destructive — book-cloth brick, not
                                 #           alarm red
  madder-bright       '#E0A5AF'  # --madder-bright  dark-mode negative — dusty rose; hue tuned
                                 #                  so protan/deutan viewers keep separation
                                 #                  from sage-bright
  madder-wash         '#E9DDC6'  # --madder-wash
  madder-wash-dark    '#343144'  # --madder-wash-dark
  madder-edge         '#A27C6D'  # --madder-edge
  madder-edge-dark    '#997683'  # --madder-edge-dark

  ochre               '#7A6119'  # --ochre  caution — dry ochre, darker+greener than caramel so
                                 #          a warning can never read as brand emphasis
  ochre-bright        '#E4CA83'  # --ochre-bright  dark-mode caution — pale gold
  ochre-wash          '#ECE2C7'  # --ochre-wash
  ochre-wash-dark     '#31333C'  # --ochre-wash-dark
  ochre-edge          '#988246'  # --ochre-edge
  ochre-edge-dark     '#8A7E60'  # --ochre-edge-dark

  # --- Neutral-chip + disabled ramps: putty (light) / slate (dark) ---
  putty-wash          '#E7DEC6'  # --putty-wash  neutral chip tint on cream
  putty-line          '#908171'  # --putty-line  3:1 edge on cream
  putty-text          '#9B8D7B'  # --putty-text  disabled ~2.7:1, WCAG-exempt
  putty-fill          '#E6DCC5'  # --putty-fill
  putty-hair          '#B9AC99'  # --putty-hair
  slate-wash          '#2F3341'  # --slate-wash  neutral chip tint on navy
  slate-line          '#827F78'  # --slate-line  3:1 edge on navy
  slate-text          '#586281'  # --slate-text  disabled (dark)
  slate-fill          '#252B42'  # --slate-fill
  slate-hair          '#414965'  # --slate-hair

  # --- Hairlines / borders ---
  hair-light          '#E4D8BE'  # --hair-light  divider on cream
  hair-dark           '#333C58'  # --hair-dark   divider on navy
)

# ---------------------------------------------------------------------------------------
# Role layer. Everything downstream reads `_inzsh_role[negative]`, never a ramp name — roles
# survive a palette change, ramps may not.
#
# Two registers, transcribed from the design system's colors.css: `light` is its `:root`
# semantic-alias block (warm/personal), `dark` its `.theme-dark` overrides (sharp/technical).
# Both tables map a role to a PALETTE KEY, never to a hex value — the one-transcription-point
# rule holds inside this file too, below the palette.
#
# Two DS roles are deliberately absent: --surface-card (web chrome — a raised card behind
# content, no prompt analogue) and --accent-wash (an rgba() marker highlight; a terminal cell
# has no alpha channel to composite against).
#
# ONE ROLE HERE IS NOT A DS ALIAS: `surface-deep`. It carries no `--` name below because the
# design system does not name it, and it does not name it because a web surface never abuts
# another filled surface — a card sits on a page with air around it. A prompt's blocks abut,
# and the boundary between two of them IS the colour change, so the engine needs a second
# surface as far from the first as the ramp goes. The DS's own surface roles do not go far
# enough: `surface-soft` and `hairline` resolve to #2A3350 and #333C58 in the dark register,
# nine points a channel and 1.14:1 — a separator you have to look for.
#
# NO NEW COLOUR IS INVENTED FOR IT. `surface-deep` points at `cream-bright` and `navy-deep`,
# two palette entries the DS already ships and already maps five times over as `on-positive`,
# `on-info`, `on-negative`, `on-caution` and `on-neutral`. What is new is a NAME that says
# what the engine draws with it — the far end of the surface ramp, which is the brightest
# value in the light register and the deepest in the dark, exactly as the DS's own gradients
# run. Against `neutral-wash` it gives 1.32:1 in light and 1.41:1 in dark.

typeset -gA _inzsh_roles_light
_inzsh_roles_light=(
  surface        cream          # --surface
  surface-soft   cream-soft     # --surface-soft
  surface-deep   cream-bright   # (engine) the far end of the surface ramp — see above
  text-strong    choc-ink       # --text-strong
  text-body      choc           # --text-body
  text-muted     choc-soft      # --text-muted
  accent         caramel        # --accent       the one saturated brand colour, both registers
  on-accent      cream          # --on-accent

  # Five slots per state: fill, on-fill, text on surface, tinted background, border/ring.
  positive       sage           # --positive
  positive-text  sage-deep      # --positive-text  raw sage is AA-large only on cream
  on-positive    cream-bright   # --on-positive
  positive-wash  sage-wash      # --positive-wash
  positive-edge  sage-edge      # --positive-edge
  info           ink-blue       # --info
  info-text      ink-blue       # --info-text
  on-info        cream-bright   # --on-info
  info-wash      ink-blue-wash  # --info-wash
  info-edge      ink-blue-edge  # --info-edge
  negative       madder         # --negative
  negative-text  madder         # --negative-text
  on-negative    cream-bright   # --on-negative
  negative-wash  madder-wash    # --negative-wash
  negative-edge  madder-edge    # --negative-edge
  caution        ochre          # --caution
  caution-text   ochre          # --caution-text
  on-caution     cream-bright   # --on-caution
  caution-wash   ochre-wash     # --caution-wash
  caution-edge   ochre-edge     # --caution-edge
  neutral        choc-soft      # --neutral
  neutral-text   choc-soft      # --neutral-text
  on-neutral     cream-bright   # --on-neutral
  neutral-wash   putty-wash     # --neutral-wash
  neutral-edge   putty-line     # --neutral-edge

  inactive-fill  putty-fill     # --inactive-fill
  inactive-text  putty-text     # --inactive-text
  inactive-edge  putty-hair     # --inactive-edge
  focus-ring     ink-blue       # --focus-ring
  hairline       hair-light     # --hairline
)

typeset -gA _inzsh_roles_dark
_inzsh_roles_dark=(
  surface        navy                # --surface
  surface-soft   navy-soft           # --surface-soft
  surface-deep   navy-deep           # (engine) the far end of the surface ramp — see above
  text-strong    cream               # --text-strong
  text-body      cream               # --text-body
  text-muted     cream-muted         # --text-muted
  accent         caramel             # --accent     unchanged from light, by design
  on-accent      choc                # --on-accent

  positive       sage-bright         # --positive
  positive-text  sage-bright         # --positive-text
  on-positive    navy-deep           # --on-positive
  positive-wash  sage-wash-dark      # --positive-wash
  positive-edge  sage-edge-dark      # --positive-edge
  info           ink-blue-bright     # --info
  info-text      ink-blue-bright     # --info-text
  on-info        navy-deep           # --on-info
  info-wash      ink-blue-wash-dark  # --info-wash
  info-edge      ink-blue-edge-dark  # --info-edge
  negative       madder-bright       # --negative
  negative-text  madder-bright       # --negative-text
  on-negative    navy-deep           # --on-negative
  negative-wash  madder-wash-dark    # --negative-wash
  negative-edge  madder-edge-dark    # --negative-edge
  caution        ochre-bright        # --caution
  caution-text   ochre-bright        # --caution-text
  on-caution     navy-deep           # --on-caution
  caution-wash   ochre-wash-dark     # --caution-wash
  caution-edge   ochre-edge-dark     # --caution-edge
  neutral        cream-muted         # --neutral
  neutral-text   cream-muted         # --neutral-text
  on-neutral     navy-deep           # --on-neutral
  neutral-wash   slate-wash          # --neutral-wash
  neutral-edge   slate-line          # --neutral-edge

  inactive-fill  slate-fill          # --inactive-fill
  inactive-text  slate-text          # --inactive-text
  inactive-edge  slate-hair          # --inactive-edge
  focus-ring     ink-blue-bright     # --focus-ring
  hairline       hair-dark           # --hairline
)

# The active register. Dark is the default because the sharp preset is. Set only when unset,
# so re-sourcing this file — bundling, reloading, a second plugin manager pass — never
# discards a register the user or a preset already chose.
(( ${+_inzsh_register} )) || typeset -g _inzsh_register=dark

# Rebuild `_inzsh_role` (role → colour value) from the active register's table and whichever
# palette the terminal can actually draw. Parameter operations only: no subprocesses, no forks
# — this may run on the render path. An unrecognised register falls back to dark;
# configuration may never break the render.
#
# Two independent choices, and only two:
#
#   register  which role table names the palette KEY   — light or dark
#   depth     which palette turns that key into a VALUE — truecolor, 256 or 8
#
# They compose rather than multiply: the register picks a key, the depth picks a table, and
# there is one loop underneath both. A degraded prompt is the same prompt with a different
# lookup, never a second code path — anything a 256-colour terminal does differently from a
# truecolor one is a bug we would only ever find on somebody else's machine.
#
# Load order: `lib/core/detect.zsh` sets `_inzsh_color_depth` and `lib/core/tokens-256.zsh`
# defines the reduced tables, and the entry point sources both before this file, so the
# resolve at the end of it already knows the depth. Neither is required. Each of the three
# files is independently sourceable, and this one alone still resolves — a missing depth, an
# unrecognised one, or a depth whose table has not been loaded all mean truecolor. Degrading
# is a feature; failing to degrade must never cost anyone their prompt.
_inzsh_tokens_resolve() {
  emulate -L zsh

  local table=_inzsh_roles_dark
  [[ $_inzsh_register == light ]] && table=_inzsh_roles_light

  local values=_inzsh_palette
  case $_inzsh_color_depth in
    (256) (( ${+_inzsh_palette_256} )) && values=_inzsh_palette_256 ;;
    (8)   (( ${+_inzsh_palette_8} ))   && values=_inzsh_palette_8   ;;
  esac
  local -A palette=("${(@Pkv)values}")

  typeset -gA _inzsh_role
  _inzsh_role=()

  # The truecolor value is the last resort for a key the reduced table happens to be missing.
  # It is the wrong depth, which shows; an empty value is a broken escape, which does not.
  local role key
  for role key in "${(@Pkv)table}"; do
    _inzsh_role[$role]=${palette[$key]:-${_inzsh_palette[$key]}}
  done
}

# The presets, by name. A preset is a name for a register and nothing more, so the whole of
# `presets/inzsh-<name>.zsh` is one of these pairs — which is why the name is answered from a
# table here rather than by sourcing that file. The single-file bundle is `lib/` concatenated
# and has no `presets/` directory beside it; a knob that worked from a clone and not from a
# bundle would be worse than no knob at all.
#
# That makes this a second copy of "warm means light", and the copy is held equal to the file
# in `test/render/presets_spec.sh` — the same way every default restated for a partial load is
# held equal to the registered one.
typeset -gA _inzsh_preset_registers
_inzsh_preset_registers=(
  sharp dark
  warm  light
)

# Apply `INZSH_PRESET`, if it names a preset. Called once, by the entry point, at source time —
# the note there says why this is the one knob that is not read again at draw time.
#
# Nothing here can fail loudly. An empty, unset or unrecognised value leaves the register exactly
# as it was found, which is the built-in one unless a preset file already chose otherwise; the
# status is always 0 and neither stream is written to. That is the config layer's own rule, kept
# here by hand because the token layer may be loaded without the config layer at all — in which
# case the variable is read raw and the table below is the only vocabulary there is.
_inzsh_preset_apply() {
  emulate -L zsh

  local name=${INZSH_PRESET-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_PRESET
    name=$REPLY
  fi

  # Normalised the way the registered `word:` spec matched it — case, spacing and punctuation
  # ignored — so a name the validator blessed is a name this table can find. A value that
  # normalises to nothing was never a name.
  name=${(L)name}
  name=${name//[^a-z0-9]/}

  local register=${_inzsh_preset_registers[$name]-}
  [[ -n $register ]] || return 0

  typeset -g _inzsh_register=$register
  _inzsh_tokens_resolve

  return 0
}

# ---------------------------------------------------------------------------------------
# Per-segment colour. The one place a segment asks "what colour am I?", so the precedence
# lives here rather than being re-derived in every segment:
#
#   INZSH_<SEGMENT>_BG / _FG  →  role  →  fallback role  →  nothing (status 1)
#
#   _inzsh_seg_color DIR bg surface-soft surface
#   [[ -n $REPLY ]] && segment+="%K{$REPLY}"
#
# SEGMENT is the uppercase config name fragment (DIR, HOST, SALAH); the channel is `bg` or
# `fg`. The answer comes back in REPLY — this runs on the render path, so no command
# substitution and no forks, parameter operations only.
#
# An override that is set and non-empty is used verbatim: anything zsh's `%F{...}` accepts is
# the user's business — truecolor hex, a named colour, a 256 index — and the theme does not
# police it beyond non-emptiness. An override that is SET BUT EMPTY counts as UNSET: an
# `INZSH_DIR_BG=` left behind in someone's zshrc must fall through to the role rather than
# blank the segment.
#
# When neither role exists the result is an empty REPLY and status 1 — the caller decides what
# to do with that. A missing role must never reach the prompt as a broken escape.
#
# `INZSH_*_BG` and `INZSH_*_FG` are registered as FAMILIES in `lib/core/config.zsh` — one
# validator and one default for every segment that exists and every one that will — so the
# override is read through the registry where it is loaded. It answers `any`, which is this
# function's own rule already: non-empty is used verbatim, empty is no opinion. What the
# registry adds is that a segment name which cannot spell a variable comes back with nothing
# instead of reaching `${(P)}`, and that the shape is declared somewhere a reader can find it.
_inzsh_seg_color() {
  emulate -L zsh

  typeset -g REPLY=

  # Read straight from the parameter, deliberately, though the knob IS registered.
  #
  # `INZSH_*_BG` and `INZSH_*_FG` register as `any` with an empty default: every non-empty value
  # is accepted — a colour someone typed for their own terminal is their business — and absence
  # falls through to the role below. So the registry's answer for these two families is the
  # parameter, character for character, and asking through it buys a call and two lookups per
  # read for an answer that cannot differ. This is the hottest read in the theme: twice per
  # segment, every draw.
  #
  # What makes the surface knowable is REGISTRATION, not the read path — the guard in
  # `test/unit/config_registry_spec.sh` requires a read to be declared, and this one is. A knob
  # whose spec could reject something must go through `_inzsh_config_get`; these cannot.
  local var=INZSH_${(U)1}_${(U)2}
  local override=${(P)var}

  if [[ -n $override ]]; then
    REPLY=$override
    return 0
  fi

  local role
  for role in "$3" "$4"; do
    if [[ -n $role && -n ${_inzsh_role[$role]+set} ]]; then
      REPLY=${_inzsh_role[$role]}
      return 0
    fi
  done

  return 1
}

# ---------------------------------------------------------------------------------------
# Glyphs. The token layer's other table: every mark the theme draws, keyed by the ROLE it
# plays rather than by the shape it has, so that no engine file and no segment carries a
# literal of its own.
#
# It exists because three files had already learned the same lesson separately — the
# separators in `lib/core/render.zsh`, the ellipsis in `lib/core/layout.zsh` and the failure
# mark in `lib/segments/retval.zsh` — and a fourth separator style would have made a fourth
# copy. Separator glyphs live in the token layer; so, now, does everything else.
#
# EVERY VALUE IS SPELLED AS RAW UTF-8 BYTES, and never as a `\u` escape. That escape is
# resolved when the file is PARSED: outside a multibyte locale zsh cannot resolve one, fails
# with `character not in range`, and abandons the rest of the file — every function in it
# included. Byte escapes parse in any locale, and in a UTF-8 one the bytes ARE the character.
# This has already cost this repo two files. It does not get a third chance.
#
# ORIENTATION, which is the opposite of what the codepoint names suggest and is the one thing
# in this table that can be got backwards. A separator cell carries two colours: the ink fills
# the side the glyph's mass sits on, and the cell's own background shows through the rest. The
# LEFT prompt's separator FOLLOWS its block, so its ink must sit on the LEFT of the cell —
# U+E0B0, the wedge pointing right, and U+E0B4, the half circle bulging right (flat edge on
# the left). The right prompt mirrors: its separator PRECEDES its block, the ink sits on the
# RIGHT, and that is U+E0B2 and U+E0B6. So `sep-left-round` is the RIGHT half circle. The keys
# are named for the SIDE THEY ARE DRAWN ON rather than for their own shape, which is what
# stops the pair from being swapped by someone reading the codepoint chart.
typeset -gA _inzsh_glyph_utf8
_inzsh_glyph_utf8=(
  # --- Separators: private-use area, drawn only by a Nerd Font ---
  sep-left         $'\xee\x82\xb0'  # U+E0B0  filled wedge, points right, ink on the left
  sep-right        $'\xee\x82\xb2'  # U+E0B2  its mirror, points left, ink on the right
  sep-left-round   $'\xee\x82\xb4'  # U+E0B4  right half circle: flat edge left, ink left
  sep-right-round  $'\xee\x82\xb6'  # U+E0B6  left half circle: flat edge right, ink right

  # --- Rules and markers: ordinary Unicode, drawn by any font with box drawing ---
  divider          $'\xe2\x94\x82'  # U+2502  box drawings light vertical
  ellipsis         $'\xe2\x80\xa6'  # U+2026  horizontal ellipsis — the truncation marker
  prompt           $'\xe2\x86\x92'  # U+2192  rightwards arrow — "type here", the input marker

  # --- The design system's sanctioned state marks ---
  ok               $'\xe2\x9c\x93'  # U+2713  check mark
  info             'i'              # the DS mark is the letter itself, already ASCII
  error            $'\xe2\x9c\x95'  # U+2715  multiplication x
  warn             '!'              # already ASCII
  dot              $'\xc2\xb7'      # U+00B7  middle dot — a separator inside a segment's text
  dash             $'\xe2\x80\x94'  # U+2014  em dash — "nothing to report", not "zero"
  ahead            $'\xe2\x86\x91'  # U+2191  up arrow — commits this side does not share
  behind           $'\xe2\x86\x93'  # U+2193  down arrow — commits the other side has
)

# The parallel fallback, one entry per key above, for a terminal that cannot carry the glyph.
#
# Colour is never the only signal in this theme, so a mark that degrades to nothing takes the
# whole signal with it. Every fallback therefore still says what its glyph said: `x` for the
# failure mark and `v` for its opposite — the same two-mark vocabulary, one column each — and a
# plain rule for a separator, because a boundary that a font cannot draw is still a boundary.
#
# The rounded pair keeps its MIRROR here, `)` on the left and `(` on the right, so the one
# property that style exists for survives the degradation even though its shape does not.
typeset -gA _inzsh_glyph_ascii
_inzsh_glyph_ascii=(
  sep-left         '|'
  sep-right        '|'
  sep-left-round   ')'
  sep-right-round  '('
  divider          '|'
  ellipsis         '...'
  prompt           '>'              # the mark every shell since sh has used for "type here"
  ok               'v'
  info             'i'
  error            'x'
  warn             '!'
  dot              '.'
  dash             '-'
  ahead            '+'              # what git's own branch.ab line prints
  behind           '-'
)

# Rebuild `_inzsh_glyph` (role → the mark to draw) from whichever of the two tables the
# terminal can actually show. Parameter operations only: no subprocesses, no forks.
#
# Two independent ways to fail, and both land on ASCII:
#
#   the locale says so     `_inzsh_multibyte` is 0 — `lib/core/detect.zsh` worked that out, and
#                          a user who can see their own screen may have said it with
#                          `INZSH_MULTIBYTE=0`.
#   the bytes say so       the value did not become ONE character. That is the narrower
#                          question this file actually cares about, and it is asked of the
#                          value itself, so a token layer sourced without a detect layer still
#                          answers it correctly rather than assuming.
#
# A key with no fallback is a theme bug rather than a user one, and it costs a legible mark
# rather than the prompt: `?` is visibly wrong, an empty string is invisibly wrong.
_inzsh_glyphs_resolve() {
  emulate -L zsh

  typeset -gA _inzsh_glyph
  _inzsh_glyph=()

  local -i multibyte=1
  [[ ${_inzsh_multibyte-1} == 0 ]] && multibyte=0

  local key value
  for key value in "${(@kv)_inzsh_glyph_utf8}"; do
    if (( multibyte )) && (( ${#value} == 1 )); then
      _inzsh_glyph[$key]=$value
    else
      _inzsh_glyph[$key]=${_inzsh_glyph_ascii[$key]:-'?'}
    fi
  done

  return 0
}

_inzsh_tokens_resolve
_inzsh_glyphs_resolve
