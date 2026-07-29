# InZsh — token layer. The single transcription point for colour in this repo.
#
# Source:     the Joe Inz design system's tokens/colors.css, transcribed 2026-07-29.
# Rule:       hex values exist here and nowhere else — not in presets, not in segments, not
#             in tests. Everything downstream reads semantic roles, never these ramp names.
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
# run once at the end of this file, so sourcing yields a ready `_inzsh_role`.

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

typeset -gA _inzsh_roles_light
_inzsh_roles_light=(
  surface        cream          # --surface
  surface-soft   cream-soft     # --surface-soft
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

# Rebuild `_inzsh_role` (role → hex) from the active register's table and the palette.
# Parameter operations only: no subprocesses, no forks — this may run on the render path.
# An unrecognised register falls back to dark; configuration may never break the render.
_inzsh_tokens_resolve() {
  emulate -L zsh

  local table=_inzsh_roles_dark
  [[ $_inzsh_register == light ]] && table=_inzsh_roles_light

  typeset -gA _inzsh_role
  _inzsh_role=()

  local role key
  for role key in "${(@Pkv)table}"; do
    _inzsh_role[$role]=${_inzsh_palette[$key]}
  done
}

_inzsh_tokens_resolve
