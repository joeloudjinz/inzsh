Include lib/core/tokens.zsh

# The glyph table — `_inzsh_glyph` in `lib/core/tokens.zsh`. Every mark the theme draws, in one
# place, with an ASCII stand-in for each.
#
# It exists because three files had solved the same problem separately: the separators in
# `lib/core/render.zsh`, the ellipsis in `lib/core/layout.zsh` and the failure mark in
# `lib/segments/retval.zsh`. What this file gates is the table itself — keys, fallbacks, and the
# resolve between them. That the three former sites now READ it is a render-layer claim and
# lives in `test/render/separators_spec.sh`; what a C locale does to the file is a locale claim
# and lives in `test/unit/locale_spec.sh`.
#
# No glyph is pasted into an assertion below. The keys are, because the key set IS the contract,
# and the ASCII table is, for the same reason the palette spot-checks in
# `test/unit/tokens_spec.sh` are: a fallback needs a second, independent copy, or the assertion
# is the definition restated.

# Every key the table must carry, written out by hand so a dropped or renamed one fails here
# rather than as a blank space in somebody's prompt.
inzsh_spec_glyph_keys=(
  sep-left sep-right sep-left-round sep-right-round
  divider ellipsis
  ok info error warn dot dash
)

# The design system's sanctioned state marks, by role. Colour is never the only signal in this
# theme, so this is the subset that a state is not allowed to be drawn without.
inzsh_spec_state_keys=(ok info error warn dot dash)

# The ASCII stand-ins, pinned as key/value pairs. `error` becomes `x` in particular is a contract
# `lib/segments/retval.zsh` degrades onto and a user reads under `LC_ALL=C`.
inzsh_spec_glyph_ascii=(
  sep-left        '|'
  sep-right       '|'
  sep-left-round  ')'
  sep-right-round '('
  divider         '|'
  ellipsis        '...'
  ok              'v'
  info            'i'
  error           'x'
  warn            '!'
  dot             '.'
  dash            '-'
)

