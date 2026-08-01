# Locale — what a `LC_ALL=C` shell does to files that draw glyphs.
#
# `test/unit/detect_spec.sh` proves what `_inzsh_detect_multibyte` makes of a locale. It cannot
# prove what a locale does to the FILES, because that damage happens when a file is parsed and
# by then this suite has already parsed everything. So every example here sources into a fresh
# `zsh -f`, with the locale forced on the way in, and reads what came back out.
#
# The bug that earned this file: `lib/core/layout.zsh` stored its ellipsis as a `\u` character
# literal. A `\u` escape is resolved at PARSE time, and outside a multibyte locale zsh cannot
# resolve one — it fails with `character not in range` and abandons the rest of the file. A
# `LC_ALL=C` user did not get a plain ellipsis; they got an error on every shell start and no
# layout functions at all.
#
# Every glyph in the repo now lives in one table in `lib/core/tokens.zsh`, so that file is the
# one this suite watches hardest: a single bad spelling there would take the palette, the roles
# and every mark the theme draws down together.
#
# Two properties, and the fix needs both:
#
#   parse   the file loads in ANY locale, silently, with a zero status.
#   render  the marker is the real glyph where the glyph works, and ASCII where it does not.
#
# A file that only satisfies the first is a file that draws mojibake; a file that only satisfies
# the second never got far enough to draw anything.

