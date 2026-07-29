Include lib/core/tokens.zsh
Include lib/core/tokens-256.zsh

# The reduced-depth tables. The checklist is written out by hand, exactly as the palette spec
# writes it out, so a token added to the design system fails here until somebody has decided
# what it looks like at 256 colours and at 8 — the tables may not drift behind the palette.
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

# Each ramp in the order the design system puts it in, lightest first. Ordering is the one
# property a degraded palette has to keep: hue can go, but if `cream-bright` stops being
# lighter than `cream` the prompt stops being legible rather than merely plainer.
inzsh_spec_ramp_cream=(cream-bright cream-soft cream cream-deep cream-muted)
inzsh_spec_ramp_choc=(choc-soft choc choc-ink)
inzsh_spec_ramp_navy=(navy-soft navy navy-deep)
inzsh_spec_ramp_caramel=(caramel-bright caramel)
inzsh_spec_ramp_sage=(
  sage-wash sage-bright sage-edge sage-edge-dark sage sage-deep sage-wash-dark
)
inzsh_spec_ramp_ink_blue=(
  ink-blue-wash ink-blue-bright ink-blue-edge ink-blue-edge-dark ink-blue ink-blue-wash-dark
)
inzsh_spec_ramp_madder=(
  madder-wash madder-bright madder-edge madder-edge-dark madder madder-wash-dark
)
inzsh_spec_ramp_ochre=(
  ochre-wash ochre-bright ochre-edge ochre-edge-dark ochre ochre-wash-dark
)
inzsh_spec_ramp_putty=(putty-wash putty-fill putty-hair putty-text putty-line)
inzsh_spec_ramp_slate=(slate-line slate-text slate-hair slate-wash slate-fill)
inzsh_spec_ramp_hair=(hair-light hair-dark)

# Foreground role / background role, as the prompt actually stacks them. At 8 colours fifty
# tokens share eight slots, so most collisions are unavoidable and harmless; these are the
# ones that are neither. A `negative-text` the same index as the `surface` under it is a
# failed command you cannot see.
inzsh_spec_stacks=(
  text-strong   surface
  text-body     surface
  text-muted    surface
  accent        surface
  positive-text surface
  info-text     surface
  negative-text surface
  caution-text  surface
  neutral-text  surface
  hairline      surface
  text-body     surface-soft
  negative-text surface-soft
  on-accent     accent
  on-positive   positive
  on-info       info
  on-negative   negative
  on-caution    caution
  on-neutral    neutral
  positive-text positive-wash
  info-text     info-wash
  negative-text negative-wash
  caution-text  caution-wash
  neutral-text  neutral-wash
  inactive-text inactive-fill
)

# An xterm index carries its own colour: 16-231 are the 6x6x6 cube over the channel levels
# 0/95/135/175/215/255, and 232-255 are a 24-step gray ramp starting at 8 and rising by 10 in
# every channel at once. That arithmetic is the xterm specification, not our palette, so
# writing it out here is not a second transcription point. Decoding it here
# rather than writing brightness numbers into the spec means the ordering examples compare
# what the terminal will actually draw, and a re-tuned index is re-checked rather than
# re-asserted. sRGB gamma is applied before weighting: without it a deep blue and a near-black
# gray sort the wrong way round, which is precisely the pair this palette leans on.
inzsh_spec_luma() {
  emulate -L zsh
  local -i index=$1 r g b j
  local -a levels=(0 95 135 175 215 255)
  if (( index >= 232 )); then
    r=$(( 8 + (index - 232) * 10 )); g=$r; b=$r
  else
    j=$(( index - 16 ))
    r=${levels[$(( j / 36 + 1 ))]}
    g=${levels[$(( (j / 6) % 6 + 1 ))]}
    b=${levels[$(( j % 6 + 1 ))]}
  fi
  typeset -g inzsh_spec_luma_reply=$((
    0.2126 * (r / 255.0) ** 2.2 + 0.7152 * (g / 255.0) ** 2.2 + 0.0722 * (b / 255.0) ** 2.2
  ))
}

