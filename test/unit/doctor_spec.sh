Include lib/core/config.zsh
Include lib/core/detect.zsh
Include lib/salah/calc.zsh
Include lib/salah/cache.zsh
Include lib/salah/location.zsh
Include lib/core/doctor.zsh

# The doctor — `lib/core/doctor.zsh`. A thin formatter over the capability detection the theme
# already runs, printed as one pasteable block, because "paste the output of `inzsh doctor`" is
# what the bug template asks for. Nothing here detects anything new: every value below is one of
# `lib/core/detect.zsh`'s globals, re-asked at call time, plus the diagnostics other files wrote
# down for exactly this reader — the guard names in the config layer, the location provenance in
# `lib/salah/location.zsh`.
#
# Two properties are load-bearing and each has its own example:
#
#   THE BLOCK COVERS THE BUG TEMPLATE. `.github/ISSUE_TEMPLATE/bug.yml` asks for terminal, TERM,
#   zsh version, tmux and Nerd Font, and the issue adds colour depth and locale. A field the
#   block dropped is a field every bug report loses.
#
#   COORDINATES NEVER APPEAR. The output exists to be pasted into a public issue, and
#   CONTRIBUTING.md asks reporters not to include their position — so the doctor prints where a
#   location CAME FROM and never where it is.
#
# Detectors recompute from the environment on every call, so each example declares the
# environment it is about `local`, exactly as `detect_spec.sh` does.

inzsh_spec_doctor_env() {
  emulate -L zsh

  # A fixed, neutral terminal for every example that does not say otherwise.
  typeset -g TERM=xterm-256color COLORTERM=truecolor
  typeset -g LC_ALL=en_US.UTF-8
  unset TMUX TERM_PROGRAM TERM_PROGRAM_VERSION LC_TERMINAL TERMINAL_EMULATOR 2>/dev/null
  unset INZSH_COLOR_DEPTH INZSH_MULTIBYTE INZSH_NERD_FONT 2>/dev/null
  unset INZSH_SALAH_LAT INZSH_SALAH_LON INZSH_SALAH_AUTOLOCATE 2>/dev/null

  return 0
}

Describe 'the inzsh command'
  It 'refuses a subcommand it has never heard of, and says what it does know'
    unknown() { inzsh frobnicate; }
    When call unknown
    The status should be failure
    The stderr should include 'usage'
    The stderr should include 'doctor'
    The stderr should include 'locate'
  End

  It 'prints the same usage when called bare'
    bare() { inzsh; }
    When call bare
    The status should be failure
    The stderr should include 'usage'
  End
End