# The locale examples force their own; this guard is for the ones that need the SUITE's locale
# to be a multibyte one, since a real UTF-8 locale name is not portable across machines and the
# inherited one is known to work.
inzsh_spec_bytes_not_cells() {
  local sample=$'é'
  (( ${#sample} != 1 ))
}

Describe 'sourcing under a C locale'
  # Every file that holds or reads a glyph, alone and in combination, in both orders.
  # `detect.zsh` answers the locale question, `tokens.zsh` acts on the answer, and `layout.zsh`,
  # `render.zsh` and `retval.zsh` read the result — but none of them may depend on another having
  # been loaded first. A bundle, a partial source and a spec each pick their own order.
  Parameters
    'lib/core/layout.zsh'
    'lib/core/detect.zsh'
    'lib/core/tokens.zsh'
    'lib/core/render.zsh'
    'lib/core/transient.zsh'
    'lib/segments/retval.zsh'
    'lib/core/detect.zsh lib/core/layout.zsh'
    'lib/core/layout.zsh lib/core/detect.zsh'
    'lib/core/detect.zsh lib/core/tokens.zsh'
    'lib/core/tokens.zsh lib/core/detect.zsh'
    'lib/core/detect.zsh lib/core/tokens.zsh lib/core/layout.zsh lib/core/render.zsh'
    'lib/core/tokens.zsh lib/segments/retval.zsh'
  End

  It "loads $1 silently and successfully"
    quiet() {
      local -a files=(${=1})
      local file
      local -a paths=()
      for file in "${files[@]}"; do
        paths+=("$SHELLSPEC_PROJECT_ROOT/$file")
      done
      LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
        for file in "$@"; do
          source "$file"
        done
      ' inzsh-locale-c "${paths[@]}"
    }
    When call quiet "$1"
    The status should be success
    The stderr should eq ''
    The output should eq ''
  End
End

Describe 'the glyph table'
  # The table is where all of this now lives, so the two properties are asked of it directly:
  # it must LOAD in a C locale, and everything it resolves must be drawable in one.
  It 'resolves every mark to its ASCII stand-in'
    stood_in() {
      LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
        source "$1/lib/core/detect.zsh"
        source "$1/lib/core/tokens.zsh"
        local key; local -a wrong=()
        for key in ${(ko)_inzsh_glyph_utf8}; do
          [[ ${_inzsh_glyph[$key]} == ${_inzsh_glyph_ascii[$key]} ]] || wrong+=$key
        done
        print -r -- "$_inzsh_multibyte ${#_inzsh_glyph} ${wrong[*]}"
      ' inzsh-locale-glyphs "$SHELLSPEC_PROJECT_ROOT"
    }
    When call stood_in
    The output should eq '0 15 '
    The stderr should eq ''
  End

  It 'puts nothing outside ASCII into anything it hands back'
    # The failure this rules out is mojibake rather than a crash: bytes that survived the parse
    # and then reached a terminal that cannot show them. Asked of the resolved table byte by
    # byte, so a single missed fallback is a named key rather than a smudge in a screenshot.
    seven_bit() {
      LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
        setopt extended_glob
        source "$1/lib/core/detect.zsh"
        source "$1/lib/core/tokens.zsh"
        source "$1/lib/core/layout.zsh"
        source "$1/lib/core/render.zsh"
        source "$1/lib/segments/retval.zsh"
        local key; local -a wrong=()
        for key in ${(ko)_inzsh_glyph}; do
          [[ ${_inzsh_glyph[$key]} == [[:ascii:]]## ]] || wrong+=glyph:$key
        done
        local style
        for style in arrow round divider; do
          typeset -g INZSH_SEPARATOR_STYLE=$style
          _inzsh_separators
          [[ $_inzsh_sep_left$_inzsh_sep_right == [[:ascii:]]## ]] || wrong+=sep:$style
        done
        [[ $_inzsh_layout_ellipsis == [[:ascii:]]## ]] || wrong+=ellipsis
        [[ $_inzsh_retval_glyph == [[:ascii:]]## ]]    || wrong+=retval
        print -r -- "${wrong[*]}"
      ' inzsh-locale-sevenbit "$SHELLSPEC_PROJECT_ROOT"
    }
    When call seven_bit
    The output should eq ''
    The stderr should eq ''
  End
End

Describe 'the truncation marker'
  # The whole point of the fallback. Three dots is not the glyph, but it is legible, it is one
  # byte per column, and it is what a C-locale terminal can actually draw.
  It 'falls back to ASCII outside a multibyte locale'
    ascii() {
      LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
        source "$1/lib/core/detect.zsh"
        source "$1/lib/core/tokens.zsh"
        source "$1/lib/core/layout.zsh"
        print -r -- "$_inzsh_multibyte [$_inzsh_layout_ellipsis]"
      ' inzsh-locale-c "$SHELLSPEC_PROJECT_ROOT"
    }
    When call ascii
    The output should eq '0 [...]'
    The stderr should eq ''
  End

  # And the other half: in a locale that can carry it, the marker is the character itself, one
  # column wide, not the three bytes it is spelled with. The suite's own locale is used because
  # it is the one UTF-8 locale this machine is known to have.
  It 'is the real glyph in a multibyte locale'
    Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
    glyph() {
      zsh -f -c '
        source "$1/lib/core/detect.zsh"
        source "$1/lib/core/tokens.zsh"
        source "$1/lib/core/layout.zsh"
        print -r -- "$_inzsh_multibyte [$_inzsh_layout_ellipsis] ${(m)#_inzsh_layout_ellipsis}"
      ' inzsh-locale-utf8 "$SHELLSPEC_PROJECT_ROOT"
    }
    When call glyph
    The output should eq '1 […] 1'
    The stderr should eq ''
  End

  # The override reaches the marker, which is the point of having one: a terminal that claims a
  # UTF-8 locale and cannot draw the glyph is exactly the case a user has to be able to correct.
  It 'follows INZSH_MULTIBYTE=0 even where the locale would carry the glyph'
    Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
    overridden() {
      INZSH_MULTIBYTE=0 zsh -f -c '
        source "$1/lib/core/detect.zsh"
        source "$1/lib/core/tokens.zsh"
        source "$1/lib/core/layout.zsh"
        print -r -- "$_inzsh_multibyte [$_inzsh_layout_ellipsis]"
      ' inzsh-locale-override "$SHELLSPEC_PROJECT_ROOT"
    }
    When call overridden
    The output should eq '0 [...]'
    The stderr should eq ''
  End

  # Truncation still truncates on the ASCII path, and the result is still no wider than the
  # budget — the marker got shorter, the invariant did not move.
  It 'truncates within budget with the fallback marker'
    budget() {
      LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
        source "$1/lib/core/detect.zsh"
        source "$1/lib/core/tokens.zsh"
        source "$1/lib/core/layout.zsh"
        local -a seen=()
        local -i width
        local -i cap
        for cap in 2 4 6 12; do
          _inzsh_truncate_text abcdefghij $cap
          _inzsh_width_raw "$REPLY"
          width=$REPLY
          (( width <= cap )) || seen+="over at $cap"
        done
        _inzsh_truncate_text abcdefghij 6
        print -r -- "${seen[*]}[$REPLY]"
      ' inzsh-locale-budget "$SHELLSPEC_PROJECT_ROOT"
    }
    When call budget
    The output should eq '[abc...]'
    The stderr should eq ''
  End
End

# Structural, and the regression guard proper. The bug was not a wrong value — it was a spelling
# that the parser cannot read in every locale. `\u` and `\U` inside a `$'…'` literal are that
# spelling, and neither file may carry one again. Comment lines are skipped, since the prose
# above and in `layout.zsh` both name the escape in order to explain it.
Describe 'parse-time character literals'
  Parameters
    'lib/core/layout.zsh'
    'lib/core/detect.zsh'
    'lib/core/tokens.zsh'
    'lib/core/render.zsh'
    'lib/core/transient.zsh'
    'lib/segments/retval.zsh'
  End

  It "holds no locale-dependent literal in $1"
    literals() {
      setopt local_options extended_glob
      local line; local -a bad=()
      while IFS= read -r line; do
        [[ $line == [[:space:]]#\#* ]] && continue
        [[ $line == *"\$'"*'\\'[uU]* ]] && bad+=$line
      done < "$SHELLSPEC_PROJECT_ROOT/$1"
      print -r -- "${#bad}"
    }
    When call literals "$1"
    The output should eq '0'
  End
End