# The suite's own locale is the one UTF-8 locale this machine is known to have, and a real
# locale name is not portable across machines — so the multibyte examples ask zsh rather than
# the environment.
inzsh_spec_bytes_not_cells() {
  local sample=$'é'
  (( ${#sample} != 1 ))
}

Describe 'the glyph table'
  # ------------------------------------------------------------------------------------------
  Describe 'shape'
    It 'exposes the resolved table as an associative array'
      kind() { print -r -- "${(t)_inzsh_glyph}"; }
      When call kind
      The output should start with 'association'
    End

    It 'carries every expected key'
      missing() {
        local key; local -a gone=()
        for key in $inzsh_spec_glyph_keys; do
          [[ -n ${_inzsh_glyph[$key]+set} ]] || gone+=$key
        done
        print -r -- "${gone[*]}"
      }
      When call missing
      The output should eq ''
    End

    It 'carries nothing the checklist does not name'
      extra() {
        local key; local -a unexpected=()
        for key in ${(ko)_inzsh_glyph}; do
          (( ${inzsh_spec_glyph_keys[(Ie)$key]} )) || unexpected+=$key
        done
        print -r -- "${unexpected[*]}"
      }
      When call extra
      The output should eq ''
    End

    It 'never resolves a key to an empty mark'
      # An empty glyph is a signal that vanished, and colour is never the only signal. A key with
      # no fallback resolves to a visible `?` instead, which is wrong in a way somebody reports.
      blank() {
        local key; local -a empty=()
        for key in ${(ko)_inzsh_glyph}; do
          [[ -n ${_inzsh_glyph[$key]} ]] || empty+=$key
        done
        print -r -- "${empty[*]}"
      }
      When call blank
      The output should eq ''
    End

    It 'carries the design systems sanctioned state marks'
      states() {
        local key; local -a gone=()
        for key in $inzsh_spec_state_keys; do
          [[ -n ${_inzsh_glyph[$key]} ]] || gone+=$key
        done
        print -r -- "${gone[*]}"
      }
      When call states
      The output should eq ''
    End

    It 'gives each state mark a different shape from every other'
      # Six roles that share a glyph are five roles a reader cannot tell apart, which is the same
      # failure as colour being the only signal, arrived at from the other side.
      distinct() {
        local key; local -a marks=()
        for key in $inzsh_spec_state_keys; do marks+=${_inzsh_glyph[$key]}; done
        local -a unique=(${(u)marks})
        print -r -- "${#marks} ${#unique}"
      }
      When call distinct
      The output should eq '6 6'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the fallback table'
    # Every glyph needs a stand-in, and the stand-in has to be drawable where the glyph was not:
    # ASCII, non-empty, and still saying what the glyph said.
    It 'has exactly the same keys as the glyph table'
      paired() {
        local key; local -a wrong=()
        for key in ${(ko)_inzsh_glyph_utf8}; do
          [[ -n ${_inzsh_glyph_ascii[$key]+set} ]] || wrong+=no-fallback:$key
        done
        for key in ${(ko)_inzsh_glyph_ascii}; do
          [[ -n ${_inzsh_glyph_utf8[$key]+set} ]] || wrong+=orphan:$key
        done
        print -r -- "${wrong[*]}"
      }
      When call paired
      The output should eq ''
    End

    It 'holds nothing a single-byte terminal cannot draw'
      seven_bit() {
        setopt local_options extended_glob
        local key; local -a bad=()
        for key in ${(ko)_inzsh_glyph_ascii}; do
          [[ -n ${_inzsh_glyph_ascii[$key]} ]]        || bad+=empty:$key
          [[ ${_inzsh_glyph_ascii[$key]} == [[:ascii:]]## ]] || bad+=wide:$key
        done
        print -r -- "${bad[*]}"
      }
      When call seven_bit
      The output should eq ''
    End

    It 'stands in for each glyph with the mark this repo chose'
      pinned() {
        local key want; local -a wrong=()
        local -i i
        for (( i = 1; i < ${#inzsh_spec_glyph_ascii}; i += 2 )); do
          key=${inzsh_spec_glyph_ascii[i]}
          want=${inzsh_spec_glyph_ascii[i + 1]}
          [[ ${_inzsh_glyph_ascii[$key]} == $want ]] ||
            wrong+="$key=${_inzsh_glyph_ascii[$key]}/$want"
        done
        print -r -- "${wrong[*]}"
      }
      When call pinned
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'mirroring'
    # A wedge and a rounded cap both have a POINT, and the side it faces is the side of the
    # prompt they belong to. A rule has no point, so it does not mirror — and that difference has
    # to survive into the ASCII table, since it is the only thing left of the style there.
    It 'gives the two sides different separators in each filled style'
      mirrored() {
        local -a same=()
        [[ ${_inzsh_glyph[sep-left]}       != ${_inzsh_glyph[sep-right]} ]]       || same+=arrow
        [[ ${_inzsh_glyph[sep-left-round]} != ${_inzsh_glyph[sep-right-round]} ]] || same+=round
        [[ ${_inzsh_glyph_ascii[sep-left-round]} !=
           ${_inzsh_glyph_ascii[sep-right-round]} ]] || same+=round-ascii
        print -r -- "${same[*]}"
      }
      When call mirrored
      The output should eq ''
    End

    It 'uses one rule for both sides in the divider style'
      symmetric() {
        print -r -- "${#_inzsh_glyph[divider]}"
      }
      When call symmetric
      The output should not eq '0'
    End

    It 'keeps the four separators distinct from one another'
      # Two styles that resolve to the same pair are one style with two spellings.
      spread() {
        local key; local -a seps=()
        for key in sep-left sep-right sep-left-round sep-right-round; do
          seps+=${_inzsh_glyph[$key]}
        done
        local -a unique=(${(u)seps})
        print -r -- "${#seps} ${#unique}"
      }
      When call spread
      The output should eq '4 4'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'resolving'
    It 'draws the real glyph where the locale can carry it'
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      real() {
        local key; local -a wrong=()
        for key in ${(ko)_inzsh_glyph_utf8}; do
          [[ ${_inzsh_glyph[$key]} == ${_inzsh_glyph_utf8[$key]} ]] || wrong+=$key
        done
        print -r -- "${wrong[*]}"
      }
      When call real
      The output should eq ''
    End

    It 'spends exactly one column on every glyph it drew'
      # A prompt budgets in columns. A mark that measures two would push a block off the row, and
      # a mark that measures zero would leave a hole where the layout expected one.
      Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
      widths() {
        local key value; local -a wrong=()
        for key in ${(ko)_inzsh_glyph}; do
          value=${_inzsh_glyph[$key]}
          (( ${(m)#value} == 1 )) || wrong+="$key=${(m)#value}"
        done
        print -r -- "${wrong[*]}"
      }
      When call widths
      The output should eq ''
    End

    # The fallback path, exercised through the resolve rather than through a locale, so the two
    # switches — `_inzsh_multibyte` and "did the bytes become one character" — are told apart.
    # Its locale half is in `test/unit/locale_spec.sh`.
    It 'falls back to the ASCII table entry by entry when multibyte is off'
      degraded() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          typeset -g _inzsh_multibyte=0
          _inzsh_glyphs_resolve
          local key; local -a wrong=()
          for key in ${(ko)_inzsh_glyph_utf8}; do
            [[ ${_inzsh_glyph[$key]} == ${_inzsh_glyph_ascii[$key]} ]] || wrong+=$key
          done
          print -r -- "${#_inzsh_glyph} ${wrong[*]}"
        ' inzsh-glyph-ascii "$SHELLSPEC_PROJECT_ROOT"
      }
      When call degraded
      The output should eq '12 '
      The stderr should eq ''
    End

    It 'is re-runnable and lands on the same table twice'
      # A plugin manager sources a theme twice, and a preset may re-resolve. Neither may leave a
      # half-built table behind.
      twice() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          local first="${(kv)_inzsh_glyph}"
          _inzsh_glyphs_resolve
          _inzsh_glyphs_resolve
          [[ $first == "${(kv)_inzsh_glyph}" ]] && print -r -- stable || print -r -- drifted
        ' inzsh-glyph-twice "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq 'stable'
      The stderr should eq ''
    End

    It 'answers from the environment as it is now, never from a previous answer'
      # `_inzsh_multibyte` can move — a user sets `INZSH_MULTIBYTE=0` and re-runs detection — and
      # the table has to move with it rather than keeping the answer it was built with.
      recomputed() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          typeset -g _inzsh_multibyte=0
          _inzsh_glyphs_resolve
          local off=${_inzsh_glyph[error]}
          typeset -g _inzsh_multibyte=1
          _inzsh_glyphs_resolve
          print -r -- "$off ${_inzsh_glyph[error]}"
        ' inzsh-glyph-recompute "$SHELLSPEC_PROJECT_ROOT"
      }
      When call recomputed
      The output should eq "x ${_inzsh_glyph_utf8[error]}"
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  # Structural, and the regression guard proper. The bug this table exists to stop happening a
  # fourth time was never a wrong value — it was a SPELLING the parser cannot read in every
  # locale. `\u` and `\U` inside a `$'…'` literal are that spelling, and the file that now holds
  # every glyph in the repo is the one file that must never carry one.
  It 'spells no glyph as a parse-time character literal'
    literals() {
      setopt local_options extended_glob
      local line; local -a bad=()
      while IFS= read -r line; do
        [[ $line == [[:space:]]#\#* ]] && continue
        [[ $line == *"\$'"*'\\'[uU]* ]] && bad+=$line
      done < "$SHELLSPEC_PROJECT_ROOT/lib/core/tokens.zsh"
      print -r -- "${#bad}"
    }
    When call literals
    The output should eq '0'
  End
End
