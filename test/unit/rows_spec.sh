Include lib/core/config.zsh
Include lib/core/engine.zsh
Include lib/core/layout.zsh
Include lib/core/rows.zsh

# Rows — the pure resolution layer. `_inzsh_rows_resolve` decides which row and which side a
# segment lands on; it draws nothing, reads no terminal of its own (`cols` is always injected,
# the same seam `_inzsh_layout_filter` already has) and fetches no segment state, so every
# example below runs in a shell with no prompt in it at all.
#
# The segment universe is a fixed, small table borrowed from the real ranks the segments ship
# with — DIR, GIT, VENV positive (left), TIME and SALAH negative (right), DATE and JOBS at 0,
# which is the shape issue #185 exists for: several real segments ship hidden by default, and a
# row array has to be able to override exactly that.
typeset -gA inzsh_spec_rows_defaults=(
  DIR 40  GIT 50  VENV 60  USER 20
  TIME -10  SALAH -20
  DATE 0  JOBS 0
)

# Every example starts from the same segment table and no row or marker knobs set — `unset -m`
# rather than trusting the next example to overwrite whatever this one left behind, the same
# defensiveness `test/unit/layout_spec.sh` uses for `INZSH_*_PRIORITY`.
inzsh_spec_rows_setup() {
  unset -m 'INZSH_ROW*_LEFT' 'INZSH_ROW*_RIGHT' 'INZSH_*_MINCOLS'
  unset INZSH_MARKER_ROW INZSH_PROMPT_LINES
  typeset -gA _inzsh_segment_defaults
  _inzsh_segment_defaults=("${(kv)inzsh_spec_rows_defaults[@]}")
}
BeforeEach 'inzsh_spec_rows_setup'

# The full candidate list, in the order the real entry point would hand it over — registration
# order, not rank order, since that is what a caller with no config on it also produces.
typeset -ga inzsh_spec_rows_candidates=(DIR GIT VENV USER TIME SALAH DATE JOBS)

# One row's side, indirectly, as a space-joined string — `${(P)name}` already coerces an array
# to its elements this way, so `[${(P)name}]` reads a dynamically-named row array without a
# second helper for the array case alone.
inzsh_spec_row_side() {
  local name=$1
  print -r -- "[${(P)name}]"
}

# The whole resolved shape, as one line: `count=N row1=[left]|[right] row2=...`, for every row
# `_inzsh_rows_resolve` actually drew. A row it did not draw never appears, which is the
# assertion "gaps collapse" needs — a stale `_inzsh_row3_left` from a previous call would show up
# here if the clearing at the top of `_inzsh_rows_resolve` ever regressed.
inzsh_spec_rows_shape() {
  _inzsh_rows_resolve "$@"
  local out="count=$_inzsh_row_count"
  local -i i
  for (( i = 1; i <= _inzsh_row_count; i++ )); do
    out+=" row${i}=$(inzsh_spec_row_side _inzsh_row${i}_left)|$(inzsh_spec_row_side _inzsh_row${i}_right)"
  done
  print -r -- "$out"
}

Describe '_inzsh_rows_entries'
  It 'answers empty and refuses when the parameter was never set'
    unset_var() { _inzsh_rows_entries INZSH_ROW1_LEFT; print -r -- "status=$? reply=[${reply[*]}]" }
    When call unset_var
    The output should eq 'status=1 reply=[]'
  End

  # The one spelling this knob accepts. A scalar is REFUSED whole, never split on whitespace —
  # two ways to write one knob is two things to document and test forever.
  It 'refuses a scalar rather than splitting it'
    scalar() { INZSH_ROW1_LEFT='TIME DIR'; _inzsh_rows_entries INZSH_ROW1_LEFT; print -r -- "status=$? reply=[${reply[*]}]" }
    When call scalar
    The output should eq 'status=1 reply=[]'
  End

  It 'accepts an explicitly empty array'
    empty_array() { INZSH_ROW1_LEFT=(); _inzsh_rows_entries INZSH_ROW1_LEFT; print -r -- "status=$? reply=[${reply[*]}]" }
    When call empty_array
    The output should eq 'status=0 reply=[]'
  End

  It 'drops an entry naming no segment this build has'
    typo() { INZSH_ROW1_LEFT=(GTI DIR); _inzsh_rows_entries INZSH_ROW1_LEFT; print -r -- "reply=[${reply[*]}]" }
    When call typo
    The output should eq 'reply=[DIR]'
  End

  It 'drops an entry that could not be a variable name'
    hostile() { INZSH_ROW1_LEFT=('a b' DIR); _inzsh_rows_entries INZSH_ROW1_LEFT; print -r -- "reply=[${reply[*]}]" }
    When call hostile
    The output should eq 'reply=[DIR]'
  End

  It 'keeps a rank-0 segment — entries validation has no opinion on rank'
    rank_zero() { INZSH_ROW1_LEFT=(DATE); _inzsh_rows_entries INZSH_ROW1_LEFT; print -r -- "reply=[${reply[*]}]" }
    When call rank_zero
    The output should eq 'reply=[DATE]'
  End

  It 'keeps a duplicate inside one array — the claim walk drops it, not this function'
    dup() { INZSH_ROW1_LEFT=(DIR DIR); _inzsh_rows_entries INZSH_ROW1_LEFT; print -r -- "reply=[${reply[*]}]" }
    When call dup
    The output should eq 'reply=[DIR DIR]'
  End
