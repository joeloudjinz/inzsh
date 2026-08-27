# InZsh — rows: which segment draws on which line, and where the input marker sits relative
# to what got drawn. Sits between `engine` and `render` in the load order, depends on the
# engine for `_inzsh_rank_split` and on nothing below it — not `render.zsh`, not the terminal.
#
# A ROW is a pair of ordered segment lists, a left side and a right side. Rows are numbered from
# 1, top down, and the numbers are SORT KEYS, not slots: a row exists because something resolved
# onto it, so declaring rows 1 and 7 draws two rows, adjacent, and a row with nothing visible on
# either side is not drawn at all. Row 1 is where every segment goes today and where every
# segment still goes by default — an existing `.zshrc` sets no row arrays, so nothing here moves
# a segment anywhere it was not already.
#
# THIS FILE IS PURE OVER ITS INPUTS. `_inzsh_rows_resolve` takes the terminal width and the
# candidate segment names as arguments rather than reading `$COLUMNS` or a segment's own state,
# which is what lets it unit-test in a shell that draws no prompt at all — the same seam
# `lib/salah/calc.zsh` has with its injected clock. Nothing here fetches segment text, reads the
# terminal or assigns a prompt parameter; it only decides where a name goes.
#
# NOTHING CONSUMES THIS YET. `render.zsh` still builds one row from `_inzsh_left` /
# `_inzsh_right` exactly as it always has — wiring the renderer to draw N rows is later work.
# Landing the resolution layer on its own, before anything reads it, is what makes it reviewable
# by itself and keeps this change byte-identical in every prompt anyone sees.
#
# ---------------------------------------------------------------------------------------------
# The row knobs — read outside the config registry, on purpose
#
# `INZSH_ROW<n>_LEFT` / `INZSH_ROW<n>_RIGHT` are ARRAYS: `INZSH_ROW2_LEFT=(USER VENV)`. Every
# validator the registry understands — `any`, `bool`, `int`, an `enum:`, a `word:` — describes a
# single value, and `_inzsh_config_get` answers in a scalar `REPLY`; there is no array knob
# anywhere else in the theme. Rather than bend the registry into holding lists, this file will
# read these parameters itself and validate them itself, holding to the one rule the registry
# states for everything else: a value that fails is never fatal and never reported at the
# prompt.
#
# The families are registered below as `any`, purely so the names appear in the `inzsh-knobs`
# vocabulary `inzsh doctor` and the playground read from the registry. That registration is not
# validation — the reader added later in this file is — and an array-valued knob answers `any`
# happily however many words it joins into when something else asks for its value as a scalar.
#
# ARRAYS ONLY. A whitespace-separated scalar spelling was considered and dropped: two ways to
# write one knob is two things to document, test and keep agreeing with each other, and shipping
# one spelling is the cheaper promise — a knob released with two accepted forms cannot lose one
# again without a major bump. So `${(Pt)name}` is checked before anything else, and a scalar
# assigned to a row knob — `INZSH_ROW1_LEFT="TIME DIR"` — is REFUSED whole rather than
# word-split into two segments; the failure is then the same as never having set it, visible
# through `_inzsh_rows_entries`'s status rather than half-working.
#
# `INZSH_MARKER_ROW` is the one scalar knob this feature adds: `enum:inline|own`, `own` is
# today's shape — a bare marker line below every drawn row. `INZSH_PROMPT_LINES` keeps working
# as a deprecated alias for it — see `_inzsh_marker_row_resolved` below.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register        INZSH_MARKER_ROW  'enum:inline|own' own
  _inzsh_config_register_family 'INZSH_ROW*_LEFT'  any               ''
  _inzsh_config_register_family 'INZSH_ROW*_RIGHT' any               ''
fi

