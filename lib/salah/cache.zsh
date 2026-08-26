# InZsh — the prayer-time day cache. The layer that stands between arithmetic that costs
# milliseconds and a render path that may not spend them.
#
# `lib/salah/calc.zsh` answers "where is the sun" in about two and a half milliseconds for a
# whole day of six prayers. That is fast for trigonometry in a shell and far too slow to pay on
# every prompt: the house budget is thirty milliseconds for the WHOLE render, and a segment that
# spent a tenth of it re-deriving an answer that cannot have changed since breakfast would be
# spending it on nothing. So the answer is computed once and written down, and the segment reads
# a table.
#
# Four ideas, in the order they matter.
#
#   THE KEY IS THE WHOLE DESIGN.  A cached prayer table is only valid for one day, at one place,
#   under one clock and one set of calculation parameters. Every one of those four can change
#   while a shell is running — midnight, a flight, a daylight-saving transition, a method changed
#   at the prompt — and every one of them makes the stored answer WRONG rather than stale. So all
#   four are in the key, the key is compared before the table is used, and a mismatch recomputes.
#   A laptop that travels does not show yesterday's city.
#
#   THE TABLE SPANS TWO DAYS.  After isha the next prayer is TOMORROW'S fajr, which is not in
#   today's table. An implementation that cached "today" would go blank — or worse, wrap round to
#   this morning's fajr and report a time that has already passed — for the several hours a day
#   when someone is most likely to be looking. So an entry holds twelve moments: the six of the
#   day the instant falls in, and the six of the day after it. The rollover is then not an event
#   anything has to handle; it is a lookup that happens to land in the second half of the table.
#
#   THE WRITE IS ATOMIC.  Several shells wake up on the same morning and all of them find the
#   entry missing. Each computes, each writes a uniquely named temporary beside the target, and
#   each renames it over. Rename within a directory is atomic, so a reader sees the whole of one
#   version or the whole of another and never half of either. The last writer wins and every
#   writer computed the same twelve numbers, so "wins" costs nothing.
#
#   NOTHING HERE MAY FAIL LOUDLY.  A cache directory that cannot be created, an entry truncated
#   by a full filesystem, a file somebody opened in an editor — each is a MISS, which recomputes,
#   which is slower and still correct. With no directory at all the table is held in memory for
#   the life of the shell, so the segment still draws; it just pays the two milliseconds once per
#   shell per day instead of once per day.
#
# ---------------------------------------------------------------------------------------------
# THE CLOCK IS AN ARGUMENT, exactly as it is in `lib/salah/calc.zsh` and for exactly that reason:
# a fixture pins the instant and asks what the cache does, and no example in the suite can be
# affected by what the sun is doing while it runs. `EPOCHSECONDS` appears once, as a default for
# a caller that did not care.
#
# WHERE THIS SITS. `lib/salah/` imports nothing from the engine. This file keeps that line: it
# reads its one knob as a plain variable rather than through `lib/core/config.zsh`, and it
# declares that knob in a table the registry absorbs by name. Nothing below calls anything
# outside `lib/salah/`.
#
# WHY THE FILE OPERATIONS ARE COPIED FROM `lib/segments/git-async.zsh`. There is no shared cache
# layer in the tree, and `CONVENTIONS.md` lists one under `lib/salah/` that has not been built.
# The atomic write is the ordinary one and it is written here as well as there. When a core cache
# layer lands, this section and its opposite number in the git worker are what move into it.

zmodload -i zsh/datetime

# `zsh/files` supplies `mkdir`, `mv` and `rm` as BUILTINS, under their own `zf_` names. Loaded
# under those names and never under the bare ones: `zmodload -F zsh/files b:rm` would replace the
# user's `rm` with a reduced implementation for the rest of the session, and a theme that draws a
# prompt has no business changing what `rm` means. Where the module is missing the three fall
# back to the external commands — a fork we would rather not make, and much better than a cache
# that cannot be written.
typeset -gi _inzsh_salah_zf=0
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm 2>/dev/null && _inzsh_salah_zf=1

_inzsh_salah_mkdir() {
  emulate -L zsh
  (( _inzsh_salah_zf )) && { zf_mkdir "$@" 2>/dev/null; return $? }
  command mkdir "$@" 2>/dev/null
}

_inzsh_salah_mv() {
  emulate -L zsh
  (( _inzsh_salah_zf )) && { zf_mv "$@" 2>/dev/null; return $? }
  command mv "$@" 2>/dev/null
}

