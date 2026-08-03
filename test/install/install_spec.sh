# The installer — `install.zsh`, run against a throwaway HOME and never any other kind.
#
# Every example builds its own HOME with `mktemp -d`, runs the installer inside it, asserts,
# and removes it. Nothing here reads or writes the real one: the installer sees the fake via
# the environment, and the shell that proves the install works is a subshell whose HOME is the
# fake too. That is the whole safety story, so it is enforced in one place — every run goes
# through `inzsh_spec_in_home`, and there is no other way to invoke the installer from this
# file.
#
# The three verbs under test, and the state each must leave:
#
#   install     .zshrc carries the managed block; the pre-install .zshrc is backed up first
#   reinstall   nothing changes — not the file, not the backup, not a byte
#   uninstall   .zshrc is back to its pre-install content; the backup stays for the user

# Run `$1` as a zsh body with HOME set to a fresh throwaway, $HOME/.zshrc optionally seeded
# from `$2`, and the installer reachable as `$installer`. The body runs in `zsh -f`, so no
# rc file of the developer's leaks in, and the throwaway is removed whatever the body did.
inzsh_spec_in_home() {
  local body=$1 seed=${2-}
  zsh -f -c '
    local root=$1 body=$2 seed=$3
    local home=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-install.XXXXXX")
    [[ -n $seed ]] && print -r -- "$seed" > $home/.zshrc
    local installer=$root/install.zsh
    # HOME moves to the throwaway; ZDOTDIR is UNSET rather than emptied — zsh treats an
    # empty-but-set ZDOTDIR as a real directory and stops reading $HOME/.zshrc at all.
    export HOME=$home
    unset ZDOTDIR
    () { eval "$body" }
    local status_=$?
    rm -rf -- $home
    return $status_
  ' inzsh-install-home "$SHELLSPEC_PROJECT_ROOT" "$body" "${seed}"
}

Describe 'the installer'
  Describe 'plain-source install'
    It 'creates .zshrc with the managed block in a clean environment'
      clean() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null || { print -r -- install-failed; return 1 }
          [[ -f $home/.zshrc ]] || { print -r -- no-zshrc; return 1 }
          grep -q ">>> inzsh >>>" $home/.zshrc &&
            grep -q "inzsh.zsh-theme" $home/.zshrc &&
            grep -q "<<< inzsh <<<" $home/.zshrc &&
            print -r -- installed
        '
      }
      When call clean
      The output should eq 'installed'
      The stderr should eq ''
    End

    It 'appends the block to an existing .zshrc and keeps every line of it'
      appends() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null
          head -1 $home/.zshrc
          grep -c "inzsh.zsh-theme" $home/.zshrc
        ' 'export EDITOR=vi'
      }
      When call appends
      The line 1 should eq 'export EDITOR=vi'
      The line 2 should eq 1
    End

    It 'backs up the pre-install .zshrc before touching it'
      backup() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null
          [[ -f $home/.zshrc.inzsh.bak ]] || { print -r -- no-backup; return 1 }
          print -r -- "$(<$home/.zshrc.inzsh.bak)"
        ' 'export EDITOR=vi'
      }
      When call backup
      The output should eq 'export EDITOR=vi'
    End

    It 'creates no backup when there was no .zshrc to back up'
      nothing_to_save() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null
          [[ -e $home/.zshrc.inzsh.bak ]] && print -r -- backup-of-nothing || print -r -- none
        '
      }
      When call nothing_to_save
      The output should eq 'none'
    End

    It 'loads the theme in a real interactive shell after install'
      loads() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null
          HOME=$home zsh -o NO_GLOBAL_RCS -i -c \
            "(( \${+functions[_inzsh_render]} )) && (( \${+_inzsh_segment_defaults[DIR]} )) &&
               print -r -- loaded || print -r -- not-loaded"
        '
      }
      When call loads
      The output should eq 'loaded'
      The stderr should eq ''
    End
  End

  Describe 'reinstall'
    It 'changes nothing — not the file, not the backup'
      twice() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null
          local file_before=$(<$home/.zshrc) bak_before=$(<$home/.zshrc.inzsh.bak)
          zsh -f $installer --plain >/dev/null
          local file_after=$(<$home/.zshrc) bak_after=$(<$home/.zshrc.inzsh.bak)
          [[ $file_before == $file_after && $bak_before == $bak_after ]] &&
            print -r -- unchanged || print -r -- changed
        ' 'export EDITOR=vi'
      }
      When call twice
      The output should eq 'unchanged'
    End

    It 'never doubles the block, however many times it runs'
      many() {
        inzsh_spec_in_home '
          local i
          for i in 1 2 3; do zsh -f $installer --plain >/dev/null; done
          grep -c ">>> inzsh >>>" $home/.zshrc
        ' 'export EDITOR=vi'
      }
      When call many
      The output should eq 1
    End

    It 'never overwrites the first backup — that is the pre-inzsh state'
      first_backup() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null
          print -r -- "# a line the user added after installing" >> $home/.zshrc
          zsh -f $installer --plain >/dev/null
          grep -c "user added" $home/.zshrc.inzsh.bak || true
        ' 'export EDITOR=vi'
      }
      When call first_backup
      The output should eq 0
    End
  End

  Describe 'uninstall'
    It 'restores the pre-install .zshrc exactly'
      restores() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null
          zsh -f $installer --uninstall >/dev/null
          print -r -- "$(<$home/.zshrc)"
        ' 'export EDITOR=vi'
      }
      When call restores
      The output should eq 'export EDITOR=vi'
    End

    It 'leaves the backup in place for the user'
      keeps_backup() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null
          zsh -f $installer --uninstall >/dev/null
          [[ -f $home/.zshrc.inzsh.bak ]] && print -r -- kept || print -r -- gone
        ' 'export EDITOR=vi'
      }
      When call keeps_backup
      The output should eq 'kept'
    End

    It 'is idempotent — uninstalling twice is uninstalling once'
      twice() {
        inzsh_spec_in_home '
          zsh -f $installer --plain >/dev/null
          zsh -f $installer --uninstall >/dev/null
          local before=$(<$home/.zshrc)
          zsh -f $installer --uninstall >/dev/null || { print -r -- failed; return 1 }
          [[ $before == $(<$home/.zshrc) ]] && print -r -- same || print -r -- different
        ' 'export EDITOR=vi'
      }
      When call twice
      The output should eq 'same'
      The stderr should eq ''
    End

    It 'succeeds quietly when nothing was ever installed'
      noop() {
        inzsh_spec_in_home '
          zsh -f $installer --uninstall >/dev/null && print -r -- ok
        ' 'export EDITOR=vi'
      }
      When call noop
      The output should eq 'ok'
      The stderr should eq ''
    End
  End
End