# The published answer. Declared here so a caller that asks before the first resolve gets empty
# arrays rather than an unset-parameter error — the same courtesy `lib/core/engine.zsh` extends
# `_inzsh_left` / `_inzsh_right` / `_inzsh_hidden`.
#
# `_inzsh_rows_hidden` is the candidates step 2 below drops for being rank 0 and unclaimed by
# anything — the same set `render.zsh` used to compute for itself before rows existed. Published
# rather than recomputed: `render.zsh` needs it for `_inzsh_hidden`'s bookkeeping, and asking
# `_inzsh_rank_of` a second time for a segment this file already asked would be exactly the
# re-read `lib/core/engine.zsh`'s own comment on `_inzsh_rank_split_pairs` exists to rule out.
typeset -gi _inzsh_row_count=0
typeset -ga _inzsh_rows_hidden
_inzsh_rows_hidden=()
typeset -ga _inzsh_row1_left  _inzsh_row1_right
typeset -ga _inzsh_row2_left  _inzsh_row2_right
typeset -ga _inzsh_row3_left  _inzsh_row3_right
typeset -ga _inzsh_row4_left  _inzsh_row4_right
typeset -ga _inzsh_row5_left  _inzsh_row5_right
typeset -ga _inzsh_row6_left  _inzsh_row6_right
typeset -ga _inzsh_row7_left  _inzsh_row7_right
typeset -ga _inzsh_row8_left  _inzsh_row8_right
_inzsh_row1_left=(); _inzsh_row1_right=()
_inzsh_row2_left=(); _inzsh_row2_right=()
_inzsh_row3_left=(); _inzsh_row3_right=()
_inzsh_row4_left=(); _inzsh_row4_right=()
_inzsh_row5_left=(); _inzsh_row5_right=()
_inzsh_row6_left=(); _inzsh_row6_right=()
_inzsh_row7_left=(); _inzsh_row7_right=()
_inzsh_row8_left=(); _inzsh_row8_right=()

