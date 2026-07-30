Include test/render/helpers.zsh

Describe 'L2 render helpers'
  It 'expands prompt escapes'
    When call inzsh_test_expand_prompt '%%'
    The output should eq '%'
  End

  It 'strips ANSI escapes'
    When call inzsh_test_strip_ansi "$(printf '\033[31mred\033[0m')"
    The output should eq 'red'
  End

  It 'computes visible width excluding escapes'
    When call inzsh_test_visible_width "$(printf '\033[38;5;208mabc\033[0m')"
    The output should eq '3'
  End

  # Outside a multibyte locale zsh counts bytes rather than cells, so these three glyphs
  # measure nine. That is the locale's answer, not a defect in the helper.
  inzsh_spec_bytes_not_cells() {
    local sample=$'é'
    (( ${#sample} != 1 ))
  }

  It 'measures multibyte glyphs by display width'
    Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
    When call inzsh_test_visible_width '·✓✕'
    The output should eq '3'
  End
End
