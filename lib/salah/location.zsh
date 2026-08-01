# InZsh — where you are. Two numbers, and the only place in this repository where anything can
# leave the machine.
#
# Prayer times are a function of an instant and a POSITION. Everything else in `lib/salah/` is
# arithmetic that runs the same on any computer; this file is the one that has to answer a
# question the computer does not know the answer to, and there are only two honest ways to get
# one. So there are exactly two, and the difference between them is the whole shape of the file.
#
#   YOU SAY WHERE YOU ARE.  `INZSH_SALAH_LAT` and `INZSH_SALAH_LON`, two decimal degrees off a
#   map. Offline, private, deterministic, and correct the moment you set it. This is the
#   documented path, it is the default, and everything below it exists only because some people
#   would rather not look their own latitude up.
#
#   YOU ASK SOMEBODY ELSE.  `INZSH_SALAH_AUTOLOCATE=1` permits ONE outbound HTTP request, to a
#   URL you can see and change, whose answer is cached and reused. It is off by default, it is
#   the only network call in the project, and every property below is about making sure it can
#   never cost you a prompt.
#
# ---------------------------------------------------------------------------------------------
# THE FOUR RULES THE NETWORK CALL LIVES UNDER
#
#   OPT IN.  `INZSH_SALAH_AUTOLOCATE` defaults to `0`. Nothing here runs — nothing here is even
#   reachable — until somebody sets it. A theme that phoned home to draw a prompt would be a
#   theme nobody should install.
#
#   NOTHING ON THE RENDER PATH CAN REACH IT.  `_inzsh_salah_locate_fetch` is called by exactly one
#   function in this repository, `_inzsh_salah_locate_refresh`, and NOTHING CALLS THAT. Not the
#   segment, not the cache, not a hook, not the entry point. It is a function you run — from your
#   own `.zshrc`, backgrounded if you like, from a timer, or by hand after you move — and a prompt
#   therefore cannot block on it, cannot be slowed by it, and cannot fail because of it. That is a
#   stronger guarantee than a timeout, because it does not depend on the timeout working.
#
#   THE ANSWER IS CACHED, AND THE LAST GOOD ONE NEVER EXPIRES.  A TTL says when a refresh is DUE,
#   not when an answer stops being usable. A laptop that has been offline for a week is still
#   almost certainly in the same city, and a prayer segment that vanished because a lookup failed
#   would be a worse answer than a week-old one. Absence is reserved for having no answer at all.
#
#   IT CANNOT INVENT A LOCATION.  No default coordinates, no "near enough" fallback, no guess from
#   `$TZ`. With nothing configured and nothing cached the segment is ABSENT, which is the truthful
#   rendering of not knowing where you are.
#
# WHAT LEAVES THE MACHINE, EXACTLY. One HTTPS GET to `INZSH_SALAH_AUTOLOCATE_URL`, made by `curl`
# or, failing that, `wget`. The request carries what any HTTP client's request carries — a method,
# a path, a Host header, the client's own user agent — and nothing this theme adds: no
# coordinates, no hostname, no username, no shell state, no identifier of any kind. The server
# learns your public IP address, which is what it is being asked to turn into a position and what
# it would learn from any request you made to it. The response is read for two numbers and the
# body is deleted. Point the URL at your own service and the answer changes accordingly.

zmodload -i zsh/datetime

# The default endpoint. A free IP-geolocation service that needs no key and answers with JSON
# holding `latitude` and `longitude`. Held in a variable so the registered default and the value
# this file falls back to when the config layer is not loaded cannot disagree.
typeset -g _inzsh_salah_autolocate_url_default='https://ipapi.co/json/'

# How long an automatic answer is considered current, in seconds. A day: shorter would spend a
# request on a machine that has not moved, and longer would leave somebody who flew yesterday
# looking at the wrong city until they noticed. It bounds a REFRESH and never a read — see the
# third rule above.
typeset -gi _inzsh_salah_autolocate_ttl_default=86400

# The hard ceiling on the request, in seconds. Five is chosen against a person waiting for a
# terminal to come back, not against a slow network: a lookup that has not answered in five
# seconds is a lookup to make again later.
typeset -gi _inzsh_salah_autolocate_timeout_default=5

# The entry format for the stored location, and the file it lives in under the cache directory.
typeset -g _inzsh_salah_location_version=1
typeset -g _inzsh_salah_location_file=location

# Where the last resolved position came from — `config`, `cache`, or empty for none. Diagnostic
# only; nothing draws it, and a `doctor` command is the reason it is written down at all.
typeset -g _inzsh_salah_location_source=

# The age of the cached position at the last read, in seconds, or -1 when it has no timestamp.
typeset -gi _inzsh_salah_location_age=-1

