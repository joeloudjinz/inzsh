# InZsh — prayer-time astronomy. Pure arithmetic over an injected instant.
#
# This file computes where the sun is and, from that, the six moments the segment draws. It is
# the only place in the repo that does trigonometry, and it is deliberately the least connected
# file in it: nothing here reads the clock, reads the terminal, or knows the engine exists.
#
# Three properties hold this together, and every one of them is load-bearing.
#
#   The injected instant.  `_inzsh_salah_compute` takes a UTC epoch as an argument and never
#   reads `EPOCHSECONDS`. That is what lets a fixture pin "now" to a day in 2026 and compare it
#   against an oracle. A single `EPOCHSECONDS` in this file would make the whole matrix
#   untestable, so there is an example that greps for one.
#
#   UTC throughout.  Every number below is either a UTC epoch second, a Julian day, or an hour
#   of LOCAL MEAN SOLAR TIME at the given longitude — never a civil clock time, and never a
#   fixed UTC offset. A zone appears exactly twice: to decide which calendar day an instant
#   falls in, and to format an answer. Both go through `strftime`, so a DST transition is the
#   C library's problem rather than ours.
#
#   Absence is a value.  Above roughly 66° the sun may never reach the horizon, let alone 18°
#   below it, and there is no time to report. That case returns the sentinel below. It is never
#   midnight, never the previous day's answer, and never a number that happens to parse.
#
# Method: the low-precision solar position from the USNO's approximation, and the prayer
# definitions as PrayTimes states them. Both are standard, and neither is anyone's code.

zmodload -i zsh/mathfunc
zmodload -i zsh/datetime

# The sentinel. A prayer that does not occur comes back as this word rather than as an epoch, an
# empty value, or zero — all three of which a caller could mistake for a time. A word on
# purpose: it survives `print`, it fails `[[ $t == <-> ]]`, and it is legible in a diff.
typeset -g _inzsh_salah_absent=none

# Degrees to radians. Derived rather than transcribed, so there is no constant here to mistype.
typeset -g _inzsh_salah_rad
(( _inzsh_salah_rad = 4.0 * atan(1.0) / 180.0 ))

# The refinement loop's stopping rule, in hours. 1e-6 h is 3.6 milliseconds, far under the
# second every answer is rounded to, so a converged result is converged for any purpose a caller
# has. The cap exists because a loop that feeds a prompt may not be unbounded; in practice the
# third pass is already inside the tolerance everywhere on Earth.
typeset -g _inzsh_salah_tolerance=0.000001
typeset -g _inzsh_salah_decl= _inzsh_salah_eqt=
typeset -gi _inzsh_salah_max_passes=8

# The prayers this file answers for, in the order a day runs. `maghrib` is sunset for every
# method the theme ships and is named separately anyway, so a method that offsets it later has
# somewhere to put the offset.
typeset -ga _inzsh_salah_prayers=(fajr sunrise dhuhr asr maghrib isha)

# Where the answers land: prayer name → UTC epoch seconds, or `$_inzsh_salah_absent`. A global
# association rather than `reply`, which the engine's layout already uses as an array — the two
# layers share nothing, and must not start by sharing a variable.
typeset -gA _inzsh_salah_reply

# How many refinement passes the last computation needed. Diagnostic only; an example reads it
# to show the loop converges rather than merely stopping.
typeset -gi _inzsh_salah_passes

# --------------------------------------------------------------------------------------------
# Numbers
#
# Nothing below may abort a prompt because a user typed a latitude wrong, so every value coming
# from outside is checked before it reaches an arithmetic expression. zsh reads a bare word in
# `(( ))` as a variable — silently zero — and an unfinished expression as a fatal error, and
# neither is an acceptable answer to a typo.

# Is `$1` a plain decimal number? Optionally signed, digits on either side of the point, no
# exponent, no whitespace, no `0x`. Deliberately narrower than zsh's own arithmetic grammar:
# `1e3` and `0x10` are almost certainly not what someone meant to type into a latitude.
_inzsh_salah_number() {
  emulate -L zsh

  local value=$1
  [[ -n $value ]] || return 1
  [[ $value == (|-|+)(<->(|.<->)|.<->) ]] || return 1

  return 0
}