Describe 'inzsh doctor'
  It 'covers every field the bug template asks for'
    block() { inzsh_spec_doctor_env; inzsh doctor; }
    When call block
    The output should include 'zsh'
    The output should include 'terminal'
    The output should include 'TERM'
    The output should include 'colour depth'
    The output should include 'locale'
    The output should include 'nerd font'
    The output should include 'tmux'
    The status should be success
  End

  It 'reports the running zsh version'
    version() { inzsh_spec_doctor_env; inzsh doctor; }
    When call version
    The output should include "$ZSH_VERSION"
  End

  It 'reports the TERM in force when it is asked, not when it was loaded'
    term_now() {
      inzsh_spec_doctor_env
      local TERM=vt100 COLORTERM=
      inzsh doctor
    }
    When call term_now
    The output should include 'vt100'
  End

  It 'names the terminal program when the environment names one'
    program() {
      inzsh_spec_doctor_env
      local TERM_PROGRAM=Ghostty TERM_PROGRAM_VERSION=1.2.0
      inzsh doctor
    }
    When call program
    The output should include 'Ghostty 1.2.0'
  End

  It 'admits it cannot name the terminal when nothing does'
    anonymous() { inzsh_spec_doctor_env; inzsh doctor; }
    When call anonymous
    The output should include 'terminal      unknown'
  End

  It 'reports the detected colour depth'
    depth() { inzsh_spec_doctor_env; inzsh doctor; }
    When call depth
    The output should include 'colour depth  truecolor'
  End

  # The bug reader's first question about any surprising value: did the user set it, or did
  # detection? A valid override is obeyed by the detector, so the doctor says whose answer it is.
  It 'marks a colour depth that came from the override rather than from detection'
    overridden() {
      inzsh_spec_doctor_env
      local INZSH_COLOR_DEPTH=8
      inzsh doctor
    }
    When call overridden
    The output should include 'colour depth  8 (INZSH_COLOR_DEPTH)'
  End

  It 'does not blame the override for a value detection produced'
    ignored() {
      inzsh_spec_doctor_env
      local INZSH_COLOR_DEPTH=chartreuse
      inzsh doctor
    }
    When call ignored
    The output should include 'colour depth  truecolor'
    The output should not include 'INZSH_COLOR_DEPTH'
  End

  It 'reports the locale and whether multibyte glyphs are safe'
    utf8() { inzsh_spec_doctor_env; inzsh doctor; }
    When call utf8
    The output should include 'locale        en_US.UTF-8 (multibyte: yes)'
  End

  It 'reads a C locale as single-byte'
    single() {
      inzsh_spec_doctor_env
      local LC_ALL=C
      inzsh doctor
    }
    When call single
    The output should include 'locale        C (multibyte: no)'
  End

  It 'reports an undetectable Nerd Font as unknown, with the note that policy owes the reader'
    unknown_font() { inzsh_spec_doctor_env; inzsh doctor; }
    When call unknown_font
    The output should include 'nerd font     unknown'
    The output should include 'INZSH_NERD_FONT=0'
  End

  It 'reports tmux as absent outside a pane'
    no_pane() { inzsh_spec_doctor_env; inzsh doctor; }
    When call no_pane
    The output should include 'tmux          no'
    The output should include 'tmux rgb      unknown'
  End

  It 'reports the pane and warns when passthrough is not proven'
    pane() {
      inzsh_spec_doctor_env
      local TMUX=/tmp/tmux-1000/default,1,0
      inzsh doctor
    }
    When call pane
    The output should include 'tmux          yes'
    The output should include 'RGB passthrough'
  End

  It 'lists the registered invariants, straight out of the registry'
    guards() { inzsh_spec_doctor_env; inzsh doctor; }
    When call guards
    The output should include 'exit-code-capture'
    The output should include 'render-budget'
    The output should include 'separator-visibility'
  End

  It 'reports where the location came from when coordinates are configured'
    provenance() {
      inzsh_spec_doctor_env
      local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
      inzsh doctor
    }
    When call provenance
    The output should include 'location: config'
  End

  # The output exists to be pasted into a public issue, and CONTRIBUTING.md asks reporters not
  # to include their coordinates. Provenance is the diagnostic; the position itself never leaves.
  It 'never prints the coordinates themselves'
    private() {
      inzsh_spec_doctor_env
      local INZSH_SALAH_LAT=21.4225 INZSH_SALAH_LON=39.8262
      inzsh doctor
    }
    When call private
    The output should not include '21.4225'
    The output should not include '39.8262'
  End

  It 'reports no location as none rather than as silence'
    nowhere() { inzsh_spec_doctor_env; inzsh doctor; }
    When call nowhere
    The output should include 'location: none'
  End

  # The command ships with the theme, so it has to work from a partial load — a bundle that
  # stopped early, a spec that included three files. Without the salah library the location line
  # is omitted rather than invented; everything the bug template needs is still there.
  It 'stands on config, detect and itself alone'
    standalone() {
      zsh -f -c '
        TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
        source "$1/lib/core/config.zsh"
        source "$1/lib/core/detect.zsh"
        source "$1/lib/core/doctor.zsh"
        inzsh doctor
      ' inzsh-doctor-standalone "$SHELLSPEC_PROJECT_ROOT"
    }
    When call standalone
    The output should include 'colour depth  truecolor'
    The output should not include 'location'
    The stderr should eq ''
  End