# --------------------------------------------------------------------------------------------
# The declaration table
#
# Six knobs, declared as DATA for the reason `lib/salah/methods.zsh` gives: this file may not call
# `lib/core/config.zsh`, so the registry finds the table by name instead. Nothing below names the
# engine.
#
# The two coordinates declare `any`, and that is not laziness. The registry's grammar has no form
# for "a real number between -90 and 90"; the nearest one it has would refuse `21.4225`, and a
# validator that is NEARLY right is worse than one that says the module decides, because it would
# make the registry disagree with the code below about what a value means. The bounds are checked
# here, against `lib/salah/calc.zsh`'s own range test, which is the same one the arithmetic uses.
typeset -ga _inzsh_salah_location_knobs
_inzsh_salah_location_knobs=(
  INZSH_SALAH_LAT                  any   ''
  INZSH_SALAH_LON                  any   ''
  INZSH_SALAH_AUTOLOCATE           bool  0
  INZSH_SALAH_AUTOLOCATE_TTL       'int:300:'  $_inzsh_salah_autolocate_ttl_default
  INZSH_SALAH_AUTOLOCATE_TIMEOUT   'int:1:60'  $_inzsh_salah_autolocate_timeout_default
  INZSH_SALAH_AUTOLOCATE_URL       any   $_inzsh_salah_autolocate_url_default
)

# --------------------------------------------------------------------------------------------
# Reading the configuration
#
# Plain variables, validated here, falling back to the values above. The same habit
# `lib/salah/methods.zsh` keeps and for the same reason: the registry's answer would be identical
# and the dependency would not be.

# Is a position usable? Both bounds, through `lib/salah/calc.zsh`'s own test, so a latitude that
# the segment accepts is exactly a latitude the arithmetic accepts. Status 1 without that file,
# which is the safe answer: an unvalidated coordinate reaching `(( ))` is a fatal error mid-hook.
_inzsh_salah_position_ok() {
  emulate -L zsh

  (( ${+functions[_inzsh_salah_in_range]} )) || return 1
  _inzsh_salah_in_range "$1" -90 90   || return 1
  _inzsh_salah_in_range "$2" -180 180 || return 1

  return 0
}

# Is the automatic lookup permitted? `bool` in the config layer's vocabulary, which is wider than
# 1 and 0 because a user writes `false` and means it. Anything unreadable is OFF: a typo may not
# switch a network call on.
_inzsh_salah_autolocate_on() {
  emulate -L zsh

  [[ ${(L)${INZSH_SALAH_AUTOLOCATE-}} == (true|yes|on|1) ]]
}

# The refresh interval in whole seconds, in REPLY.
_inzsh_salah_autolocate_ttl() {
  emulate -L zsh

  typeset -g REPLY=$_inzsh_salah_autolocate_ttl_default

  local value=${INZSH_SALAH_AUTOLOCATE_TTL-}
  [[ $value == <300-> ]] && typeset -g REPLY=$value

  return 0
}

# The request ceiling in whole seconds, in REPLY. Never zero and never negative: a timeout of 0
# would kill the request before it started.
_inzsh_salah_autolocate_timeout() {
  emulate -L zsh

  typeset -g REPLY=$_inzsh_salah_autolocate_timeout_default

  local value=${INZSH_SALAH_AUTOLOCATE_TIMEOUT-}
  [[ $value == <1-60> ]] && typeset -g REPLY=$value

  return 0
}