# Is `$1` a number inside the inclusive bounds `$2`..`$3`? Either bound may be empty.
_inzsh_salah_in_range() {
  emulate -L zsh

  _inzsh_salah_number "$1" || return 1
  [[ -z $2 ]] || (( $1 >= $2 )) || return 1
  [[ -z $3 ]] || (( $1 <= $3 )) || return 1

  return 0
}

# --------------------------------------------------------------------------------------------
# Calendars
#
# The bridge between "an instant" and "a day". A prayer table is per calendar day, and which day
# an instant belongs to depends on where the person is standing: 21:00 UTC is one date in
# Algiers and the next one in Auckland.

# The Julian day number at 00:00 UT on the civil date `$1`-`$2`-`$3`, in REPLY. The standard
# Gregorian conversion; the trailing `.5` is because a Julian day starts at noon.
_inzsh_salah_jd_civil() {
  emulate -L zsh

  local year=$1 month=$2 day=$3 a b
  _inzsh_salah_number "$year" || return 1
  _inzsh_salah_number "$month" || return 1
  _inzsh_salah_number "$day" || return 1

  if (( month <= 2 )); then
    (( year -= 1 ))
    (( month += 12 ))
  fi
  (( a = floor(year / 100.0) ))
  (( b = 2.0 - a + floor(a / 4.0) ))
  REPLY=$(( floor(365.25 * (year + 4716.0)) + floor(30.6001 * (month + 1.0)) \
       + day + b - 1524.5 ))

  return 0
}