_inzsh_salah_rm() {
  emulate -L zsh
  (( _inzsh_salah_zf )) && { zf_rm "$@" 2>/dev/null; return $? }
  command rm "$@" 2>/dev/null
}

# The entry format version. An entry written by a future format is a MISS rather than a parse
# attempt: a cache that guesses at a layout it does not know is a cache that reports a wrong time
# rather than no time.
typeset -g _inzsh_salah_cache_version=1

# How far ahead of the recorded day an entry is allowed to speak for, in seconds. Two days and a
# little, which is the twelve moments plus the slack a zone change can move them by. It is read
# by nothing here — the segment applies its own horizon to what it draws — and exists so that the
# span the entry covers is written down once, beside the code that fills it.
typeset -gi _inzsh_salah_cache_span=180000

# --------------------------------------------------------------------------------------------
# The declaration table
#
# One knob, declared the way `lib/salah/methods.zsh` declares its seven: as DATA, in an array the
# registry finds by name, because this file may not call the registry. Sourced on its own it is
# an array nothing reads.
typeset -ga _inzsh_salah_cache_knobs
_inzsh_salah_cache_knobs=(
  INZSH_SALAH_CACHE_DIR  any  ''
)

# --------------------------------------------------------------------------------------------
# The table itself
#
# Twelve moments and two pieces of provenance, in one association. Declared with `typeset -gA`
# over whatever is there, so re-sourcing never empties a table a running shell already filled.
#
#   fajr … isha            the six moments of the day the instant fell in, as UTC epoch seconds
#                          rounded to the minute, or the sentinel from `lib/salah/calc.zsh`
#   next_fajr … next_isha  the same six for the day after it
#   key                    the key the table was computed for, compared before it is used
#   day                    the civil date it describes, for a human reading the file
#
# EPOCHS ARE ROUNDED TO THE MINUTE HERE, once, on the way in. Prayer times are published to the
# minute and every consumer rounds anyway; rounding at the source means the clock a reader sees
# and the countdown they see are derived from the SAME number, so a prayer never reads as "19:59,
# in 25m" because one half rounded and the other truncated.
typeset -gA _inzsh_salah_table

# The pieces of the key, filled by `_inzsh_salah_cache_keys` and read by its caller. Three rather
# than one because the file NAME is built from the stable part and the ENTRY is checked against
# the whole: a location and a method make a file, and a day makes a version of it. That is what
# keeps the cache directory from growing by one file per day, forever, while still refusing an
# entry that is about the wrong day.
typeset -g _inzsh_salah_key=
typeset -g _inzsh_salah_seed=
typeset -g _inzsh_salah_day=

# --------------------------------------------------------------------------------------------
# Where the entries live

# The cache directory, in REPLY, created if it is not there. Status 1 when it cannot be made — a
# read-only home, a `$HOME` that is not set, a path that is a file — and every caller reads that
# as "no cache", which degrades to computing once per shell rather than to an error.
#
# The knob is read as a plain variable. `lib/core/config.zsh` validates it as `any`, which accepts
# every non-empty value, so reading the variable directly gives the same answer the registry
# would and costs this file no dependency on the engine.
_inzsh_salah_cache_dir() {
  emulate -L zsh

  typeset -g REPLY=

  local dir=${INZSH_SALAH_CACHE_DIR-}
  if [[ -z $dir ]]; then
    local base=${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}
    [[ -n $base ]] || return 1
    dir=$base/inzsh/salah
  fi

  [[ -d $dir ]] || _inzsh_salah_mkdir -p -- "$dir" || return 1

  typeset -g REPLY=$dir

  return 0
}