# The endpoint, in REPLY. Only `http://` and `https://` are accepted, and only with something
# after them: the value reaches an external command's argument list, and a knob that could name a
# `file://` path or a scheme a client invents its own meaning for is a knob that does more than it
# says. Anything else falls back to the default, silently, like every other value in this theme.
_inzsh_salah_autolocate_url() {
  emulate -L zsh

  typeset -g REPLY=$_inzsh_salah_autolocate_url_default

  local value=${INZSH_SALAH_AUTOLOCATE_URL-}
  [[ $value == (http|https)://?* ]] && typeset -g REPLY=$value

  return 0
}

# --------------------------------------------------------------------------------------------
# The stored answer

# The path of the location entry, in REPLY. Status 1 when there is no cache directory, which is
# what `lib/salah/cache.zsh` answers for a read-only home.
_inzsh_salah_location_path() {
  emulate -L zsh

  typeset -g REPLY=

  (( ${+functions[_inzsh_salah_cache_dir]} )) || return 1
  _inzsh_salah_cache_dir || return 1

  typeset -g REPLY=$REPLY/$_inzsh_salah_location_file

  return 0
}

# `_inzsh_salah_location_read [now]` — the stored position, in REPLY as `<lat> <lon>`, with its
# age in `_inzsh_salah_location_age`.
#
# Every field is validated exactly as the day cache validates its own, and for the same reasons:
# the file outlives the shell, it can be truncated, and it can be edited. A position that does not
# parse or does not lie on the globe is a MISS, not a coordinate of zero — `0 0` is a real place
# in the Gulf of Guinea and a prompt that quietly moved somebody there would be worse than one
# that drew nothing.
#
# THE AGE IS REPORTED AND NEVER ENFORCED. This function has no opinion about how old is too old;
# `_inzsh_salah_locate_refresh` is where the TTL lives, because it is the only thing that can
# usefully act on one.
_inzsh_salah_location_read() {
  emulate -L zsh
  setopt extended_glob

  typeset -g REPLY=
  typeset -gi _inzsh_salah_location_age=-1

  _inzsh_salah_location_path || return 1
  local file=$REPLY
  # `_inzsh_salah_location_path` answers in REPLY, and REPLY is this function's answer too. A
  # failure below would otherwise leave a PATH where a caller expects a position or nothing.
  typeset -g REPLY=

  [[ -f $file && -r $file ]] || return 1

  local -A raw
  local line k v
  while IFS= read -r line; do
    [[ $line == *$'\t'* ]] || continue
    k=${line%%$'\t'*}
    v=${line#*$'\t'}
    [[ $k == [a-z][a-z0-9_]# ]] || continue
    raw[$k]=$v
  done < "$file" 2>/dev/null

  [[ ${raw[version]-} == $_inzsh_salah_location_version ]] || return 1
  _inzsh_salah_position_ok "${raw[lat]-}" "${raw[lon]-}"   || return 1

  local stamp=${raw[epoch]-}
  local now=${1-}
  if [[ $stamp == <-> && $now == <-> ]]; then
    typeset -gi _inzsh_salah_location_age=$(( now - stamp ))
    (( _inzsh_salah_location_age < 0 )) && typeset -gi _inzsh_salah_location_age=0
  fi

  typeset -g REPLY="${raw[lat]} ${raw[lon]}"

  return 0
}

# `_inzsh_salah_location_write <lat> <lon> <epoch>` — the position, atomically. Same temporary,
# same rename, same reasons as `lib/salah/cache.zsh`: two shells that refresh at once write two
# different temporaries and the later rename wins, and a half-written file is never readable.
_inzsh_salah_location_write() {
  emulate -L zsh

  local lat=$1 lon=$2 stamp=$3
  _inzsh_salah_position_ok "$lat" "$lon" || return 1
  [[ $stamp == <-> ]] || return 1

  _inzsh_salah_location_path || return 1
  local file=$REPLY

  local tmp=$file.$$.$RANDOM.tmp
  local tab=$'\t'

  {
    {
      print -r -- "version$tab$_inzsh_salah_location_version"
      print -r -- "lat$tab$lat"
      print -r -- "lon$tab$lon"
      print -r -- "epoch$tab$stamp"
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
# The answer

# `_inzsh_salah_location [now]` — where we are, in REPLY as `<lat> <lon>`, with the provenance in
# `_inzsh_salah_location_source`. Status 1 and an empty REPLY when nobody knows.
#
# Precedence is one sentence: what you configured, then what was looked up, then nothing. The
# configured pair wins even when it is stale by a continent, because it is a STATEMENT and the
# other is an inference — and it wins even while `INZSH_SALAH_AUTOLOCATE` is on, so turning the
# lookup on and then setting the coordinates by hand does the obvious thing.
#
# Reads no file and starts no process on the configured path, which is the path everybody is on:
# two variables, two range checks, done. The cached path costs one small file read, and only where
# the lookup was switched on.
_inzsh_salah_location() {
  emulate -L zsh

  typeset -g REPLY=
  typeset -g _inzsh_salah_location_source=

  local lat=${INZSH_SALAH_LAT-} lon=${INZSH_SALAH_LON-}
  if _inzsh_salah_position_ok "$lat" "$lon"; then
    typeset -g REPLY="$lat $lon"
    typeset -g _inzsh_salah_location_source=config
    return 0
  fi

  _inzsh_salah_autolocate_on || return 1
  _inzsh_salah_location_read "${1-}" || return 1

  typeset -g _inzsh_salah_location_source=cache

  return 0
}

# --------------------------------------------------------------------------------------------
# The lookup
#
# Everything below forks, reaches the network and may take seconds. NOTHING IN THIS REPOSITORY
# CALLS IT. See the second rule at the top of the file — that is what makes the timeout a
# belt-and-braces measure rather than the thing standing between a slow DNS server and your
# prompt.

# The two numbers out of `$1`, a body of JSON, into REPLY as `<lat> <lon>`. Status 1 when either
# is missing or is not a position.
#
# Read with `read`, matched with a pattern, and parsed nowhere: this is not a JSON parser and does
# not pretend to be one. It looks for a `latitude`/`longitude` pair, or the `lat`/`lon` spelling
# the other common services use, and takes the number after the colon. A body that says something
# else — an error page, an HTML redirect, a rate-limit notice — matches nothing and is a failure,
# which is exactly the treatment it deserves.
_inzsh_salah_locate_parse() {
  emulate -L zsh
  setopt local_options extended_glob

  typeset -g REPLY=

  local file=$1
  [[ -f $file && -r $file ]] || return 1

  local body= chunk
  while IFS= read -r chunk || [[ -n $chunk ]]; do
    body+="$chunk "
  done < "$file" 2>/dev/null
  [[ -n $body ]] || return 1

  # THE TAIL AFTER THE NUMBER IS NOT DECORATION. A leading `*` in a zsh pattern is greedy and the
  # capture that follows it takes the SHORTEST match that still lets the rest of the pattern
  # succeed — so `(number)*` reads `21.4225` as `21`, which is a different continent. Requiring
  # the character after the number to be one a number cannot continue with forces the whole of it
  # into the capture. The empty alternative is for a body that ends on the number itself.
  local number='(|-|+)(<->(|.<->)|.<->)'
  local lat= lon= name

  for name in latitude lat; do
    [[ -n $lat ]] && break
    [[ $body == (#b)*'"'$name'"'[[:space:]]#:[[:space:]]#(${~number})([^0-9.]*|) ]] &&
      lat=$match[1]
  done
  for name in longitude lon; do
    [[ -n $lon ]] && break
    [[ $body == (#b)*'"'$name'"'[[:space:]]#:[[:space:]]#(${~number})([^0-9.]*|) ]] &&
      lon=$match[1]
  done

  _inzsh_salah_position_ok "$lat" "$lon" || return 1

  typeset -g REPLY="$lat $lon"

  return 0
}

# `_inzsh_salah_locate_fetch [now]` — one request, and the answer written down.
#
# `curl` first, `wget` second, nothing third. Both are given a hard ceiling and told to be quiet;
# `curl -f` refuses to write an error page to the body file, and `wget --tries=1` stops it
# retrying its way past the timeout. Where neither exists this returns 1, silently, which the
# caller reads as "the lookup did not happen" — the same outcome as a network that is down.
#
# The body goes to a uniquely named temporary in the cache directory and is removed however this
# ends. A downloaded file left behind in a cache directory is a downloaded file somebody finds a
# year later and wonders about.
_inzsh_salah_locate_fetch() {
  emulate -L zsh

  _inzsh_salah_autolocate_on || return 1

  _inzsh_salah_location_path || return 1
  local target=$REPLY

  _inzsh_salah_autolocate_url
  local url=$REPLY
  _inzsh_salah_autolocate_timeout
  local -i seconds=$REPLY

  local now=${1:-${EPOCHSECONDS-}}
  [[ $now == <-> ]] || return 1

  local body=$target.$$.$RANDOM.raw
  local -i fetched=1

  if (( ${+commands[curl]} )); then
    command curl -fsS --max-time $seconds -o "$body" -- "$url" >/dev/null 2>&1 || fetched=0
  elif (( ${+commands[wget]} )); then
    command wget -q --tries=1 --timeout=$seconds -O "$body" -- "$url" >/dev/null 2>&1 ||
      fetched=0
  else
    return 1
  fi

  local -i ok=0
  if (( fetched )) && _inzsh_salah_locate_parse "$body"; then
    local -a where=(${=REPLY})
    _inzsh_salah_location_write "${where[1]}" "${where[2]}" "$now" && ok=1
  fi

  _inzsh_salah_rm -f -- "$body"

  (( ok ))
}

# `_inzsh_salah_locate_refresh [now]` — look the position up if one is due.
#
# THE ONLY CALLER OF THE FETCH, AND NOTHING CALLS THIS. Run it yourself, however you like:
#
#   _inzsh_salah_locate_refresh          from a shell, after you move
#   (_inzsh_salah_locate_refresh &!)     from `.zshrc`, detached, so login does not wait
#   a timer                              cron, launchd, systemd — whatever the machine has
#
# Status 0 when a position is available afterwards, whether it was refreshed or was already
# current. Status 1 when the lookup is off, or was needed and did not work — and in that second
# case the previous answer is still on disk and still readable, which is the fallback the segment
# actually runs on.
_inzsh_salah_locate_refresh() {
  emulate -L zsh

  _inzsh_salah_autolocate_on || return 1

  local now=${1:-${EPOCHSECONDS-}}
  [[ $now == <-> ]] || return 1

  _inzsh_salah_autolocate_ttl
  local -i ttl=$REPLY

  if _inzsh_salah_location_read "$now"; then
    (( _inzsh_salah_location_age >= 0 && _inzsh_salah_location_age < ttl )) && return 0
  fi

  _inzsh_salah_locate_fetch "$now"
}