End

Describe '_inzsh_rows_resolve'
  Describe 'the default shape — nothing set'
    # An existing .zshrc sets no row arrays, so every segment derives onto row 1 exactly as
    # `_inzsh_rank_split` alone would answer — the byte-identity property §2.5 promises.
    It 'derives everything onto row 1, from rank alone'
      default_shape() { inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}" }
      When call default_shape
      The output should eq 'count=1 row1=[USER DIR GIT VENV]|[SALAH TIME]'
    End
  End

  Describe 'claiming'
    It 'places a segment ahead of its rank-derived position, bypassing rank entirely'
      claim() {
        INZSH_ROW1_LEFT=(GIT)
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call claim
      The output should eq 'count=1 row1=[GIT]|[SALAH TIME]'
    End

    # The override the whole feature exists to make possible: DATE ships at rank 0, and naming
    # it in a row array shows it anyway — issue #185's guard has to let this claim stand.
    It 'shows a segment that ships at rank 0 when a row array names it'
      rank_zero_override() {
        INZSH_ROW2_LEFT=(DATE)
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call rank_zero_override
      The output should eq 'count=2 row1=[USER DIR GIT VENV]|[SALAH TIME] row2=[DATE]|[]'
    End

    It 'lets an earlier row win a duplicate over a later one'
      earlier_wins() {
        INZSH_ROW1_LEFT=(DIR)
        INZSH_ROW2_LEFT=(DIR GIT)
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call earlier_wins
      The output should eq 'count=2 row1=[DIR]|[SALAH TIME] row2=[GIT]|[]'
    End

    It 'drops a typo without losing the rest of the array'
      typo_costs_a_block() {
        INZSH_ROW1_LEFT=(GTI DIR)
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call typo_costs_a_block
      The output should eq 'count=1 row1=[DIR]|[SALAH TIME]'
    End
  End

  Describe 'per-side override'
    It 'leaves an unset side deriving while the set side is explicit'
      one_side() {
        INZSH_ROW1_LEFT=(DIR)
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call one_side
      The output should eq 'count=1 row1=[DIR]|[SALAH TIME]'
    End

    # A derived segment whose side is explicitly set is dropped, not rehomed: USER and GIT and
    # VENV do not slide onto the right, or onto row 2, just because the left was named whole.
    It 'does not rehome the rest of a side that was named whole'
      whole_side() {
        INZSH_ROW1_LEFT=(DIR)
        INZSH_ROW1_RIGHT=(SALAH)
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call whole_side
      The output should eq 'count=1 row1=[DIR]|[SALAH]'
    End

    # "Set" and "unset" are different answers on row 1. An explicitly empty array is still SET,
    # so it does not fall through to the derived answer the way a genuinely unset side does.
    It 'treats an explicitly empty array as set, not as unset'
      explicit_empty() {
        INZSH_ROW1_LEFT=()
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call explicit_empty
      The output should eq 'count=1 row1=[]|[SALAH TIME]'
    End
  End

  Describe 'width beats placement'
    # MINCOLS is a width rule; a row array is a placement rule. A claimed segment that does not
    # survive MINCOLS is dropped from the row it was claimed onto, never resurrected by having
    # been named (§2.4).
    It 'drops a claimed segment the terminal has no room for'
      mincols_wins() {
        INZSH_ROW1_LEFT=(SALAH)
        INZSH_SALAH_MINCOLS=999
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call mincols_wins
      The output should eq 'count=1 row1=[]|[TIME]'
    End
  End

  Describe 'gap collapse'
    # Row numbers are sort keys, not slots: declaring rows 1 and 7 draws two rows, adjacent, and
    # the internal numbering is renumbered down to that so a caller never scans eight slots.
    It 'draws rows 1 and 7 as two adjacent rows'
      gap() {
        INZSH_ROW1_LEFT=(USER)
        INZSH_ROW7_LEFT=(DATE)
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call gap
      The output should eq 'count=2 row1=[USER]|[SALAH TIME] row2=[DATE]|[]'
    End
  End

  Describe 'the 1-8 bound'
    It 'ignores a row array numbered 9'
      row_nine() {
        INZSH_ROW9_LEFT=(DIR)
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call row_nine
      The output should eq 'count=1 row1=[USER DIR GIT VENV]|[SALAH TIME]'
    End
  End

  Describe 'a scalar row knob'
    # Refused, not split — the same rule `_inzsh_rows_entries` states, observed from the whole
    # resolution: a scalar behaves exactly as an unset row would, falling through to what rank
    # alone would have drawn, rather than being torn apart on whitespace.
    It 'is treated as unset rather than being split into segments'
      scalar_row() {
        INZSH_ROW1_LEFT='TIME DIR'
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call scalar_row
      The output should eq 'count=1 row1=[USER DIR GIT VENV]|[SALAH TIME]'
    End
  End

  Describe 'resolving more than once in the same shell'
    # A second resolve with a smaller shape must not leave the first call's higher-numbered rows
    # sitting around — the clearing at the top of `_inzsh_rows_resolve` is what a resize or a
    # second test run in this same interpreter depends on.
    It 'clears a row a later call no longer draws'
      twice() {
        INZSH_ROW1_LEFT=(USER)
        INZSH_ROW7_LEFT=(DATE)
        _inzsh_rows_resolve 200 "${inzsh_spec_rows_candidates[@]}"
        unset INZSH_ROW7_LEFT
        inzsh_spec_rows_shape 200 "${inzsh_spec_rows_candidates[@]}"
      }
      When call twice
      The output should eq 'count=1 row1=[USER]|[SALAH TIME]'
    End
  End

  Describe 'cost'
    # Resolution runs on the render path, once per prompt. A fork here would be paid on every
    # one of them, so the file may not contain one — the same guard `test/unit/layout_spec.sh`
    # keeps over `lib/core/layout.zsh`.
    It 'resolves without a subprocess anywhere in rows.zsh'
      substitutions() {
        setopt local_options extended_glob
        local line; local -a bad=()
        while IFS= read -r line; do
          [[ $line == [[:space:]]#\#* ]] && continue
          [[ $line == *'$('* || $line == *'`'* ]] && bad+="$line"
        done < "$SHELLSPEC_PROJECT_ROOT/lib/core/rows.zsh"
        print -r -- "${#bad}"
      }
      When call substitutions
      The output should eq '0'
    End
  End
End

# Issue #243. `_inzsh_rows_entries` and `_inzsh_rows_resolve` both drop a bad row-array entry on
# purpose and stay silent about it — the design `inzsh doctor` cannot leave unanswered, since
# `_inzsh_doctor_ignored` never sees an entry naming no segment: the family resolves and `any`
# accepts whatever the entry is. `_inzsh_rows_diagnose` is the detector that answers it; the
# formatter that turns this into a printed row lives in `doctor_spec.sh`, not here.
Describe '_inzsh_rows_diagnose'
  # One line per quadruple, `row:side:entry:reason`, so an assertion can pin the exact tuple
  # without reaching into `reply` by hand in every example.
  inzsh_spec_rows_diagnose_lines() {
    _inzsh_rows_diagnose "$@"
    local -a out=()
    local -i i
    for (( i = 1; i <= ${#reply}; i += 4 )); do
      out+="${reply[i]}:${reply[i + 1]}:${reply[i + 2]}:${reply[i + 3]}"
    done
    print -rl -- "${out[@]}"
  }

  It 'reports nothing when no row array is set'
    clean() { inzsh_spec_rows_diagnose_lines 200 }
    When call clean
    The output should eq ''
  End

  It 'reports nothing for a row array that resolved cleanly'
    resolved() {
      INZSH_ROW1_LEFT=(DIR)
      inzsh_spec_rows_diagnose_lines 200
    }
    When call resolved
    The output should eq ''
  End

  It 'names an entry that resolves to no segment this build has'
    unknown_segment() {
      INZSH_ROW2_LEFT=(GTI)
      inzsh_spec_rows_diagnose_lines 200
    }
    When call unknown_segment
    The output should eq '2:left:GTI:unknown segment'
  End

  It 'names an entry that cannot be a variable at all'
    not_identifier() {
      INZSH_ROW1_LEFT=('a b')
      inzsh_spec_rows_diagnose_lines 200
    }
    When call not_identifier
    The output should eq '1:left:a b:not an identifier'
  End

  It 'treats an empty entry as not an identifier rather than skipping it silently'
    empty_entry() {
      INZSH_ROW1_LEFT=('')
      inzsh_spec_rows_diagnose_lines 200
    }
    When call empty_entry
    The output should eq '1:left::not an identifier'
  End

  It 'attributes a duplicate to the later row, and only the later one'
    claimed_by_earlier_row() {
      INZSH_ROW1_LEFT=(DIR)
      INZSH_ROW2_LEFT=(DIR)
      inzsh_spec_rows_diagnose_lines 200
    }
    When call claimed_by_earlier_row
    The output should eq '2:left:DIR:claimed elsewhere'
  End

  It 'attributes a duplicate inside one array to its second mention'
    claimed_within_array() {
      INZSH_ROW1_LEFT=(DIR DIR)
      inzsh_spec_rows_diagnose_lines 200
    }
    When call claimed_within_array
    The output should eq '1:left:DIR:claimed elsewhere'
  End

  It 'attributes a duplicate across sides to the later side'
    claimed_across_sides() {
      INZSH_ROW1_LEFT=(DIR)
      INZSH_ROW1_RIGHT=(DIR)
      inzsh_spec_rows_diagnose_lines 200
    }
    When call claimed_across_sides
    The output should eq '1:right:DIR:claimed elsewhere'
  End

  It 'names a claimed entry the terminal has no room for'
    mincols() {
      INZSH_ROW1_LEFT=(SALAH)
      INZSH_SALAH_MINCOLS=999
      inzsh_spec_rows_diagnose_lines 200
    }
    When call mincols
    The output should eq '1:left:SALAH:hidden by MINCOLS'
  End

  It 'never reports MINCOLS against an entry that never claimed anything'
    mincols_unclaimed() {
      INZSH_ROW1_LEFT=(GTI)
      INZSH_SALAH_MINCOLS=999
      inzsh_spec_rows_diagnose_lines 200
    }
    When call mincols_unclaimed
    The output should eq '1:left:GTI:unknown segment'
  End

  # Refused whole, never split — the same rule `_inzsh_rows_entries` states — and reported once
  # for the side, with no entry to name.
  It 'reports a scalar row knob as refused rather than examining it entry by entry'
    scalar() {
      INZSH_ROW1_LEFT='TIME DIR'
      inzsh_spec_rows_diagnose_lines 200
    }
    When call scalar
    The output should eq '1:left::not an array'
  End

  # An unset row array is the ordinary case — every existing `.zshrc` leaves all eight unset —
  # and must not grow a diagnostic of its own, unlike a scalar, which is a real refusal.
  It 'says nothing about a row array that was never set at all'
    unset_side() {
      INZSH_ROW1_RIGHT=(SALAH)
      inzsh_spec_rows_diagnose_lines 200
    }
    When call unset_side
    The output should eq ''
  End

  # The block this feeds is pasted into a public issue. A newline or an escape sequence inside an
  # entry must come back as the raw quadruple `_inzsh_rows_diagnose` promises — sanitising is
  # `inzsh doctor`'s job, covered in `doctor_spec.sh` — but it must not, on its own, forge a second
  # quadruple or otherwise corrupt `reply`'s shape.
  It 'keeps a hostile entry to exactly one quadruple, unsanitised'
    hostile() {
      local forged=$'evil\nrow entry     INZSH_ROW9_LEFT=FORGED - unknown segment'
      INZSH_ROW1_LEFT=("$forged")
      _inzsh_rows_diagnose 200
      print -r -- "count=${#reply}"
      print -r -- "row=${reply[1]} side=${reply[2]} reason=${reply[4]}"
      [[ ${reply[3]} == "$forged" ]] && print -r -- 'entry: preserved verbatim'
    }
    When call hostile
    The line 1 should eq 'count=4'
    The line 2 should eq 'row=1 side=left reason=not an identifier'
    The line 3 should eq 'entry: preserved verbatim'
  End

  It 'never fails, whatever combination of bad entries it is given'
    everything_at_once() {
      INZSH_ROW1_LEFT=(GTI 'a b' DIR)
      INZSH_ROW2_RIGHT=(DIR)
      INZSH_SALAH_MINCOLS=999
      INZSH_ROW3_LEFT=(SALAH)
      inzsh_spec_rows_diagnose_lines 200
      print $?
    }
    When call everything_at_once
    The line 1 should eq '1:left:GTI:unknown segment'
    The line 2 should eq '1:left:a b:not an identifier'
    The line 3 should eq '2:right:DIR:claimed elsewhere'
    The line 4 should eq '3:left:SALAH:hidden by MINCOLS'
    The line 5 should eq '0'
  End
End

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
