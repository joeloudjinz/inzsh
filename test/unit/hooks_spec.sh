# The hook layer, read rather than run — `lib/core/hooks.zsh`.
#
# Nothing here is `Include`d and nothing here sources the file into the runner. Three of the
# four rules the hook layer exists to enforce are properties of the TEXT, not of a return
# value, and a spec that only ran the code would pass on a version that had lost them:
#
#   the capture is the first command in `_inzsh_precmd`   — one line lower and `$?` is 0
#   no hook is ever assigned, anywhere in the shipped source — an assignment discards the
#                                                             registrations of every other
#                                                             plugin, silently
#   precmd forks nothing                                  — a fork per prompt is invisible in
#                                                             every result and visible in every
#                                                             session
#
# The behaviour those rules protect is asserted in `test/render/hooks_render_spec.sh`, in real
# interactive subshells. Both halves are needed: a first line that captures the wrong thing
# fails there, a right capture that has drifted down the function fails here.

inzsh_spec_hooks() {
  print -r -- "$SHELLSPEC_PROJECT_ROOT/lib/core/hooks.zsh"
}

Describe 'the hook layer'
  Describe 'the exit-status capture'
    # Structural, and deliberately so: the capture's correctness is a property of its POSITION.
    # Whatever runs above it — an `emulate`, a `typeset`, a `local` — is a command, and a
    # command overwrites `$?` and `$pipestatus` with its own success before the theme has read
    # either. So the first line of the function body that is not blank and not a comment has to
    # be the capture itself, and it has to take both values in ONE assignment.
    It 'is the first executable line of _inzsh_precmd, above everything else'
      first_line() {
        setopt local_options extended_glob
        local line; local -i inside=0
        while IFS= read -r line; do
          if (( ! inside )); then
            [[ $line == '_inzsh_precmd() {' ]] && inside=1
            continue
          fi
          [[ -z ${line//[[:space:]]/} || ${line##[[:space:]]#} == \#* ]] && continue
          print -r -- "${line##[[:space:]]#}"
          return 0
        done < "$(inzsh_spec_hooks)"
      }
      When call first_line
      The output should eq '_inzsh_last_status=$? _inzsh_last_pipestatus=("${pipestatus[@]}")'
    End

    # The pair belongs to one command for the same reason it belongs to the first line.
    # `typeset` — or any other builtin — between the two reads leaves `$pipestatus` describing
    # that builtin, so the declarations live at source time and the capture is a bare
    # assignment. This example fails the moment a second command appears between them.
    It 'takes both values in a single assignment, so neither reads off the other'
      one_command() {
        setopt local_options extended_glob
        local body=$(<"$(inzsh_spec_hooks)")
        local -a bad=()
        [[ $body == *'_inzsh_last_status=$? _inzsh_last_pipestatus='* ]] || bad+=split
        [[ $body == *'typeset -g  _inzsh_last_status='* ]]               || bad+=undeclared
        [[ $body == *'typeset -ga _inzsh_last_pipestatus='* ]]           || bad+=unarrayed
        print -r -- "${bad[*]}"
      }
      When call one_command
      The output should eq ''
    End
  End

  # The registration rule, checked across everything that is shipped and sourced into a user's
  # shell rather than only across our own file. `precmd=`, `precmd_functions=(...)`, and the
  # `+=` that looks harmless are all the same bug from the other plugins' point of view: the
  # array is shared, and the theme that writes it directly owns whatever it happened to hold.
  #
  # The subject is padded with spaces so an occurrence at the start of a line is still preceded
  # by a non-word character, which is what keeps `_inzsh_precmd() {` from matching.
  Describe 'registration'
    It 'never assigns a hook array anywhere in the shipped source'
      assignments() {
        setopt local_options extended_glob null_glob
        local root=$SHELLSPEC_PROJECT_ROOT
        local -a files=(
          $root/inzsh.zsh-theme $root/lib/**/*.zsh $root/presets/*.zsh $root/tools/*.zsh
        )
        local f line; local -a bad=()
        (( ${#files} > 1 )) || bad+=no-files-scanned
        for f in $files; do
          while IFS= read -r line; do
            [[ ${line##[[:space:]]#} == \#* ]] && continue
            [[ " $line " == \
               *[^[:alnum:]_](precmd|preexec|chpwd|periodic)(|_functions)(|'+')=* ]] &&
              bad+="${f:t}: ${line##[[:space:]]#}"
          done < $f
        done
        print -rl -- $bad
      }
      When call assignments
      The output should eq ''
    End

    It 'goes through add-zsh-hook in both directions'
      delegated() {
        local body=$(<"$(inzsh_spec_hooks)")
        local -a missing=()
        [[ $body == *'autoload -Uz add-zsh-hook'* ]]           || missing+=autoload
        [[ $body == *'add-zsh-hook precmd _inzsh_precmd'* ]]   || missing+=install
        [[ $body == *'add-zsh-hook -d precmd _inzsh_precmd'* ]] || missing+=uninstall
        print -r -- "${missing[*]}"
      }
      When call delegated
      The output should eq ''
    End
  End

  # Structural rather than behavioural, exactly as in the detection spec: `_inzsh_precmd` runs
  # before every prompt in the session, so the cost that matters is a fork, and a fork is
  # invisible in the result. Comment lines are skipped — the prose above names `whence` and
  # `$(...)` precisely because it explains why we do not use them.
  Describe 'cost'
    It 'hooks without forking — no command substitution on the render path'
      forks() {
        setopt local_options extended_glob
        local line; local -a bad=()
        while IFS= read -r line; do
          [[ ${line##[[:space:]]#} == \#* ]] && continue
          [[ $line == *'$('* || $line == *'`'* || $line == *whence* ]] && bad+=$line
        done < "$(inzsh_spec_hooks)"
        print -r -- "${#bad}"
      }
      When call forks
      The output should eq '0'
    End
  End

  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$(inzsh_spec_hooks)"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    # One link in a chain — tokens, config, engine, then this — but each link has to stand on
    # its own for a bundle, a partial source or a spec to work. `zsh -f` because nothing else
    # of ours is loaded there, which is the point.
    It 'is independently sourceable and defines the three functions'
      standalone() {
        zsh -f -c '
          source "$1/lib/core/hooks.zsh" || print -r -- "non-zero exit"
          local -a missing=() fn
          for fn in _inzsh_precmd _inzsh_hooks_install _inzsh_hooks_uninstall; do
            (( ${+functions[$fn]} )) || missing+=$fn
          done
          print -r -- "${missing[*]}"
        ' inzsh-hooks-standalone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call standalone
      The output should eq ''
      The stderr should eq ''
    End

    # Nothing the theme defines may collide with a user's functions or another plugin's. The
    # check is a diff of `$functions` either side of the source rather than a list we maintain,
    # so a helper added later is caught without anyone remembering to add it here.
    It 'defines nothing outside the _inzsh_ prefix'
      prefixed() {
        zsh -f -c '
          local -a before=(${(k)functions})
          source "$1/lib/core/hooks.zsh"
          local -a added=(${${(k)functions}:|before})
          print -r -- "${${added:#_inzsh_*}[*]}"
        ' inzsh-hooks-prefix "$SHELLSPEC_PROJECT_ROOT"
      }
      When call prefixed
      The output should eq ''
    End
  End
End
