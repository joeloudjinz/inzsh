# InZsh — the reduced-depth palettes. Part of the token layer, so hex belongs here; the
# values themselves are xterm colour indices, which are not hex at all.
#
# Two tables, one key set. Both carry every key `_inzsh_palette` carries, so the resolver can
# swap tables without knowing anything about what is in them:
#
#   _inzsh_palette_256   256-colour terminals — hand-tuned, one index per token
#   _inzsh_palette_8     8-colour terminals   — the last resort, ANSI 0-7
#
# WHY THESE ARE HAND-TUNED. Nearest-neighbour quantisation is not merely imprecise here, it is
# wrong in the one place it matters. `navy` #191F33 and `choc` #3A281E are the two registers'
# defining darks — one cool, one warm — and both snap to the same near-black gray, because the
# 6x6x6 cube's channel levels jump 0 -> 95 and there is nothing chromatic underneath. The
# nearest index is the index that destroys the theme. So every value below was chosen against
# three constraints, in this order:
#
#   1. Distinctness where it shows. Two tokens from different ramps that can sit next to each
#      other in a prompt get different indices. Two tokens the design system itself keeps
#      within a couple of RGB units — the five light washes, say — are allowed to collapse,
#      because they are already indistinguishable at 24-bit and pretending otherwise would
#      invent a difference the design does not have.
#   2. Lightness ordering inside each ramp. `cream-bright` >= `cream` >= `cream-deep`, and so
#      on down every ramp. Contrast is a relationship, not a value: if the ordering survives,
#      a degraded prompt is still legible even where the hue is gone.
#   3. Hue, as far as the cube allows. Above roughly L* 30 it allows quite a lot. Below that
#      it allows almost nothing, and lightness wins — an accurate dark gray beats a saturated
#      dark red that was never in the design.
#
# The light and dark registers are never both live, so a token used only by `_inzsh_roles_light`
# may share an index with one used only by `_inzsh_roles_dark`. Several do; each says so.
#
# Indices 0-15 are never used. Those sixteen are exactly the ones every terminal scheme
# remaps — Solarized, Gruvbox and the rest all repaint them — so a value chosen there is a
# value chosen by somebody else. 16-255 are fixed by the xterm specification and mean what
# they say.

