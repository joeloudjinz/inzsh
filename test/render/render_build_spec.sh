Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh

# The assembly — `_inzsh_render_build` in `lib/core/render.zsh`. What the prompt STRING is: which
# blocks, in what order, carrying which escapes, and how wide the result claims to be.
#
# No hex, and no palette value of any kind, reaches this file. Every example that pins colour
# pins it STRUCTURALLY: the built string is rewritten so that each distinct colour value becomes
# a letter — A for the first value seen, B for the second — and the assertion is on the pattern
# of letters. `%K{A}%F{B} one %K{C}%F{A}>` reads as "this block's fill, this block's face, its
# text, then a separator filled with the NEXT block's colour and inked with THIS one's", which is
# the chaining rule itself, and a palette change cannot fail it.
#
# The one thing the shape deliberately cannot see is which value a letter stands for. The
# per-segment override group therefore reads the raw string, where the user's own value is the
# assertion.
#
# What is NOT here, and where it is instead:
#   the surface machinery       test/render/surfaces_spec.sh
#   rank sorting                test/unit/engine_spec.sh
#   width and truncation maths  test/unit/layout_spec.sh
#   what the terminal shows     test/ui/test_render_build.py

# The built string with every colour value replaced by a letter and the separator glyphs by `>`
# (left, U+E0B0) and `<` (right, U+E0B2). Answer in `inzsh_spec_shaped`.
inzsh_spec_shape() {
  emulate -L zsh

  local text=$1 out='' ch value tail
  local -A letter
  local -a alphabet=(A B C D E F G H I J)
  local -i i=1 n=${#text} next=1

  while (( i <= n )); do
    ch=${text[i]}
    if [[ $ch == '%' && ${text[i+1]} == [KF] && ${text[i+2]} == '{' ]]; then
      tail=${text[i+3,-1]}
      value=${tail%%\}*}
      [[ -n ${letter[$value]} ]] || { letter[$value]=${alphabet[next]}; (( next++ )) }
      out+="%${text[i+1]}{${letter[$value]}}"
      (( i += 4 + ${#value} ))
    else
      out+=$ch
      (( i++ ))
    fi
  done

  out=${out//$_inzsh_sep_left/'>'}
  out=${out//$_inzsh_sep_right/'<'}

  typeset -g inzsh_spec_shaped=$out
  return 0
}

# The shape as a token list in `inzsh_spec_tok`, so a sweep can assert POSITIONS rather than a
# whole string: `%K{A}` → `K:A`, `%k` → `K:-`, `%F{A}` → `F:A`, `%f` → `F:-`, a separator glyph →
# `S>` or `S<`, and any run of visible characters → a single `T`.
inzsh_spec_tokenise() {
  emulate -L zsh

  typeset -ga inzsh_spec_tok
  inzsh_spec_tok=()

  local shape=$1 ch value tail
  local -i i=1 n=${#shape}

  while (( i <= n )); do
    ch=${shape[i]}
    if [[ $ch == '%' && ${shape[i+1]} == [KF] && ${shape[i+2]} == '{' ]]; then
      tail=${shape[i+3,-1]}
      value=${tail%%\}*}
      inzsh_spec_tok+="${shape[i+1]}:$value"
      (( i += 4 + ${#value} ))
    elif [[ $ch == '%' && ${shape[i+1]} == [kf] ]]; then
      inzsh_spec_tok+="${(U)shape[i+1]}:-"
      (( i += 2 ))
    elif [[ $ch == '>' || $ch == '<' ]]; then
      inzsh_spec_tok+="S$ch"
      (( i++ ))
    else
      [[ ${inzsh_spec_tok[-1]} == T ]] || inzsh_spec_tok+=T
      (( i++ ))
    fi
  done

  return 0
}

# Build one side and leave everything an example might want behind it. $1 is the side; $2.. are
# SEGMENT TEXT pairs in render order. A text of `-` puts the segment on the side but leaves it out
# of the text map entirely — the absent case, where a stray separator would show up.
#
# Both rank arrays and the text map are reset every time, so no example can inherit the previous
# one's prompt. The role and importance maps are not reset here: the examples that use them
# shadow them with `local -A`, which is tidier and cannot leak either.
inzsh_spec_build() {
  emulate -L zsh

  local side=$1
  shift

  _inzsh_segment_text=()
  _inzsh_left=()
  _inzsh_right=()

  local -a order=()
  while (( $# >= 2 )); do
    order+=$1
    [[ $2 == '-' ]] || _inzsh_segment_text[$1]=$2
    shift 2
  done

  if [[ $side == right ]]; then
    _inzsh_right=("${order[@]}")
  else
    _inzsh_left=("${order[@]}")
  fi

  _inzsh_render_build "$side"
  typeset -g inzsh_spec_status=$?
  typeset -g inzsh_spec_built=$REPLY
  typeset -g inzsh_spec_width=$_inzsh_render_width

  inzsh_spec_shape "$inzsh_spec_built"
  inzsh_spec_tokenise "$inzsh_spec_shaped"

  return 0
}

# Build and print the shape. The workhorse of the literal-shape groups.
inzsh_spec_render() {
  inzsh_spec_build "$@"
  print -r -- "$inzsh_spec_shaped"
}

# The visible text of the last build, in the order it was drawn, with the escapes and separators
# taken out. Each block is ` text `, so neighbouring blocks abut as a double space and collapse
# back to one. Used where the claim is about ORDER and colour is beside the point.
inzsh_spec_bare() {
  emulate -L zsh
  setopt extended_glob

  local bare=$inzsh_spec_built
  bare=${bare//'%'[KF]'{'[^\}]#'}'/}
  bare=${bare//'%'[fk]/}
  bare=${bare//$_inzsh_sep_left/}
  bare=${bare//$_inzsh_sep_right/}
  print -r -- "${${bare//  / }## }"
}

# The chaining rule, checked positionally at any length, in any mode, on either side.
#
# One segment is six tokens, and their ORDER is the side's orientation:
#
#   left   K:bg  F:fg  T  K:next  F:bg  S>      the separator FOLLOWS its block
#   right  K:prev  F:bg  S<  K:bg  F:fg  T      the separator PRECEDES it
#
# so a build that drew the right prompt with the left prompt's orientation fails on the very
# first token. `K:-` is the terminal's own background and appears exactly twice: once on the cap
# — last on the left, first on the right — and once in the closing reset, because a prompt that
# leaves a background open colours the line the user is typing.
#
# $1 side, $2 the number of segments, $3 the surface mode.
inzsh_spec_chain() {
  emulate -L zsh

  local side=$1 mode=$3
  local INZSH_SURFACE_MODE=$mode
  local -i want=$2 i base caps=0
  local -a pairs=()

  for (( i = 1; i <= want; i++ )); do pairs+=(S$i seg$i); done
  inzsh_spec_build "$side" "${pairs[@]}"

  local -a tok=("${inzsh_spec_tok[@]}") bad=() bg=()
  local -i expected=0
  (( want )) && (( expected = 6 * want + 2 ))
  if (( ${#tok} != expected )); then
    print -r -- "segments=$want tokens=${#tok} want=$expected broken=length"
    return 0
  fi
  if (( ! want )); then
    print -r -- 'segments=0 tokens=0 broken='
    return 0
  fi

  # The fills first, so a separator can be judged against a neighbour that is already known.
  for (( i = 1; i <= want; i++ )); do
    (( base = (i - 1) * 6 ))
    if [[ $side == right ]]; then
      bg[i]=${tok[base + 4]#K:}
    else
      bg[i]=${tok[base + 1]#K:}
    fi
    [[ ${bg[i]} == [A-J] ]] || bad+=$i:no-fill
  done

  for (( i = 1; i <= want; i++ )); do
    (( base = (i - 1) * 6 ))
    if [[ $side == right ]]; then
      [[ ${tok[base + 3]} == 'S<' ]]         || bad+=$i:glyph
      [[ ${tok[base + 2]} == F:${bg[i]} ]]   || bad+=$i:ink
      [[ ${tok[base + 5]} == F:[A-J] ]]      || bad+=$i:face
      [[ ${tok[base + 6]} == T ]]            || bad+=$i:text
      if (( i > 1 )); then
        [[ ${tok[base + 1]} == K:${bg[i - 1]} ]] || bad+=$i:fill
      else
        [[ ${tok[base + 1]} == 'K:-' ]] || bad+=$i:cap
      fi
    else
      [[ ${tok[base + 6]} == 'S>' ]]         || bad+=$i:glyph
      [[ ${tok[base + 5]} == F:${bg[i]} ]]   || bad+=$i:ink
      [[ ${tok[base + 2]} == F:[A-J] ]]      || bad+=$i:face
      [[ ${tok[base + 3]} == T ]]            || bad+=$i:text
      if (( i < want )); then
        [[ ${tok[base + 4]} == K:${bg[i + 1]} ]] || bad+=$i:fill
      else
        [[ ${tok[base + 4]} == 'K:-' ]] || bad+=$i:cap
      fi
    fi
    # The invariant, observed on the drawn string rather than on the assignment behind it.
    # `flat` is exempt: it has no filled boundary to lose.
    if (( i > 1 )) && [[ $mode != flat ]]; then
      [[ ${bg[i]} != ${bg[i - 1]} ]] || bad+=$i:adjacent
    fi
  done

  [[ ${tok[-2]} == 'F:-' && ${tok[-1]} == 'K:-' ]] || bad+=reset
  for (( i = 1; i <= ${#tok}; i++ )); do
    [[ ${tok[i]} == 'K:-' ]] && (( caps++ ))
  done
  (( caps == 2 )) || bad+=caps:$caps

  print -r -- "segments=$want tokens=${#tok} broken=${bad[*]}"
  return 0
}

# A render core whose surface assigner has been replaced by a hostile one, run in a fresh `zsh -f`
# so the replacement cannot outlive the example. $1 the segment count, $2 whether even `alternate`
# is sabotaged. The stub reports itself as `ramp` and hands back a run of identical surfaces —
# what a future mode, or a clobbered `_inzsh_surface_cycle`, would look like.
inzsh_spec_hostile() {
  zsh -f -c '
    source "$1/lib/core/render.zsh"
    eval "inzsh_spec_real_assign() { ${functions[_inzsh_surface_assign]} }"
    _inzsh_surface_assign() {
      if [[ $INZSH_SURFACE_MODE == alternate ]] && (( ! INZSH_SPEC_ALWAYS_BAD )); then
        inzsh_spec_real_assign "$@"
        return 0
      fi
      typeset -ga reply
      reply=()
      local -i i
      for (( i = 1; i <= $1; i++ )); do reply+=surface; done
      typeset -g _inzsh_surface_mode_resolved=ramp
      return 0
    }
    typeset -gi INZSH_SPEC_ALWAYS_BAD=$3
    _inzsh_render_surfaces "$2"
    print -r -- "${reply[*]} mode=$_inzsh_surface_mode_resolved"
  ' inzsh-render-hostile "$SHELLSPEC_PROJECT_ROOT" "$1" "${2:-0}"
}

Describe 'render assembly'
  # ------------------------------------------------------------------------------------------
  Describe 'nothing to draw'
    # Not an error, and not a nearly-empty string either. A prompt that comes back as `%f%k`
    # writes two escapes into a line that should have been left alone, and a caller that has to
    # check a status before drawing is a caller that will forget.
    Describe 'an empty side'
      Parameters
        left
        right
      End

      It "builds nothing for an empty $1 side"
        When call inzsh_spec_build "$1"
        The variable inzsh_spec_built should eq ''
        The variable inzsh_spec_width should eq 0
        The variable inzsh_spec_status should eq 0
      End
    End

    Describe 'a side name that is neither'
      # Config never breaks the render, and neither does a caller's typo. Both rank arrays are
      # deliberately non-empty here, so a build that ignored its argument would draw something.
      Parameters
        Left
        LEFT
        'left '
        centre
        ''
        0
        -
      End

      It "builds nothing for the side '$1'"
        astray() {
          _inzsh_segment_text=(A one B two)
          _inzsh_left=(A B)
          _inzsh_right=(A B)
          _inzsh_render_build "$1"
          print -r -- "status=$? len=${#REPLY} width=$_inzsh_render_width"
        }
        When call astray "$1"
        The output should eq 'status=0 len=0 width=0'
      End
    End

    It 'builds nothing when every ranked segment is missing from the text map'
      When call inzsh_spec_build left A - B - C -
      The variable inzsh_spec_built should eq ''
      The variable inzsh_spec_width should eq 0
    End

    It 'treats a set-but-empty entry as absent, the way every other layer does'
      blanked() {
        _inzsh_segment_text=(A '' B '')
        _inzsh_left=(A B)
        _inzsh_render_build left
        print -r -- "len=${#REPLY} width=$_inzsh_render_width"
      }
      When call blanked
      The output should eq 'len=0 width=0'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the left prompt'
    # The wedge points right and follows its block. Read the second case aloud: fill A, face B,
    # ` one `, then a separator filled with C — the NEXT block — and inked with A, the one just
    # drawn. The final separator is filled with `%k`, the terminal's own background.
    Describe 'the shape'
      Parameters
        1 '%K{A}%F{B} one %k%F{A}>%f%k'
        2 '%K{A}%F{B} one %K{C}%F{A}>%K{C}%F{B} two %k%F{C}>%f%k'
        3 '%K{A}%F{B} one %K{C}%F{A}>%K{C}%F{B} two %K{A}%F{C}>%K{A}%F{B} three %k%F{A}>%f%k'
      End

      It "chains $1 segment(s) left to right"
        render() {
          local -a pairs=(A one B two C three)
          inzsh_spec_render left "${pairs[@]:0:$(( 2 * $1 ))}"
        }
        When call render "$1"
        The output should eq "$2"
      End
    End
  End

  Describe 'the right prompt'
    # Mirrored, and it has to be: the right prompt's ribbon ends at the RIGHT edge and OPENS on
    # the left, so the wedge points left (U+E0B2) and each separator PRECEDES its block. The cap
    # is therefore the FIRST separator, not the last, and the ink is the background of the block
    # the separator introduces rather than of the one behind it.
    #
    # Worked example, two segments A then B: `%k%F{bgA}<` opens the ribbon over the terminal's own
    # background with A's colour as the ink; ` one ` is drawn on bgA; `%K{bgA}%F{bgB}<` is the
    # boundary, sitting on A's background and inked with B's; then ` two ` on bgB.
    Describe 'the shape'
      Parameters
        1 '%k%F{A}<%K{A}%F{B} one %f%k'
        2 '%k%F{A}<%K{A}%F{B} one %K{A}%F{C}<%K{C}%F{B} two %f%k'
        3 '%k%F{A}<%K{A}%F{B} one %K{A}%F{C}<%K{C}%F{B} two %K{C}%F{A}<%K{A}%F{B} three %f%k'
      End

      It "chains $1 segment(s) right to left"
        render() {
          local -a pairs=(A one B two C three)
          inzsh_spec_render right "${pairs[@]:0:$(( 2 * $1 ))}"
        }
        When call render "$1"
        The output should eq "$2"
      End
    End

    It 'is not the left prompt drawn backwards — the orientation itself differs'
      # The strongest single statement of the mirror: same segments, same order, and the two
      # sides still share no structure at all.
      mirrored() {
        inzsh_spec_build left A one B two
        local left=$inzsh_spec_shaped
        inzsh_spec_build right A one B two
        local -a same=()
        [[ $left == $inzsh_spec_shaped ]] && same+=shape
        [[ $left == *'>'* && $inzsh_spec_shaped == *'<'* ]] || same+=glyph
        [[ $left == '%K'* && $inzsh_spec_shaped == '%k'* ]] || same+=opening
        [[ $left == *'>%f%k' && $inzsh_spec_shaped == *' two %f%k' ]] || same+=closing
        print -r -- "${same[*]}"
      }
      When call mirrored
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  # The rule, positionally, at every length either side is likely to see and in every mode. The
  # literal shapes above say what two and three segments look like; this says what n of them must
  # always look like, and it is the example that fails if the orientations are ever swapped.
  Describe 'chaining at any length'
    Parameters:matrix
      left right
      alternate ramp flat
      0 1 2 3 7
    End

    It "$1 / $2 / $3 segment(s) chain correctly"
      When call inzsh_spec_chain "$1" "$3" "$2"
      The output should eq "segments=$3 tokens=$(( $3 ? 6 * $3 + 2 : 0 )) broken="
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'a segment with no text'
    # The classic artefact: a segment drops out of the run and leaves its separator behind, so
    # the prompt grows a dangling wedge in a colour nothing else uses. It cannot happen here
    # because visibility is decided before a single surface is assigned — an absent segment never
    # enters the run, so there is no boundary for a separator to sit on.
    Describe 'the survivors chain as if the absentee were never ranked'
      # $1 which of three positions is missing, $2 the shape the survivors must draw.
      Parameters
        first  '%K{A}%F{B} two %K{C}%F{A}>%K{C}%F{B} three %k%F{C}>%f%k'
        middle '%K{A}%F{B} one %K{C}%F{A}>%K{C}%F{B} three %k%F{C}>%f%k'
        last   '%K{A}%F{B} one %K{C}%F{A}>%K{C}%F{B} two %k%F{C}>%f%k'
      End

      It "drops the $1 segment without leaving a separator"
        absent() {
          case $1 in
            (first)  inzsh_spec_render left A - B two C three ;;
            (middle) inzsh_spec_render left A one B - C three ;;
            (last)   inzsh_spec_render left A one B two C - ;;
          esac
        }
        When call absent "$1"
        The output should eq "$2"
      End
    End

    It 'draws one separator per VISIBLE segment, never one per ranked segment'
      # Counted rather than pattern-matched, on both sides and at every number of absentees, so a
      # stray separator anywhere in the row shows up as a number and not as a near-miss.
      counted() {
        local side glyph stripped; local -i present i seps blocks
        local -a wrong=() pairs=() texts=()
        for side in left right; do
          for present in 0 1 2 3; do
            pairs=(A - B - C - D -)
            for (( i = 1; i <= present; i++ )); do pairs[$(( 2 * i ))]=seg$i; done
            inzsh_spec_build $side "${pairs[@]}"
            glyph='>'
            [[ $side == right ]] && glyph='<'
            stripped=${inzsh_spec_shaped//$glyph/}
            (( seps = ${#inzsh_spec_shaped} - ${#stripped} ))
            (( seps == present )) || wrong+=$side:$present:seps=$seps
            texts=(${(M)inzsh_spec_tok[@]:#T})
            (( blocks = ${#texts} ))
            (( blocks == present )) || wrong+=$side:$present:blocks=$blocks
          done
        done
        print -r -- "${wrong[*]}"
      }
      When call counted
      The output should eq ''
    End

    It 'spends no surface on an absent segment — the run is the visible run'
      # Four ranked, two visible: the assignment must be two long, not four. A build that assigned
      # over the ranked list would give the two survivors positions 1 and 4 of an alternating
      # sequence — the same surface — and the boundary between them would vanish.
      spent() {
        inzsh_spec_build left A one B - C - D four
        print -r -- "${#inzsh_spec_tok} ${inzsh_spec_tok[1]} ${inzsh_spec_tok[7]}"
      }
      When call spent
      The output should eq '14 K:A K:C'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'rank order'
    # The builder never sorts. It reads `_inzsh_left` / `_inzsh_right` in the order
    # `_inzsh_rank_split` left them, so a rank change is visible in the drawn string with no other
    # input moving at all.
    Describe 'reordering by rank alone'
      # $1 DIR's rank, $2 GIT's, $3 CLOCK's, $4 the visible text in drawn order.
      Parameters
        1  2  3  'dir git clock'
        3  2  1  'clock git dir'
        10 4  1  'clock git dir'
        1  10 4  'dir clock git'
        2  2  1  'clock dir git'
      End

      It "draws ranks ($1,$2,$3) as $4"
        ordered() {
          local INZSH_DIR_RANK=$1 INZSH_GIT_RANK=$2 INZSH_CLOCK_RANK=$3
          _inzsh_segment_text=(DIR dir GIT git CLOCK clock)
          _inzsh_rank_split DIR GIT CLOCK
          _inzsh_render_build left
          typeset -g inzsh_spec_built=$REPLY
          inzsh_spec_bare
        }
        When call ordered "$1" "$2" "$3" "$4"
        The output should eq "$4 "
      End
    End

    It 'draws the right prompt most-negative-first, counting inward from the edge'
      # -1 is the RIGHTMOST segment, so ascending rank order is already render order and the
      # segment nearest the edge is the one drawn LAST.
      inward() {
        local INZSH_A_RANK=-1 INZSH_B_RANK=-2 INZSH_C_RANK=-3
        _inzsh_segment_text=(A alpha B beta C gamma)
        _inzsh_rank_split A B C
        _inzsh_render_build right
        typeset -g inzsh_spec_built=$REPLY
        print -r -- "${_inzsh_right[*]} | $(inzsh_spec_bare)"
      }
      When call inward
      The output should eq 'C B A | gamma beta alpha '
    End

    It 'hides a rank of zero from both sides without disturbing the chain'
      hidden() {
        local INZSH_A_RANK=1 INZSH_B_RANK=0 INZSH_C_RANK=2
        _inzsh_segment_text=(A alpha B beta C gamma)
        _inzsh_rank_split A B C
        _inzsh_render_build left
        inzsh_spec_shape "$REPLY"
        print -r -- "${_inzsh_hidden[*]} | $inzsh_spec_shaped"
      }
      When call hidden
      The output should eq \
        'B | %K{A}%F{B} alpha %K{C}%F{A}>%K{C}%F{B} gamma %k%F{C}>%f%k'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'surface modes'
    # `_inzsh_render_surfaces` is the guard: whatever the mode produced, what gets DRAWN holds the
    # invariant. The check is on the assignment rather than on the knob, because only the sequence
    # can answer "do two adjacent blocks share a surface".
    It 'drops a mode that produced an invalid assignment for alternate'
      When call inzsh_spec_hostile 4
      The output should eq 'surface-soft hairline surface-soft hairline mode=alternate'
      The stderr should eq ''
    End

    It 'draws anyway when even alternate cannot produce a valid one'
      # The floor. A clobbered `_inzsh_surface_cycle` or a half-sourced bundle makes every mode
      # invalid; a prompt whose separators are hard to see beats no prompt at all, so the
      # assignment is drawn as it stands rather than the build failing or looping.
      When call inzsh_spec_hostile 3 1
      The output should eq 'surface surface surface mode=ramp'
      The stderr should eq ''
    End

    It 'leaves a valid assignment exactly as the mode produced it'
      kept() {
        local INZSH_SURFACE_MODE=flat
        _inzsh_render_surfaces 4
        print -r -- "${reply[*]} mode=$_inzsh_surface_mode_resolved"
      }
      When call kept
      The output should eq 'surface surface surface surface mode=flat'
    End

    It 'honours the per-segment importance vector under ramp'
      # `_inzsh_segment_importance` is read for the VISIBLE run, in drawn order, so an absent
      # segment's importance is not consumed by the segment after it. Importances 1, 3, 2 give
      # three DIFFERENT surfaces; a build that had read the ranked list's 1, 3, 3 would collide
      # and repair to two.
      weighted() {
        local INZSH_SURFACE_MODE=ramp
        local -A _inzsh_segment_importance=(A 1 B 3 C 3 D 2)
        inzsh_spec_build left A one B - C three D four
        print -r -- "${inzsh_spec_tok[1]} ${inzsh_spec_tok[7]} ${inzsh_spec_tok[13]}"
      }
      When call weighted
      The output should eq 'K:A K:C K:D'
    End

    It 'falls back to the middle of the ramp for an unreadable importance'
      unreadable() {
        local INZSH_SURFACE_MODE=ramp
        local -A _inzsh_segment_importance=(A x B '' C 9)
        inzsh_spec_render left A one B two C three
      }
      When call unreadable
      # All three default to 2, all three collide, and the collision rule pulls them apart — the
      # same three surfaces `_inzsh_surface_assign 3 2 2 2` gives on its own.
      The output should eq \
        '%K{A}%F{B} one %K{C}%F{A}>%K{C}%F{B} two %K{A}%F{C}>%K{A}%F{B} three %k%F{A}>%f%k'
    End

    It 'draws a legible ribbon under every mode a user can set, valid or not'
      # The end-to-end version of the invariant: whatever `INZSH_SURFACE_MODE` says, no two
      # adjacent blocks in the finished string share a fill. `flat` is the one exemption.
      sweep() {
        local INZSH_SURFACE_MODE; local -a bad=(); local -i i
        for INZSH_SURFACE_MODE in alternate ramp flat Alternate chartreuse '' 0; do
          inzsh_spec_build left A one B two C three D four E five
          [[ $INZSH_SURFACE_MODE == flat ]] && continue
          for (( i = 7; i <= 25; i += 6 )); do
            [[ ${inzsh_spec_tok[i]} != ${inzsh_spec_tok[i - 6]} ]] ||
              bad+=${INZSH_SURFACE_MODE:-empty}:$i
          done
        done
        print -r -- "${bad[*]}"
      }
      When call sweep
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'per-segment colour'
    # `_inzsh_seg_color` owns the precedence — override, then role, then fallback role — and the
    # builder asks it rather than re-deriving it, so `INZSH_<SEG>_BG` and `INZSH_<SEG>_FG` work
    # here without the builder knowing they exist. Named colours, never hex: what is asserted is
    # that the user's value arrived verbatim, and any value zsh's `%K{…}` accepts proves that.
    It 'draws the override verbatim in both channels'
      overridden() {
        local INZSH_A_BG=magenta INZSH_A_FG=blue
        inzsh_spec_build left A one B two
        local -a missing=()
        [[ $inzsh_spec_built == *'%K{magenta}%F{blue} one '* ]] || missing+=block
        print -r -- "${missing[*]}"
      }
      When call overridden
      The output should eq ''
    End

    It 'carries the override into the separator inked with that background'
      # The chaining reads the same background the block was filled with, so an override changes
      # the boundary beside it too. A separator left on the role's colour would draw a seam.
      seamless() {
        local INZSH_A_BG=magenta
        inzsh_spec_build left A one B two
        local -a missing=()
        [[ $inzsh_spec_built == *"%F{magenta}$_inzsh_sep_left"* ]] || missing+=ink
        print -r -- "${missing[*]}"
      }
      When call seamless
      The output should eq ''
    End

    It 'carries it the other way on the right prompt — the ink is the block ahead'
      backwards() {
        local INZSH_B_BG=magenta
        inzsh_spec_build right A one B two
        local -a missing=()
        # B is the second block, so its colour inks the separator BEFORE it and fills the block
        # immediately after that separator.
        [[ $inzsh_spec_built == *"%F{magenta}$_inzsh_sep_right%K{magenta}"* ]] || missing+=ink
        print -r -- "${missing[*]}"
      }
      When call backwards
      The output should eq ''
    End

    It 'reads the foreground role a segment registered, and text-body when it registered none'
      roled() {
        local -A _inzsh_segment_fg_role=(A accent)
        inzsh_spec_build left A one B two
        local -a wrong=()
        [[ $inzsh_spec_built == *"%F{${_inzsh_role[accent]}} one "* ]]    || wrong+=accent
        [[ $inzsh_spec_built == *"%F{${_inzsh_role[text-body]}} two "* ]] || wrong+=default
        print -r -- "${wrong[*]}"
      }
      When call roled
      The output should eq ''
    End

    It 'treats a set-but-empty override as unset rather than blanking the block'
      emptied() {
        local INZSH_A_BG= INZSH_A_FG=
        inzsh_spec_render left A one
      }
      When call emptied
      The output should eq '%K{A}%F{B} one %k%F{A}>%f%k'
    End

    It 'resets the channel rather than emitting an empty escape when no role resolves'
      # `%K{}` reaches the screen as a literal pair of braces. A role the palette does not carry
      # must cost colour and nothing else, so the empty answer becomes `%k` / `%f` instead.
      unresolvable() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          _inzsh_seg_color() { typeset -g REPLY=; return 1 }
          _inzsh_segment_text=(A one B two)
          _inzsh_left=(A B)
          _inzsh_render_build left
          print -r -- "${REPLY//$_inzsh_sep_left/>}"
        ' inzsh-render-unresolvable "$SHELLSPEC_PROJECT_ROOT"
      }
      When call unresolvable
      The output should eq '%k%f one %k%f>%k%f two %k%f>%f%k'
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'width accounting'
    # The width is tracked as the pieces go on, never measured off the finished string — the
    # result is escape-laden and its width cannot be recovered from it. These examples measure the
    # finished string anyway, with `_inzsh_width`, and require the two to agree: the builder and
    # the measurer must arrive at the same number by different routes.
    Describe 'the running total matches the drawn row'
      # $1 the side, $2.. the segment texts. Deliberately hostile: escapes that occupy no columns,
      # a literal per cent, a multibyte glyph, and an empty text in the middle of a run.
      Parameters
        left  'plain'
        right 'plain'
        left  'one' 'two' 'three' 'four' 'five' 'six' 'seven'
        right 'one' 'two' 'three' 'four' 'five' 'six' 'seven'
        left  '%F{red}coloured%f'
        right '%F{red}coloured%f' 'plain'
        left  '100%% done'
        left  'ellipsis…'
        left  'main' '%F{red}x%f 1' ''
        left  '%{'$'\e''[1m%}bold%{'$'\e''[0m%}'
      End

      It "agrees with _inzsh_width for ($2 …) on the $1 prompt"
        agrees() {
          local side=$1
          shift
          local text; local -i i=0; local -a pairs=()
          for text in "$@"; do
            (( i++ ))
            pairs+=(S$i "$text")
          done
          inzsh_spec_build "$side" "${pairs[@]}"
          _inzsh_width "$inzsh_spec_built"
          if [[ $inzsh_spec_width == $REPLY ]]; then
            print -r -- agree
          else
            print -r -- "tracked=$inzsh_spec_width measured=$REPLY"
          fi
        }
        When call agrees "$@"
        The output should eq 'agree'
      End
    End

    It 'counts a block as its visible text plus one column of padding either side'
      # Stated as arithmetic rather than as a number, so the example survives a change of glyph:
      # n blocks and n separators, every block two columns wider than its text.
      arithmetic() {
        local side; local -a wrong=() texts=(one 'two two' 'three•three')
        _inzsh_width_raw "$_inzsh_sep_left"
        local -i sep=$REPLY want i
        for side in left right; do
          want=0
          for (( i = 1; i <= ${#texts}; i++ )); do
            _inzsh_width "${texts[i]}"
            (( want += REPLY + 2 + sep ))
          done
          inzsh_spec_build $side S1 "${texts[1]}" S2 "${texts[2]}" S3 "${texts[3]}"
          (( inzsh_spec_width == want )) || wrong+=$side:$inzsh_spec_width/$want
        done
        print -r -- "${wrong[*]}"
      }
      When call arithmetic
      The output should eq ''
    End

    It 'is not fooled by escapes in the injected text'
      # Two prompts with the same visible text, one of which carries colour runs of its own. A
      # builder that measured characters rather than columns would report the escapes as width.
      escaped() {
        inzsh_spec_build left A 'main' B 'ok'
        local -i plain=$inzsh_spec_width
        inzsh_spec_build left A '%F{red}main%f' B '%K{blue}ok%k'
        print -r -- "plain=$plain escaped=$inzsh_spec_width"
      }
      When call escaped
      The output should eq 'plain=12 escaped=12'
    End

    It 'reports zero for a side that drew nothing, even after a side that drew something'
      zeroed() {
        inzsh_spec_build left A one
        inzsh_spec_build right
        print -r -- "$inzsh_spec_width"
      }
      When call zeroed
      The output should eq '0'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'hostile input'
    # None of this can come from a user's config — the text map is the theme's own — but the
    # builder is the last thing between a segment's mistake and the line the user is typing.
    It 'survives a segment name that cannot form a variable'
      # `_inzsh_seg_color` builds `INZSH_<NAME>_BG` and reads it through `${(P)…}`, which is a
      # FATAL error on a non-identifier. The block loses its colour; the prompt keeps its shape,
      # its separators and its status.
      unnameable() {
        _inzsh_segment_text=('a b' one ok two)
        _inzsh_left=('a b' ok)
        _inzsh_render_build left
        local -i rc=$?
        inzsh_spec_shape "$REPLY"
        print -r -- "status=$rc $inzsh_spec_shaped"
      }
      When call unnameable
      The output should eq 'status=0 %k%f one %K{A}%f>%K{A}%F{B} two %k%F{A}>%f%k'
      The stderr should eq ''
    End

    It 'passes a separator glyph in the text through without re-chaining on it'
      # The glyph is data here, not structure. Three come out of a two-segment prompt: one per
      # boundary the builder drew, plus the one the segment carried.
      carried() {
        _inzsh_segment_text=(A "left${_inzsh_sep_left}right" B two)
        _inzsh_left=(A B)
        _inzsh_render_build left
        local stripped=${REPLY//$_inzsh_sep_left/}
        print -r -- "$(( ${#REPLY} - ${#stripped} ))"
      }
      When call carried
      The output should eq '3'
    End

    It 'draws a very long side without losing the chain'
      # Twenty segments is more than any prompt will hold, and the point is that nothing in the
      # assembly is length-dependent — no fixed cycle, no reused index, no silent truncation.
      When call inzsh_spec_chain left 20 alternate
      The output should eq 'segments=20 tokens=122 broken='
    End

    It 'leaves the rank arrays exactly as it found them'
      # The builder reads the split; it must never write it. A build that sorted, filtered or
      # reordered in place would make the second prompt differ from the first.
      readonly_split() {
        # One of the three is absent, so a build that wrote the VISIBLE run back would
        # shorten the array and the second prompt would differ from the first.
        inzsh_spec_build left A one B - C three
        local first=$inzsh_spec_built after=${_inzsh_left[*]}
        _inzsh_render_build left
        [[ $first == $REPLY ]] || print -r -- 'unstable'
        print -r -- "$after / ${_inzsh_left[*]}"
      }
      When call readonly_split
      The output should eq 'A B C / A B C'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the dormant dispatch'
    # `lib/core/hooks.zsh` runs `_inzsh_render` before every prompt the moment a function of that
    # exact name exists. There are no segments until M3, so such a function would draw an EMPTY
    # prompt over the user's real one. These examples are the tripwire: sourcing the render core
    # must define no `_inzsh_render` and assign no PROMPT.
    It 'defines no function called _inzsh_render'
      dormant() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local -a live=()
          (( ${+functions[_inzsh_render]} ))       && live+=_inzsh_render
          (( ${+functions[_inzsh_render_build]} )) || live+=missing-builder
          print -r -- "${live[*]}"
        ' inzsh-render-dormant "$SHELLSPEC_PROJECT_ROOT"
      }
      When call dormant
      The output should eq ''
      The stderr should eq ''
    End

    It 'leaves PROMPT and RPROMPT untouched, through a source and two builds'
      untouched() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local before="${PROMPT-unset}|${RPROMPT-unset}"
          _inzsh_segment_text=(A one)
          _inzsh_left=(A)
          _inzsh_render_build left
          _inzsh_render_build right
          local after="${PROMPT-unset}|${RPROMPT-unset}"
          [[ $before == $after ]] && print -r -- same || print -r -- "$before / $after"
        ' inzsh-render-prompt "$SHELLSPEC_PROJECT_ROOT"
      }
      When call untouched
      The output should eq 'same'
      The stderr should eq ''
    End

    # Structural, and deliberately so: the rule is about the TEXT of the file, not about what
    # sourcing it happens to do today. An assignment guarded by a condition that is false right
    # now is still an assignment waiting to fire.
    It 'contains no PROMPT or RPROMPT assignment anywhere in the render core'
      grepped() {
        setopt local_options extended_glob
        local line bare; local -a found=()
        while IFS= read -r line; do
          bare=${line##[[:space:]]#}
          [[ -z $bare || $bare == \#* ]] && continue
          [[ $bare == *((|R)PROMPT|PS1)=* ]] && found+=$bare
        done < "$SHELLSPEC_PROJECT_ROOT/lib/core/render.zsh"
        print -r -- "${found[*]}"
      }
      When call grepped
      The output should eq ''
    End
  End
End