Describe 'reduced-depth palettes'
  Describe 'table shape'
    Parameters
      256 _inzsh_palette_256
      8   _inzsh_palette_8
    End

    It "exposes the $1-colour table as an associative array"
      kind() { print -r -- "${(Pt)1}"; }
      When call kind "$2"
      The output should start with 'association'
    End

    It "the $1-colour table carries every token on the checklist"
      missing() {
        local -A table=("${(@Pkv)1}")
        local name; local -a gone=()
        for name in $inzsh_spec_tokens; do
          [[ -n ${table[$name]+set} ]] || gone+=$name
        done
        print -r -- "${gone[*]}"
      }
      When call missing "$2"
      The output should eq ''
    End

    It "the $1-colour table carries nothing the checklist does not name"
      extra() {
        local -A table=("${(@Pkv)1}")
        local name; local -a unexpected=()
        for name in ${(ko)table}; do
          (( ${inzsh_spec_tokens[(Ie)$name]} )) || unexpected+=$name
        done
        print -r -- "${unexpected[*]}"
      }
      When call extra "$2"
      The output should eq ''
    End

    It "the $1-colour table holds exactly the expected number of entries"
      count() {
        local -A table=("${(@Pkv)1}")
        print -r -- "${#table} ${#inzsh_spec_tokens}"
      }
      When call count "$2"
      The output should eq '50 50'
    End

    # The checklist could go stale in both files at once. This one cannot: it compares the
    # fallback table against the palette the theme actually renders from.
    It "the $1-colour table has the same keys as the truecolor palette, no more and no fewer"
      parity() {
        local -A table=("${(@Pkv)1}")
        local name; local -a gone=() unexpected=()
        for name in ${(ko)_inzsh_palette}; do
          [[ -n ${table[$name]+set} ]] || gone+=$name
        done
        for name in ${(ko)table}; do
          [[ -n ${_inzsh_palette[$name]+set} ]] || unexpected+=$name
        done
        print -r -- "${gone[*]}${unexpected[*]}"
      }
      When call parity "$2"
      The output should eq ''
    End
  End

  Describe 'the 256-colour table'
    It 'stores every value as a bare index in 16-255'
      malformed() {
        local name value; local -a bad=()
        for name in ${(ko)_inzsh_palette_256}; do
          value=${_inzsh_palette_256[$name]}
          [[ $value == <16-255> ]] || bad+="$name=$value"
        done
        print -r -- "${bad[*]}"
      }
      When call malformed
      The output should eq ''
    End

    # 0-15 are the sixteen every terminal scheme repaints — Solarized, Gruvbox, the user's
    # own — so a token placed there is a token somebody else chose. 16-255 are fixed by the
    # xterm specification and mean what they say.
    It 'never reaches into the sixteen indices a colour scheme is allowed to remap'
      remappable() {
        local name; local -a bad=()
        for name in ${(ko)_inzsh_palette_256}; do
          (( ${_inzsh_palette_256[$name]} < 16 )) && bad+=$name
        done
        print -r -- "${bad[*]}"
      }
      When call remappable
      The output should eq ''
    End
  End

  Describe 'the 8-colour table'
    It 'stores every value as a bare ANSI index in 0-7'
      malformed() {
        local name value; local -a bad=()
        for name in ${(ko)_inzsh_palette_8}; do
          value=${_inzsh_palette_8[$name]}
          [[ $value == <0-7> ]] || bad+="$name=$value"
        done
        print -r -- "${bad[*]}"
      }
      When call malformed
      The output should eq ''
    End
  End

  # The collisions nearest-neighbour makes and a human would not. Each pair is two ramps that
  # can sit side by side in one prompt, so one index for both is one colour where the design
  # has two.
  Describe 'anti-collision'
    Parameters
      navy       choc        'the two registers defining darks, one cool and one warm'
      navy-soft  hair-dark   'a raised surface and the rule drawn on it'
      cream      cream-deep  'the light surface and the tint under it'
      sage       sage-deep   'the positive fill and the positive text beside it'
      caramel    ochre-edge  'the brand accent and a caution ring'
      choc-soft  madder      'muted text and negative text, both on cream'
    End

    It "keeps $1 and $2 apart at 256 colours — $3"
      distinct() {
        [[ ${_inzsh_palette_256[$1]} != ${_inzsh_palette_256[$2]} ]] && print -r -- 'distinct'
      }
      When call distinct "$1" "$2"
      The output should eq 'distinct'
    End
  End

  Describe 'the dark register state colours'
    # Four states, drawn from four ramps, all live at once in a single prompt line. If any two
    # share an index the prompt is telling the user something it does not mean.
    It 'gives madder-bright, ochre-bright, sage-bright and ink-blue-bright four indices'
      spread() {
        local name; local -a values=()
        for name in madder-bright ochre-bright sage-bright ink-blue-bright; do
          values+=${_inzsh_palette_256[$name]}
        done
        local -a distinct=(${(u)values})
        print -r -- "${#values} ${#distinct}"
      }
      When call spread
      The output should eq '4 4'
    End
  End

  Describe 'lightness ordering'
    Parameters
      cream    inzsh_spec_ramp_cream
      choc     inzsh_spec_ramp_choc
      navy     inzsh_spec_ramp_navy
      caramel  inzsh_spec_ramp_caramel
      sage     inzsh_spec_ramp_sage
      ink-blue inzsh_spec_ramp_ink_blue
      madder   inzsh_spec_ramp_madder
      ochre    inzsh_spec_ramp_ochre
      putty    inzsh_spec_ramp_putty
      slate    inzsh_spec_ramp_slate
      hair     inzsh_spec_ramp_hair
    End

    It "keeps the $1 ramp in order, lightest first, after quantisation"
      ordered() {
        local -a ramp=("${(@P)1}")
        local name; local -a inverted=()
        local previous=2 current
        for name in $ramp; do
          inzsh_spec_luma ${_inzsh_palette_256[$name]}
          current=$inzsh_spec_luma_reply
          (( current <= previous )) || inverted+=$name
          previous=$current
        done
        # A ramp that failed to load would compare vacuously and pass in silence.
        (( ${#ramp} >= 2 )) || inverted+=empty-ramp
        print -r -- "${inverted[*]}"
      }
      When call ordered "$2"
      The output should eq ''
    End

    # The decoder itself, pinned against three indices whose relationship is known by
    # inspection: pure white is the brightest thing in the table, the grayscale ramp climbs
    # with its index, and a deep blue outranks a darker gray despite the larger digits.
    It 'decodes an index to the brightness the terminal will actually draw'
      decoder() {
        local white ramp_low ramp_high blue gray; local -a wrong=()
        inzsh_spec_luma 231; white=$inzsh_spec_luma_reply
        inzsh_spec_luma 232; ramp_low=$inzsh_spec_luma_reply
        inzsh_spec_luma 255; ramp_high=$inzsh_spec_luma_reply
        inzsh_spec_luma 17;  blue=$inzsh_spec_luma_reply
        inzsh_spec_luma 233; gray=$inzsh_spec_luma_reply
        (( white > ramp_high ))   || wrong+=white
        (( ramp_high > ramp_low )) || wrong+=ramp
        (( blue > gray ))          || wrong+=gamma
        print -r -- "${wrong[*]}"
      }
      When call decoder
      The output should eq ''
    End
  End

  # Eight colours is a shortage, not a palette, so most tokens share. These are the shares
  # that would cost the user something they cannot recover: text and the thing under it.
  Describe 'the 8-colour foreground and background stacks'
    Parameters
      dark  _inzsh_roles_dark
      light _inzsh_roles_light
    End

    It "never puts text and its background on the same ANSI index in the $1 register"
      readable() {
        local -A register=("${(@Pkv)1}")
        local fg bg; local -a merged=()
        for fg bg in $inzsh_spec_stacks; do
          [[ ${_inzsh_palette_8[${register[$fg]}]} == ${_inzsh_palette_8[${register[$bg]}]} ]] &&
            merged+="$fg-on-$bg"
        done
        # An empty stack list, or roles that stopped resolving, would pass vacuously.
        (( ${#inzsh_spec_stacks} >= 2 )) || merged+=empty-stacks
        for fg bg in $inzsh_spec_stacks; do
          [[ -n ${register[$fg]} && -n ${register[$bg]} ]] || merged+="unknown:$fg/$bg"
        done
        print -r -- "${merged[*]}"
      }
      When call readable "$2"
      The output should eq ''
    End
  End

  Describe 'sourcing'
    # A bundle, a partial source or another spec may load this file on its own. It is pure
    # data and must not need the token layer, or anything else, underneath it.
    It 'is independently sourceable and defines both tables'
      standalone() {
        zsh -f -c '
          source "$1/lib/core/tokens-256.zsh" || print -r -- "non-zero exit"
          print -r -- "${#_inzsh_palette_256} ${#_inzsh_palette_8} ${#_inzsh_palette}"
        ' inzsh-tokens-256-standalone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call standalone
      The output should eq '50 50 0'
    End
  End
End