typeset -gA _inzsh_palette_256
_inzsh_palette_256=(
  # --- Base ramps ---
  cream               '230'  # F3EAD2 -> FFFFD7  the cube's one creamy light. The warm
                             #                   register's whole character rests on this
                             #                   value; ~6 L* hot, which on a background
                             #                   costs nothing but contrast in our favour
  cream-soft          '231'  # F7F1E1 -> FFFFFF  above cream, as the DS has it. White is all
                             #                   that is left above 230
  cream-bright        '231'  # FFFDF6 -> FFFFFF  near-white by definition. Shares with
                             #                   cream-soft, safely: this is on-fill TEXT and
                             #                   that is a surface, so they never touch
  cream-muted         '144'  # C9BFA6 -> AFAF87  warm khaki. Secondary text on navy keeps its
                             #                   warmth rather than going gray
  cream-deep          '187'  # EEE2C6 -> D7D7AF  parchment, one clear step under cream
  choc                '236'  # 3A281E -> 303030  L* 18.0 against 18.5, near exact. The cube
                             #                   holds no dark brown at any saturation, so the
                             #                   warm ink degrades to neutral rather than red
  choc-soft           '241'  # 6B5A4C -> 626262  875F5F is the nearer hue and reads rosy
                             #                   beside madder; muted TEXT that can be taken
                             #                   for negative text is worse than gray
  choc-ink            '234'  # 241B14 -> 1C1C1C  L* 10.6 against 10.5
  navy                '17'   # 191F33 -> 00005F  the hand-set one. Nearest-neighbour puts navy
                             #                   and choc on the same gray and the dark
                             #                   register stops being navy at all, so this
                             #                   takes the cube's only deep blue and pays ~5
                             #                   L* for the hue
  navy-soft           '18'   # 2A3350 -> 000087  the raised surface stays in the blue family,
                             #                   and stays above navy
  navy-deep           '233'  # 12172A -> 121212  under 00005F in luminance, which is what the
                             #                   ramp needs. Nothing chromatic is darker than
                             #                   17, so the floor of this ramp goes neutral
  caramel             '137'  # B07A3C -> AF875F  the accent, unchanged across registers, so it
                             #                   is the one value that must not collide with
                             #                   anything in either. Desaturated but accurate;
                             #                   AF8700 is punchier and twice as far off
  caramel-bright      '179'  # C68A45 -> D7AF5F  gold, clearly above caramel

  # --- Muted semantics ---
  sage                '65'   # 5E7A5B -> 5F875F  dE 7.9, the best match in the table
  sage-bright         '108'  # 8FAE8B -> 87AF87  dE 4.4
  ink-blue            '60'   # 41507A -> 5F5F87  dE 8.8
  ink-blue-bright     '103'  # 8F9BC4 -> 8787AF  dE 7.9

  # --- State ramps ---
  sage-deep           '22'   # 4F6B4C -> 005F00  hand-set. The DS made sage-deep because raw
                             #                   sage is AA-large only on cream; 5F875F would
                             #                   put positive TEXT back at 4.0:1 and undo
                             #                   exactly that. 005F00 is over-saturated and
                             #                   lands at 7.8:1, which is the point of it
  sage-wash           '187'  # E8E2C9 -> D7D7AF  one of five near-identical light washes; see
                             #                   the note under putty-wash
  sage-wash-dark      '237'  # 2B3440 -> 3A3A3A  one of five near-identical dark washes
  sage-edge           '108'  # 748A6D -> 87AF87  the soft sage reads right for a ring on cream.
                             #                   Shares with sage-bright, which is dark-only
  sage-edge-dark      '65'   # 6E8572 -> 5F875F  a ring on navy, under sage-bright as the DS
                             #                   has it. Shares with sage, which is light-only
  ink-blue-wash       '187'  # E5DECB -> D7D7AF  light wash
  ink-blue-wash-dark  '237'  # 2C334A -> 3A3A3A  dark wash
  ink-blue-edge       '103'  # 7D8497 -> 8787AF  shares with ink-blue-bright, which is dark-only
  ink-blue-edge-dark  '67'   # 747EA3 -> 5F87AF  distinct from ink-blue-bright, which it rings
  madder              '95'   # 7A443A -> 875F5F  4.6:1 on cream, so negative TEXT still clears
                             #                   AA. AF5F5F is redder and drops to 3.8:1
  madder-bright       '181'  # E0A5AF -> D7AFAF  dusty rose, dE 9.1
  madder-wash         '187'  # E9DDC6 -> D7D7AF  light wash
  madder-wash-dark    '237'  # 343144 -> 3A3A3A  dark wash. 5F0000 sits at the right lightness
                             #                   but invents a saturation the DS wash does not
                             #                   have; a tinted chip is not a red chip
  madder-edge         '138'  # A27C6D -> AF8787  rosy, above madder as the DS has it
  madder-edge-dark    '138'  # 997683 -> AF8787  same value, other register — never both live
  ochre               '94'   # 7A6119 -> 875F00  dE 11.1, and 5.7:1 on cream for caution text
  ochre-bright        '186'  # E4CA83 -> D7D787  hand-set. FFD787 is the closer hue but lands
                             #                   above ochre-wash and inverts the ramp; a pale
                             #                   yellow that keeps the ordering is the better
                             #                   trade
  ochre-wash          '187'  # ECE2C7 -> D7D7AF  light wash
  ochre-wash-dark     '237'  # 31333C -> 3A3A3A  dark wash
  ochre-edge          '101'  # 988246 -> 87875F  olive. Deliberately not 137 — the accent may
                             #                   not be confusable with a caution ring
  ochre-edge-dark     '101'  # 8A7E60 -> 87875F  dE 7.7; same value, other register

  # --- Neutral-chip + disabled ramps ---
  # The five light washes and putty-fill are within a few RGB units of each other in the DS
  # itself — E5DECB, E6DCC5, E7DEC6, E8E2C9, E9DDC6, ECE2C7. They are indistinguishable at
  # 24-bit, so collapsing them onto one index loses nothing that was ever there. The same
  # holds for the four dark washes and slate-wash. State is carried by the glyph regardless.
  putty-wash          '187'  # E7DEC6 -> D7D7AF
  putty-line          '244'  # 908171 -> 808080  a 3:1 edge on cream; shares with slate-line,
                             #                   which is dark-only
  putty-text          '246'  # 9B8D7B -> 949494  disabled, ~2.7:1 by design; stays dim
  putty-fill          '187'  # E6DCC5 -> D7D7AF
  putty-hair          '144'  # B9AC99 -> AFAF87  warm rather than gray; shares with
                             #                   cream-muted, which is dark-only
  slate-wash          '237'  # 2F3341 -> 3A3A3A
  slate-line          '244'  # 827F78 -> 808080  dE 4.2
  slate-text          '60'   # 586281 -> 5F5F87  dE 6.8; shares with ink-blue, light-only
  slate-fill          '236'  # 252B42 -> 303030  under slate-wash, as the DS has it
  slate-hair          '239'  # 414965 -> 4E4E4E  5F5F87 is closer in hue but is already
                             #                   slate-text, and a disabled ring must not
                             #                   read as disabled text

  # --- Hairlines / borders ---
  hair-light          '187'  # E4D8BE -> D7D7AF  a rule on cream, one step down from it
  hair-dark           '238'  # 333C58 -> 444444  a rule on navy, and clear of navy-soft — the
                             #                   pair nearest-neighbour would have merged
)

