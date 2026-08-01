# InZsh — calculation methods. The configuration face of `calc.zsh`.
#
# `calc.zsh` knows about angles. Nobody configures a prompt in angles: they name the authority
# their masjid follows, or they read two numbers off its noticeboard. This file is the
# translation, and it is the only file in `lib/salah/` that reads an `INZSH_` variable.
#
# Three ideas, in the order they matter.
#
#   The table.  A handful of authorities, each one a fajr angle plus either an isha angle or a
#   fixed interval after maghrib. Both isha forms are first-class — Umm al-Qura's ninety
#   minutes is not a special case bolted on beside "the real one".
#
#   Overrides beat the table.  `INZSH_SALAH_FAJR_ANGLE` and its two siblings win over whatever
#   the named method said. That is deliberate: an authority the theme does not ship is a
#   two-variable configuration rather than a feature request, and nobody has to wait for a
#   release to be able to pray on time.
#
#   Nothing a user types may stop the prompt drawing.  Every value below is validated and every
#   invalid one is dropped in favour of the fallback — never reported, never fatal. An
#   unrecognised method name computes MWL; a fajr angle of `banana` computes the method's own.
#   This mirrors `lib/core/config.zsh`'s habit, which this file may not call: `lib/salah/`
#   imports nothing from the engine, so the habit is repeated here rather than shared.
#
# Angles and intervals are transcribed from the published parameters of each authority; the
# spot-checks in `test/fixtures/salah/methods.txt` pin them against the reference oracle.

# The table. Keys are normalised names — upper case, letters and digits only — so that
# `Umm al-Qura`, `umm_al_qura` and `ummalqura` are the same request. Values are the argument
# list `_inzsh_salah_compute` takes, which is why they are written the way they are: there is no
# second vocabulary between here and the arithmetic.
typeset -gA _inzsh_salah_methods=(
  MWL       'fajr_angle=18 isha_angle=17'
  ISNA      'fajr_angle=15 isha_angle=15'
  UMMALQURA 'fajr_angle=18.5 isha_interval=90'
  EGYPTIAN  'fajr_angle=19.5 isha_angle=17.5'
  KARACHI   'fajr_angle=18 isha_angle=18'
  ALGERIA   'fajr_angle=18 isha_angle=17'
)

# Names people actually type for a method the table holds under a different one.
typeset -gA _inzsh_salah_method_aliases=(
  MAKKAH            UMMALQURA
  MECCA             UMMALQURA
  UMMALQURAUNIVERSITY UMMALQURA
  EGYPT             EGYPTIAN
  MUSLIMWORLDLEAGUE MWL
)

# The method used when nothing valid was asked for. MWL is the broadest of the six and the one
# the reference oracle treats as its own default.
typeset -g _inzsh_salah_default_method=MWL

# The prayers a user may nudge, and the suffix each one's offset knob carries.
typeset -ga _inzsh_salah_offset_prayers=(fajr sunrise dhuhr asr maghrib isha)

# How far an offset may move a prayer, in minutes either way. Three hours is far past any
# calibration against a local masjid and comfortably short of "this knob moved it to yesterday".
typeset -gi _inzsh_salah_offset_limit=180

# The bound on a configured depression angle, in degrees. Nothing published sits above the
# twenties; thirty leaves room without letting a stray keystroke ask for a fajr at noon.
typeset -gi _inzsh_salah_angle_limit=30

# The bound on a configured isha interval, in minutes after maghrib.
typeset -gi _inzsh_salah_interval_limit=240

# --------------------------------------------------------------------------------------------
# The declaration table
#
# Every knob this file reads, declared where the theme's registry can find it — name, validator
# spec, default, three words each, with a `*` naming a family rather than a name. The engine
# absorbs any array named `_inzsh_<module>_knobs` once both halves are in the same shell.
#
# It is a TABLE and not a series of calls because `lib/salah/` imports nothing from the engine:
# that is what lets the prayer maths be tested standalone against a fixture oracle, and a
# guarded registration call would still be this file naming an engine function — which
# `test/unit/salah_calc_spec.sh` fails on, by prefix, deliberately. Nothing below refers to
# anything outside this file. Sourced on its own, it is an array nothing reads.
#
# Five of the seven declare `any`, and that is not laziness. The registry's spec grammar has
# five forms and none of them can say "one of three words, in any case" or "a real number above
# zero and no higher than thirty" — and a spec that is NEARLY right is worse than one that says
# the module decides, because it would make the registry disagree with the code below about what
# a value means. The vocabulary each one accepts is in `docs/configuration.md`; the two the
# grammar can state exactly are built from the limits above rather than restating them, so a
# bound cannot be raised in one place only.
typeset -ga _inzsh_salah_knobs
_inzsh_salah_knobs=(
  INZSH_SALAH_METHOD         any  $_inzsh_salah_default_method
  INZSH_SALAH_ASR            any  standard
  INZSH_SALAH_HIGHLAT        any  angle
  INZSH_SALAH_FAJR_ANGLE     any  ''
  INZSH_SALAH_ISHA_ANGLE     any  ''
  INZSH_SALAH_ISHA_INTERVAL  "int:1:$_inzsh_salah_interval_limit"  ''
  'INZSH_SALAH_OFFSET_*'  "int:-$_inzsh_salah_offset_limit:$_inzsh_salah_offset_limit"  0
)

# --------------------------------------------------------------------------------------------
# Reading the configuration

