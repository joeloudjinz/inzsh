# The single-file bundle — `tools/bundle.zsh` and what it emits. The bundle is the entry point
# with the `source` lines replaced by the files themselves, so what is under test is the same
# contract `entrypoint_spec.sh` holds the entry point to: the guard, the load order, the hooks,
# and idempotence. A bundle that passes here is a drop-in for `inzsh.zsh-theme`.
#
# Nothing here is `Include`d, for the same reason as the entry-point spec: what is under test is
# what SOURCING the artifact does, so every example runs it in a fresh `zsh -f`. The bundle is
# built once per suite run, into shellspec's own tmp dir — never into the tree, and never into
# anybody's `$HOME`.

inzsh_spec_bundle() {
  local out=$SHELLSPEC_TMPBASE/inzsh-bundle.zsh-theme
  if [[ ! -s $out ]]; then
    zsh -f "$SHELLSPEC_PROJECT_ROOT/tools/bundle.zsh" "$out" >/dev/null 2>&1 || return 1
  fi
  print -r -- "$out"
}

# Same build, but with `INZSH_BUNDLE_VERSION` set — the release workflow's own input
# (`.releaserc.yml`'s `prepare` step, issue #244) — into a file of its own rather than the
# cached one above, so the default-case examples never see a stamped build by accident.
inzsh_spec_bundle_stamped() {
  local version=$1
  local out=$SHELLSPEC_TMPBASE/inzsh-bundle-stamped.zsh-theme
  INZSH_BUNDLE_VERSION=$version \
    zsh -f "$SHELLSPEC_PROJECT_ROOT/tools/bundle.zsh" "$out" >/dev/null 2>&1 || return 1
  print -r -- "$out"
}

