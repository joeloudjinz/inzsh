Include lib/core/tokens.zsh

# Presets are overlays. Sourcing one picks a register and rebuilds the resolved roles from it,
# and that is the whole contract — an engine variable set from a preset, or a hex literal
# carried in one, is a bug. These examples pin both halves: the switch works in either
# direction and in either source order, and nothing else moves.
#
# No hex literal lives in this file either. A resolved role is asserted against the palette
# entry its register's table names — the second-copy carve-out belongs to the palette spec.

Describe 'presets'
  Describe 'switching register'
    # $1 the preset under test, $2 the one sourced first so every case is a real switch,
    # $3 the register it selects, $4 its role table, $5 the surface key, $6 the on-accent key.
    Parameters
      warm  sharp  light  _inzsh_roles_light  cream  cream
      sharp warm   dark   _inzsh_roles_dark   navy   choc
    End

    It "inzsh-$1 selects the $3 register"
      register() {
        source "$SHELLSPEC_PROJECT_ROOT/presets/inzsh-$2.zsh"
        source "$SHELLSPEC_PROJECT_ROOT/presets/inzsh-$1.zsh"
        print -r -- "$_inzsh_register"
      }
      When call register "$1" "$2"
      The output should eq "$3"
    End

    It "inzsh-$1 resolves surface to $5 and on-accent to $6"
      anchors() {
        source "$SHELLSPEC_PROJECT_ROOT/presets/inzsh-$2.zsh"
        source "$SHELLSPEC_PROJECT_ROOT/presets/inzsh-$1.zsh"
        local -a wrong=()
        [[ ${_inzsh_role[surface]}   == ${_inzsh_palette[$3]} ]] || wrong+=surface
        [[ ${_inzsh_role[on-accent]} == ${_inzsh_palette[$4]} ]] || wrong+=on-accent
        print -r -- "${wrong[*]}"
      }
      When call anchors "$1" "$2" "$5" "$6"
      The output should eq ''
    End

    It "inzsh-$1 rebuilds every role from the $3 table, not just the ones we name"
      rebuilt() {
        source "$SHELLSPEC_PROJECT_ROOT/presets/inzsh-$2.zsh"
        source "$SHELLSPEC_PROJECT_ROOT/presets/inzsh-$1.zsh"
        local -A table=("${(@Pkv)3}")
        local role; local -a wrong=() unexpected=()
        for role in ${(ko)table}; do
          [[ ${_inzsh_role[$role]} == ${_inzsh_palette[${table[$role]}]} ]] || wrong+=$role
        done
        for role in ${(ko)_inzsh_role}; do
          [[ -n ${table[$role]+set} ]] || unexpected+=$role
        done
        print -r -- "${#_inzsh_role} ${#wrong} ${#unexpected}"
      }
      When call rebuilt "$1" "$2" "$4"
      The output should eq '38 0 0'
    End
  End

  Describe 'source order'
    # A preset may land either side of the token layer — a plugin manager decides the order,
    # not us. Sourced after, the preset re-resolves itself; sourced before, it only leaves the
    # register behind and the token layer's own end-of-file resolve picks it up. Run in a
    # fresh `zsh -f` because this spec file has already loaded the token layer.
    It 'applies when the preset is sourced before the token layer'
      ordered() {
        zsh -f -c '
          source "$1/presets/inzsh-warm.zsh"
          source "$1/lib/core/tokens.zsh"
          local -a wrong=()
          [[ ${_inzsh_role[surface]}   == ${_inzsh_palette[cream]} ]] || wrong+=surface
          [[ ${_inzsh_role[on-accent]} == ${_inzsh_palette[cream]} ]] || wrong+=on-accent
          print -r -- "$_inzsh_register ${#wrong}"
        ' inzsh-preset-order "$SHELLSPEC_PROJECT_ROOT"
      }
      When call ordered
      The output should eq 'light 0'
    End

    It 'is a no-op beyond the register when the token layer is absent entirely'
      standalone() {
        zsh -f -c '
          source "$1/presets/inzsh-warm.zsh" || print -r -- "non-zero exit"
          print -r -- "$_inzsh_register ${#_inzsh_role}"
        ' inzsh-preset-standalone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call standalone
      The output should eq 'light 0'
    End
  End

  Describe 'overlay purity'
    # The boundary, enforced rather than documented: snapshot every parameter with `typeset -p`
    # either side of the source and compare line by line. Only the register and the rebuilt
    # role table may differ; any other name appearing, vanishing or changing value fails here.
    #
    # Snapshots go to files, not to locals, so that holding them cannot itself perturb the
    # second snapshot. `$snap` is assigned before either one and never changes, so it reads
    # identically in both.
    It 'changes the register and the resolved roles, and nothing else'
      purity() {
        # Touch `$functions` first. The preset's guard reads it, which lazily loads
        # zsh/parameter — a module load, not a variable the preset owns, and it would
        # otherwise surface as a spurious difference.
        : ${+functions[_inzsh_tokens_resolve]}
        local snap=${SHELLSPEC_TMPBASE:-${TMPDIR:-/tmp}}/inzsh-preset-purity
        mkdir -p $snap
        typeset -p >| $snap/before
        source "$SHELLSPEC_PROJECT_ROOT/presets/inzsh-warm.zsh"
        typeset -p >| $snap/after
        local -a before=("${(f)$(<$snap/before)}") after=("${(f)$(<$snap/after)}")
        local line; local -a touched=()
        # A snapshot that failed to write would compare equal to anything and pass silently.
        (( ${#before} > 1 && ${#after} > 1 )) || touched+=snapshot-empty
        for line in $after; do
          (( ${before[(Ie)$line]} )) || touched+=${${line%%=*}##* }
        done
        for line in $before; do
          (( ${after[(Ie)$line]} )) || touched+=${${line%%=*}##* }
        done
        # RANDOM and SECONDS move on their own between any two snapshots — reading one is what
        # changes it. They are the only volatile names zsh reports here; everything else that
        # moved, moved because something assigned to it.
        touched=(${(ou)touched})
        touched=(${touched:#(_inzsh_register|_inzsh_role|RANDOM|SECONDS)})
        print -r -- "${touched[*]}"
      }
      When call purity
      The output should eq ''
    End
  End

  Describe 'no colour of their own'
    Parameters
      warm
      sharp
    End

    # Structural, not chromatic: read the file and refuse a '#' followed by exactly six hex
    # digits. Bounded on both sides so ordinary prose — `# a decade of facade` — cannot match,
    # and so a literal at the very start of the file still does.
    It "inzsh-$1 carries no hex literal — presets set variables, the token layer holds colour"
      hexfree() {
        setopt local_options extended_glob
        local body=$(<"$SHELLSPEC_PROJECT_ROOT/presets/inzsh-$1.zsh")
        [[ $body == (|*[^[:xdigit:]])'#'[[:xdigit:]](#c6)(|[^[:xdigit:]]*) ]] &&
          print -r -- "hex literal in inzsh-$1.zsh"
        print -r -- 'clean'
      }
      When call hexfree "$1"
      The output should eq 'clean'
    End
  End
End
