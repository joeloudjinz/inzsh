Include lib/core/tokens.zsh

# Per-segment colour: override → role → fallback role → nothing. The configurability
# cornerstone, so every branch of the precedence is pinned here.
#
# No hex literals live in this file. An expected colour is always read back from
# `_inzsh_role` or `_inzsh_palette`, so a palette change can never make this spec lie. The
# override values are deliberately not hex either — a named colour and a 256 index, the two
# other forms `%F{...}` accepts, which also proves the resolver passes them through untouched.
Describe 'per-segment colour'
  Describe 'with no override set'
    Parameters
      DIR   bg surface
      DIR   fg text-body
      HOST  bg accent
      SALAH fg neutral-text
    End

    It "resolves $1 $2 to the $3 role"
      resolved() {
        _inzsh_seg_color "$1" "$2" "$3" || return
        [[ $REPLY == ${_inzsh_role[$3]} ]] && print -r -- 'role'
      }
      When call resolved "$1" "$2" "$3"
      The output should eq 'role'
    End
  End

  Describe 'with an override set'
    Parameters
      DIR   bg INZSH_DIR_BG   red
      DIR   fg INZSH_DIR_FG   237
      SALAH bg INZSH_SALAH_BG 237
      SALAH fg INZSH_SALAH_FG red
    End

    It "uses $3 verbatim for $1 $2, ahead of the role"
      override() {
        typeset -g "$3"="$4"
        _inzsh_seg_color "$1" "$2" surface || return
        [[ $REPLY == ${_inzsh_role[surface]} ]] && print -r -- 'the role won'
        print -r -- "$REPLY"
      }
      When call override "$1" "$2" "$3" "$4"
      The output should eq "$4"
    End
  End

  Describe 'precedence and fallbacks'
    # An `INZSH_DIR_BG=` left behind in someone's zshrc must not blank the segment.
    It 'treats an override that is set but empty as unset'
      blank() {
        typeset -g INZSH_DIR_BG=
        _inzsh_seg_color DIR bg surface || return
        [[ $REPLY == ${_inzsh_role[surface]} ]] && print -r -- 'role'
      }
      When call blank
      The output should eq 'role'
    End

    It 'takes the fallback role when the first role is unknown'
      fallback() {
        _inzsh_seg_color DIR bg no-such-role accent || return
        [[ $REPLY == ${_inzsh_role[accent]} ]] && print -r -- 'fallback'
      }
      When call fallback
      The output should eq 'fallback'
    End

    It 'prefers the first role over the fallback when both exist'
      preferred() {
        _inzsh_seg_color DIR bg accent surface || return
        [[ $REPLY == ${_inzsh_role[accent]} ]] && print -r -- 'first'
      }
      When call preferred
      The output should eq 'first'
    End

    # A missing role must never reach the prompt as a broken escape — the caller is told.
    It 'yields an empty result and a failing status for an unknown role with no fallback'
      When call _inzsh_seg_color DIR bg no-such-role
      The status should be failure
      The variable REPLY should eq ''
    End

    It 'yields an empty result and a failing status when the fallback is unknown too'
      When call _inzsh_seg_color DIR bg no-such-role no-such-fallback
      The status should be failure
      The variable REPLY should eq ''
    End

    It 'keeps overrides on different segments out of each other'
      independent() {
        typeset -g INZSH_DIR_BG=red
        local dir host
        _inzsh_seg_color DIR bg surface  && dir=$REPLY
        _inzsh_seg_color HOST bg surface && host=$REPLY
        [[ $host == ${_inzsh_role[surface]} ]] && print -r -- "$dir role"
      }
      When call independent
      The output should eq 'red role'
    End
  End

  Describe 'register awareness'
    It 'follows a register flip — the same call returns the light value after resolving light'
      flipped() {
        local dark light
        _inzsh_register=dark;  _inzsh_tokens_resolve
        _inzsh_seg_color DIR bg surface && dark=$REPLY
        _inzsh_register=light; _inzsh_tokens_resolve
        _inzsh_seg_color DIR bg surface && light=$REPLY
        [[ $dark == ${_inzsh_palette[navy]} && $light == ${_inzsh_palette[cream]} ]] &&
          print -r -- 'flipped'
      }
      When call flipped
      The output should eq 'flipped'
    End

    It 'keeps an override in force across a register flip'
      pinned() {
        typeset -g INZSH_DIR_BG=red
        local dark light
        _inzsh_register=dark;  _inzsh_tokens_resolve
        _inzsh_seg_color DIR bg surface && dark=$REPLY
        _inzsh_register=light; _inzsh_tokens_resolve
        _inzsh_seg_color DIR bg surface && light=$REPLY
        print -r -- "$dark $light"
      }
      When call pinned
      The output should eq 'red red'
    End
  End

  # Structural rather than behavioural: a fork on the render path is a cost you feel rather
  # than see, so the gate is that the token layer contains no command substitution at all.
  # Comment lines are skipped — prose there quotes zsh syntax.
  It 'resolves without forking — no command substitution in the token layer'
    substitutions() {
      setopt local_options extended_glob
      local line; local -a bad=()
      while IFS= read -r line; do
        [[ $line == [[:space:]]#\#* ]] && continue
        [[ $line == *'$('* || $line == *'`'* ]] && bad+=$line
      done < "$SHELLSPEC_PROJECT_ROOT/lib/core/tokens.zsh"
      print -r -- "${#bad}"
    }
    When call substitutions
    The output should eq '0'
  End
End
