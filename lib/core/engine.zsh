# InZsh — engine core: the rank system. One integer per segment decides both where the segment
# goes and whether it appears at all, because those are one decision and not two. A segment you
# have ordered but not enabled is a segment you have to configure twice.
#
#   INZSH_<SEGMENT>_RANK
#     > 0   left prompt, ascending — 1 sits nearest the left edge
#     < 0   right prompt, counting inward from the right edge — -1 is the rightmost
#     = 0   hidden
#
# Nothing here draws. This file answers two questions — "which side is this segment on?" and
# "in what order?" — and answers them in segment names. It loads nothing: no tokens, no colour,
# no glyphs. Parameter operations and arithmetic only, so it is safe on the render path.
#
# Ranks are SPARSE. They are a user-facing knob, and a user who wants a segment moved will type
# 10 rather than renumber the six segments in front of it. The failure this file exists to
# prevent is the obvious implementation: key an array by the rank value, then walk 1..count.
# That walk renders nothing for a lone segment at rank 10 and silently drops the gaps out of
# 1, 4, 10. Every ordering below is a sort over the ranks that were actually given; no code
# here ever treats a rank as an index or infers a count from the largest value.
#
# Config never breaks the render. Every unreadable rank — a word, a float, a stray space, a
# doubled sign, an empty assignment left in a zshrc — falls back to a default and then to 0.
# `_inzsh_rank_of` has no failing status to return, because a prompt that refuses to draw over
# a typo is worse than a prompt that quietly hides one segment.

# Default rank per segment, keyed by the uppercase segment name. Seeded empty; each segment
# registers its own default when it loads, which is how a segment ships defaulted-off — it
# registers 0 and only a user's `INZSH_<SEGMENT>_RANK` brings it out.
typeset -gA _inzsh_segment_defaults
_inzsh_segment_defaults=()

# The split, in render order. Declared here so a caller that reads them before the first split
# gets empty arrays rather than an unset-parameter error.
typeset -ga _inzsh_left
typeset -ga _inzsh_right
typeset -ga _inzsh_hidden
_inzsh_left=()
_inzsh_right=()
_inzsh_hidden=()

# The rank grammar, as a predicate: an optional single leading sign and then digits, with
# nothing else — no spaces, no decimal point, no doubled sign, not empty. Status 0 iff $1 is a
# rank. Written once and used by both the reader and the sorter so the two cannot drift.
_inzsh_rank_valid() {
  emulate -L zsh

  [[ $1 == <-> || $1 == [-+]<-> ]]
}

# Read the rank of segment $1 into REPLY. $2, if given, is the caller's default.
#
# Precedence, first readable value wins:
#   1. `INZSH_<SEGMENT>_RANK` — the user's word, uppercased from $1 so `_inzsh_rank_of dir`
#      and `_inzsh_rank_of DIR` read the same variable.
#   2. $2 — the caller's explicit ask, which outranks the registry because the caller is
#      closer to the call than the registration was.
#   3. `_inzsh_segment_defaults[<SEGMENT>]` — what the segment shipped with.
#   4. 0 — hidden. The safe landing place: an unreadable configuration loses a segment, never
#      the prompt.
#
# Unreadable at any level falls through to the next, so an invalid default is no more fatal
# than an invalid variable. REPLY is always set and the status is always 0; `+3` and `007`
# come back normalised to 3 and 7. No command substitution — this runs on the render path.
_inzsh_rank_of() {
  emulate -L zsh

  typeset -g REPLY=0

  local segment=${(U)1}
  local var=INZSH_${segment}_RANK
  local -i rank=0
  local candidate

  # The user's word. `INZSH_*_RANK` is registered as a FAMILY in `lib/core/config.zsh` — one
  # pattern, one validator, one default for every segment there will ever be — so the read goes
  # through the registry where it is loaded and the rank grammar is stated in one place. The
  # family's default is empty, which is what keeps the rest of the ladder below reachable: a
  # registry that answered 0 here would hide every segment whose knob had a typo in it, rather
  # than falling through to what the segment shipped with.
  local configured=${(P)var}
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get "$var"
    configured=$REPLY
  fi

  # The ladder, quoted so that it is always exactly three candidates long: an unset variable or
  # an unregistered default arrives as the empty string and is rejected by the grammar like any
  # other non-rank, rather than vanishing from the list. Quoting also keeps a value with a
  # space in it — ` 2` — whole, so the grammar gets to reject it; `emulate -L zsh` already
  # rules out word splitting, and this does not depend on that staying true.
  for candidate in "$configured" "$2" "${_inzsh_segment_defaults[$segment]}"; do
    if _inzsh_rank_valid "$candidate"; then
      rank=$candidate
      REPLY=$rank
      return 0
    fi
  done

  return 0
}

