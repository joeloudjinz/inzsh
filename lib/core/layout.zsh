# InZsh — layout. How wide a thing is, what still fits, and what to do when it does not.
#
# Three mechanisms live here, and they are deliberately independent of one another:
#
#   width      `_inzsh_width` — how many COLUMNS a rendered fragment occupies.
#   hide/show  MINCOLS and the degradation ladder — whether a segment is drawn at all.
#   truncate   `_inzsh_truncate_path` — making one segment's TEXT shorter so it still fits.
#
# Hiding and truncating are SEPARATE mechanisms and neither is a fallback for the other. A
# hidden segment contributes nothing, not even a separator; a truncated segment is still there,
# just shorter. A path that has run out of budget shortens — it does not disappear — and a
# segment below its MINCOLS disappears whole rather than shrinking to an illegible stub.
#
# Rank and MINCOLS are independent too. Rank is POSITION: where a segment sits in the row.
# MINCOLS is PRIORITY: how much room the terminal must have before it is worth drawing. The
# segment nearest the edge is not necessarily the first to drop, and nothing here couples the
# two — `_inzsh_layout_filter` hands the survivors back in the order it was given them.
#
# Everything below is parameter expansion and arithmetic. This is the render path: no forks, no
# command substitution, and no reading of the terminal — the width is always injected by the
# caller, which is the seam that makes every rule here testable at a width no terminal has.

# ---------------------------------------------------------------------------------------------
# Width
# ---------------------------------------------------------------------------------------------

# `${#string}` lies about a rendered segment. A prompt fragment is a mix of visible text and
# escapes that occupy no columns at all — `%F{...}` to open a colour, `%f` to close it, `%{...%}`
# around a raw terminal sequence — and counting characters counts those too. What a layout needs
# is the number of CELLS the fragment will fill, so the escapes come out first and what is left
# is measured with `${(m)#...}`, which asks the C library for each character's display width
# rather than assuming one column per character.
#
# The measurement is only as good as the locale. Outside a multibyte locale `${(m)#...}` counts
# BYTES, so a multibyte glyph measures wider than the cell it will occupy. That direction is the
# safe one: an over-count makes the layout hide or truncate slightly more than it had to, and
# never overflows the row. Locale capability is detected once, in `lib/core/detect.zsh`; this
# file does not repeat the question.

# The truncation marker. The glyph itself is `_inzsh_glyph[ellipsis]` in `lib/core/tokens.zsh`,
# which is where every mark the theme draws now lives — including the byte-spelling and the
# locale fallback this file used to carry alone. The lesson it learned the hard way is written
# down there: a character escape is resolved when a file is PARSED, and under `LC_ALL=C` the one
# that used to sit on this line failed with `character not in range` and took every function
# below it down with it.
#
# Read at source time and guarded. The entry point sources the token layer above this file, but
# this file stays independently sourceable and a layout layer that came up without one must
# still truncate: three ASCII dots are not the glyph, but they are legible, one byte per column,
# and drawable in any locale.
typeset -g _inzsh_layout_ellipsis='...'
if [[ ${(t)_inzsh_glyph} == association* && -n ${_inzsh_glyph[ellipsis]} ]]; then
  _inzsh_layout_ellipsis=${_inzsh_glyph[ellipsis]}
fi

