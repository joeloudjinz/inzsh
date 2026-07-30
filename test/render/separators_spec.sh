Include lib/core/tokens.zsh
Include lib/core/config.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh

# Separators — `INZSH_SEPARATOR_STYLE` and the glyphs it chooses, in `lib/core/render.zsh`.
#
# Three styles: `arrow` (the filled powerline wedge), `round` (the same ribbon with rounded caps)
# and `divider` (a thin rule, and no filled boundary at all). What is gated here is the CHOOSING
# and what the chosen pair does to the drawn string — the table the pair comes out of is gated in
# `test/unit/glyphs_spec.sh`, and the chaining rule itself in `test/render/render_build_spec.sh`.
#
# No glyph is pasted into an assertion anywhere below. Every expectation names a `_inzsh_glyph`
# key, so a change of glyph is a change in one table and not a sweep through a spec file.

# Build one side with `n` plain segments under `style`, and leave behind everything an example
# might want: the built string, the separator the style chose, and every `%K{…}` value in draw
# order. A block's fill is at every ODD position in that list — the builder emits one for the
# block and one for the separator beside it, on both sides.
inzsh_sep_build() {
  emulate -L zsh
  setopt extended_glob

  local side=$1
  local INZSH_SEPARATOR_STYLE=$2
  local -i n=$3 i

  _inzsh_segment_text=()
  _inzsh_left=()
  _inzsh_right=()

  local -a order=()
  for (( i = 1; i <= n; i++ )); do
    order+=S$i
    _inzsh_segment_text[S$i]=seg$i
  done
  if [[ $side == right ]]; then
    _inzsh_right=("${order[@]}")
  else
    _inzsh_left=("${order[@]}")
  fi

  _inzsh_render_build "$side"
  typeset -g inzsh_sep_built=$REPLY
  typeset -g inzsh_sep_width=$_inzsh_render_width
  typeset -g inzsh_sep_glyph=$_inzsh_sep_left
  [[ $side == right ]] && typeset -g inzsh_sep_glyph=$_inzsh_sep_right

  typeset -ga inzsh_sep_fills
  inzsh_sep_fills=()
  local rest=$inzsh_sep_built
  while [[ $rest == *'%K{'* ]]; do
    rest=${rest#*'%K{'}
    inzsh_sep_fills+=${rest%%\}*}
  done

  return 0
}