# Sort (rank, name) pairs ascending by rank, stably. Arguments are read in pairs — a rank then
# the name it belongs to — and the sorted NAMES come back in `reply`, zsh's usual channel for
# a function returning a list.
#
# Ascending serves both prompts, which is the whole reason the two sides share one sort:
#
#   left    1 4 10   →  1 4 10       array order is left → right, 1 nearest the left edge
#   right  -1 -3 -2  →  -3 -2 -1     array order is left → right, -1 nearest the RIGHT edge
#
# So the right prompt's render order is most-negative-first. A right prompt of A=-1, B=-2,
# C=-3 draws as `C B A`, with A hard against the right edge and each further-from-zero rank
# stepping one place inward. Counting inward from the edge is what a negative rank means, and
# ascending numeric order is that sentence already sorted.
#
# Stable by construction: the scan stops at the first element that is not strictly greater, so
# equal ranks never cross and segments that tie stay in registration order.
#
# The sort is over the ranks that were passed and nothing else. There is no count to walk and
# no largest value to trust, so gaps of any size cost nothing — 1, 4, 10 and 1, 4, 9000 are
# the same amount of work and the same answer. An unreadable rank sorts as 0 rather than
# erroring, and a trailing rank with no name is ignored.
_inzsh_rank_sort() {
  emulate -L zsh

  typeset -ga reply
  reply=()

  local -a names
  local -a ranks
  names=()
  ranks=()

  while (( $# >= 2 )); do
    if _inzsh_rank_valid "$1"; then
      ranks+=$1
    else
      ranks+=0
    fi
    names+=$2
    shift 2
  done

  # Insertion sort. n is the number of visible segments on one side of one prompt — small
  # enough that the simple, obviously-stable algorithm is also the fast one, and it needs no
  # forks, no temp files and no sort binary.
  local -i i j held_rank
  local held_name

  for (( i = 2; i <= $#names; i++ )); do
    held_rank=${ranks[i]}
    held_name=${names[i]}
    for (( j = i - 1; j >= 1 && ranks[j] > held_rank; j-- )); do
      ranks[j+1]=${ranks[j]}
      names[j+1]=${names[j]}
    done
    ranks[j+1]=$held_rank
    names[j+1]=$held_name
  done

  reply=("${names[@]}")

  return 0
}

# `_inzsh_rank_split_pairs <rank> <name> [<rank> <name> …]` — split rank/name pairs into
# `_inzsh_left`, `_inzsh_right` and `_inzsh_hidden`, each already in render order. Positive
# ranks land in `_inzsh_left`, negative in `_inzsh_right`, ascending on both sides — see
# `_inzsh_rank_sort` for what "ascending" means on the right, where it reads as counting inward
# from the edge — and 0 lands in `_inzsh_hidden`. Names come back exactly as they were passed:
# this function does no lookup of its own and no uppercasing, only the sort.
#
# THE GRAMMAR IS ENFORCED HERE TOO, not merely inherited from a caller. A rank arrives over the
# wire rather than through `_inzsh_rank_of`, so this function cannot lean on a caller to have
# already rejected an ungrammatical one — `local -i rank; rank=$1` is an ARITHMETIC assignment,
# and arithmetic truncates `1.5` to 1, reads straight through the leading space in `' 2'`, and
# DEREFERENCES a bare `abc` as a parameter name — rejecting none of them the way the grammar
# does. A rank that is not `_inzsh_rank_valid` sorts as 0, the same rule `_inzsh_rank_sort`
# already applies to what it is handed, and for the same reason: a caller that passed a rank
# through unvalidated must not quietly reopen the hole `_inzsh_rank_valid` exists to close.
#
# `_inzsh_render` is the reason this exists apart from `_inzsh_rank_split`: it reads a
# segment's rank once, to decide whether the segment is even worth building and
# width-filtering, and re-reading it here — through `_inzsh_rank_of`, a config registry lookup
# — would be a second read of a value that cannot have changed since the first one, paid again
# on every segment that survived to this point. `_inzsh_rank_split` is a thin wrapper over
# this: it reads the ranks and delegates, so the split-and-sort itself is written in exactly
# one place.
#
# `reply` is clobbered — the sorter answers there — so a caller reads it before calling this,
# not after. Called with no pairs, this leaves three empty arrays and status 0: nothing to draw
# is not an error.
_inzsh_rank_split_pairs() {
  emulate -L zsh

  typeset -ga _inzsh_left _inzsh_right _inzsh_hidden
  _inzsh_left=()
  _inzsh_right=()
  _inzsh_hidden=()

  local -a left_pairs right_pairs
  left_pairs=()
  right_pairs=()

  local -i rank
  local name

  while (( $# >= 2 )); do
    if _inzsh_rank_valid "$1"; then
      rank=$1
    else
      rank=0
    fi
    name=$2
    if (( rank > 0 )); then
      left_pairs+=("$rank" "$name")
    elif (( rank < 0 )); then
      right_pairs+=("$rank" "$name")
    else
      _inzsh_hidden+=("$name")
    fi
    shift 2
  done

  _inzsh_rank_sort "${left_pairs[@]}"
  _inzsh_left=("${reply[@]}")

  _inzsh_rank_sort "${right_pairs[@]}"
  _inzsh_right=("${reply[@]}")

  return 0
}

# `_inzsh_rank_split <segment>…` — the same split as `_inzsh_rank_split_pairs`, for a caller
# that has not read any ranks yet. See it for the shape of the answer and the grammar both are
# held to; this wrapper only adds the READ. Segment names come back exactly as they were
# passed — only the variable lookup uppercases, through `_inzsh_rank_of`, so
# `_inzsh_rank_split dir` and `_inzsh_rank_split DIR` read the same `INZSH_DIR_RANK` and both
# hand `_inzsh_rank_split_pairs` the name spelled the way it arrived.
#
# A caller that has already read the ranks — `_inzsh_render` — calls `_inzsh_rank_split_pairs`
# directly instead and skips this file's second read of the registry.
#
# `reply` is clobbered — the sorter answers there — so read it before splitting, not after.
_inzsh_rank_split() {
  emulate -L zsh

  local segment
  local -a pairs
  pairs=()

  for segment in "$@"; do
    _inzsh_rank_of "$segment"
    pairs+=("$REPLY" "$segment")
  done

  _inzsh_rank_split_pairs "${pairs[@]}"

  return 0
}