End

Describe 'inzsh locate'
  # The lookup's public face — issue #186. `INZSH_SALAH_AUTOLOCATE` permits the one network call
  # in the theme, and this command is the only shipped way to make it: typed by a person, never
  # reached from a hook or the render path. Every example here keeps the suite offline the way
  # `salah_location_spec.sh` does — the only endpoint ever contacted is a port on 127.0.0.1 that
  # nothing serves, under a one-second ceiling.

  inzsh_spec_locate_now=1780315200

  inzsh_spec_locate_env() {
    emulate -L zsh

    typeset -g inzsh_spec_locate_cache=
    inzsh_spec_locate_cache=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-locate-XXXXXX") || return 1

    typeset -g INZSH_SALAH_CACHE_DIR=$inzsh_spec_locate_cache
    typeset -g INZSH_SALAH_LAT= INZSH_SALAH_LON=
    typeset -g INZSH_SALAH_AUTOLOCATE=1
    typeset -g INZSH_SALAH_AUTOLOCATE_TTL=
    typeset -g INZSH_SALAH_AUTOLOCATE_TIMEOUT=1
    typeset -g INZSH_SALAH_AUTOLOCATE_URL='http://127.0.0.1:1/'

    return 0
  }

  inzsh_spec_locate_clean() {
    emulate -L zsh

    [[ ${inzsh_spec_locate_cache:t} == inzsh-locate-* ]] || return 0
    rm -rf -- "$inzsh_spec_locate_cache" 2>/dev/null

    return 0
  }

  It 'refuses while the knob is off, and says which knob permits it'
    off() {
      inzsh_spec_locate_env
      local INZSH_SALAH_AUTOLOCATE=0
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call off
    The status should be failure
    The stderr should include 'INZSH_SALAH_AUTOLOCATE'
  End

  # A typo may not switch a network call on — the same rule the knob itself keeps.
  It 'reads an unreadable knob as off'
    typo() {
      inzsh_spec_locate_env
      local INZSH_SALAH_AUTOLOCATE=banana
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call typo
    The status should be failure
    The stderr should include 'INZSH_SALAH_AUTOLOCATE'
  End

  It 'leaves a current position alone and says how to insist'
    current() {
      inzsh_spec_locate_env
      _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_locate_now - 300 )) || return 1
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call current
    The status should be success
    The output should include 'current'
    The output should include '--force'
  End

  It 'reports a failed lookup and keeps the previous position'
    kept() {
      inzsh_spec_locate_env
      local INZSH_SALAH_AUTOLOCATE_TTL=300
      _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_locate_now - 86400 )) || return 1
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call kept
    The status should be failure
    The stderr should include 'kept'
  End

  It 'says so when the lookup fails and nothing was ever stored'
    nothing() {
      inzsh_spec_locate_env
      inzsh locate $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call nothing
    The status should be failure
    The stderr should include 'no position'
  End

  It 'looks a current position up anyway under --force'
    forced() {
      inzsh_spec_locate_env
      _inzsh_salah_location_write 21.4225 39.8262 $(( inzsh_spec_locate_now - 300 )) || return 1
      inzsh locate --force $inzsh_spec_locate_now
      local -i rc=$?
      inzsh_spec_locate_clean
      return $rc
    }
    When call forced
    The status should be failure
    The stderr should include 'kept'
  End
End

Describe 'make doctor'
  # The Makefile target runs the same `inzsh doctor` the shipped command defines, through the
  # harness launcher — never by re-implementing the block in make.
  It 'wires the harness to the same code path as the shipped command'
    harness() { zsh -f "$SHELLSPEC_PROJECT_ROOT/tools/doctor.zsh"; }
    When call harness
    The output should include 'InZsh doctor'
    The output should include 'colour depth'
    The output should include 'zsh'
    The status should be success
  End
End
