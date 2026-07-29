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

  It 'measures multibyte glyphs by display width'
    When call inzsh_test_visible_width '·✓✕'
    The output should eq '3'
  End
End
