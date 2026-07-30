# The entry point — `inzsh.zsh-theme`, the file a plugin manager sources.
#
# Nothing here is `Include`d. Every example runs the real file in a fresh `zsh -f`, because what
# is under test is what SOURCING it does: the guard, the load order, and the two things that
# must not happen yet. A spec that loaded the theme into its own shell would be testing a
# different thing entirely, and would be sourcing work in progress into a live shell besides.
#
# The four properties, in the order they matter:
#
#   silent      a non-interactive shell gets no output, no escapes and a zero status
#   inert       and no functions, no roles and no PROMPT change either
#   loaded      an interactive shell gets the library, and still no PROMPT change — the
#               renderer and its precmd hook land at M2
#   idempotent  sourcing twice is sourcing once; plugin managers do it, so it has to be

# `zsh -f -i -c` is a genuinely interactive shell without an rc file or a tty. That is the only
# way to exercise the guard's true branch from a test runner, so it is worth naming: -f skips
# every startup file, -i sets the interactive option the theme reads, -c runs the script.
inzsh_spec_theme() {
  print -r -- "$SHELLSPEC_PROJECT_ROOT/inzsh.zsh-theme"
}

Describe 'the entry point'
  Describe 'non-interactive'
    It 'sources cleanly and says nothing at all'
      silent() {
        zsh -f -c 'source "$1"; print -r -- "status=$?"' inzsh-entry "$(inzsh_spec_theme)"
      }
      When call silent
      The output should eq 'status=0'
      The stderr should eq ''
    End

    It 'leaves the shell exactly as it found it — no functions, no roles, no PROMPT'
      inert() {
        zsh -f -c '
          local before=$PROMPT
          source "$1"
          local -a leaked=()
          [[ $PROMPT == $before ]]                   || leaked+=PROMPT
          (( ${+functions[_inzsh_tokens_resolve]} )) && leaked+=functions
          (( ${+_inzsh_role} ))                      && leaked+=roles
          (( ${+_inzsh_color_depth} ))               && leaked+=depth
          (( ${+_inzsh_theme_root} ))                && leaked+=root
          print -r -- "${leaked[*]}"
        ' inzsh-entry-inert "$(inzsh_spec_theme)"
      }
      When call inert
      The output should eq ''
    End

    # Structural, and deliberately so: the guard's correctness is a property of its POSITION.
    # Anything above it runs in every script and every `ssh host command` on the machine, so
    # the first line of the file that is not a comment or blank has to be the guard itself.
    It 'guards on the first executable line, above everything else'
      first_line() {
        local line
        while IFS= read -r line; do
          [[ -z ${line//[[:space:]]/} || $line == \#* ]] && continue
          print -r -- "$line"
          return 0
        done < "$(inzsh_spec_theme)"
      }
      When call first_line
      The output should eq '[[ -o interactive ]] || return 0'
    End
  End

  Describe 'interactive'
    It 'loads the library in dependency order and resolves the roles'
      loaded() {
        zsh -f -i -c '
          source "$1"
          local -a missing=() fn
          for fn in _inzsh_detect_color_depth _inzsh_tokens_resolve _inzsh_seg_color \
                    _inzsh_surface_mode _inzsh_surface_assign _inzsh_surfaces_valid; do
            (( ${+functions[$fn]} )) || missing+=$fn
          done
          (( ${#_inzsh_role} ))       || missing+=roles
          (( ${#_inzsh_palette} ))    || missing+=palette
          (( ${#_inzsh_palette_256} )) || missing+=palette-256
          (( ${#_inzsh_palette_8} ))  || missing+=palette-8
          [[ -n $_inzsh_color_depth ]] || missing+=depth
          [[ -d $_inzsh_theme_root ]]  || missing+=root
          print -r -- "${missing[*]}"
        ' inzsh-entry-loaded "$(inzsh_spec_theme)"
      }
      When call loaded
      The output should eq ''
      The stderr should eq ''
    End

    # The renderer lands at M2. Until it does, sourcing the theme must leave the user's prompt
    # alone rather than half-drawing one: an entry point that assigns PROMPT before there is
    # anything to draw is how a theme ships a broken prompt.
    It 'assigns no PROMPT and registers no hook — both are M2'
      quiescent() {
        zsh -f -i -c '
          local before=$PROMPT
          source "$1"
          local -a moved=()
          [[ $PROMPT == $before ]] || moved+=PROMPT
          [[ -z ${precmd_functions[*]} ]] || moved+=precmd:${precmd_functions[*]}
          [[ -z ${preexec_functions[*]} ]] || moved+=preexec:${preexec_functions[*]}
          print -r -- "${moved[*]}"
        ' inzsh-entry-quiescent "$(inzsh_spec_theme)"
      }
      When call quiescent
      The output should eq ''
    End

    # Plugin managers source a theme twice more often than anyone would like: a reload, a second
    # manager, a bundle and a checkout of the same files. The second source must land on the
    # same state as the first, not on a doubled one.
    It 'is idempotent — sourcing twice lands on the state sourcing once did'
      twice() {
        zsh -f -i -c '
          source "$1"
          local first="$_inzsh_register $_inzsh_color_depth ${#_inzsh_role}"
          first+=" ${_inzsh_role[accent]} ${#_inzsh_surface_cycle}"
          source "$1"
          local second="$_inzsh_register $_inzsh_color_depth ${#_inzsh_role}"
          second+=" ${_inzsh_role[accent]} ${#_inzsh_surface_cycle}"
          [[ $first == $second ]] && print -r -- same || print -r -- "$first / $second"
        ' inzsh-entry-twice "$(inzsh_spec_theme)"
      }
      When call twice
      The output should eq 'same'
      The stderr should eq ''
    End
  End
End