# The load list the entry point fixes — every `source …/lib/…` line, in order. This is the
# contract the manifest transcribes, so it is read from the entry point rather than spelled a
# second time here.
inzsh_spec_entry_list() {
  local line
  while IFS= read -r line; do
    [[ $line == source*_inzsh_theme_root/lib/* ]] || continue
    print -r -- "${line##*_inzsh_theme_root/}"
  done < "$SHELLSPEC_PROJECT_ROOT/inzsh.zsh-theme"
}

Describe 'the bundle'
  Describe 'construction'
    It 'builds cleanly'
      When call inzsh_spec_bundle
      The output should not eq ''
      The stderr should eq ''
    End

    # The manifest is explicit, and this is what holds it to the contract: the section markers
    # in the bundle name the same files in the same order as the entry point's source list.
    # A file added to the tree and to the entry point but not to the manifest fails here.
    It 'concatenates exactly the files the entry point sources, in the same order'
      sections() {
        local bundle=$(inzsh_spec_bundle) line
        local -a want=("${(f)$(inzsh_spec_entry_list)}") got=()
        while IFS= read -r line; do
          [[ $line == '# ── lib/'*' ──' ]] || continue
          line=${line#'# ── '}
          got+=("${line%' ──'}")
        done < "$bundle"
        [[ "${(j: :)want}" == "${(j: :)got}" ]] && print -r -- same ||
          print -r -- "want: ${want[*]} / got: ${got[*]}"
      }
      When call sections
      The output should eq 'same'
    End

    # Self-contained means SELF-contained: nothing left in the bundle reaches back into the
    # tree it was built from. A surviving `source` line is a bundle that only works where the
    # repo happens to be checked out.
    It 'leaves no source line pointing back into the tree'
      leftover() {
        grep -c '_inzsh_theme_root/lib/' "$(inzsh_spec_bundle)" || true
      }
      When call leftover
      The output should eq 0
    End

    # Same structural property the entry point holds, for the same reason: everything above the
    # guard runs in every script and every `ssh host command` on the machine.
    It 'guards on the first executable line, above everything else'
      first_line() {
        local line
        while IFS= read -r line; do
          [[ -z ${line//[[:space:]]/} || $line == \#* ]] && continue
          print -r -- "$line"
          return 0
        done < "$(inzsh_spec_bundle)"
      }
      When call first_line
      The output should eq '[[ -o interactive ]] || return 0'
    End
  End

  # Issue #244. The single-source version constant: `source` in the tree, and the one thing
  # `tools/bundle.zsh` is trusted to stamp a real tag over, from `INZSH_BUNDLE_VERSION` rather
  # than a number written anywhere in this repo — see the comment at the head of that file.
  Describe 'the version stamp'
    It 'defaults to source when no version is given at build time'
      default_version() {
        zsh -f -i -c 'source "$1"; print -r -- "$_inzsh_version"' \
          inzsh-bundle-version-default "$(inzsh_spec_bundle)"
      }
      When call default_version
      The output should eq 'source'
      The stderr should eq ''
    End

    It 'stamps the exact version handed to the build'
      stamped_version() {
        zsh -f -i -c 'source "$1"; print -r -- "$_inzsh_version"' \
          inzsh-bundle-version-stamped "$(inzsh_spec_bundle_stamped v9.9.9)"
      }
      When call stamped_version
      The output should eq 'v9.9.9'
      The stderr should eq ''
    End
  End

  # The L2 gate the issue names: the bundle behaves as the entry point does. The examples mirror
  # `entrypoint_spec.sh` — same harness, same assertions — run against the artifact.
  Describe 'behaviour'
    It 'sources cleanly and says nothing in a non-interactive shell'
      silent() {
        zsh -f -c 'source "$1"; print -r -- "status=$?"' inzsh-bundle-silent "$(inzsh_spec_bundle)"
      }
      When call silent
      The output should eq 'status=0'
      The stderr should eq ''
    End

    It 'loads the library and resolves the roles in an interactive shell'
      loaded() {
        zsh -f -i -c '
          source "$1"
          local -a missing=() fn
          for fn in _inzsh_detect_color_depth _inzsh_tokens_resolve _inzsh_seg_color \
                    _inzsh_surface_mode _inzsh_surface_assign _inzsh_surfaces_valid; do
            (( ${+functions[$fn]} )) || missing+=$fn
          done
          (( ${#_inzsh_role} ))        || missing+=roles
          (( ${#_inzsh_palette} ))     || missing+=palette
          (( ${#_inzsh_palette_256} )) || missing+=palette-256
          (( ${#_inzsh_palette_8} ))   || missing+=palette-8
          [[ -n $_inzsh_color_depth ]] || missing+=depth
          print -r -- "${missing[*]}"
        ' inzsh-bundle-loaded "$(inzsh_spec_bundle)"
      }
      When call loaded
      The output should eq ''
      The stderr should eq ''
    End

    It 'ends with every segment registered in a real shell'
      registered() {
        zsh -f -i -c '
          source "$1"
          local -a want=(ROOT USER HOST SSH DIR VENV GIT RETVAL DURATION JOBS TIME DATE SALAH)
          local -a missing=()
          local name
          for name in $want; do
            (( ${+_inzsh_segment_defaults[$name]} )) || missing+=$name
          done
          print -r -- "${missing[*]}"
        ' inzsh-bundle-registered "$(inzsh_spec_bundle)"
      }
      When call registered
      The output should eq ''
      The stderr should eq ''
    End

    It 'installs its hooks in order and assigns no PROMPT at source time'
      quiescent() {
        zsh -f -i -c '
          local before=$PROMPT
          source "$1"
          local -a moved=()
          [[ $PROMPT == $before ]] || moved+=PROMPT
          local want="_inzsh_precmd _inzsh_title_precmd _inzsh_transient_precmd _inzsh_git_async_precmd"
          [[ ${precmd_functions[*]} == $want ]] || moved+=precmd:${precmd_functions[*]}
          [[ ${preexec_functions[*]} == _inzsh_title_preexec ]] ||
            moved+=preexec:${preexec_functions[*]}
          [[ ${chpwd_functions[*]} == _inzsh_git_async_chpwd ]] ||
            moved+=chpwd:${chpwd_functions[*]}
          [[ ${zshexit_functions[*]} == _inzsh_git_async_exit ]] ||
            moved+=zshexit:${zshexit_functions[*]}
          print -r -- "${moved[*]}"
        ' inzsh-bundle-quiescent "$(inzsh_spec_bundle)"
      }
      When call quiescent
      The output should eq ''
    End

    It 'draws the prompt once precmd has run'
      draws() {
        zsh -f -i -c '
          source "$1"
          _inzsh_render
          [[ -n $PROMPT ]] && print -r -- drawn || print -r -- empty
        ' inzsh-bundle-draws "$(inzsh_spec_bundle)"
      }
      When call draws
      The output should eq 'drawn'
    End

    # The knob a concatenated bundle could easily not have had. `INZSH_PRESET` names a preset,
    # and the theme answers the name from a table in the token layer rather than by sourcing
    # `presets/inzsh-<name>.zsh` — which is exactly what lets it work HERE, in a temp directory
    # with no `presets/` beside the artifact. That absence is asserted rather than assumed: a
    # bundle that happened to sit in the tree would pass this for the wrong reason.
    It 'honours INZSH_PRESET with no presets directory beside it'
      preset() {
        zsh -f -i -c '
          [[ -d ${1:h}/presets ]] && print -r -- "a presets directory sits beside the bundle"
          INZSH_PRESET=warm
          source "$1"
          print -r -- "$_inzsh_register"
        ' inzsh-bundle-preset "$(inzsh_spec_bundle)"
      }
      When call preset
      The output should eq 'light'
      The stderr should eq ''
    End

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
        ' inzsh-bundle-twice "$(inzsh_spec_bundle)"
      }
      When call twice
      The output should eq 'same'
      The stderr should eq ''
    End
  End
End