# The structural claim for one side, one style and one length, as a diagnostic line:
#
#   count      n visible blocks draw n separators — n-1 boundaries and one cap.
#   cap        the open end of the ribbon is drawn over the TERMINAL's own background (`%k`),
#              which is the end that differs between the two sides: last on the left, first on
#              the right.
#   adjacent   no two blocks share a fill. Under the default `alternate` this holds for every
#              style; the case where it is allowed NOT to is the exemption group below.
inzsh_sep_probe() {
  emulate -L zsh
  setopt extended_glob

  local side=$1 style=$2
  local -i n=$3
  inzsh_sep_build "$side" "$style" "$n"

  local g=$inzsh_sep_glyph
  local -a bad=()

  local stripped=${inzsh_sep_built//"$g"/}
  local -i seps=$(( (${#inzsh_sep_built} - ${#stripped}) / ${#g} ))
  (( seps == n )) || bad+=count:$seps

  if [[ $side == right ]]; then
    [[ $inzsh_sep_built == '%k%F{'[^\}]#'}'"$g"'%K{'* ]] || bad+=cap
  else
    [[ $inzsh_sep_built == *'%k%F{'[^\}]#'}'"$g"'%f%k' ]] || bad+=cap
  fi

  local -i i
  for (( i = 3; i <= 2 * n - 1; i += 2 )); do
    [[ ${inzsh_sep_fills[i]} != ${inzsh_sep_fills[i - 2]} ]] || bad+=adjacent:$i
  done

  print -r -- "seps=$n broken=${bad[*]}"
  return 0
}

# A render core whose surface assigner has been replaced by a hostile one, run in a fresh `zsh -f`
# so the replacement cannot outlive the example. The stub reports itself as `ramp` and hands back
# a run of identical surfaces for every mode except `alternate`, which it lets through to the real
# assigner — so a style that enforces the invariant repairs the run and a style that is exempt
# keeps it. $1 the segment count, $2 the separator style.
inzsh_sep_hostile() {
  zsh -f -c '
    source "$1/lib/core/tokens.zsh"
    source "$1/lib/core/render.zsh"
    eval "inzsh_sep_real_assign() { ${functions[_inzsh_surface_assign]} }"
    _inzsh_surface_assign() {
      if [[ $INZSH_SURFACE_MODE == alternate ]]; then
        inzsh_sep_real_assign "$@"
        return 0
      fi
      typeset -ga reply
      reply=()
      local -i i
      for (( i = 1; i <= $1; i++ )); do reply+=surface; done
      typeset -g _inzsh_surface_mode_resolved=ramp
      return 0
    }
    typeset -g INZSH_SEPARATOR_STYLE=$3
    _inzsh_render_surfaces "$2"
    print -r -- "${reply[*]} mode=$_inzsh_surface_mode_resolved"
  ' inzsh-sep-hostile "$SHELLSPEC_PROJECT_ROOT" "$1" "$2"
}

Describe 'separator style'
  # ------------------------------------------------------------------------------------------
  Describe 'resolving the knob'
    # Config may never break the render, so every unreadable value lands on the shipped default
    # rather than on an error or on a blank boundary.
    Describe 'what a value resolves to'
      Parameters
        arrow     arrow
        round     round
        divider   divider
        Arrow     arrow
        ROUND     arrow
        'arrow '  arrow
        chartreuse arrow
        ''        arrow
        0         arrow
        -         arrow
      End

      It "resolves '$1' to $2"
        resolved() {
          local INZSH_SEPARATOR_STYLE=$1
          _inzsh_sep_style
          print -r -- "$_inzsh_sep_style_resolved"
        }
        When call resolved "$1"
        The output should eq "$2"
      End
    End

    It 'resolves to the default when the knob was never set at all'
      unset_knob() {
        unset INZSH_SEPARATOR_STYLE
        _inzsh_sep_style
        print -r -- "$_inzsh_sep_style_resolved"
      }
      When call unset_knob
      The output should eq 'arrow'
    End

    It 'is registered with the config layer, validator and default'
      # The knob goes through the same registry as every other one, so `_inzsh_config_get` and
      # `_inzsh_config_resolve` know about it without `render.zsh` telling them.
      registered() {
        print -r -- "${_inzsh_config_validators[INZSH_SEPARATOR_STYLE]}"
        print -r -- "${_inzsh_config_defaults[INZSH_SEPARATOR_STYLE]}"
      }
      When call registered
      The line 1 of output should eq 'enum:arrow|round|divider'
      The line 2 of output should eq 'arrow'
    End

    It 'resolves without a config layer at all'
      # `lib/core/render.zsh` is independently sourceable, and a render core that came up without
      # `lib/core/config.zsh` still has to read the knob and still has to refuse a bad value.
      alone() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local style; local -a seen=()
          for style in round chartreuse; do
            typeset -g INZSH_SEPARATOR_STYLE=$style
            _inzsh_sep_style
            seen+=$_inzsh_sep_style_resolved
          done
          print -r -- "${seen[*]} config=${+functions[_inzsh_config_get]}"
        ' inzsh-sep-alone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call alone
      The output should eq 'round arrow config=0'
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the Nerd Font answer'
    # 0 resolves any style to `divider`; 1 and `unknown` draw the powerline. `lib/core/detect.zsh`
    # never INFERS a 0, so the only way one arrives is a user reporting their own screen — which
    # is a statement worth obeying, where `unknown` is most terminals and worth nothing.
    Describe 'what each answer does to a powerline style'
      Parameters
        1       arrow    arrow
        unknown arrow    arrow
        ''      arrow    arrow
        0       arrow    divider
        0       round    divider
        0       divider  divider
        1       round    round
        unknown divider  divider
      End

      It "draws $3 when the font answer is '$1' and the style is $2"
        fonted() {
          local _inzsh_nerd_font=$1 INZSH_SEPARATOR_STYLE=$2
          _inzsh_sep_style
          print -r -- "$_inzsh_sep_style_resolved"
        }
        When call fonted "$1" "$2"
        The output should eq "$3"
      End
    End

    It 'draws the powerline when nothing answered the question at all'
      # An unset `_inzsh_nerd_font` — a render core sourced without a detect layer — is `unknown`
      # by another name, and `unknown` is not a no.
      undetected() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/render.zsh"
          _inzsh_sep_style
          print -r -- "$_inzsh_sep_style_resolved detected=${+_inzsh_nerd_font}"
        ' inzsh-sep-nofont "$SHELLSPEC_PROJECT_ROOT"
      }
      When call undetected
      The output should eq 'arrow detected=0'
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the glyphs a style chooses'
    # Every expectation names a token-layer key. A style that read the wrong key, or that carried
    # a literal of its own, fails here without anybody having to look at a glyph.
    Describe 'the pair per style'
      Parameters
        arrow   sep-left       sep-right
        round   sep-left-round sep-right-round
        divider divider        divider
      End

      It "draws $1 with the $2 / $3 glyphs"
        chosen() {
          local INZSH_SEPARATOR_STYLE=$1
          _inzsh_separators
          local -a wrong=()
          [[ $_inzsh_sep_left  == ${_inzsh_glyph[$2]} ]] || wrong+=left
          [[ $_inzsh_sep_right == ${_inzsh_glyph[$3]} ]] || wrong+=right
          print -r -- "${wrong[*]}"
        }
        When call chosen "$1" "$2" "$3"
        The output should eq ''
      End
    End

    It 'gives the two sides the same rule under divider and different wedges otherwise'
      # The mirror is a property of a POINT, and a thin rule has none. So `divider` is the one
      # style where the two sides are identical, and a build that mirrored it anyway would be
      # drawing a distinction that is not there.
      mirroring() {
        local style; local -a wrong=()
        for style in arrow round divider; do
          local INZSH_SEPARATOR_STYLE=$style
          _inzsh_separators
          if [[ $style == divider ]]; then
            [[ $_inzsh_sep_left == $_inzsh_sep_right ]] || wrong+=$style:mirrored
          else
            [[ $_inzsh_sep_left != $_inzsh_sep_right ]] || wrong+=$style:flat
          fi
        done
        print -r -- "${wrong[*]}"
      }
      When call mirroring
      The output should eq ''
    End

    It 'reads the pair fresh on every build rather than caching the first answer'
      # A knob is whatever the user's shell says right now. `INZSH_SEPARATOR_STYLE=round` typed at
      # a prompt takes effect at the next one, with no re-source and no new shell.
      live() {
        inzsh_sep_build left arrow 2
        local first=$inzsh_sep_glyph
        inzsh_sep_build left round 2
        local second=$inzsh_sep_glyph
        local -a wrong=()
        [[ $first  == ${_inzsh_glyph[sep-left]} ]]       || wrong+=first
        [[ $second == ${_inzsh_glyph[sep-left-round]} ]] || wrong+=second
        print -r -- "${wrong[*]}"
      }
      When call live
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  # Both caps and every boundary, for every style, on both sides, at every length a prompt is
  # likely to see. The cap is the piece that differs between the sides — the ribbon ends in open
  # terminal on the left and opens into it on the right — so a style that got its orientation
  # wrong fails here rather than looking slightly odd in a screenshot.
  Describe 'what a style draws'
    Parameters:matrix
      left right
      arrow round divider
      1 2 3 7
    End

    It "$1 / $2 / $3 segment(s) draw both caps and every boundary"
      When call inzsh_sep_probe "$1" "$2" "$3"
      The output should eq "seps=$3 broken="
    End
  End

  Describe 'the right prompt mirrors the left'
    # The rounded style is where a mirror can be got wrong invisibly: both halves are filled
    # semicircles, and swapping them draws a ribbon whose ends bulge INTO the terminal instead of
    # away from it. The two sides must therefore differ in glyph, in opening and in closing —
    # the same three claims `render_build_spec` makes for the arrow.
    It 'draws the rounded caps the other way round on the right'
      mirrored() {
        inzsh_sep_build left round 2
        local left=$inzsh_sep_built lglyph=$inzsh_sep_glyph
        inzsh_sep_build right round 2
        local -a same=()
        [[ $left != $inzsh_sep_built ]]                       || same+=shape
        [[ $lglyph == ${_inzsh_glyph[sep-left-round]} ]]      || same+=left-glyph
        [[ $inzsh_sep_glyph == ${_inzsh_glyph[sep-right-round]} ]] || same+=right-glyph
        [[ $lglyph != $inzsh_sep_glyph ]]                     || same+=glyph
        [[ $left == '%K'* && $inzsh_sep_built == '%k'* ]]     || same+=opening
        [[ $inzsh_sep_built == *' seg2 %f%k' ]]               || same+=closing
        print -r -- "${same[*]}"
      }
      When call mirrored
      The output should eq ''
    End

    It 'puts the rounded cap the ribbon opens with at the far end of each side'
      # Stated positionally: on the left the cap is the LAST separator and it is the only one
      # drawn over `%k`; on the right it is the FIRST. Both are single occurrences.
      capped() {
        local side; local -a wrong=()
        for side in left right; do
          inzsh_sep_build $side round 3
          local caps=${inzsh_sep_built//'%k'/}
          local -i n=$(( (${#inzsh_sep_built} - ${#caps}) / 2 ))
          # Two: the cap, and the reset that closes the line.
          (( n == 2 )) || wrong+=$side:caps=$n
        done
        print -r -- "${wrong[*]}"
      }
      When call capped
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the separator-visibility invariant'
    # A filled boundary is only visible while the two blocks it sits between differ. `arrow` and
    # `round` are filled, so an assignment that would put equal backgrounds side by side is
    # dropped for `alternate`, which holds the property by construction. `divider` draws its own
    # boundary and is exempt for exactly the reason `flat` is.
    Describe 'a filled style repairs a colliding assignment'
      Parameters
        arrow
        round
      End

      It "drops an invalid assignment under $1"
        When call inzsh_sep_hostile 4 "$1"
        The output should eq 'surface-soft hairline surface-soft hairline mode=alternate'
        The stderr should eq ''
      End
    End

    It 'leaves the same assignment alone under divider'
      # The whole exemption in one line: identical surfaces are drawn as they came, because the
      # rule between them does not depend on their being different.
      When call inzsh_sep_hostile 4 divider
      The output should eq 'surface surface surface surface mode=ramp'
      The stderr should eq ''
    End

    It 'asks the one predicate rather than restating it'
      # `_inzsh_surfaces_valid` is the invariant written down as code, and `divider` is put to it
      # AS `flat` rather than through a second exemption. So removing the delegate must break the
      # guard rather than leaving a private copy behind that quietly still works.
      delegated() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          unset -f _inzsh_surfaces_valid
          _inzsh_surface_assign() {
            typeset -ga reply
            reply=(surface surface surface)
            typeset -g _inzsh_surface_mode_resolved=ramp
            return 0
          }
          _inzsh_render_surfaces 3
          print -r -- "status=$? ${reply[*]}"
        ' inzsh-sep-delegate "$SHELLSPEC_PROJECT_ROOT" 2>/dev/null
      }
      When call delegated
      The output should start with 'status=0'
    End

    It 'holds under every style a user can set, valid or not'
      # The end-to-end version: whatever the knob says, the drawn ribbon is legible. `divider` is
      # exempt from the RULE, not from the outcome — under the default surface mode it separates
      # its blocks anyway, and this sweep says so.
      sweep() {
        local style; local -a bad=(); local -i i
        for style in arrow round divider Arrow chartreuse '' 0; do
          inzsh_sep_build left "$style" 5
          for (( i = 3; i <= 9; i += 2 )); do
            [[ ${inzsh_sep_fills[i]} != ${inzsh_sep_fills[i - 2]} ]] || bad+=${style:-empty}:$i
          done
        done
        print -r -- "${bad[*]}"
      }
      When call sweep
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'width accounting'
    # A style change is a glyph change, and the tracked width has to follow it. Measured back off
    # the finished string, so the builder and the measurer arrive at the same number by different
    # routes for each style rather than only for the default one.
    Describe 'the running total matches the drawn row'
      Parameters:matrix
        left right
        arrow round divider
      End

      It "agrees with _inzsh_width for $2 on the $1 prompt"
        agrees() {
          inzsh_sep_build "$1" "$2" 3
          _inzsh_width "$inzsh_sep_built"
          if [[ $inzsh_sep_width == $REPLY ]]; then
            print -r -- agree
          else
            print -r -- "tracked=$inzsh_sep_width measured=$REPLY"
          fi
        }
        When call agrees "$1" "$2"
        The output should eq 'agree'
      End
    End

    It 'costs the same row width whichever style drew it'
      # Every separator is one column, so a style is a change of shape and never of layout. A
      # style that cost two columns would push a block off a narrow terminal.
      even() {
        local style; local -a widths=()
        for style in arrow round divider; do
          inzsh_sep_build left "$style" 4
          widths+=$inzsh_sep_width
        done
        local -a unique=(${(u)widths})
        print -r -- "${#unique}"
      }
      When call even
      The output should eq '1'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the glyph table drives what gets drawn'
    It 'redraws all three former literal sites from the table'
      # The point of #156, as one example. The separators, the truncation marker and the failure
      # mark each used to carry a literal of their own; a table written before those three files
      # are sourced must now reach all of them. A site that kept its literal fails here.
      rewired() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          _inzsh_glyph[sep-left]=L
          _inzsh_glyph[sep-right]=R
          _inzsh_glyph[ellipsis]=E
          _inzsh_glyph[error]=X
          source "$1/lib/core/layout.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/retval.zsh"
          _inzsh_truncate_text abcdef 4
          local cut=$REPLY
          _inzsh_segment_retval_build 1
          print -r -- "$_inzsh_sep_left$_inzsh_sep_right $cut ${_inzsh_segment_text[RETVAL]}"
        ' inzsh-sep-rewired "$SHELLSPEC_PROJECT_ROOT"
      }
      When call rewired
      The output should eq 'LR abcE X 1'
      The stderr should eq ''
    End

    It 'falls back rather than drawing nothing when the table was never sourced'
      # Each of the three files stays independently sourceable. Without a token layer they draw
      # the ASCII stand-in — a prompt with plain boundaries beats a prompt with none.
      orphaned() {
        zsh -f -c '
          source "$1/lib/core/layout.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/retval.zsh"
          _inzsh_truncate_text abcdefgh 6
          print -r -- "$_inzsh_sep_left$_inzsh_sep_right $REPLY $_inzsh_retval_glyph"
        ' inzsh-sep-orphan "$SHELLSPEC_PROJECT_ROOT"
      }
      When call orphaned
      The output should eq "${_inzsh_glyph_ascii[sep-left]}${_inzsh_glyph_ascii[sep-right]}\
 abc${_inzsh_glyph_ascii[ellipsis]} ${_inzsh_glyph_ascii[error]}"
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'outside a multibyte locale'
    # The regression that has bitten twice: the file must LOAD, and then it must draw something a
    # single-byte terminal can show. Under `LC_ALL=C` a Nerd Font glyph could not be drawn even if
    # the bytes survived, so every style degrades — and the rounded pair keeps its mirror, which
    # is the only thing left of that style at this width.
    It 'gives every style an ASCII pair'
      ascii() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/render.zsh"
          local style; local -a seen=()
          for style in arrow round divider; do
            typeset -g INZSH_SEPARATOR_STYLE=$style
            _inzsh_separators
            seen+="$style:$_inzsh_sep_left$_inzsh_sep_right"
          done
          print -r -- "${seen[*]}"
        ' inzsh-sep-c "$SHELLSPEC_PROJECT_ROOT"
      }
      When call ascii
      The output should eq \
        "arrow:${_inzsh_glyph_ascii[sep-left]}${_inzsh_glyph_ascii[sep-right]}\
 round:${_inzsh_glyph_ascii[sep-left-round]}${_inzsh_glyph_ascii[sep-right-round]}\
 divider:${_inzsh_glyph_ascii[divider]}${_inzsh_glyph_ascii[divider]}"
      The stderr should eq ''
    End

    It 'still draws a whole ribbon, caps and all'
      # Not just the glyphs: the assembled prompt on the degraded path has the same shape as on
      # the real one, because the degradation is a different lookup and never a second code path.
      ribbon() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          setopt extended_glob
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/tokens.zsh"
          source "$1/lib/core/layout.zsh"
          source "$1/lib/core/render.zsh"
          typeset -g INZSH_SEPARATOR_STYLE=round
          _inzsh_segment_text=(A one B two)
          _inzsh_left=(A B)
          _inzsh_render_build left
          local out=$REPLY
          out=${out//(%[KF]\{[^\}]#\}|%[fk])/}
          print -r -- "[$out]"
        ' inzsh-sep-c-ribbon "$SHELLSPEC_PROJECT_ROOT"
      }
      When call ribbon
      The output should eq \
        "[ one ${_inzsh_glyph_ascii[sep-left-round]} two ${_inzsh_glyph_ascii[sep-left-round]}]"
      The stderr should eq ''
    End
  End
End
