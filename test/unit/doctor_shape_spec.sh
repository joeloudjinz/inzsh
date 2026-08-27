Include lib/core/config.zsh
Include lib/core/detect.zsh
Include lib/core/engine.zsh
Include lib/core/layout.zsh
Include lib/core/rows.zsh
Include lib/core/render.zsh
Include lib/core/doctor.zsh

# `_inzsh_doctor_shape` and `_inzsh_doctor_segments` — issue #227, covering #246 and #247. The
# `shape` rows report what the render actually resolved (never the knob), and the `segment` rows
# say where every registered segment landed and, when it did not draw, exactly one of the four
# reasons `lib/core/doctor.zsh`'s own header lays out for why — never a guess dressed up as one.
#
# The segment universe is a small fixture rather than the shipped segments, the same choice
# `test/unit/rows_spec.sh` makes and for the same reason: a change to the git segment's ladder
# must not move an assertion here. Every segment gets short, fixed text by default — `_inzsh_
# doctor_row_survivors` and `_inzsh_render_fit_args` both read real measured widths, not ranks —
# so the arithmetic in the width-driven examples is over numbers this file chose.
typeset -gA inzsh_spec_shape_defaults=(
  DIR 10  GIT 20  VENV 30  USER 40
  TIME -10  SALAH -20
  DATE 0  JOBS 0
)

# Every shipped segment registers its own `_inzsh_segment_priority` default — `_inzsh_priority_
# of` falls back to it once the knob has nothing to say, and every real segment source file does
# this. The fixture follows the same convention with the shipped values for the names it reuses,
# so a segment with no override behaves exactly as it would in the real theme rather than
# exercising the unregistered-stranger path `test/unit/layout_spec.sh` already covers on its own.
typeset -gA inzsh_spec_shape_priorities=(
  DIR 20  GIT 40  VENV 70  USER 50
  TIME 80  SALAH 90
  DATE 85  JOBS 45
)

inzsh_spec_shape_setup() {
  unset -m 'INZSH_ROW*_LEFT' 'INZSH_ROW*_RIGHT' 'INZSH_*_MINCOLS' 'INZSH_*_PRIORITY'
  unset INZSH_MARKER_ROW INZSH_PROMPT_LINES INZSH_SEPARATOR_STYLE INZSH_SURFACE_MODE
  unset INZSH_SEGMENT_PAD INZSH_NERD_FONT COLUMNS
  typeset -gA _inzsh_segment_defaults
  _inzsh_segment_defaults=("${(kv)inzsh_spec_shape_defaults[@]}")

  typeset -gA _inzsh_segment_priority
  _inzsh_segment_priority=("${(kv)inzsh_spec_shape_priorities[@]}")

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text=()
  local seg
  for seg in "${(k)inzsh_spec_shape_defaults[@]}"; do
    _inzsh_segment_text[$seg]=$seg
  done

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
End

Describe '_inzsh_doctor_segments'
  It 'reports where a drawn segment landed'
    placed() {
      local COLUMNS=80
      inzsh doctor
    }
    When call placed
    The output should include 'segment       DIR row=1 side=left rank=10 priority=20 mincols=0'
  End

  It 'places a segment on the row a row array names, not on its rank-derived one'
    claimed() {
      local COLUMNS=80
      INZSH_ROW2_LEFT=(USER)
      inzsh doctor
    }
    When call claimed
    The output should include 'segment       USER row=2 side=left rank=40 priority=50 mincols=0'
  End

  Describe 'the four reasons a segment does not draw'
    It 'reports rank 0, unclaimed by any row'
      rank_zero() {
        local COLUMNS=80
        inzsh doctor
      }
      When call rank_zero
      The output should include \
        'segment       DATE row=- side=- rank=0 priority=85 mincols=0 - rank 0, not named in any row'
    End

    It 'reports a claim overriding a rank of 0, and drops the rank-0 reason with it'
      claimed_rank_zero() {
        local COLUMNS=80
        INZSH_ROW1_LEFT=(DATE)
        inzsh doctor
      }
      When call claimed_rank_zero
      The output should include 'segment       DATE row=1 side=left rank=0 priority=85 mincols=0'
      The output should not include 'DATE row=1 side=left rank=0 priority=85 mincols=0 -'
    End

    It 'reports a segment dropped by its own MINCOLS'
      mincols_drop() {
        local COLUMNS=80
        local INZSH_SALAH_MINCOLS=999
        inzsh doctor
      }
      When call mincols_drop
      The output should include \
        'segment       SALAH row=- side=- rank=-20 priority=90 mincols=999 - dropped by MINCOLS (999 > 80)'
    End

    It 'reports a segment that built no text this render'
      no_text() {
        local COLUMNS=80
        _inzsh_segment_text[GIT]=
        inzsh doctor
      }
      When call no_text
      The output should include \
        'segment       GIT row=1 side=left rank=20 priority=40 mincols=0 - built no text this render'
    End

    # Neither segment carries a MINCOLS, so both are placed by `lib/core/rows.zsh` regardless of
    # the terminal width — MINCOLS' own filter only ever compares against a threshold, and the
    # default is 0. What decides which of two REAL, equally-placed segments actually draws at a
    # narrow width is `_inzsh_render_row`'s own fit, over their measured text and priority —
    # exactly the mechanism this reason names, and the one MINCOLS above is not.
    It 'reports a segment dropped by the row fit rather than by MINCOLS'
      fit_drop() {
        local COLUMNS=12
        _inzsh_segment_text[DIR]='DIRDIRDIRDIR'
        _inzsh_segment_text[GIT]='GITGITGITGIT'
        local INZSH_DIR_PRIORITY=1 INZSH_GIT_PRIORITY=2
        inzsh doctor
      }
      When call fit_drop
      The output should include "dropped by the row's fit"
      The output should not include 'GIT row=1 side=left rank=20 priority=2 mincols=0 - dropped by MINCOLS'
    End
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
    The output should not include 'segment '
    The stderr should eq ''
  End
End
