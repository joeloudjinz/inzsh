# Loaded into every spec via .shellspec (--require spec_helper). `.shellspec` pins `--shell zsh`,
# so this runs under zsh like every spec file, not under `sh`.

spec_helper_configure() {
  : # minimum_version, before/after hooks land here as the suite grows
}

# The locale guard, for `Skip if`. In a single-byte locale the theme deliberately draws its
# ASCII register — different separators, marks and ellipses — so an example that pins the
# multibyte output is skipped there rather than failed: the difference is the design, not a
# defect. One copy here, because it is one rule.
inzsh_spec_bytes_not_cells() {
  local sample=é
  [ ${#sample} -ne 1 ]
}

# The root guard, for `Skip if`. `[[ -r $f ]]` and `[[ -x $dir ]]` read TRUE for root whatever a
# file's mode says — root bypasses permission bits entirely — so an example that provokes a
# mode-based refusal (`denied`, `nodir`) cannot hold under a root shell. This is the ordinary
# case for a CI job that runs inside a container, which runs as root unless told otherwise, and
# is why `zsh-floor` (the one job in the matrix that runs in a container) failed where the other
# eight did not. One copy here for the same reason `inzsh_spec_bytes_not_cells` is: it is one
# fact, asked by more than one spec file.
inzsh_spec_is_root() {
  emulate -L zsh
  (( EUID == 0 ))
}

# --------------------------------------------------------------------------------------------
# The salah fixture — a scratch cache directory, an injected clock and the neutral Mecca
# position — shared by every spec that exercises `lib/salah/cache.zsh` from either side: the
# cache functions directly (`salah_cache_spec.sh`) or through `inzsh doctor` (`doctor_spec.sh`).
# One copy, because a second one is how two suites end up disagreeing about what "the fixture
# instant" is.

# The fixture instant: 2026-06-01, 15:00 in Asia/Riyadh, which is 12:00 UTC. Riyadh keeps no
# daylight saving, so the wall clock in these examples moves only when the code moves it.
typeset -gi inzsh_spec_salah_now=1780315200

# The neutral position the whole repository uses.
typeset -g inzsh_spec_salah_lat=21.4225
typeset -g inzsh_spec_salah_lon=39.8262

# A scratch cache directory, in REPLY. Named so the cleanup below can refuse anything else.
inzsh_spec_salah_dir() {
  emulate -L zsh

  typeset -g REPLY=
  local dir
  dir=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-salah-spec-XXXXXX") || return 1
  typeset -g REPLY=$dir

  return 0
}

inzsh_spec_salah_clean() {
  emulate -L zsh

  local target=${1-}
  [[ ${target:t} == inzsh-salah-spec-* ]] || return 1
  rm -rf -- "$target" 2>/dev/null

  return 0
}

# The fixture environment, as locals in the CALLER: a scratch directory, the neutral position,
# Riyadh, and an empty table. Every example starts here.
inzsh_spec_salah_env() {
  emulate -L zsh

  inzsh_spec_salah_dir || return 1
  typeset -g inzsh_spec_salah_cache=$REPLY

  typeset -gx TZ=Asia/Riyadh
  typeset -g INZSH_SALAH_CACHE_DIR=$inzsh_spec_salah_cache
  typeset -g INZSH_SALAH_LAT=$inzsh_spec_salah_lat
  typeset -g INZSH_SALAH_LON=$inzsh_spec_salah_lon
  typeset -g INZSH_SALAH_AUTOLOCATE=0
  typeset -g INZSH_SALAH_METHOD=MWL
  typeset -g INZSH_SALAH_ASR=standard
  typeset -g INZSH_SALAH_HIGHLAT=angle
  typeset -g INZSH_SALAH_FAJR_ANGLE= INZSH_SALAH_ISHA_ANGLE= INZSH_SALAH_ISHA_INTERVAL=
  local name
  for name in FAJR SUNRISE DHUHR ASR MAGHRIB ISHA; do
    typeset -g INZSH_SALAH_OFFSET_$name=0
  done

  typeset -gA _inzsh_salah_table
  _inzsh_salah_table=()

  return 0
}
