Include lib/core/config.zsh
Include lib/core/engine.zsh
Include lib/core/layout.zsh
Include lib/core/rows.zsh

# Rows — the pure resolution layer. `_inzsh_rows_resolve` decides which row and which side a
# segment lands on; it draws nothing, reads no terminal of its own (`cols` is always injected,
# the same seam `_inzsh_layout_filter` already has) and fetches no segment state, so every
# example below runs in a shell with no prompt in it at all.

# Every example starts with no row or marker knobs set — `unset -m` rather than trusting the
# next example to overwrite whatever this one left behind, the same defensiveness
# `test/unit/layout_spec.sh` uses for `INZSH_*_PRIORITY`.
inzsh_spec_rows_setup() {
  unset -m 'INZSH_ROW*_LEFT' 'INZSH_ROW*_RIGHT' 'INZSH_*_MINCOLS'
  unset INZSH_MARKER_ROW INZSH_PROMPT_LINES
}
BeforeEach 'inzsh_spec_rows_setup'

Describe '_inzsh_marker_row_resolved'
  # `INZSH_PROMPT_LINES` is the knob every existing `.zshrc` already carries, and it keeps
  # working, mapped onto `INZSH_MARKER_ROW` — §3.1. The removal is v2.0.0 and is not this file's
  # concern; this is only the alias.
  inzsh_spec_marker() {
    _inzsh_marker_row_resolved
    print -r -- "$REPLY"
  }

  It 'defaults to own when nothing is set'
    When call inzsh_spec_marker
    The output should eq 'own'
  End

  It 'resolves PROMPT_LINES=1 to inline'
    lines_one() { INZSH_PROMPT_LINES=1; inzsh_spec_marker }
    When call lines_one
    The output should eq 'inline'
  End

  It 'resolves PROMPT_LINES=2 to own'
    lines_two() { INZSH_PROMPT_LINES=2; inzsh_spec_marker }
    When call lines_two
    The output should eq 'own'
  End

  It 'ignores an unreadable PROMPT_LINES and falls back to own'
    lines_bad() { INZSH_PROMPT_LINES=three; inzsh_spec_marker }
    When call lines_bad
    The output should eq 'own'
  End

  It 'lets an explicit MARKER_ROW win outright over PROMPT_LINES'
    marker_wins() { INZSH_MARKER_ROW=inline; INZSH_PROMPT_LINES=2; inzsh_spec_marker }
    When call marker_wins
    The output should eq 'inline'
  End

  It 'falls through PROMPT_LINES when MARKER_ROW is unreadable'
    marker_bad() { INZSH_MARKER_ROW=sideways; INZSH_PROMPT_LINES=1; inzsh_spec_marker }
    When call marker_bad
    The output should eq 'inline'
  End

  It 'treats a set-but-empty MARKER_ROW as unset'
    marker_empty() { INZSH_MARKER_ROW=; INZSH_PROMPT_LINES=1; inzsh_spec_marker }
    When call marker_empty
    The output should eq 'inline'
  End
End
