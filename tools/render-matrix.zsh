#!/usr/bin/env zsh
# InZsh — the M1 review artifact. Draws the demonstration prompt across every combination a
# human has to judge before the engine is built, in one scroll.
#
# Two questions are being answered here, and they are the reason the matrix is a matrix:
#
#   fallback fidelity  Does the theme survive 256 and 8 colours, or does it become a different
#                      theme? Read a preset DOWN the depths — the three renders of one register
#                      are meant to be recognisably the same prompt.
#   the dark negative  Does madder-bright, the dusty rose the dark register uses for negative,
#                      read as a state at all? It is the ✕ in the fourth block.
#
# Every pass runs in its own `zsh -f` subshell, so nothing one combination sets can reach the
# next. Output goes to stdout AND to render-out/, which is gitignored: these are artifacts to
# look at and throw away, not golden files. A golden gate over the prompt lands at M8.
#
#   zsh -f tools/render-matrix.zsh

_inzsh_matrix_root=${${(%):-%x}:A:h:h}

_inzsh_matrix_run() {
  emulate -L zsh

  local out=$_inzsh_matrix_root/render-out
  mkdir -p $out || return 1

  local -a presets=(sharp warm)
  local -a depths=(truecolor 256 8)
  local preset depth mode rule text file
  local combined=$out/matrix.txt

  # A rule wide enough to separate two filled prompts without competing with them.
  rule=${(l:86::=:):-}

  : >| $combined

  _inzsh_matrix_emit() {
    # $1 the section title, $2 the file stem, $3.. the environment for the pass.
    local title=$1 stem=$2
    shift 2
    local body
    body=$(env "$@" zsh -f $_inzsh_matrix_root/tools/render.zsh)
    local block="$rule"$'\n'"  $title"$'\n'"$rule"$'\n'"$body"$'\n'
    print -rn -- "$block" >| $out/$stem.txt
    print -rn -- "$block" >> $combined
    print -rn -- "$block"
  }

  print -r -- "# InZsh M1 render matrix — artifacts also written to render-out/"
  print -r -- ''

  # Block one: both registers, every depth, in the default surface mode. This is the fidelity
  # comparison — same prompt, same mode, only the palette underneath it moves.
  for preset in $presets; do
    for depth in $depths; do
      _inzsh_matrix_emit "$preset · $depth · alternate" "$preset-$depth-alternate" \
        INZSH_PRESET=$preset INZSH_COLOR_DEPTH=$depth INZSH_SURFACE_MODE=alternate
    done
  done

  # Block two: the three surface modes, held at one preset and one depth so that the only thing
  # differing between them is the assignment.
  #
  # `flat` will look like one unbroken bar, and that is not a defect in the render: a solid
  # separator is only visible as the boundary between two different backgrounds, and flat has
  # none. A flat prompt wants a thin separator drawn in the hairline role instead — a glyph the
  # token layer will own at M2. It is here as the reason `alternate` is the default.
  print -r -- "# note: flat has no colour change at a boundary, so the solid separator is"
  print -r -- "# invisible there by construction. The thin separator that mode wants is M2."
  print -r -- ''
  for mode in alternate ramp flat; do
    _inzsh_matrix_emit "sharp · truecolor · $mode" "sharp-truecolor-$mode" \
      INZSH_PRESET=sharp INZSH_COLOR_DEPTH=truecolor INZSH_SURFACE_MODE=$mode
  done

  print -r -- "# $(( ${#presets} * ${#depths} + 3 )) renders written to ${out:t}/"
}

_inzsh_matrix_run "$@"
