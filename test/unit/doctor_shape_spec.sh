Include lib/core/config.zsh
Include lib/core/detect.zsh
Include lib/core/engine.zsh
Include lib/core/layout.zsh
Include lib/core/rows.zsh
Include lib/core/render.zsh
Include lib/core/doctor.zsh

# `_inzsh_doctor_shape` — issue #227. The `shape` rows report what the render actually resolved,
# never the knob: the separator style, including the Nerd Font downgrade, the surface mode, the
# marker row (through the deprecated `INZSH_PROMPT_LINES` alias where that is where the answer
# came from), the padding, and the row count `_inzsh_rows_resolve` gives right now.
#
# The segment universe is a small fixture rather than the shipped segments, the same choice
# `test/unit/rows_spec.sh` makes and for the same reason: a change to a shipped segment's own
# rank must not move an assertion here.
typeset -gA inzsh_spec_shape_defaults=(
  DIR 10  GIT 20  VENV 30  USER 40
  TIME -10  SALAH -20
  DATE 0  JOBS 0
)

inzsh_spec_shape_setup() {
  unset -m 'INZSH_ROW*_LEFT' 'INZSH_ROW*_RIGHT' 'INZSH_*_MINCOLS' 'INZSH_*_PRIORITY'
  unset INZSH_MARKER_ROW INZSH_PROMPT_LINES INZSH_SEPARATOR_STYLE INZSH_SURFACE_MODE
  unset INZSH_SEGMENT_PAD INZSH_NERD_FONT COLUMNS
  typeset -gA _inzsh_segment_defaults
  _inzsh_segment_defaults=("${(kv)inzsh_spec_shape_defaults[@]}")

  return 0
}
BeforeEach 'inzsh_spec_shape_setup'

Describe '_inzsh_doctor_shape'
  It 'reports the default single-row shape'
    default_shape() {
      local COLUMNS=80
      inzsh doctor
    }
    When call default_shape
    The output should include 'shape         separator: arrow'
    The output should include 'shape         surface: alternate'
    The output should include 'shape         marker: own'
    The output should include 'shape         padding: 1'
    The output should include 'shape         rows: 1'
  End

  It 'reports the row count for a multi-row layout'
    multi_row() {
      local COLUMNS=80
      INZSH_ROW2_LEFT=(USER)
      inzsh doctor
    }
    When call multi_row
    The output should include 'shape         rows: 2'
  End

  # Resolved, not configured — issue #227's own example. `INZSH_NERD_FONT=0` downgrades any
  # filled style to `divider`, and the row has to say what actually drew, with a note that names
  # what was asked for and why it did not.
  It 'reports the separator as resolved, with the Nerd Font downgrade noted'
    downgraded() {
      local COLUMNS=80
      local INZSH_SEPARATOR_STYLE=arrow INZSH_NERD_FONT=0
      inzsh doctor
    }
    When call downgraded
    The output should include 'shape         separator: divider (would be arrow with a Nerd Font)'
  End

  It 'does not add a downgrade note when the resolved style needed no help'
    plain() {
      local COLUMNS=80
      local INZSH_SEPARATOR_STYLE=round
      inzsh doctor
    }
    When call plain
    The output should include 'shape         separator: round'
    The output should not include 'would be'
  End

  # `INZSH_PROMPT_LINES` is the deprecated alias — the marker row resolves THROUGH it rather than
  # only ever answering the newer knob's own default.
  It 'resolves the marker row through the deprecated INZSH_PROMPT_LINES alias'
    alias_marker() {
      local COLUMNS=80
      local INZSH_PROMPT_LINES=1
      inzsh doctor
    }
    When call alias_marker
    The output should include 'shape         marker: inline (via the deprecated INZSH_PROMPT_LINES)'
  End

  It 'does not credit the alias when INZSH_MARKER_ROW answers directly'
    explicit_marker() {
      local COLUMNS=80
      local INZSH_MARKER_ROW=inline INZSH_PROMPT_LINES=2
      inzsh doctor
    }
    When call explicit_marker
    The output should include 'shape         marker: inline'
    The output should not include 'deprecated'
  End

  It 'still returns success and reports nothing when the row layer is entirely absent'
    standalone() {
      zsh -f -c '
        TERM=xterm-256color COLORTERM=truecolor LC_ALL=en_US.UTF-8
        source "$1/lib/core/config.zsh"
        source "$1/lib/core/detect.zsh"
        source "$1/lib/core/doctor.zsh"
        inzsh doctor
      ' inzsh-doctor-shape-standalone "$SHELLSPEC_PROJECT_ROOT"
    }
    When call standalone
    The status should be success
    The output should not include 'shape'
    The stderr should eq ''
  End
End