# The calendar date the UTC epoch `$1` falls on, as `year month day` in REPLY, read in the zone
# `$2` — or in the ambient zone when `$2` is empty. The zone is scoped to this call: TZ is a
# global, and the theme does not get to change the shell's.
_inzsh_salah_civil_date() {
  emulate -L zsh

  local epoch=$1 zone=$2 stamp
  [[ $epoch == (|-)<-> ]] || return 1

  if [[ -n $zone ]]; then
    local -x TZ=$zone
  fi
  strftime -s stamp '%Y %m %d' $epoch 2>/dev/null || return 1

  # `%m` and `%d` are zero-padded and a leading zero makes an octal literal in `(( ))`. Stripped
  # here, once, rather than left for every arithmetic expression downstream to remember.
  local -a parts=(${=stamp})
  (( ${#parts} == 3 )) || return 1
  REPLY="${parts[1]#0} ${parts[2]#0} ${parts[3]#0}"

  return 0
}

# The UTC epoch of 00:00 UT on the day the epoch `$1` falls on in zone `$2`, in REPLY, with the
# matching Julian day in `_inzsh_salah_jd0`. This is the origin every hour below is measured
# from, and the only step at which a zone touches the maths at all.
_inzsh_salah_day_origin() {
  emulate -L zsh

  _inzsh_salah_civil_date "$1" "$2" || return 1
  local -a date=(${=REPLY})
  _inzsh_salah_jd_civil "${date[1]}" "${date[2]}" "${date[3]}" || return 1

  typeset -g _inzsh_salah_jd0=$REPLY
  REPLY=$(( int(rint((_inzsh_salah_jd0 - 2440587.5) * 86400.0)) ))

  return 0
}

# --------------------------------------------------------------------------------------------
# The sun
#
# The USNO low-precision solar position: good to about a hundredth of a degree for a couple of
# centuries either side of 2000, which is an order of magnitude finer than the minute the answer
# is eventually rounded to.

# Declination in degrees and equation of time in hours at Julian day `$1`, into
# `_inzsh_salah_decl` and `_inzsh_salah_eqt`.
_inzsh_salah_sun() {
  emulate -L zsh

  local jd=$1 rad=$_inzsh_salah_rad
  local d anomaly mean longitude obliquity ra

  (( d = jd - 2451545.0 ))
  (( anomaly = 357.529 + 0.98560028 * d ))
  (( anomaly -= 360.0 * floor(anomaly / 360.0) ))
  (( mean = 280.459 + 0.98564736 * d ))
  (( mean -= 360.0 * floor(mean / 360.0) ))
  (( longitude = mean + 1.915 * sin(anomaly * rad) + 0.020 * sin(2.0 * anomaly * rad) ))
  (( longitude -= 360.0 * floor(longitude / 360.0) ))
  (( obliquity = 23.439 - 0.00000036 * d ))

  (( ra = atan(cos(obliquity * rad) * sin(longitude * rad), cos(longitude * rad)) / rad ))
  (( ra /= 15.0 ))
  (( ra -= 24.0 * floor(ra / 24.0) ))

  # The equation of time is a small correction — it never leaves ±20 minutes — so it is folded
  # into (-12, 12] rather than left wherever the subtraction landed. Without this fold, the few
  # days a year when the mean longitude has wrapped past 360° and the right ascension has not
  # would come back a whole day out.
  (( _inzsh_salah_eqt = mean / 15.0 - ra ))
  (( _inzsh_salah_eqt -= 24.0 * floor((_inzsh_salah_eqt + 12.0) / 24.0) ))
  (( _inzsh_salah_decl = asin(sin(obliquity * rad) * sin(longitude * rad)) / rad ))

  return 0
}

# --------------------------------------------------------------------------------------------
# Prayer times
#
# Every hour below is LOCAL MEAN SOLAR TIME at the given longitude, measured from the origin
# day's 00:00 UT, and deliberately NOT wrapped into 0..24. A sunset at 24.08 in Reykjavík is a
# sunset just after midnight; wrapping it would move it eighteen hours earlier on the same day
# rather than a few minutes into the next one.

# Fold `$1` into 0..24, in REPLY. Used for durations only, where the wrap is the point.
_inzsh_salah_fix_hour() {
  emulate -L zsh

  local value=$1
  REPLY=$(( value - 24.0 * floor(value / 24.0) ))

  return 0
}

# The hour at which the sun sits `$1` degrees below the horizon, given the current estimate `$2`
# for that hour and the direction `$3` — `before` for the morning side of noon, anything else
# for the evening side. Latitude, longitude and the origin Julian day come from the computation
# in progress.
#
# Returns 1, leaving REPLY alone, when the sun never reaches that angle: the cosine of the hour
# angle leaves -1..1. That is not an error, it is the answer "this does not happen here today" —
# and `acos` of an out-of-range value is exactly what a naive implementation reports as
# midnight.
_inzsh_salah_angle_hour() {
  emulate -L zsh

  local angle=$1 estimate=$2 direction=$3 rad=$_inzsh_salah_rad
  local jd noon ratio span

  (( jd = _inzsh_salah_jd0 - _inzsh_salah_lon / 360.0 + estimate / 24.0 ))
  _inzsh_salah_sun "$jd"

  (( noon = 12.0 - _inzsh_salah_eqt ))
  (( noon -= 24.0 * floor(noon / 24.0) ))

  (( ratio = (-sin(angle * rad) - sin(_inzsh_salah_decl * rad) * sin(_inzsh_salah_lat * rad)) \
       / (cos(_inzsh_salah_decl * rad) * cos(_inzsh_salah_lat * rad)) ))
  (( ratio >= -1.0 && ratio <= 1.0 )) || return 1

  (( span = acos(ratio) / rad / 15.0 ))

  if [[ $direction == before ]]; then
    REPLY=$(( noon - span ))
  else
    REPLY=$(( noon + span ))
  fi

  return 0
}

# Solar noon, in REPLY, refined at the current estimate `$1`. Always defined: the sun crosses
# the meridian everywhere, every day, including where it never rises.
_inzsh_salah_noon_hour() {
  emulate -L zsh

  local estimate=$1 jd
  (( jd = _inzsh_salah_jd0 - _inzsh_salah_lon / 360.0 + estimate / 24.0 ))
  _inzsh_salah_sun "$jd"

  local noon
  (( noon = 12.0 - _inzsh_salah_eqt ))
  REPLY=$(( noon - 24.0 * floor(noon / 24.0) ))

  return 0
}

# Asr, in REPLY, for shadow factor `$1` at estimate `$2`. This prayer is defined by shadow
# length rather than by a fixed depression, so its angle is derived from the declination of the
# moment and has to be rebuilt on every refinement pass — it is the prayer the loop moves most.
#
# Returns 1 when the derived angle puts the sun BELOW the horizon at its own prayer. That is the
# polar night: the rule measures a shadow against the one an object casts at noon, and where the
# sun does not rise there is no noon shadow to measure against. The arithmetic will still
# produce a number there — the shadow rule degenerates rather than failing — and that number is
# a time of day at which nothing happens. The reference oracle reports it; we do not.
_inzsh_salah_asr_hour() {
  emulate -L zsh

  local factor=$1 estimate=$2 rad=$_inzsh_salah_rad
  local jd angle

  (( jd = _inzsh_salah_jd0 - _inzsh_salah_lon / 360.0 + estimate / 24.0 ))
  _inzsh_salah_sun "$jd"

  (( angle = -atan(1.0 / (factor + tan(abs(_inzsh_salah_lat - _inzsh_salah_decl) * rad))) \
       / rad ))
  (( angle <= 0.0 )) || return 1

  _inzsh_salah_angle_hour "$angle" "$estimate" after
}

# --------------------------------------------------------------------------------------------
# High latitudes
#
# Between roughly 48° and 66° the sun sets but never reaches 18° below the horizon, so fajr and
# isha have no astronomical time and the night is divided instead. Three conventions, all of
# them measuring a portion of the night outward from sunrise and from sunset:
#
#   angle     — the depression angle over sixty, times the night. The default, and what the
#               reference oracle uses unless told otherwise.
#   seventh   — a flat one seventh of the night.
#   middle    — half the night.
#   none      — no division at all; a prayer with no astronomical time stays absent.
#
# Beyond the polar circles the sun may not rise or set. Then there is no night to take a portion
# OF, every convention above is undefined, and the answer is the sentinel.

# The portion of a night of `$2` hours that convention `$1` allots to depression angle `$3`, in
# REPLY. Only `angle` reads the angle; the other two are why it is a parameter and not a
# constant.
_inzsh_salah_night_portion() {
  emulate -L zsh

  local convention=$1 night=$2 angle=$3

  case $convention in
    (seventh) REPLY=$(( night / 7.0 )) ;;
    (middle)  REPLY=$(( night / 2.0 )) ;;
    (*)       REPLY=$(( night * angle / 60.0 )) ;;
  esac

  return 0
}

# --------------------------------------------------------------------------------------------
# The entry point

# `_inzsh_salah_compute <epoch> <lat> <lon> [key=value …]` → `_inzsh_salah_reply`.
#
# The epoch is UTC seconds and picks the day; this file never reads it from the clock. Latitude
# and longitude are decimal degrees, north and east positive.
#
# Recognised keys, all optional:
#
#   fajr_angle=<deg>       depression angle for fajr; absent means fajr is not computed
#   isha_angle=<deg>       depression angle for isha
#   isha_interval=<min>    minutes after maghrib instead of an angle; wins over isha_angle
#   asr_factor=<1|2>       shadow multiplier — 1 for the majority schools, 2 for the Hanafi one
#   highlat=<angle|seventh|middle|none>   what to do when an angle has no solution
#   tz=<zone>              zone deciding which calendar day the epoch falls on
#
# Anything unrecognised, unparseable or out of range is dropped in favour of the default: a
# mistyped angle produces a prayer table, never an error. Returns 1 only when the location or
# the instant is unusable, and even then leaves every key set to the sentinel so that a caller
# which ignored the status still has something safe to render.
_inzsh_salah_compute() {
  emulate -L zsh

  local epoch=$1 lat=$2 lon=$3
  shift 3

  local pair key value
  local fajr_angle= isha_angle= isha_interval= zone= convention=angle asr_factor=1
  for pair in "$@"; do
    [[ $pair == *=* ]] || continue
    key=${pair%%=*}
    value=${pair#*=}
    case $key in
      (fajr_angle)    _inzsh_salah_in_range "$value" 0 89 && fajr_angle=$value ;;
      (isha_angle)    _inzsh_salah_in_range "$value" 0 89 && isha_angle=$value ;;
      (isha_interval) _inzsh_salah_in_range "$value" 1 1440 && isha_interval=$value ;;
      (asr_factor)    _inzsh_salah_in_range "$value" 1 2 && asr_factor=$value ;;
      (highlat)       [[ $value == (angle|seventh|middle|none) ]] && convention=$value ;;
      (tz)            zone=$value ;;
    esac
  done
  [[ -n $isha_interval ]] && isha_angle=

  typeset -gA _inzsh_salah_reply
  _inzsh_salah_reply=()
  local name
  for name in "${_inzsh_salah_prayers[@]}"; do
    _inzsh_salah_reply[$name]=$_inzsh_salah_absent
  done
  typeset -gi _inzsh_salah_passes=0

  [[ $epoch == (|-)<-> ]] || return 1
  _inzsh_salah_in_range "$lat" -90 90 || return 1
  _inzsh_salah_in_range "$lon" -180 180 || return 1

  typeset -g _inzsh_salah_lat=$lat _inzsh_salah_lon=$lon
  _inzsh_salah_day_origin "$epoch" "$zone" || return 1
  local origin=$REPLY

  # The estimates the refinement starts from: a rough hour for each prayer, in local mean solar
  # time. They only have to be close enough that the first pass evaluates the sun somewhere on
  # the right day — every pass after this one starts from the previous answer.
  local -A hour=(fajr 5 sunrise 6 dhuhr 12 asr 13 maghrib 18 isha 18)
  local -A known=(fajr 0 sunrise 0 dhuhr 0 asr 0 maghrib 0 isha 0)

  # Refinement. Each prayer's sun position is recomputed at that prayer's own current estimate
  # rather than once at noon: evaluating isha's declination at noon puts it about a minute out
  # at mid latitudes, and the error grows with the latitude.
  #
  # A prayer with no solution keeps its previous estimate as a seed — carrying an absence into
  # the next pass would poison the sun position with a non-number — and is marked unknown.
  # Convergence is the largest move across all six falling under the tolerance, so the loop stops
  # when the answer has stopped changing rather than after a count someone chose.
  local moved delta solved
  local -i pass
  for (( pass = 1; pass <= _inzsh_salah_max_passes; pass++ )); do
    moved=0
    for name in "${_inzsh_salah_prayers[@]}"; do
      case $name in
        (dhuhr)   _inzsh_salah_noon_hour "${hour[$name]}" ;;
        (asr)     _inzsh_salah_asr_hour "$asr_factor" "${hour[$name]}" ;;
        (sunrise) _inzsh_salah_angle_hour 0.833 "${hour[$name]}" before ;;
        (maghrib) _inzsh_salah_angle_hour 0.833 "${hour[$name]}" after ;;
        (fajr)    [[ -n $fajr_angle ]] &&
                    _inzsh_salah_angle_hour "$fajr_angle" "${hour[$name]}" before ;;
        (isha)    [[ -n $isha_angle ]] &&
                    _inzsh_salah_angle_hour "$isha_angle" "${hour[$name]}" after ;;
      esac
      solved=$?
      if (( solved == 0 )); then
        known[$name]=1
        (( delta = REPLY - ${hour[$name]} ))
        (( delta < 0 )) && (( delta = -delta ))
        (( delta > moved )) && moved=$delta
        hour[$name]=$REPLY
      else
        known[$name]=0
      fi
    done
    (( _inzsh_salah_passes = pass ))
    (( moved < _inzsh_salah_tolerance )) && break
  done

  # The night, and the two prayers that may have to be carved out of it. Both edges have to
  # exist: under a midnight sun there is no night, and no convention invents one.
  local night portion gap
  if [[ $convention != none && ${known[sunrise]} == 1 && ${known[maghrib]} == 1 ]]; then
    (( gap = ${hour[sunrise]} - ${hour[maghrib]} ))
    _inzsh_salah_fix_hour "$gap"
    night=$REPLY

    if [[ -n $fajr_angle ]]; then
      _inzsh_salah_night_portion "$convention" "$night" "$fajr_angle"
      portion=$REPLY
      (( gap = ${hour[sunrise]} - ${hour[fajr]} ))
      _inzsh_salah_fix_hour "$gap"
      if [[ ${known[fajr]} != 1 ]] || (( REPLY > portion )); then
        (( hour[fajr] = ${hour[sunrise]} - portion ))
        known[fajr]=1
      fi
    fi

    if [[ -n $isha_angle ]]; then
      _inzsh_salah_night_portion "$convention" "$night" "$isha_angle"
      portion=$REPLY
      (( gap = ${hour[isha]} - ${hour[maghrib]} ))
      _inzsh_salah_fix_hour "$gap"
      if [[ ${known[isha]} != 1 ]] || (( REPLY > portion )); then
        (( hour[isha] = ${hour[maghrib]} + portion ))
        known[isha]=1
      fi
    fi
  fi

  # A fixed interval after maghrib — the Umm al-Qura form. It replaces whatever an angle said,
  # so it is applied last, and it depends on maghrib alone.
  if [[ -n $isha_interval ]]; then
    if [[ ${known[maghrib]} == 1 ]]; then
      (( hour[isha] = ${hour[maghrib]} + isha_interval / 60.0 ))
      known[isha]=1
    else
      known[isha]=0
    fi
  fi

  # Local mean solar hours back to UTC epoch seconds. The longitude term is the whole of the
  # conversion: there is no zone offset here and there never will be, because the answer is an
  # instant, and an instant has no zone.
  local seconds
  for name in "${_inzsh_salah_prayers[@]}"; do
    if [[ ${known[$name]} == 1 ]]; then
      (( seconds = (${hour[$name]} - _inzsh_salah_lon / 15.0) * 3600.0 ))
      _inzsh_salah_reply[$name]=$(( int(rint(origin + seconds)) ))
    else
      _inzsh_salah_reply[$name]=$_inzsh_salah_absent
    fi
  done

  return 0
}

# --------------------------------------------------------------------------------------------
# Formatting
#
# Kept apart from the maths on purpose. Everything above is an instant; this is the one function
# with an opinion about how an instant reads, and the one place a zone appears in an answer
# rather than in a question.

# Round the epoch `$1` to the nearest minute, in REPLY. Prayer times are published to the minute
# and every oracle rounds rather than truncates, so a bare `strftime` on an unrounded epoch
# reads half a minute early, half the time.
_inzsh_salah_round_minute() {
  emulate -L zsh

  [[ $1 == (|-)<-> ]] || return 1
  REPLY=$(( int(floor(($1 + 30.0) / 60.0)) * 60 ))

  return 0
}

# `_inzsh_salah_format <epoch> [zone] [format]` → REPLY.
#
# The zone is the caller's; empty means the shell's own. DST is never computed here — the C
# library owns those rules, which is why an instant is carried all the way down to this line
# rather than being turned into a civil time earlier, where a hardcoded offset could creep in.
#
# The epoch is rounded to the nearest minute unless the format asks for seconds, so that what
# the prompt shows and what an oracle publishes agree. Absent, empty or unparseable input gives
# an empty REPLY and status 1: there is nothing to draw, and the caller draws its absent glyph.
_inzsh_salah_format() {
  emulate -L zsh

  local epoch=$1 zone=$2 format=${3:-%H:%M}
  REPLY=

  [[ $epoch == (|-)<-> ]] || return 1

  if [[ $format != *%S* ]]; then
    _inzsh_salah_round_minute "$epoch" || return 1
    epoch=$REPLY
  fi

  if [[ -n $zone ]]; then
    local -x TZ=$zone
  fi

  local rendered
  strftime -s rendered "$format" $epoch 2>/dev/null || { REPLY=; return 1 }
  REPLY=$rendered

  return 0
}
