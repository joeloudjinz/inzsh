Describe 'environment'
  It 'runs specs under zsh'
    version() { echo "$ZSH_VERSION"; }
    When call version
    The output should not eq ''
  End

  It 'meets the zsh floor (5.8)'
    floor() { autoload -Uz is-at-least && is-at-least 5.8 "$ZSH_VERSION"; }
    When call floor
    The status should be success
  End

  It 'has zsh/mathfunc and zsh/datetime'
    mods() { zmodload zsh/mathfunc zsh/datetime; }
    When call mods
    The status should be success
  End
End