# Display width of a literal string, nothing stripped. The one place `${(m)#...}` is spelled
# out, so the locale caveat above has a single home. Answer in REPLY.
_inzsh_width_raw() {
  emulate -L zsh

  local text=$1
  typeset -g REPLY=${(m)#text}
  return 0
}

# Display width of the VISIBLE text of a prompt fragment, in REPLY.
#
# Removed, in order: `%%` is protected first (it is a literal per cent, one column wide, and
# every rule below would otherwise see the second character as the start of an escape); then
# `%{...%}` blocks, whose contents are zero-width by definition; then `%F{...}` and `%K{...}`;
# then the single-letter switches `%f %k %b %B %u %U %s %S`; then raw CSI sequences a segment
# emitted itself rather than asking zsh for.
#
# What is NOT removed: escapes that EXPAND to visible text — `%~`, `%n`, `%*`. They are counted
# as the literal characters they are, because their width is not knowable from the string. A
# caller measuring a fragment that contains one must expand it first; segments build their text
# before they hand it over, so this is a rule about hand-written prompt strings, not about the
# render path.
_inzsh_width() {
  emulate -L zsh
  setopt extended_glob

  local text=$1

  # \x01 stands in for a literal per cent while the escapes come out, and goes back afterwards.
  # A string that genuinely contains \x01 measures one column short; nothing draws control
  # characters into a prompt, so that trade buys correct `%%` handling for free.
  text=${text//'%%'/$'\x01'}
  text=${text//'%{'(%[^\}]|[^%])#'%}'/}
  text=${text//'%'[FK]'{'[^\}]#'}'/}
  text=${text//'%'[fkbBuUsS]/}
  text=${text//$'\e'\[[0-9;:?]#[a-zA-Z]/}
  text=${text//$'\x01'/%}

  typeset -g REPLY=${(m)#text}
  return 0
}

# Add a visible width to a running total: `_inzsh_width_add <accumulator-name> <width>`.
#
# The accumulator convention, and the reason there is one: a builder appends escape-laden pieces
# to a string, and the width of the result cannot be recovered from the result. So it is tracked
# as the pieces go on —
#
#   local -i used=0
#   for piece in "${pieces[@]}"; do
#     rendered+=$piece
#     _inzsh_width "$piece"
#     _inzsh_width_add used "$REPLY"
#   done
#
# The accumulator is named, not returned, so a builder can keep several (body, separators, a
# reserved tail) without a temporary each time. zsh's dynamic scoping means a `local -i` in the
# caller is what gets updated. A width that is not a non-negative integer adds nothing rather
# than erroring — a mis-measured piece must not poison the total. A name that is not a valid
# identifier is refused with status 1, the one failure here, because there is nothing sensible
# to add to. Accumulator names beginning `_inzsh_wa_` are reserved by this function.
_inzsh_width_add() {
  emulate -L zsh
  setopt extended_glob

  local _inzsh_wa_name=$1
  [[ $_inzsh_wa_name == [A-Za-z_][A-Za-z0-9_]# ]] || return 1

  local -i _inzsh_wa_delta=0
  [[ $2 == <-> ]] && _inzsh_wa_delta=$2

  local _inzsh_wa_current=${(P)_inzsh_wa_name-}
  [[ $_inzsh_wa_current == <-> ]] || _inzsh_wa_current=0

  (( ${_inzsh_wa_name} = _inzsh_wa_current + _inzsh_wa_delta ))
  return 0
}

# The width one row of segments needs: `_inzsh_layout_total <sep-width> <width>...`, answer in
# REPLY. Widths are the visible widths of the segment bodies; `sep-width` is the cost of ONE
# boundary between two of them, counted n-1 times because a row of n blocks has n-1 boundaries.
# A leading or trailing cap glyph is the caller's own arithmetic — it is drawn once, whatever n
# is, so folding it in here would make the total wrong for every caller that does not draw one.
# Anything unparseable counts as zero, so a missing measurement under-states the total rather
# than aborting the render.
_inzsh_layout_total() {
  emulate -L zsh
  setopt extended_glob

  local -i sep=0
  [[ $1 == <-> ]] && sep=$1
  shift

  local width
  local -i total=0 count=0 each
  for width in "$@"; do
    each=0
    [[ $width == <-> ]] && each=$width
    (( total += each, count++ ))
  done
  (( count > 1 )) && (( total += sep * (count - 1) ))

  typeset -g REPLY=$total
  return 0
}

# The one-row invariant, as a predicate: `_inzsh_layout_fits <cols> <sep-width> <width>...`.
# Status 0 iff the row can be drawn without wrapping; REPLY carries the total either way, so a
# caller that needs to know by how much it overflowed does not measure twice. A width that is
# not a non-negative integer means the terminal size is unknown, and an unknown width fits —
# see the note on `_inzsh_layout_filter` for why the unknown case always assumes room.
_inzsh_layout_fits() {
  emulate -L zsh
  setopt extended_glob

  local cols=$1
  shift
  _inzsh_layout_total "$@"

  [[ $cols == <-> ]] || return 0
  (( REPLY <= cols ))
}

# ---------------------------------------------------------------------------------------------
# MINCOLS — hiding a segment below a width
# ---------------------------------------------------------------------------------------------

# `INZSH_<SEG>_MINCOLS` is the terminal width below which segment SEG is not drawn. It is a
# priority knob, not a position one: the first segment to go when the window narrows is the one
# with the highest MINCOLS, wherever it happens to sit in the row.
#
# The default is 0, which reads as "never hide on width" — a segment the user never configured
# keeps behaving exactly as it did before this file existed. Anything that is not a non-negative
# integer resolves to 0 as well: a typo'd MINCOLS shows a segment that should have hidden, which
# is a cosmetic wrong, where obeying it could hide the prompt.
_inzsh_mincols_of() {
  emulate -L zsh
  setopt extended_glob

  typeset -g REPLY=0

  # The name is checked as the VARIABLE it builds, not as a segment name in the abstract —
  # `${(P)}` on something that is not an identifier is an error, and an error here is a broken
  # prompt. Anything that cannot name a variable simply has no MINCOLS.
  local var=INZSH_${(U)1}_MINCOLS
  [[ $var == [A-Za-z_][A-Za-z0-9_]# ]] || return 0

  # `INZSH_*_MINCOLS` is registered as a FAMILY in `lib/core/config.zsh`, so the read goes
  # through the registry where it is loaded: one validator and one default — 0 — for every
  # segment, rather than a rule restated per read site. The grammar below is that same rule for
  # a layout layer sourced without the config layer, and the two accept the same values: a
  # non-negative integer, optional leading `+`, which is what `int:0:` means.
  local value=${(P)var-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get "$var"
    value=$REPLY
  fi

  # Normalised through an integer, so `007` and `7` are the same MINCOLS and every caller can
  # compare what comes back arithmetically without re-reading the config.
  local -i resolved=0
  [[ $value == (|+)<-> ]] && resolved=$value
  REPLY=$resolved

  return 0
}

# `_inzsh_layout_filter <cols> <SEGMENT>...` — the segments that survive at that width, in the
# order they were given, in `reply`. Order in equals order out: this function decides IF, never
# WHERE, and the rank layer is untouched by it.
#
# A `cols` that is not a non-negative integer means the width is unknown, and an unknown width
# hides nothing. That is the same rule the ladder and `_inzsh_layout_fits` follow, and the
# reason is that the failure modes are not symmetric: assuming room too readily wraps a prompt,
# assuming none empties it. `$COLUMNS` is set in every interactive shell, so the unknown case is
# a bug elsewhere, and the response to a bug elsewhere is to draw everything.
_inzsh_layout_filter() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga reply
  reply=()

  local cols=$1
  shift

  if [[ $cols != <-> ]]; then
    reply=("$@")
    return 0
  fi

  local segment
  for segment in "$@"; do
    _inzsh_mincols_of "$segment"
    (( cols >= REPLY )) && reply+=("$segment")
  done

  return 0
}

# ---------------------------------------------------------------------------------------------
# PRIORITY — the order things are given up in
# ---------------------------------------------------------------------------------------------

# `INZSH_<SEG>_PRIORITY` is the survival order: LOWER SURVIVES LONGER. It answers a different
# question from `INZSH_<SEG>_RANK`, which is why it is a second number rather than a reading of
# the first — rank is WHERE a segment sits, priority is WHEN it goes, and the segment nearest the
# edge is not necessarily the one to lose first.
#
# MINCOLS still works and still means what it meant: a hard floor the user sets by hand. The
# difference is what happens when nothing is set. A MINCOLS default can only ever be a guess,
# because it is a fixed number compared against a segment whose width changes every render — the
# path grows a directory, the branch name is longer on one repo than another, `Maghrib` is two
# columns wider than `Isha`. Fitting the row from measured widths at the moment it is drawn is
# not a better guess, it is the absence of one.
#
# The default is EMPTY for the reason `INZSH_*_RANK` registers empty: nothing set is not a
# missing answer, it is the instruction to use what the segment registered for itself in
# `_inzsh_segment_priority`. A segment that registered nothing either lands last.

# Where an unregistered segment lands. Not a magic number buried in the arithmetic: a stranger
# has to sort somewhere, and this is the one place that says where.
typeset -gi _inzsh_priority_unknown=99999

# Declared here as well as in `lib/core/render.zsh` so that this file answers sensibly when it is
# sourced on its own — the same courtesy `_inzsh_ladder_defaults` paid the breakpoints.
typeset -gA _inzsh_segment_priority

_inzsh_priority_of() {
  emulate -L zsh
  setopt extended_glob

  # Last, not first. An unregistered segment is one this file knows nothing about, and the safe
  # place for a stranger in a survival order is the end of it — being wrong there costs a
  # segment nobody configured, where being wrong at the front costs one they did.
  typeset -g REPLY=$_inzsh_priority_unknown

  local var=INZSH_${(U)1}_PRIORITY
  [[ $var == [A-Za-z_][A-Za-z0-9_]# ]] || return 0

  local value=${(P)var-}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get "$var"
    value=$REPLY
  fi

  # The knob first, then the segment's own registration, then the stranger's place. Negative is
  # allowed and means what it says — kept longer than anything at zero — because a user who wants
  # one block to outlive every default should not have to renumber the defaults to say so.
  # Arithmetic as a COMMAND, never as an expansion. `$(( … ))` is not a subprocess, but the guard
  # in `test/unit/layout_spec.sh` cannot tell it from `$( … )` and refuses both — which is the
  # right trade for a file on the render path, and the reason nothing here uses the form.
  if [[ $value == (|-|+)<-> ]]; then
    (( REPLY = value ))
  elif [[ ${_inzsh_segment_priority[$1]-} == (|-|+)<-> ]]; then
    (( REPLY = _inzsh_segment_priority[$1] ))
  fi

  return 0
}

# `_inzsh_layout_fit <budget> <sep-width> <NAME> <WIDTH> [<NAME> <WIDTH>...]` — the segments that
# fit, IN THE ORDER THEY WERE GIVEN, in `reply`.
#
# This is the function that makes the no-wrap rule true rather than likely. Segments are taken in
# priority order, each one's real measured width added to what is already kept, and the moment
# one does not fit the walk STOPS.
#
# Stopping rather than skipping is deliberate, and it is the difference between a prompt you can
# predict and one you cannot. Skipping packs the row tighter — an 8-column clock would slip into
# the gap an 18-column prayer block was refused — but it means a LESS important segment can
# outlive a MORE important one, and which of them you get depends on arithmetic no one watching
# the window resize can follow. What survives here is always a PREFIX of the priority order, so
# the rule a user learns is one sentence: things go in the order you listed them.
#
# A budget that is not a non-negative integer keeps everything, the same rule and for the same
# reason as `_inzsh_layout_filter`: assuming room too readily wraps a prompt, assuming none
# empties it, and only one of those is recoverable by looking at it.
_inzsh_layout_fit() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga reply
  reply=()

  local budget=$1 sep=$2
  shift 2

  local -a args=("$@")
  local -a names=() widths=()
  local -i i
  for (( i = 1; i <= $#args; i += 2 )); do
    names+=("${args[i]}")
    widths+=("${args[i + 1]}")
  done

  (( $#names )) || return 0

  if [[ $budget != (|+)<-> ]]; then
    reply=("${names[@]}")
    return 0
  fi

  # Sorted by priority, ties by the order given. Zero-padded and offset so that a plain string
  # sort orders them numerically and negatives sort below zero — `${(n)…}` reads a leading `-` as
  # part of no number at all, and the numbers here are exactly the ones it gets wrong.
  local -a keys=()
  local -i sortable
  for (( i = 1; i <= $#names; i++ )); do
    _inzsh_priority_of "${names[i]}"
    (( sortable = REPLY + 1000000 ))
    keys+=("${(l:9::0:)sortable}:${(l:4::0:)i}")
  done

  local -a kept_widths=()
  local -A kept=()
  local key
  local -i idx
  for key in ${(o)keys}; do
    idx=${key##*:}
    kept_widths+=("${widths[idx]}")
    _inzsh_layout_total "$sep" "${kept_widths[@]}"
    if (( REPLY > budget )); then
      kept_widths[-1]=()
      break
    fi
    kept[${names[idx]}]=1
  done

  for (( i = 1; i <= $#names; i++ )); do
    (( ${+kept[${names[i]}]} )) && reply+=("${names[i]}")
  done

  return 0
}

# ---------------------------------------------------------------------------------------------
# The degradation ladder
# ---------------------------------------------------------------------------------------------

# Four steps, widest first. A step is a NAME, not a rule: this file says which one a width lands
# on, and the engine decides what each one means. Naming them rather than passing the number
# around is what keeps the breakpoints tunable — a segment asks "which step?", never "is COLUMNS
# over 80?".
#
#   full     everything the configuration asks for
#   wide     the comfortable prompt
#   narrow   the prompt that still says something useful in a split pane
#   minimal  the floor; whatever remains when there is no room to negotiate
typeset -ga _inzsh_ladder_steps
_inzsh_ladder_steps=(full wide narrow minimal)

# The minimum width for each step except the floor, which needs none. 120 / 80 / 60 are
# PLACEHOLDERS from the roadmap and will be tuned at the M3 gate against a real prompt — which
# is exactly why they are overridable. Tuning must be a config change, not a code change, so
# every number here has an `INZSH_LADDER_<STEP>_COLS` in front of it.
#
# The three knobs are registered with these same defaults in `lib/core/config.zsh`. This array
# is what a layout layer sourced WITHOUT the config layer degrades to — the same reason
# `lib/segments/time.zsh` keeps `_inzsh_time_format_default` — and the two copies are held
# equal by `test/unit/config_registry_spec.sh` rather than by anybody remembering.
typeset -ga _inzsh_ladder_defaults
_inzsh_ladder_defaults=(120 80 60)

# Resolve the configured breakpoints into `_inzsh_ladder_bounds`. Re-read on every call: a
# breakpoint is config, and config is whatever the user's shell says right now.
#
# Two validity rules, and both of them fall back rather than fail. A breakpoint that is not a
# non-negative integer takes its default, per knob. Then the resolved trio must be
# non-increasing — a `wide` above `full` is not a narrower prompt, it is an unreachable step —
# and if it is not, the WHOLE trio reverts to the defaults. Partial repair of an ordering is
# guesswork about which of the three numbers the user meant; reverting is one behaviour the user
# can recognise, and the shipped ladder is a working ladder.
_inzsh_ladder_resolve() {
  emulate -L zsh
  setopt extended_glob

  local -a bounds=()
  local var value
  local -i i resolved

  for (( i = 1; i <= ${#_inzsh_ladder_defaults}; i++ )); do
    var=INZSH_LADDER_${(U)_inzsh_ladder_steps[i]}_COLS
    value=${(P)var-}
    if (( ${+functions[_inzsh_config_get]} )); then
      _inzsh_config_get "$var"
      value=$REPLY
    fi
    [[ $value == (|+)<-> ]] || value=${_inzsh_ladder_defaults[i]}
    resolved=$value
    bounds+=($resolved)
  done

  for (( i = 2; i <= ${#bounds}; i++ )); do
    if (( bounds[i] > bounds[i - 1] )); then
      bounds=("${_inzsh_ladder_defaults[@]}")
      break
    fi
  done

  typeset -ga _inzsh_ladder_bounds
  _inzsh_ladder_bounds=("${bounds[@]}")
  return 0
}

# `_inzsh_layout_ladder <cols>` — the step name for that width, in REPLY. Widest step whose
# breakpoint the width reaches; the floor when it reaches none. An unknown width answers with
# the widest step, for the same reason `_inzsh_layout_filter` hides nothing: over-degrading a
# prompt because a number was missing is the worse of the two mistakes.
_inzsh_layout_ladder() {
  emulate -L zsh
  setopt extended_glob

  _inzsh_ladder_resolve

  typeset -g REPLY=${_inzsh_ladder_steps[1]}
  [[ $1 == <-> ]] || return 0

  local -i cols=$1 i
  for (( i = 1; i <= ${#_inzsh_ladder_bounds}; i++ )); do
    if (( cols >= _inzsh_ladder_bounds[i] )); then
      REPLY=${_inzsh_ladder_steps[i]}
      return 0
    fi
  done

  REPLY=${_inzsh_ladder_steps[-1]}
  return 0
}

# ---------------------------------------------------------------------------------------------
# Progressive path truncation
# ---------------------------------------------------------------------------------------------

# `_inzsh_truncate_path <path> <budget>` — the path, shortened to at most `budget` columns, in
# REPLY.
#
# This is TRUNCATION, not hiding, and the two never stand in for each other. A directory segment
# that has run out of room gets shorter and keeps saying something; it does not vanish. Whether
# the segment is drawn at all is MINCOLS' business, decided before this is ever called.
#
# The ladder, each rung tried in turn and the first that fits taken:
#
#   ~/a/b/c/d    the whole thing, with $HOME collapsed to ~ first
#   …/b/c/d      leading components dropped, the ellipsis standing for what went
#   …/c/d
#   …/d
#   d            the basename alone — at this width the ellipsis costs more than it says
#   d…           the basename itself cut, when even the basename is too wide
#
# The result is never wider than the budget, at any budget, for any path. A budget of 0 yields
# the empty string; that is the honest answer to "no room", and the caller that asked for it is
# the one that should have hidden the segment instead.
#
# A budget that is not a non-negative integer means no budget is known, and the path comes back
# collapsed but untruncated — the same "assume room" rule the rest of this file follows.
_inzsh_truncate_path() {
  emulate -L zsh
  setopt extended_glob

  typeset -g REPLY=

  # $HOME collapses first, because it is the shortening that costs nothing: `~` is not an
  # abbreviation a reader has to decode. `$home` is quoted on both matches — a home directory is
  # allowed to contain glob characters, and only the `/*` after it is meant as a pattern.
  local shown=$1
  local home=${HOME%/}
  if [[ -n $home ]]; then
    if [[ $shown == "$home" ]]; then
      shown='~'
    elif [[ $shown == "$home"/* ]]; then
      shown='~'${shown[${#home} + 1,-1]}
    fi
  fi

  # Root marker off, then split. Splitting drops empty fields, so a trailing slash, a doubled
  # slash and a bare root all normalise here rather than in a rule of their own.
  local root=''
  local body=$shown
  case $body in
    ('~')    root='~'; body='' ;;
    ('~/'*)  root='~'; body=${body#'~/'} ;;
    ('/')    root='/'; body='' ;;
    ('/'*)   root='/'; body=${body#'/'} ;;
  esac
  local -a comps=(${(s:/:)body})
  local -i n=${#comps}

  # Rebuilt rather than reused, so the candidate that "fits" is the string that gets drawn and
  # not the raw argument it came from.
  local full=$root
  if (( n )); then
    [[ $root == '~' ]] && full+='/'
    full+=${(j:/:)comps}
  fi

  local budget=$2
  if [[ $budget != <-> ]]; then
    REPLY=$full
    return 0
  fi
  local -i cap=$budget

  local -a rungs=("$full")
  local -i k
  for (( k = 1; k < n; k++ )); do
    rungs+=("${_inzsh_layout_ellipsis}/${(j:/:)comps[k + 1,-1]}")
  done
  (( n )) && rungs+=("${comps[-1]}")

  local rung
  local -i width
  for rung in "${rungs[@]}"; do
    _inzsh_width_raw "$rung"
    width=$REPLY
    if (( width <= cap )); then
      REPLY=$rung
      return 0
    fi
  done

  # Nothing on the ladder fits, so the last rung is cut down. For a path with components that is
  # the basename; for a bare root it is the root marker, which is one column and only fails to
  # fit at a budget of 0.
  _inzsh_truncate_text "${rungs[-1]}" $cap
  return 0
}

# `_inzsh_truncate_text <text> <budget>` — at most `budget` columns of `text`, in REPLY, with
# the ellipsis on the end when there is room for both it and something to elide. Below that
# width the marker is dropped rather than the text: at two columns, two letters of a name say
# more than one letter and a promise of more.
_inzsh_truncate_text() {
  emulate -L zsh
  setopt extended_glob

  typeset -g REPLY=

  local text=$1
  local -i cap=0
  [[ $2 == <-> ]] && cap=$2
  (( cap > 0 )) || return 0

  _inzsh_width_raw "$text"
  if (( REPLY <= cap )); then
    REPLY=$text
    return 0
  fi

  _inzsh_width_raw "$_inzsh_layout_ellipsis"
  local -i marker=$REPLY
  if (( cap < marker )); then
    _inzsh_width_prefix "$text" $cap
    return 0
  fi

  local -i room
  (( room = cap - marker ))
  _inzsh_width_prefix "$text" $room
  REPLY=$REPLY$_inzsh_layout_ellipsis
  return 0
}

# `_inzsh_width_prefix <text> <columns>` — the longest leading run of `text` that fits in
# `columns`, in REPLY. Cutting by character would overshoot on a double-width glyph, so the cut
# starts at `columns` characters — never fewer characters than columns, since no character is
# narrower than one column — and steps back until the width fits. The loop runs once per
# double-width character in the cut, not once per column.
_inzsh_width_prefix() {
  emulate -L zsh
  setopt extended_glob

  typeset -g REPLY=

  local text=$1
  local -i cap=0
  [[ $2 == <-> ]] && cap=$2
  (( cap > 0 && ${#text} > 0 )) || return 0

  local -i take=${#text}
  (( take > cap )) && take=cap

  local cut=${text[1,take]}
  _inzsh_width_raw "$cut"
  while (( REPLY > cap && take > 0 )); do
    (( take-- ))
    cut=${text[1,take]}
    _inzsh_width_raw "$cut"
  done

  REPLY=$cut
  return 0
}
