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
    # The oh-my-zsh fixture, in one place because every omz example needs it and because it is
    # what makes the framework real rather than merely present: the directory AND a one-line
    # stand-in for `oh-my-zsh.sh` doing the one thing the installer relies on — sourcing
    # `$ZSH_CUSTOM/themes/$ZSH_THEME.zsh-theme`. The rc is left to the example.
    inzsh_spec_omz_dir() {
      mkdir -p $home/.oh-my-zsh/custom/themes
      print -r -- "source \${ZSH_CUSTOM:-\$ZSH/custom}/themes/\$ZSH_THEME.zsh-theme" \
        > $home/.oh-my-zsh/oh-my-zsh.sh
    }
    # The stock three-line omz rc, sourcing the stand-in above.
    inzsh_spec_omz_rc() {
      print -rl -- "export ZSH=\"\$HOME/.oh-my-zsh\"" \
        "ZSH_THEME=\"robbyrussell\"" \
        "source \$ZSH/oh-my-zsh.sh" > $home/.zshrc
    }
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

  # The oh-my-zsh path. No real oh-my-zsh is downloaded: the fixture is the three lines of a
  # stock omz `.zshrc` plus a one-line stand-in for `oh-my-zsh.sh` that does the one thing the
  # installer relies on — source `$ZSH_CUSTOM/themes/$ZSH_THEME.zsh-theme`. That keeps the
  # examples offline and pins the actual contract rather than omz's implementation.
  Describe 'oh-my-zsh install'
    It 'links the theme into custom/themes and takes over ZSH_THEME'
      omz() {
        inzsh_spec_in_home '
          inzsh_spec_omz_dir; inzsh_spec_omz_rc
          zsh -f $installer --omz >/dev/null || { print -r -- install-failed; return 1 }
          [[ -L $home/.oh-my-zsh/custom/themes/inzsh.zsh-theme ]] || { print -r -- no-link; return 1 }
          grep -q "^ZSH_THEME=\"inzsh\" # inzsh:managed$" $home/.zshrc || { print -r -- not-managed; return 1 }
          grep -q "^#ZSH_THEME=\"robbyrussell\" # inzsh:disabled$" $home/.zshrc || { print -r -- not-disabled; return 1 }
          print -r -- installed
        '
      }
      When call omz
      The output should eq 'installed'
      The stderr should eq ''
    End

    It 'loads the theme through the omz theme machinery in a real shell'
      loads() {
        inzsh_spec_in_home '
          inzsh_spec_omz_dir; inzsh_spec_omz_rc
          zsh -f $installer --omz >/dev/null
          HOME=$home zsh -o NO_GLOBAL_RCS -i -c \
            "(( \${+functions[_inzsh_render]} )) && (( \${+_inzsh_segment_defaults[DIR]} )) &&
               print -r -- loaded || print -r -- not-loaded"
        '
      }
      When call loads
      The output should eq 'loaded'
      The stderr should eq ''
    End

    It 'is idempotent — a second run changes neither .zshrc nor the link'
      twice() {
        inzsh_spec_in_home '
          inzsh_spec_omz_dir; inzsh_spec_omz_rc
          zsh -f $installer --omz >/dev/null
          local before=$(<$home/.zshrc)
          zsh -f $installer --omz >/dev/null
          [[ $before == $(<$home/.zshrc) && \
             $(grep -c "inzsh:managed" $home/.zshrc) == 1 ]] &&
            print -r -- unchanged || print -r -- changed
        '
      }
      When call twice
      The output should eq 'unchanged'
    End

    It 'inserts the managed theme line before oh-my-zsh.sh when none existed'
      no_theme_line() {
        inzsh_spec_in_home '
          inzsh_spec_omz_dir
          print -rl -- "export ZSH=\"\$HOME/.oh-my-zsh\"" "source \$ZSH/oh-my-zsh.sh" > $home/.zshrc
          zsh -f $installer --omz >/dev/null
          local -a lines=("${(@f)$(<$home/.zshrc)}")
          local -i managed=0 omz_source=0 i
          for i in {1..${#lines}}; do
            [[ ${lines[i]} == *"inzsh:managed"* ]] && managed=$i
            [[ ${lines[i]} == source*oh-my-zsh.sh* ]] && omz_source=$i
          done
          (( managed > 0 && managed < omz_source )) && print -r -- before || \
            print -r -- "managed=$managed source=$omz_source"
        '
      }
      When call no_theme_line
      The output should eq 'before'
    End

    It 'honours ZSH_CUSTOM for the themes directory'
      custom() {
        inzsh_spec_in_home '
          inzsh_spec_omz_dir; mkdir -p $home/my-custom
          print -rl -- "export ZSH=\"\$HOME/.oh-my-zsh\"" \
            "export ZSH_CUSTOM=\"\$HOME/my-custom\"" \
            "source \$ZSH/oh-my-zsh.sh" > $home/.zshrc
          ZSH_CUSTOM=$home/my-custom zsh -f $installer --omz >/dev/null
          [[ -L $home/my-custom/themes/inzsh.zsh-theme ]] && print -r -- linked || print -r -- not-linked
        '
      }
      When call custom
      The output should eq 'linked'
    End

    It 'refuses --omz when there is no oh-my-zsh to install into'
      refuses() {
        inzsh_spec_in_home '
          zsh -f $installer --omz >/dev/null 2>&1 && print -r -- accepted || print -r -- refused
        '
      }
      When call refuses
      The output should eq 'refused'
    End

    It 'auto-detects oh-my-zsh when no path flag is given'
      auto() {
        inzsh_spec_in_home '
          inzsh_spec_omz_dir; inzsh_spec_omz_rc
          zsh -f $installer >/dev/null
          [[ -L $home/.oh-my-zsh/custom/themes/inzsh.zsh-theme ]] && print -r -- omz-chosen || \
            print -r -- plain-chosen
        '
      }
      When call auto
      The output should eq 'omz-chosen'
    End

    It 'still installs plain when --plain says so, oh-my-zsh or not'
      forced_plain() {
        inzsh_spec_in_home '
          inzsh_spec_omz_dir; inzsh_spec_omz_rc
          zsh -f $installer --plain >/dev/null
          [[ -L $home/.oh-my-zsh/custom/themes/inzsh.zsh-theme ]] && { print -r -- linked-anyway; return 1 }
          grep -q ">>> inzsh >>>" $home/.zshrc && print -r -- plain || print -r -- neither
        '
      }
      When call forced_plain
      The output should eq 'plain'
    End

    It 'uninstall restores .zshrc exactly and removes the link'
      restores() {
        inzsh_spec_in_home '
          inzsh_spec_omz_dir; inzsh_spec_omz_rc
          local before=$(<$home/.zshrc)
          zsh -f $installer --omz >/dev/null
          zsh -f $installer --uninstall >/dev/null
          [[ -L $home/.oh-my-zsh/custom/themes/inzsh.zsh-theme ]] && { print -r -- link-left; return 1 }
          [[ $before == $(<$home/.zshrc) ]] && print -r -- restored || {
            print -r -- different; print -r -- "$(<$home/.zshrc)"
          }
        '
      }
      When call restores
      The output should eq 'restored'
      The stderr should eq ''
    End
  End

  # Auto-detection. A framework directory is not a framework: `~/.oh-my-zsh` outlives an
  # uninstall, and `$ZSH` outlives an export somebody forgot to delete. What decides is the rc
  # under the installer's hands — if it never sources `oh-my-zsh.sh`, nothing will ever read a
  # `ZSH_THEME` line or a custom-themes symlink, and the plain path is the only one that works.
  Describe 'auto-detection'
    It 'takes the plain path when the rc does not source oh-my-zsh'
      leftover_dir() {
        inzsh_spec_in_home '
          mkdir -p $home/.oh-my-zsh/custom/themes
          print -r -- "export EDITOR=vi" > $home/.zshrc
          zsh -f $installer >/dev/null
          [[ -L $home/.oh-my-zsh/custom/themes/inzsh.zsh-theme ]] && { print -r -- omz-chosen; return 1 }
          grep -q ">>> inzsh >>>" $home/.zshrc && print -r -- plain-chosen || print -r -- neither
        '
      }
      When call leftover_dir
      The output should eq 'plain-chosen'
    End

    It 'takes the plain path when $ZSH points at a leftover directory'
      leftover_export() {
        inzsh_spec_in_home '
          mkdir -p $home/.oh-my-zsh/custom/themes
          print -r -- "export EDITOR=vi" > $home/.zshrc
          ZSH=$home/.oh-my-zsh zsh -f $installer >/dev/null
          [[ -L $home/.oh-my-zsh/custom/themes/inzsh.zsh-theme ]] && { print -r -- omz-chosen; return 1 }
          grep -q ">>> inzsh >>>" $home/.zshrc && print -r -- plain-chosen || print -r -- neither
        '
      }
      When call leftover_export
      The output should eq 'plain-chosen'
    End

    It 'does not count a commented-out oh-my-zsh source line'
      commented() {
        inzsh_spec_in_home '
          mkdir -p $home/.oh-my-zsh/custom/themes
          print -rl -- "export ZSH=\"\$HOME/.oh-my-zsh\"" \
            "# source \$ZSH/oh-my-zsh.sh" > $home/.zshrc
          zsh -f $installer >/dev/null
          [[ -L $home/.oh-my-zsh/custom/themes/inzsh.zsh-theme ]] && { print -r -- omz-chosen; return 1 }
          grep -q ">>> inzsh >>>" $home/.zshrc && print -r -- plain-chosen || print -r -- neither
        '
      }
      When call commented
      The output should eq 'plain-chosen'
    End

    It 'still takes the oh-my-zsh path when the rc guards its source line'
      guarded() {
        inzsh_spec_in_home '
          inzsh_spec_omz_dir
          print -rl -- "export ZSH=\"\$HOME/.oh-my-zsh\"" \
            "ZSH_THEME=\"robbyrussell\"" \
            "[[ -f \$ZSH/oh-my-zsh.sh ]] && source \$ZSH/oh-my-zsh.sh" > $home/.zshrc
          zsh -f $installer >/dev/null
          [[ -L $home/.oh-my-zsh/custom/themes/inzsh.zsh-theme ]] && print -r -- omz-chosen || \
            print -r -- plain-chosen
        '
      }
      When call guarded
      The output should eq 'omz-chosen'
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