# ---------------------------------------------------------------------------------------
# Eight colours. There is no tuning left to do at this depth, only a scheme, so here it is
# once rather than fifty times:
#
#   surfaces, fills and dark ink            0   every dark background and every dark text
#   creams, and neutral text on dark        7
#   caramel and ochre                       3   the warm accent and caution share a yellow
#   madder                                  1
#   sage                                    2
#   ink-blue                                4
#   light washes                            7   a tint on cream is still cream
#   dark washes                             0   a tint on navy is still navy
#
# Collisions are the medium: fifty tokens into eight slots. The one invariant that survives
# is the one that has to — in the default (dark) register, no role used as a foreground shares
# an index with a role used as the background under it. `negative-text` on `surface` is the
# case that matters, because a non-zero exit status that cannot be seen is worse than no
# colour at all. Every dark surface, fill and wash is 0 and every foreground is 1-4 or 7,
# which makes that hold by construction rather than by luck.
#
# Hairlines take 0 on light and 7 on dark. Heavy for a divider, and the alternative is a
# divider that is not there.

typeset -gA _inzsh_palette_8
_inzsh_palette_8=(
  cream               '7'
  cream-soft          '7'
  cream-bright        '7'
  cream-muted         '7'
  cream-deep          '7'

  choc                '0'
  choc-soft           '0'
  choc-ink            '0'

  navy                '0'
  navy-soft           '0'
  navy-deep           '0'

  caramel             '3'
  caramel-bright      '3'

  sage                '2'
  sage-bright         '2'
  ink-blue            '4'
  ink-blue-bright     '4'

  sage-deep           '2'
  sage-wash           '7'
  sage-wash-dark      '0'
  sage-edge           '2'
  sage-edge-dark      '2'
  ink-blue-wash       '7'
  ink-blue-wash-dark  '0'
  ink-blue-edge       '4'
  ink-blue-edge-dark  '4'

  madder              '1'
  madder-bright       '1'
  madder-wash         '7'
  madder-wash-dark    '0'
  madder-edge         '1'
  madder-edge-dark    '1'

  ochre               '3'
  ochre-bright        '3'
  ochre-wash          '7'
  ochre-wash-dark     '0'
  ochre-edge          '3'
  ochre-edge-dark     '3'

  putty-wash          '7'
  putty-line          '0'
  putty-text          '0'
  putty-fill          '7'
  putty-hair          '0'
  slate-wash          '0'
  slate-line          '7'
  slate-text          '7'
  slate-fill          '0'
  slate-hair          '7'

  hair-light          '0'
  hair-dark           '7'
)