# `_inzsh_rows_entries <parameter-name>` → `reply`. Status 0 iff `$1` names an ARRAY parameter —
# empty or not — and status 1 when it is unset or refuses to be one at all, which is the "refused,
# not split" rule for a scalar stated above. `${(Pt)name}` answers what kind of parameter `$1` is
# without ever reading it as anything else first, so the scalar case is caught before a single
# entry is looked at.
#
# Per-entry, this applies exactly the two rules §2.2 states that concern ONE array in isolation:
# an entry must be a valid identifier — `${(P)}` on anything else is fatal mid-render, and a
# later reader of a claimed name will do exactly that — and it must name a segment this build
# actually has, checked against `_inzsh_segment_defaults` directly rather than against whatever
# candidate list a caller happens to be resolving against, so a row array can still claim a
# segment the caller filtered out upstream. Everything else §2.2 lists — already claimed, did
# not survive MINCOLS — is a fact about the WHOLE resolution rather than about this one array, so
# `_inzsh_rows_resolve` asks it instead. A duplicate entry inside a single array is not dropped
# here either: the claim walk below drops it the same way it drops a duplicate that came from two
# different arrays, one mechanism for both.
_inzsh_rows_entries() {
  emulate -L zsh
  setopt local_options extended_glob

  typeset -ga reply
  reply=()

  local name=$1
  [[ $name == [A-Za-z_][A-Za-z0-9_]# ]] || return 1
  (( ${+parameters[$name]} )) || return 1
  [[ ${(Pt)name} == array* ]] || return 1

  local -a raw
  raw=("${(@P)name}")

  local entry
  for entry in "${raw[@]}"; do
    [[ -n $entry && $entry == [A-Za-z_][A-Za-z0-9_]# ]] || continue
    (( ${+_inzsh_segment_defaults[$entry]} )) || continue
    reply+=("$entry")
  done

  return 0
}

# `_inzsh_marker_row_resolved` → REPLY: `inline` or `own`.
#
# `INZSH_PROMPT_LINES` is the knob every existing `.zshrc` already carries, and it keeps working
# — this is the alias precedence §3.1 describes, not the removal:
#
#   1. an explicit, valid `INZSH_MARKER_ROW` wins outright
#   2. otherwise an explicit, valid `INZSH_PROMPT_LINES` resolves to the marker row it names
#      (`1` is `inline`, `2` is `own`)
#   3. otherwise the default, `own`
#
# "Explicit" is load-bearing: `_inzsh_config_get` would hand back the registered default the
# moment nothing is set, and that default must not shortcut past step 2 the way it would if this
# read `INZSH_MARKER_ROW`'s resolved value instead of its raw one. So the raw variable is read
# and validated by hand at both levels, set-but-empty counting as unset the same way it does
# everywhere else in this tree.
#
# `INZSH_PROMPT_LINES` is registered in `lib/core/render.zsh`, which loads AFTER this file — this
# file depends on nothing below it, so its grammar is restated here as the literal `1`/`2` it has
# always been, rather than asked of a registry entry that may not exist yet when THIS file is
# sourced. `INZSH_MARKER_ROW`, registered a few lines up in this same file, is instead checked
# through `_inzsh_config_validate` where the config layer is loaded, and by the literal enum
# otherwise — config.zsh loads BEFORE this file, so leaning on it here is the ordinary direction.
_inzsh_marker_row_resolved() {
  emulate -L zsh

  typeset -g REPLY=own

  local raw=${INZSH_MARKER_ROW-}
  if [[ -n $raw ]]; then
    if (( ${+functions[_inzsh_config_validate]} )); then
      if _inzsh_config_validate INZSH_MARKER_ROW "$raw"; then
        REPLY=$raw
        return 0
      fi
    elif [[ $raw == inline || $raw == own ]]; then
      REPLY=$raw
      return 0
    fi
  fi

  local lines=${INZSH_PROMPT_LINES-}
  case $lines in
    (1) REPLY=inline; return 0 ;;
    (2) REPLY=own;    return 0 ;;
  esac

  return 0
}

# `_inzsh_rows_resolve <cols> <segment>...` — resolve every declared row array against the
# candidate segment list, publishing `_inzsh_row_count` and, for `n` from 1 to that count,
# `_inzsh_row<n>_left` / `_inzsh_row<n>_right` — already renumbered and in render order, so a
# caller loops `1.._inzsh_row_count` and never scans eight slots hoping some of them are empty.
#
# `<cols>` is the terminal width to filter against, injected rather than read from `$COLUMNS` —
# the same seam `_inzsh_layout_filter` already has, and the reason this file unit-tests with no
# terminal in the shell at all. `<segment>...` is every segment this build knows about — the
# renderer will pass `${(k)_inzsh_segment_defaults}` once something wires this up — UNFILTERED by
# rank, because filtering by rank is now this function's own job: see step 2.
#
# The five steps are the whole contract, and the order is the subtle part:
#
#   1. CLAIM      every valid entry of every explicit array, rows ascending, left before right
#                 within a row, so the first side that names a segment keeps it and every later
#                 mention — same array, this row's other side, or a later row — is dropped. A
#                 claim bypasses rank entirely.
#   2. DROP RANK 0 among candidates NOBODY claimed — issue #185's guard, relocated one step
#                 later than it used to run. Dropping rank 0 before claiming would have thrown
#                 away exactly what step 1 exists to rescue: DATE, DURATION, JOBS and SSH all
#                 register a rank of 0, and a row array names one of them to override that.
#   3. WIDTH      MINCOLS over everything still standing, claimed segments included — a
#                 placement rule never overrules a width rule (§2.4), so a claimed segment that
#                 does not survive comes back out of whatever row it was claimed onto.
#   4. DERIVE     the unclaimed remainder that survived width is split by rank, reusing the rank
#                 step 2 already read for it rather than asking `_inzsh_rank_of` a second time —
#                 `_inzsh_rank_split_pairs` is `_inzsh_rank_split`'s own answer to a caller that
#                 has already read the ranks (see `lib/core/engine.zsh`), and a caller that reads
#                 ranks once per candidate and then calls `_inzsh_rank_split` anyway is precisely
#                 the second read that function exists to avoid.
#   5. FILL       each side takes its explicit array if one was SET — even explicitly empty —
#                 and otherwise nothing, except row 1, whose UNSET side takes the derived
#                 answer, because rank has no row axis and can only ever describe row 1.
_inzsh_rows_resolve() {
  emulate -L zsh
  setopt local_options extended_glob

  local -i cols=0
  [[ $1 == <-> ]] && cols=$1
  shift
  local -a candidates=("$@")

  # Every published slot cleared before anything else runs, so a second call in the same shell
  # — a resize, a test that resolves twice — never sees a row the CURRENT configuration dropped.
  typeset -gi _inzsh_row_count=0
  local -i n
  for (( n = 1; n <= 8; n++ )); do
    typeset -ga _inzsh_row${n}_left _inzsh_row${n}_right
    set -A _inzsh_row${n}_left
    set -A _inzsh_row${n}_right
  done

  # Step 1 — claim. `explicit[N:SIDE]` holds that side's claimed entries, space-joined; `has`
  # marks a side that was a real array at all, even an explicitly empty one, which is what lets
  # step 5 tell "explicit and empty" from "never set" apart for row 1.
  local -A explicit=() has=() claimed=()
  local side key entry
  local -a got
  for (( n = 1; n <= 8; n++ )); do
    for side in left right; do
      key="${n}:${side}"
      if _inzsh_rows_entries "INZSH_ROW${n}_${(U)side}"; then
        has[$key]=1
        got=()
        for entry in "${reply[@]}"; do
          (( ${+claimed[$entry]} )) && continue
          claimed[$entry]=1
          got+=("$entry")
        done
        explicit[$key]="${(j: :)got}"
      fi
    done
  done

  # Step 2 — drop the switched-off. Only a candidate nobody claimed is even asked its rank, and
  # its rank is KEPT rather than thrown away once read — `unclaimed_ranks` is what lets step 4
  # split by rank without asking `_inzsh_rank_of` again for the same candidate. `dropped` is the
  # rank-0, unclaimed set: published below as `_inzsh_rows_hidden` for `render.zsh`'s own hidden
  # bookkeeping, for the same reason — a second read here would answer a question step 2 already
  # answered.
  local -a unclaimed=() dropped=()
  local -A unclaimed_ranks=()
  local seg
  for seg in "${candidates[@]}"; do
    (( ${+claimed[$seg]} )) && continue
    _inzsh_rank_of "$seg"
    if (( REPLY == 0 )); then
      dropped+=("$seg")
      continue
    fi
    unclaimed_ranks[$seg]=$REPLY
    unclaimed+=("$seg")
  done
  typeset -ga _inzsh_rows_hidden
  _inzsh_rows_hidden=("${dropped[@]}")

  # Step 3 — width filter. Claimed and unclaimed stand together so a claim cannot outrun MINCOLS.
  local -a standing=("${(k)claimed[@]}" "${unclaimed[@]}")
  _inzsh_layout_filter "$cols" "${standing[@]}"
  local -A survives=()
  for seg in "${reply[@]}"; do
    survives[$seg]=1
  done

  # Step 4 — derive. The pairs are built from `unclaimed_ranks`, step 2's own reading, rather
  # than from `_inzsh_rank_split`, which would read every one of them again.
  local -a derive_pool=()
  for seg in "${unclaimed[@]}"; do
    (( ${+survives[$seg]} )) && derive_pool+=("$seg")
  done
  local -a derive_pairs=()
  for seg in "${derive_pool[@]}"; do
    derive_pairs+=("${unclaimed_ranks[$seg]}" "$seg")
  done
  _inzsh_rank_split_pairs "${derive_pairs[@]}"
  local -a derived_left=("${_inzsh_left[@]}") derived_right=("${_inzsh_right[@]}")

  # Step 5 — fill, and compact. Rows with nothing on either side are not drawn at all, and what
  # survives is renumbered 1.._inzsh_row_count in ascending original-row order — this is where
  # the gap in "rows 1 and 7 draw two rows, adjacent" actually collapses.
  local -i drawn=0
  local -a left_list right_list filtered
  for (( n = 1; n <= 8; n++ )); do
    if (( ${+has[${n}:left]} )); then
      left_list=(${=explicit[${n}:left]})
      filtered=()
      for seg in "${left_list[@]}"; do
        (( ${+survives[$seg]} )) && filtered+=("$seg")
      done
      left_list=("${filtered[@]}")
    elif (( n == 1 )); then
      left_list=("${derived_left[@]}")
    else
      left_list=()
    fi

    if (( ${+has[${n}:right]} )); then
      right_list=(${=explicit[${n}:right]})
      filtered=()
      for seg in "${right_list[@]}"; do
        (( ${+survives[$seg]} )) && filtered+=("$seg")
      done
      right_list=("${filtered[@]}")
    elif (( n == 1 )); then
      right_list=("${derived_right[@]}")
    else
      right_list=()
    fi

    (( ${#left_list} == 0 && ${#right_list} == 0 )) && continue

    (( drawn++ ))
    typeset -ga _inzsh_row${drawn}_left _inzsh_row${drawn}_right
    set -A _inzsh_row${drawn}_left "${left_list[@]}"
    set -A _inzsh_row${drawn}_right "${right_list[@]}"
  done

  typeset -gi _inzsh_row_count=$drawn

  return 0
}
