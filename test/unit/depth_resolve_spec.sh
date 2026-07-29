Include lib/core/tokens.zsh
Include lib/core/tokens-256.zsh

# Degradation along one path. The register picks a palette KEY, the depth picks the table that
# turns that key into a VALUE, and there is a single loop underneath both — so what these
# examples are really pinning is that nothing else changes with the depth. Same roles, same
# count, same keys, different table.
#
# No literal colour value appears here, at any depth. Every expectation is read back out of
# the table the depth selects, so a re-tuned index or a re-transcribed hex cannot make this
# spec lie about what the resolver did.
Describe 'depth-aware resolution'
  Describe 'the register and depth matrix'
    # $1 the register, $2 its role table, $3 the depth, $4 the value table that depth selects.
    Parameters
      dark  _inzsh_roles_dark  truecolor _inzsh_palette
      dark  _inzsh_roles_dark  256       _inzsh_palette_256
      dark  _inzsh_roles_dark  8         _inzsh_palette_8
      light _inzsh_roles_light truecolor _inzsh_palette
      light _inzsh_roles_light 256       _inzsh_palette_256
      light _inzsh_roles_light 8         _inzsh_palette_8
    End

    It "resolves the $1 register at depth $3 entirely from $4"
      resolved() {
        local -A table=("${(@Pkv)2}") values=("${(@Pkv)4}")
        local role; local -a wrong=() unexpected=()
        _inzsh_register=$1
        _inzsh_color_depth=$3
        _inzsh_tokens_resolve
        for role in ${(ko)table}; do
          [[ ${_inzsh_role[$role]} == ${values[${table[$role]}]} ]] || wrong+=$role
        done
        for role in ${(ko)_inzsh_role}; do
          [[ -n ${table[$role]+set} ]] || unexpected+=$role
        done
        print -r -- "${#_inzsh_role} ${#wrong} ${#unexpected}"
      }
      When call resolved "$1" "$2" "$3" "$4"
      The output should eq '37 0 0'
    End
  End

  Describe 'the depth actually moves the values'
    # Structural agreement with a table is not enough on its own: a resolver that ignored the
    # depth entirely would still agree with the truecolor table at every depth if the tables
    # happened to match. They do not, and every role has to move when the depth does.
    Parameters
      dark  256
      dark  8
      light 256
      light 8
    End

    It "hands back something other than the truecolor value in the $1 register at depth $2"
      moved() {
        local -A truecolor=()
        local role; local -a same=()
        _inzsh_register=$1
        _inzsh_color_depth=truecolor
        _inzsh_tokens_resolve
        truecolor=("${(@kv)_inzsh_role}")
        _inzsh_color_depth=$2
        _inzsh_tokens_resolve
        for role in ${(ko)truecolor}; do
          [[ ${_inzsh_role[$role]} != ${truecolor[$role]} ]] || same+=$role
        done
        print -r -- "${#same}"
      }
      When call moved "$1" "$2"
      The output should eq '0'
    End
  End

  Describe 'anchor spot-checks'
    # $1 the register, $2 the role, $3 the depth, $4 the table it selects, $5 the palette key
    # the register's table names for that role.
    Parameters
      dark  surface       256       _inzsh_palette_256 navy
      dark  surface       8         _inzsh_palette_8   navy
      dark  surface       truecolor _inzsh_palette     navy
      light surface       8         _inzsh_palette_8   cream
      light surface       256       _inzsh_palette_256 cream
      dark  negative-text 256       _inzsh_palette_256 madder-bright
      light negative-text 8         _inzsh_palette_8   madder
      dark  accent        256       _inzsh_palette_256 caramel
      light hairline      256       _inzsh_palette_256 hair-light
    End

    It "resolves $1 $2 at depth $3 to the $5 entry of $4"
      anchor() {
        local -A values=("${(@Pkv)4}")
        _inzsh_register=$1
        _inzsh_color_depth=$3
        _inzsh_tokens_resolve
        [[ ${_inzsh_role[$2]} == ${values[$5]} ]] && print -r -- 'matched'
      }
      When call anchor "$1" "$2" "$3" "$4" "$5"
      The output should eq 'matched'
    End
  End

  Describe 'behaving as truecolor when it cannot do better'
    # Every way the depth can be absent or unusable is the same answer: draw the real palette.
    # A theme that refused to render because it could not work out the terminal would be worse
    # than one that renders too many colours.
    Parameters
      ''
      truecolor
      TRUECOLOR
      24bit
      16
      banana
      '256 '
      0
    End

    It "resolves from the truecolor palette for a depth of '$1'"
      fallback() {
        local -A expected=()
        local role; local -a wrong=()
        _inzsh_register=dark
        _inzsh_color_depth=truecolor
        _inzsh_tokens_resolve
        expected=("${(@kv)_inzsh_role}")
        _inzsh_color_depth=$1
        _inzsh_tokens_resolve
        for role in ${(ko)expected}; do
          [[ ${_inzsh_role[$role]} == ${expected[$role]} ]] || wrong+=$role
        done
        print -r -- "${wrong[*]}"
      }
      When call fallback "$1"
      The output should eq ''
    End

    It 'resolves from the truecolor palette when the depth is not set at all'
      unset_depth() {
        local role; local -a wrong=()
        _inzsh_register=dark
        unset _inzsh_color_depth
        _inzsh_tokens_resolve
        for role in ${(ko)_inzsh_roles_dark}; do
          [[ ${_inzsh_role[$role]} == ${_inzsh_palette[${_inzsh_roles_dark[$role]}]} ]] ||
            wrong+=$role
        done
        print -r -- "${#_inzsh_role} ${wrong[*]}"
      }
      When call unset_depth
      The output should eq '37 '
    End

    # The reduced tables live in their own file, and a bundle, an old install or a partial
    # source may not have it. A depth of 256 with no 256 table is not an error condition, it
    # is truecolor. Run in `zsh -f`, where the file genuinely has not been loaded.
    It 'resolves from the truecolor palette when the reduced tables were never sourced'
      absent() {
        zsh -f -c '
          typeset -g _inzsh_color_depth=256
          source "$1/lib/core/tokens.zsh"
          local -a wrong=()
          local role
          for role in ${(ko)_inzsh_roles_dark}; do
            [[ ${_inzsh_role[$role]} == ${_inzsh_palette[${_inzsh_roles_dark[$role]}]} ]] ||
              wrong+=$role
          done
          print -r -- "${#_inzsh_palette_256} ${#_inzsh_role} ${#wrong}"
        ' inzsh-depth-absent "$SHELLSPEC_PROJECT_ROOT"
      }
      When call absent
      The output should eq '0 37 0'
    End

    # Belt and braces for a table that loaded but came up short — a key added to the palette
    # and not yet tuned. The role gets the wrong depth, which is visible and survivable; what
    # it must never get is an empty value, which reaches the prompt as a broken escape.
    It 'falls back per key to the truecolor value for a token the reduced table is missing'
      partial() {
        _inzsh_register=dark
        _inzsh_color_depth=256
        unset "_inzsh_palette_256[navy]"
        _inzsh_tokens_resolve
        local -a wrong=()
        [[ ${_inzsh_role[surface]} == ${_inzsh_palette[navy]} ]] || wrong+=surface
        [[ ${_inzsh_role[accent]} == ${_inzsh_palette_256[caramel]} ]] || wrong+=accent
        local role
        for role in ${(ko)_inzsh_role}; do
          [[ -n ${_inzsh_role[$role]} ]] || wrong+="empty:$role"
        done
        print -r -- "${wrong[*]}"
      }
      When call partial
      The output should eq ''
    End
  End

  Describe 'no role is left without a value'
    Parameters
      dark  truecolor
      dark  256
      dark  8
      light truecolor
      light 256
      light 8
    End

    It "gives every role in the $1 register a value at depth $2"
      populated() {
        local role; local -a empty=()
        _inzsh_register=$1
        _inzsh_color_depth=$2
        _inzsh_tokens_resolve
        for role in ${(ko)_inzsh_role}; do
          [[ -n ${_inzsh_role[$role]} ]] || empty+=$role
        done
        print -r -- "${#_inzsh_role} ${empty[*]}"
      }
      When call populated "$1" "$2"
      The output should eq '37 '
    End
  End

  Describe 'composition with the rest of the token layer'
    It 'tracks a depth change on the next resolve, in both directions'
      tracked() {
        local -a seen=()
        local depth
        _inzsh_register=dark
        for depth in truecolor 256 8 truecolor; do
          _inzsh_color_depth=$depth
          _inzsh_tokens_resolve
          seen+=${_inzsh_role[surface]}
        done
        local -a expected=(
          ${_inzsh_palette[navy]} ${_inzsh_palette_256[navy]}
          ${_inzsh_palette_8[navy]} ${_inzsh_palette[navy]}
        )
        [[ ${seen[*]} == ${expected[*]} ]] && print -r -- 'tracked'
      }
      When call tracked
      The output should eq 'tracked'
    End

    It 'keeps the register and the depth independent of each other'
      independent() {
        local -a wrong=()
        _inzsh_color_depth=256
        _inzsh_register=light; _inzsh_tokens_resolve
        [[ ${_inzsh_role[surface]} == ${_inzsh_palette_256[cream]} ]] || wrong+=light-256
        _inzsh_register=dark;  _inzsh_tokens_resolve
        [[ ${_inzsh_role[surface]} == ${_inzsh_palette_256[navy]} ]] || wrong+=dark-256
        _inzsh_color_depth=8
        [[ ${_inzsh_role[surface]} == ${_inzsh_palette_256[navy]} ]] || wrong+=resolve-needed
        _inzsh_tokens_resolve
        [[ ${_inzsh_role[surface]} == ${_inzsh_palette_8[navy]} ]] || wrong+=dark-8
        print -r -- "${wrong[*]}"
      }
      When call independent
      The output should eq ''
    End

    # The per-segment resolver reads `_inzsh_role` and knows nothing about depth — which is
    # the design. If it needed to, the swap would not be a table swap.
    It 'reaches the per-segment resolver without that resolver knowing about depth'
      segment() {
        local -a wrong=()
        _inzsh_register=dark
        _inzsh_color_depth=8
        _inzsh_tokens_resolve
        _inzsh_seg_color DIR bg surface || return
        [[ $REPLY == ${_inzsh_palette_8[navy]} ]] || wrong+=degraded
        _inzsh_color_depth=truecolor
        _inzsh_tokens_resolve
        _inzsh_seg_color DIR bg surface || return
        [[ $REPLY == ${_inzsh_palette[navy]} ]] || wrong+=truecolor
        print -r -- "${wrong[*]}"
      }
      When call segment
      The output should eq ''
    End

    # A user's explicit override outranks the palette at every depth — it is a value they
    # typed for their own terminal, and degrading it would be second-guessing them.
    It 'leaves a per-segment override untouched at every depth'
      override() {
        typeset -g INZSH_DIR_BG=red
        local -a seen=()
        local depth
        _inzsh_register=dark
        for depth in truecolor 256 8; do
          _inzsh_color_depth=$depth
          _inzsh_tokens_resolve
          _inzsh_seg_color DIR bg surface && seen+=$REPLY
        done
        print -r -- "${seen[*]}"
      }
      When call override
      The output should eq 'red red red'
    End
  End

  Describe 'source order'
    # The entry point loads detection and the reduced tables before this file, so the resolve
    # at the end of the token layer already knows the depth and no second pass is needed. A
    # forced environment stands in for a small terminal.
    It 'has the right depth by the time the token layer resolves at the end of its own file'
      ordered() {
        TERM=linux COLORTERM= INZSH_COLOR_DEPTH= zsh -f -c '
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/tokens-256.zsh"
          source "$1/lib/core/tokens.zsh"
          local -a wrong=()
          [[ ${_inzsh_role[surface]} == ${_inzsh_palette_8[navy]} ]] || wrong+=surface
          [[ ${_inzsh_role[accent]} == ${_inzsh_palette_8[caramel]} ]] || wrong+=accent
          print -r -- "$_inzsh_color_depth ${#wrong}"
        ' inzsh-depth-order "$SHELLSPEC_PROJECT_ROOT"
      }
      When call ordered
      The output should eq '8 0'
    End

    It 'reaches the same place when the override picks the depth instead of the terminal'
      forced() {
        TERM=xterm-256color COLORTERM=truecolor INZSH_COLOR_DEPTH=256 zsh -f -c '
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/tokens-256.zsh"
          source "$1/lib/core/tokens.zsh"
          local -a wrong=()
          [[ ${_inzsh_role[surface]} == ${_inzsh_palette_256[navy]} ]] || wrong+=surface
          print -r -- "$_inzsh_color_depth ${#wrong}"
        ' inzsh-depth-forced "$SHELLSPEC_PROJECT_ROOT"
      }
      When call forced
      The output should eq '256 0'
    End
  End

  # Same gate as the token layer's other examples: the depth swap may not have bought a fork.
  Describe 'cost'
    It 'still resolves without command substitution anywhere in the token layer'
      substitutions() {
        setopt local_options extended_glob
        local file line; local -a bad=()
        for file in tokens.zsh tokens-256.zsh; do
          while IFS= read -r line; do
            [[ $line == [[:space:]]#\#* ]] && continue
            [[ $line == *'$('* || $line == *'`'* ]] && bad+="$file:$line"
          done < "$SHELLSPEC_PROJECT_ROOT/lib/core/$file"
        done
        print -r -- "${#bad}"
      }
      When call substitutions
      The output should eq '0'
    End
  End
End