# A filesystem-safe name for the key material `$1`, in REPLY: FNV-1a, 32 bits, eight lower-case
# hex digits. A hash rather than an encoding, for the reason the git worker gives: an encoded key
# would carry a longitude, a method and a zone into a filename and exceed `NAME_MAX` on nothing
# very unusual. The collision a hash admits is caught on read by the key stored inside the entry.
#
# The character code is taken through a NAMED parameter — `#c`, never `##${…}`. The literal form
# takes the character that follows it in the SOURCE, so a key with a space in it would be an
# arithmetic syntax error rather than a hash.
_inzsh_salah_cache_key() {
  emulate -L zsh

  typeset -g REPLY=

  local s=$1 c
  local -i h=2166136261 i n=${#s}
  for (( i = 1; i <= n; i++ )); do
    c=${s[i]}
    (( h = ((h ^ #c) * 16777619) & 0xFFFFFFFF ))
  done

  printf -v REPLY '%08x' $h

  return 0
}

# The entry path for seed `$1`, in REPLY. Status 1 when there is no cache directory.
_inzsh_salah_cache_path() {
  emulate -L zsh

  typeset -g REPLY=

  [[ -n $1 ]] || return 1

  _inzsh_salah_cache_dir || return 1
  local base=$REPLY

  _inzsh_salah_cache_key "$1"
  typeset -g REPLY=$base/$REPLY

  return 0
}

# --------------------------------------------------------------------------------------------
# The key
#
# Everything that can make a stored table wrong, in one string. Read it as a sentence: on this
# date, at this place, under this clock, computed this way.

# The calculation parameters and the display offsets, as one word, in REPLY. Asked of
# `lib/salah/methods.zsh` rather than rebuilt, so a knob added there lands in the key for free —
# and a knob added there that did NOT land in the key would be a knob that silently kept showing
# the previous method's times until midnight.
#
# The offsets have to be here as well as the parameters: `_inzsh_salah_times` applies them to the
# answer, so they are baked into the numbers this file stores.
_inzsh_salah_recipe() {
  emulate -L zsh

  typeset -g REPLY=

  (( ${+functions[_inzsh_salah_params]} )) || return 1
  _inzsh_salah_params || return 1
  local params=$REPLY

  local name
  local -a nudges=()
  if (( ${+functions[_inzsh_salah_offset_of]} )); then
    for name in ${_inzsh_salah_offset_prayers[@]}; do
      _inzsh_salah_offset_of "$name"
      (( REPLY )) && nudges+="$name:$REPLY"
    done
  fi

  typeset -g REPLY="$params${nudges:+ ${nudges[*]}}"

  return 0
}

# `_inzsh_salah_cache_keys <epoch> <lat> <lon>` → `_inzsh_salah_key`, `_inzsh_salah_seed` and
# `_inzsh_salah_day`. Status 1 when the instant cannot be placed on a calendar.
#
# THE ZONE IS IN THE KEY AS AN OFFSET AND NOT AS A NAME. `$TZ` is frequently unset, and then the
# zone comes from a system file that a travelling laptop rewrites without telling anyone — so a
# key built from `$TZ` would not change when the machine moved, which is precisely the case the
# key exists for. `%z` is what the C library actually resolved for this instant: it moves when
# the machine moves, and it moves at a daylight-saving transition, which shifts the day boundary
# and therefore the table. Both are recomputes, and both are correct.
_inzsh_salah_cache_keys() {
  emulate -L zsh

  typeset -g _inzsh_salah_key=
  typeset -g _inzsh_salah_seed=
  typeset -g _inzsh_salah_day=

  local epoch=$1 lat=$2 lon=$3
  [[ $epoch == (|-)<-> ]] || return 1
  [[ -n $lat && -n $lon ]] || return 1

  (( ${+functions[_inzsh_salah_civil_date]} )) || return 1
  _inzsh_salah_civil_date "$epoch" '' || return 1
  local -a date=(${=REPLY})
  (( ${#date} == 3 )) || return 1

  local offset=
  strftime -s offset '%z' $epoch 2>/dev/null || return 1

  _inzsh_salah_recipe || return 1
  local recipe=$REPLY

  typeset -g _inzsh_salah_day="${date[1]}-${date[2]}-${date[3]}"
  typeset -g _inzsh_salah_seed="$lat|$lon|$offset|$recipe"
  typeset -g _inzsh_salah_key="$_inzsh_salah_day|$_inzsh_salah_seed"

  return 0
}

# --------------------------------------------------------------------------------------------
# Reading and writing an entry

# The twelve slot names, in `reply`. Derived from `lib/salah/calc.zsh`'s own prayer list rather
# than transcribed, so a prayer added there is cached without this file moving. Status 1 when
# that list is not loaded, which is the honest answer: there is nothing to cache.
#
# The list is copied UNQUOTED first, and that is not a style choice. `"${array[@]}"` of a
# parameter that does not exist at all yields ONE EMPTY WORD in zsh, so a quoted loop over an
# unloaded prayer list would run once, for a prayer with no name, and produce a two-slot table
# nobody could read. Unquoted, an absent parameter yields nothing and the count below can say so.
_inzsh_salah_slots() {
  emulate -L zsh

  typeset -ga reply
  reply=()

  local -a names=(${_inzsh_salah_prayers[@]})
  (( ${#names} )) || return 1

  local name
  for name in "${names[@]}"; do
    reply+=("$name" "next_$name")
  done

  return 0
}

# `_inzsh_salah_cache_parse <entry-path>` — the raw tab fields of an entry, validated for SHAPE,
# into `_inzsh_salah_cache_raw`. Shared by the two things that read an entry off disk for two
# different questions: `_inzsh_salah_cache_read` below, which also insists the entry is for the
# key it was asked about, and `_inzsh_salah_cache_health`, which asks a question a strict
# pass/fail cannot answer — not "is this usable" but "usable under what recipe, for what day".
# One parse, two callers, so the read loop, the key filter, the version check and the slot
# validation each exist once.
#
# EVERY FIELD IS VALIDATED, and this is the whole of the corrupt-cache story. The file outlives
# the shell that wrote it, a full filesystem can truncate it mid-write, and a user can open it in
# an editor. So the version must be the one this file writes and every one of the twelve moments
# must be an epoch or the sentinel — a slot that is missing, empty or anything else fails the
# whole entry rather than defaulting to a number.
#
# Status 1 leaves `_inzsh_salah_cache_raw` EMPTY and REPLY carrying the reason, for a caller that
# wants to say more than "no": `open` — the file cannot be opened or read; `future` — the format
# VERSION is a number, just not this one, which in a project that has only ever shipped version 1
# means a later InZsh wrote it; `corrupt` — anything else: no version line at all, a truncated
# write, a hand-edited slot. REPLY is empty on success.
_inzsh_salah_cache_parse() {
  emulate -L zsh
  setopt extended_glob

  typeset -gA _inzsh_salah_cache_raw
  _inzsh_salah_cache_raw=()
  typeset -g REPLY=

  local file=$1
  if [[ -z $file || ! -f $file || ! -r $file ]]; then
    typeset -g REPLY=open
    return 1
  fi

  local -A raw
  local line k v
  while IFS= read -r line; do
    [[ $line == *$'\t'* ]] || continue
    k=${line%%$'\t'*}
    v=${line#*$'\t'}
    [[ $k == [a-z][a-z0-9_]# ]] || continue
    raw[$k]=$v
  done < "$file" 2>/dev/null

  local version=${raw[version]-}
  if [[ $version != $_inzsh_salah_cache_version ]]; then
    # `<2->` and not `<->`: this file has shipped exactly one format, version 1, so a NUMBER that
    # is not 1 is only honestly "future" starting at 2. `<->` would have called `0` and a
    # leading-zero `01` future too — neither is a version anything has ever written, both are as
    # corrupt as a version field with no digits in it at all.
    if [[ $version == <2-> ]]; then
      typeset -g REPLY=future
    else
      typeset -g REPLY=corrupt
    fi
    return 1
  fi

  _inzsh_salah_slots || { typeset -g REPLY=corrupt; return 1 }
  local -a slots=("${reply[@]}")

  local absent=${_inzsh_salah_absent:-none}
  local slot value
  for slot in "${slots[@]}"; do
    value=${raw[$slot]-}
    [[ $value == (|-)<-> || $value == $absent ]] || { typeset -g REPLY=corrupt; return 1 }
  done

  _inzsh_salah_cache_raw=("${(@kv)raw}")

  return 0
}

# `_inzsh_salah_cache_read <key> <entry-path>` — the entry into `_inzsh_salah_table`.
#
# The key check is the second half of the corrupt-cache story `_inzsh_salah_cache_parse` starts:
# a shape that parses cleanly can still be the wrong day, the wrong place or the wrong method, so
# the exact key being asked about is compared before anything is trusted.
#
# A miss leaves the table EMPTY and returns 1, which the segment already reads as "nothing to
# draw". Never an error, never a partial table, and never a diagnostic: a prompt is not a place to
# report that a cache file was odd.
#
# REPLY IS THE CALLER'S, NOT THIS FUNCTION'S, AND IT IS RESTORED ON EVERY PATH OUT. Before the
# parse split this never touched REPLY at all; `_inzsh_salah_cache_parse` answers in it, so
# borrowing that answer without giving REPLY back would be a silent contract change on a function
# the render path calls. `_inzsh_salah_cache_raw`, likewise, is `_inzsh_salah_cache_parse`'s
# workspace and not somewhere this function's coordinates belong once they are copied into
# `_inzsh_salah_table` — cleared here for the same reason `_inzsh_salah_table` itself is emptied
# at the top on a miss, not because holding it longer would leak anything new, but because a file
# under COORDINATES NEVER LEAVE should not grow a fourth place they sit without a reason to.
_inzsh_salah_cache_read() {
  emulate -L zsh

  typeset -gA _inzsh_salah_table
  _inzsh_salah_table=()

  local saved_reply=$REPLY

  local key=$1 file=$2
  if [[ -z $key || -z $file ]]; then
    typeset -g REPLY=$saved_reply
    return 1
  fi

  if ! _inzsh_salah_cache_parse "$file"; then
    typeset -g REPLY=$saved_reply
    return 1
  fi
  if [[ ${_inzsh_salah_cache_raw[key]-} != $key ]]; then
    typeset -gA _inzsh_salah_cache_raw
    _inzsh_salah_cache_raw=()
    typeset -g REPLY=$saved_reply
    return 1
  fi

  if ! _inzsh_salah_slots; then
    typeset -gA _inzsh_salah_cache_raw
    _inzsh_salah_cache_raw=()
    typeset -g REPLY=$saved_reply
    return 1
  fi
  local -a slots=("${reply[@]}")

  local -A table
  local slot
  for slot in "${slots[@]}"; do
    table[$slot]=${_inzsh_salah_cache_raw[$slot]-}
  done
  table[key]=$key
  table[day]=${_inzsh_salah_cache_raw[day]-}

  _inzsh_salah_table=("${(@kv)table}")

  typeset -gA _inzsh_salah_cache_raw
  _inzsh_salah_cache_raw=()
  typeset -g REPLY=$saved_reply

  return 0
}

# `_inzsh_salah_cache_write <entry-path>` — `_inzsh_salah_table`, atomically.
#
# The temporary carries the shell's pid and a random suffix, so two shells computing the same
# morning cannot pick the same name, and it is created BESIDE the target so the rename stays
# within one filesystem and is therefore a rename. A failed write removes its own temporary: a
# cache directory that fills with half-written entries is worse than one that is empty.
#
# TWO NESTED BLOCKS, and the outer one is the point. A redirection that cannot be OPENED — the
# cache directory removed between the `mkdir` and here — is reported by the shell BEFORE the
# redirection takes effect, so `{ … } > "$tmp" 2>/dev/null` still writes the diagnostic to
# wherever stderr was pointing. The outer block silences the inner block's own failure.
_inzsh_salah_cache_write() {
  emulate -L zsh

  local file=$1
  [[ -n $file ]] || return 1
  (( ${#_inzsh_salah_table} )) || return 1

  _inzsh_salah_slots || return 1
  local -a slots=("${reply[@]}")

  local tmp=$file.$$.$RANDOM.tmp
  local tab=$'\t'

  {
    {
      print -r -- "version$tab$_inzsh_salah_cache_version"
      print -r -- "key$tab${_inzsh_salah_table[key]-}"
      print -r -- "day$tab${_inzsh_salah_table[day]-}"
      local slot
      for slot in "${slots[@]}"; do
        print -r -- "$slot$tab${_inzsh_salah_table[$slot]-}"
      done
    } > "$tmp"
  } 2>/dev/null || {
    _inzsh_salah_rm -f -- "$tmp"
    return 1
  }

  _inzsh_salah_mv -f -- "$tmp" "$file" || {
    _inzsh_salah_rm -f -- "$tmp"
    return 1
  }

  return 0
}

# --------------------------------------------------------------------------------------------
# Computing one

# `_inzsh_salah_compute_table <epoch> <lat> <lon>` → the twelve moments in `_inzsh_salah_table`.
#
# TWO CALLS, AND THE SECOND ONE IS SEEDED FROM THE FIRST. Reaching tomorrow by adding 86400 to
# `now` is wrong twice a year: an instant late on the evening before a spring-forward lands on the
# day after TOMORROW, and the day this table is supposed to hold is skipped entirely. Solar noon
# is the seed instead — `dhuhr` is defined everywhere on Earth every day, it sits in the middle of
# its own civil day by construction, and a day later it is still comfortably inside the next one
# whatever the clocks did overnight.
#
# Status 1 when the location is unusable, and the table is left empty. A caller that ignored the
# status has an empty table, which every reader already treats as nothing to draw.
_inzsh_salah_compute_table() {
  emulate -L zsh

  typeset -gA _inzsh_salah_table
  _inzsh_salah_table=()

  local epoch=$1 lat=$2 lon=$3
  (( ${+functions[_inzsh_salah_times]} )) || return 1

  _inzsh_salah_slots || return 1

  local -A table
  local name value

  _inzsh_salah_times "$epoch" "$lat" "$lon" '' || return 1
  for name in "${_inzsh_salah_prayers[@]}"; do
    value=${_inzsh_salah_reply[$name]}
    [[ $value == (|-)<-> ]] && { _inzsh_salah_round_minute "$value" && value=$REPLY }
    table[$name]=$value
  done

  # Solar noon is the only moment guaranteed to exist, which is why it and not a prayer is the
  # bridge to tomorrow. Where even it is absent the location was not usable in the first place.
  local noon=${table[dhuhr]-}
  [[ $noon == (|-)<-> ]] || return 1

  _inzsh_salah_times $(( noon + 86400 )) "$lat" "$lon" '' || return 1
  for name in "${_inzsh_salah_prayers[@]}"; do
    value=${_inzsh_salah_reply[$name]}
    [[ $value == (|-)<-> ]] && { _inzsh_salah_round_minute "$value" && value=$REPLY }
    table[next_$name]=$value
  done

  _inzsh_salah_table=("${(@kv)table}")

  return 0
}

# --------------------------------------------------------------------------------------------
# The entry point
#
# `_inzsh_salah_cache_refresh [epoch]` — make `_inzsh_salah_table` describe this instant.
#
# THIS IS NOT ON THE RENDER PATH AND MUST NEVER BE PUT ON IT. `lib/segments/salah.zsh` calls it
# from a precmd hook of its own, beside the render rather than inside it, exactly as the git
# worker's hook sits beside `_inzsh_render`. The segment's build function reads the table and
# nothing else — no file, no arithmetic, no fork — which is the property that keeps a prayer time
# free at draw time.
#
# Four outcomes, cheapest first:
#
#   the key is unchanged   nothing happens at all. This is every prompt but a handful a day, and
#                          it costs one `strftime`, one read of the method knobs, and a compare.
#   the entry is on disk   one small file read, every field validated.
#   neither                two computations, about five milliseconds, and an atomic write.
#   no location            the table is EMPTIED. A location that has gone away must not leave
#                          yesterday's city on the prompt.
#
# Always leaves the table either correct or empty, and never leaves it stale.
_inzsh_salah_cache_refresh() {
  emulate -L zsh

  typeset -gA _inzsh_salah_table

  local now=${1:-${EPOCHSECONDS-}}
  [[ $now == (|-)<-> ]] || return 1

  if (( ! ${+functions[_inzsh_salah_location]} )); then
    _inzsh_salah_table=()
    return 1
  fi

  if ! _inzsh_salah_location "$now"; then
    _inzsh_salah_table=()
    return 1
  fi
  local -a where=(${=REPLY})
  (( ${#where} == 2 )) || { _inzsh_salah_table=(); return 1 }

  if ! _inzsh_salah_cache_keys "$now" "${where[1]}" "${where[2]}"; then
    _inzsh_salah_table=()
    return 1
  fi
  local key=$_inzsh_salah_key day=$_inzsh_salah_day seed=$_inzsh_salah_seed

  # The warm path. Held in memory rather than re-read, because the entry cannot have changed
  # since this shell wrote or read it under this key — the key is what changing would change.
  [[ ${_inzsh_salah_table[key]-} == $key ]] && return 0

  local file=
  _inzsh_salah_cache_path "$seed" && file=$REPLY

  [[ -n $file ]] && _inzsh_salah_cache_read "$key" "$file" && return 0

  if ! _inzsh_salah_compute_table "$now" "${where[1]}" "${where[2]}"; then
    _inzsh_salah_table=()
    return 1
  fi

  _inzsh_salah_table[key]=$key
  _inzsh_salah_table[day]=$day

  # A write that fails costs nothing but the next shell's two milliseconds. The table in memory
  # is already correct, so the status is deliberately not propagated.
  [[ -n $file ]] && _inzsh_salah_cache_write "$file"

  return 0
}

# --------------------------------------------------------------------------------------------
# Diagnostics
#
# `_inzsh_salah_cache_dir_probe` — the cache directory in REPLY, resolved the same way
# `_inzsh_salah_cache_dir` resolves it, but NEVER CREATED. Status 1 when it cannot be resolved
# (no override, no `$HOME`) or does not already exist as a directory this process can look
# inside — missing, a stray file where the directory should be, or one neither readable nor
# searchable. `-r` and never `-w`: an unwritable directory a reader can still list is not this
# function's business, only a directory it cannot see into is.
#
# The read-only sibling of `_inzsh_salah_cache_dir`, for `_inzsh_salah_cache_health` below, which
# only ever LOOKS. `inzsh doctor` had zero filesystem side effects before that function existed,
# and it still must have none — an earlier version of it called `_inzsh_salah_cache_path`, which
# calls `_inzsh_salah_cache_dir`, which `mkdir -p`s a directory that was not there. Running the
# diagnostic is not a reason to create the thing it is diagnosing the absence of.
_inzsh_salah_cache_dir_probe() {
  emulate -L zsh

  typeset -g REPLY=

  local dir=${INZSH_SALAH_CACHE_DIR-}
  if [[ -z $dir ]]; then
    local base=${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}
    [[ -n $base ]] || return 1
    dir=$base/inzsh/salah
  fi

  [[ -d $dir && -r $dir && -x $dir ]] || return 1

  typeset -g REPLY=$dir

  return 0
}

# The entry path for seed `$1`, in REPLY, exactly as `_inzsh_salah_cache_path` builds it but from
# `_inzsh_salah_cache_dir_probe` rather than `_inzsh_salah_cache_dir` — so it answers the same
# question without the side effect. Status 1 under the same conditions the probe refuses on.
_inzsh_salah_cache_path_probe() {
  emulate -L zsh

  typeset -g REPLY=

  [[ -n $1 ]] || return 1

  _inzsh_salah_cache_dir_probe || return 1
  local base=$REPLY

  _inzsh_salah_cache_key "$1"
  typeset -g REPLY=$base/$REPLY

  return 0
}

# `_inzsh_salah_cache_health [epoch]` — issue #229. `inzsh doctor` reports where the POSITION
# came from; it says nothing about the TABLE computed from it, and a blank prayer segment gives
# a reader nothing to act on beyond that. This answers what the issue asked for: whether a table
# is cached, whether it is readable, and how stale — deliberately not "for which recipe key", the
# fourth question the issue also asked, because that turned out to be unanswerable without a
# second problem. See NO DIGEST below.
#
# READ-ONLY, ON PURPOSE. `_inzsh_salah_cache_refresh` above is the function that may compute and
# write — it is what the segment's own hook calls, and calling it from a diagnostic would make
# running `inzsh doctor` have a side effect nobody asked for, exactly the reason `inzsh doctor`
# calls `_inzsh_salah_location` rather than `_inzsh_salah_locate_refresh` for the position. This
# never touches `_inzsh_salah_table`, never computes a table, never writes a file, and never
# creates the cache directory — `_inzsh_salah_cache_dir_probe` above is what makes that last part
# true, and is the whole reason it exists.
#
# NO DIGEST. An earlier version of this hashed the recipe — position, offset and method together
# — with the same one-way hash `_inzsh_salah_cache_path` uses for a filename, on the theory that a
# hash a human cannot read back is not a coordinate. It is wrong twice over. First, the coordinate
# space at any precision a person actually types is smaller than the 32-bit hash space, so the
# hash is a slow but complete ENCODING of the position rather than a redaction of it — a two-
# minute brute force recovers it globally, twenty seconds inside one degree once a reader has
# narrowed the city, which the same doctor block helps with by printing `locale`. Second, it is
# STABLE: two doctor blocks pasted into two issues months apart with the same eight characters
# prove the same reporter at the same place, which `location: config` never does, because that
# reads identically for everyone who configured a position at all. Existence on the filesystem is
# not publication; a public issue tracker is. What `lib/salah/methods.zsh` already has words for —
# a method name, an Asr school — IS the recipe a reader can act on, and neither is derived from
# where anyone is standing, so `inzsh doctor` prints them the way it prints `TERM` or the locale.
#
# REPLY is one word, cheapest fact first:
#
#   none         no position is resolved, so there is no recipe to look for. Not an error — the
#                segment has nothing to draw either, and this says why.
#   nodir        the cache directory cannot be found or looked inside — missing, a stray file
#                where it should be, or one this process cannot read or search. Whatever is or is
#                not inside it, the segment recomputes every shell it does not learn otherwise.
#   missing      the directory is fine and nothing has ever been written under today's recipe.
#   denied       an entry sits at that path and this process cannot read it — a permissions
#                problem, not a format one.
#   future       an entry sits at that path with a format VERSION that is not this file's own —
#                in a project that has only ever shipped version 1, the honest reading is that a
#                newer InZsh wrote it, and this one should not guess at what else changed.
#   unreadable   an entry sits at that path and cannot be trusted for any other reason: garbage,
#                a truncated write, a hand-edited slot, or a key naming a seed this path's hash
#                could not have produced. That last case is a 32-bit collision or a hand edit —
#                either way not an entry this recipe wrote — and gets the same word as one that
#                does not parse at all, rather than a word implying a cause nobody could act on.
#   stale        the entry parses cleanly and was computed under the SAME recipe, for a day that
#                is not today's — the ordinary case of a shell that has not opened since.
#   current      the entry matches today and matches the recipe in force. This is what the
#                segment itself would read right now, with nothing left to compute.
#
# Always returns 0. A diagnostic that could fail is a diagnostic nobody could run in the broken
# environment it exists to describe, and every branch below ends on an honest word instead.
_inzsh_salah_cache_health() {
  emulate -L zsh
  setopt extended_glob

  # No default of its own: `_inzsh_salah_cache_refresh` above is the one place this file reads
  # `EPOCHSECONDS`, and a second place would be a second clock a fixture could not pin. The one
  # caller this has — `inzsh doctor` — already reads it once and passes the same reading here.
  local now=$1

  # `REPLY` IS SET LAST ON EVERY PATH BELOW, NEVER FIRST. `_inzsh_salah_location`,
  # `_inzsh_salah_cache_path_probe` and `_inzsh_salah_cache_parse` all answer in REPLY
  # themselves, so setting this function's own word before calling any of them only means the
  # call throws the word away a moment later.
  if (( ! ${+functions[_inzsh_salah_location]} )); then
    typeset -g REPLY=none
    return 0
  fi
  if ! _inzsh_salah_location "$now"; then
    typeset -g REPLY=none
    return 0
  fi
  local -a where=(${=REPLY})
  if (( ${#where} != 2 )); then
    typeset -g REPLY=none
    return 0
  fi

  if ! _inzsh_salah_cache_keys "$now" "${where[1]}" "${where[2]}"; then
    typeset -g REPLY=none
    return 0
  fi
  local key=$_inzsh_salah_key seed=$_inzsh_salah_seed

  if ! _inzsh_salah_cache_path_probe "$seed"; then
    typeset -g REPLY=nodir
    return 0
  fi
  local file=$REPLY

  if [[ ! -e $file ]]; then
    typeset -g REPLY=missing
    return 0
  fi
  if [[ ! -f $file || ! -r $file ]]; then
    typeset -g REPLY=denied
    return 0
  fi

  if ! _inzsh_salah_cache_parse "$file"; then
    # `future` is the one reason worth keeping; anything else — an unreadable open, a garbled
    # version, a bad slot — is the same `unreadable` this function would say about a file that
    # never parsed at all.
    [[ $REPLY == future ]] || typeset -g REPLY=unreadable
    return 0
  fi

  local stored=${_inzsh_salah_cache_raw[key]-}
  # Copied out; `_inzsh_salah_cache_parse`'s workspace has nothing left to answer for once this
  # function has taken the one field it needed from it.
  typeset -gA _inzsh_salah_cache_raw
  _inzsh_salah_cache_raw=()

  if [[ -z $stored ]]; then
    typeset -g REPLY=unreadable
    return 0
  fi

  if [[ $stored == $key ]]; then
    typeset -g REPLY=current
    return 0
  fi

  # Everything after the first `|` is the seed — position, offset and recipe — and everything
  # before it is the day. Same seed, different day is the ordinary case of a shell that has not
  # opened since. A different seed at THIS path is not a different recipe's entry: the path is
  # itself a hash of the seed, so a real recipe change moves the FILE rather than leaving a
  # conflicting one behind — what is left is a collision or a hand edit, and neither is trustable
  # enough to earn a word implying a cause a reader could act on.
  if [[ ${stored#*|} == ${key#*|} ]]; then
    typeset -g REPLY=stale
  else
    typeset -g REPLY=unreadable
  fi

  return 0
}