# Normalise a method name into a table key, in REPLY: upper case, letters and digits only, then
# aliases resolved. Punctuation and spacing carry no meaning in an authority's name.
_inzsh_salah_method_key() {
  emulate -L zsh

  local key=${(U)1}
  key=${key//[^A-Z0-9]/}
  REPLY=${_inzsh_salah_method_aliases[$key]:-$key}

  return 0
}

# The compute arguments for method `$1`, in REPLY. An unrecognised or empty name answers with
# the default method's arguments and status 1 — the caller gets something usable either way, and
# can tell that the name was not one of ours if it cares.
_inzsh_salah_method_params() {
  emulate -L zsh

  _inzsh_salah_method_key "$1"
  local key=$REPLY

  if [[ -n ${_inzsh_salah_methods[$key]-} ]]; then
    REPLY=${_inzsh_salah_methods[$key]}
    return 0
  fi

  REPLY=${_inzsh_salah_methods[$_inzsh_salah_default_method]}
  return 1
}

# Is `$1` a usable depression angle? Strictly above zero — an angle of zero is sunrise, not
# fajr — and no higher than the limit above.
_inzsh_salah_angle_ok() {
  emulate -L zsh

  _inzsh_salah_number "$1" || return 1
  (( $1 > 0 && $1 <= _inzsh_salah_angle_limit ))
}

# The signed offset in minutes for prayer `$1`, in REPLY, from `INZSH_SALAH_OFFSET_<PRAYER>`.
# Unset, unreadable or out of range is zero — the same "fall back rather than fail" rule as
# everything else here, and the fallback is the prayer as computed.
_inzsh_salah_offset_of() {
  emulate -L zsh

  local knob=INZSH_SALAH_OFFSET_${(U)1}
  local value=${(P)knob}
  REPLY=0

  [[ -n $value ]] || return 0
  [[ $value == (|-|+)<-> ]] || return 0
  (( value >= -_inzsh_salah_offset_limit && value <= _inzsh_salah_offset_limit )) || return 0

  REPLY=$(( value ))

  return 0
}

# Everything the user has said about how to calculate, as one argument list for
# `_inzsh_salah_compute`, in REPLY. Read fresh on every call: a knob changed at a prompt takes
# effect at the next one, with no re-source and no new shell.
#
# Precedence, per parameter: the override knob, then the named method, then the default method.
# The two isha forms are exclusive — a valid `INZSH_SALAH_ISHA_INTERVAL` replaces whatever angle
# was in play, because an interval is the explicit statement "my authority does not use an
# angle", and there would be no way to say it otherwise.
_inzsh_salah_params() {
  emulate -L zsh

  _inzsh_salah_method_params "$INZSH_SALAH_METHOD"
  local -a params=(${=REPLY})

  local fajr= isha= interval= entry
  for entry in "${params[@]}"; do
    case $entry in
      (fajr_angle=*)    fajr=${entry#*=} ;;
      (isha_angle=*)    isha=${entry#*=} ;;
      (isha_interval=*) interval=${entry#*=} ;;
    esac
  done

  _inzsh_salah_angle_ok "$INZSH_SALAH_FAJR_ANGLE" && fajr=$INZSH_SALAH_FAJR_ANGLE
  if _inzsh_salah_angle_ok "$INZSH_SALAH_ISHA_ANGLE"; then
    isha=$INZSH_SALAH_ISHA_ANGLE
    interval=
  fi
  if [[ $INZSH_SALAH_ISHA_INTERVAL == (|+)<-> ]] &&
     (( INZSH_SALAH_ISHA_INTERVAL > 0 &&
        INZSH_SALAH_ISHA_INTERVAL <= _inzsh_salah_interval_limit )); then
    interval=$(( INZSH_SALAH_ISHA_INTERVAL ))
    isha=
  fi

  local factor=1
  case ${(L)INZSH_SALAH_ASR} in
    (hanafi)              factor=2 ;;
    (standard|shafi|'')   factor=1 ;;
  esac

  local convention=angle
  case ${(L)INZSH_SALAH_HIGHLAT} in
    (seventh|middle|none|angle) convention=${(L)INZSH_SALAH_HIGHLAT} ;;
  esac

  local -a out=()
  [[ -n $fajr ]] && out+="fajr_angle=$fajr"
  [[ -n $isha ]] && out+="isha_angle=$isha"
  [[ -n $interval ]] && out+="isha_interval=$interval"
  out+=("asr_factor=$factor" "highlat=$convention")
  REPLY="${out[*]}"

  return 0
}

# --------------------------------------------------------------------------------------------
# The entry point users reach

# `_inzsh_salah_times <epoch> <lat> <lon> [tz]` → `_inzsh_salah_reply`.
#
# The whole pipeline: read the configuration, compute, then nudge. The epoch is injected by the
# caller — this file does not read the clock either.
#
# Offsets are applied last and never feed back into the arithmetic. A user who moves maghrib
# five minutes later has not moved the isha that an interval measures from it: they have
# calibrated a displayed time against a masjid, which is a statement about the display and not
# about the sun. An absent prayer stays absent — an offset from nothing is still nothing.
_inzsh_salah_times() {
  emulate -L zsh

  local epoch=$1 lat=$2 lon=$3 zone=$4
  local status_code=0

  _inzsh_salah_params
  _inzsh_salah_compute "$epoch" "$lat" "$lon" ${=REPLY} "tz=$zone" || status_code=$?

  local name moment
  for name in "${_inzsh_salah_offset_prayers[@]}"; do
    moment=${_inzsh_salah_reply[$name]-}
    [[ $moment == (|-)<-> ]] || continue
    _inzsh_salah_offset_of "$name"
    (( REPLY == 0 )) && continue
    _inzsh_salah_reply[$name]=$(( moment + REPLY * 60 ))
  done

  return $status_code
}
