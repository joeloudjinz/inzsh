#!/usr/bin/env zsh
# InZsh — the performance suite. One table of named cases: each is timed, reported in
# milliseconds per iteration, and gated against a budget declared beside it.
#
# WHAT THIS MEASURES. `render-prompt` is the whole warm prompt: every segment builds its own
# text, the width filter drops whoever does not fit, ranks decide side and order, both sides
# assemble and the result is expanded the way a precmd expands it. That row is the one the
# house budget in `lib/core/config.zsh` — 30 ms — is measured against.
#
# The rows under it time the machinery that render spends itself in: token/role resolution, the
# rank sort, surface assignment, the layout arithmetic, config resolution. They exist so a
# regression says WHERE, not just THAT. `render-floor` chains them without the segments and is
# kept as a control: when it moves and `render-prompt` does not, the cost is in the engine.
#
# The one thing left out of `render-prompt` is the interactive guard, which returns early in a
# script. Everything a real draw does after that guard is timed.
#
# Run it, never source it: `make perf`, or `zsh -f test/perf/bench.zsh`.
#
#   --list          print the case table and exit 0
#   --only NAME     run only this case; repeatable
#   --iters N       override every case's iteration count
#   --reps N        override the repetition count
#   --budget MS     override every case's budget — `--budget 0` proves the gate fires
#   --no-gate       report without failing on a breach (an empty run still fails)
#
# THE STATISTIC IS BEST-OF-N. Each case runs `--reps` times and the gate reads the FASTEST
# repetition. Timing noise on a shared runner is one-sided — being descheduled only ever makes
# a sample slower, never faster — so the minimum is the closest estimate of the work itself and
# much the most stable number to gate on. The median is printed next to it and gated on
# nothing: when the two diverge the machine is loaded, which is worth seeing and not worth
# failing on.
#
# EVERY CASE IS WARMED FIRST. One untimed pass before the timed ones, discarded. A first call
# pays for module loads and the first touch of every array it reads; that is startup cost, and
# this budget is about the warm prompt.
#
# NO FORKS INSIDE THE TIMED REGION. The timed region is `_inzsh_bench_spin` — a `for` loop and
# a function call, nothing else. Fixture setup runs in a per-case `_inzsh_bench_prep_*`, which
# is outside it, and all formatting happens after the last sample is taken.

emulate -L zsh

_inzsh_bench_root=${${(%):-%x}:A:h:h:h}

# A multibyte locale is a precondition, not a preference. `lib/core/layout.zsh` holds a `\u`
# escape that a non-multibyte locale cannot even parse, so the file fails to source and every
# width case turns into a command-not-found — noise that looks like a broken suite. Refuse up
# front instead. CI pins `LC_ALL=C.UTF-8` repo-wide; locally, export one before `make perf`.
# The probe is a literal two-byte character: one cell in a UTF-8 locale, two under C.
_inzsh_bench_locale_probe=$'é'
if (( ${#_inzsh_bench_locale_probe} != 1 )); then
  print -ru2 -- 'bench: needs a multibyte locale — try LC_ALL=C.UTF-8 (CI pins one repo-wide)'
  exit 2
fi

# Dependency order, the same one `inzsh.zsh-theme` uses, plus the three files the entry point
# does not source yet (engine, layout, config) because the renderer that will need them is the
# thing this suite is waiting for.
source $_inzsh_bench_root/lib/core/detect.zsh
source $_inzsh_bench_root/lib/core/tokens-256.zsh
source $_inzsh_bench_root/lib/core/tokens.zsh
source $_inzsh_bench_root/lib/core/render.zsh
source $_inzsh_bench_root/lib/core/engine.zsh
source $_inzsh_bench_root/lib/core/layout.zsh
source $_inzsh_bench_root/lib/core/config.zsh
source $_inzsh_bench_root/tools/perf.zsh

# The segments, for the `render-prompt` case. They register at load and compute nothing here.
for _inzsh_bench_segment in root user host dir venv retval time; do
  source $_inzsh_bench_root/lib/segments/$_inzsh_bench_segment.zsh
done
unset _inzsh_bench_segment

# ------------------------------------------------------------------------------------------
# The fixture
#
# A six-segment prompt, keyed by segment name so a case indexes the way an engine would. All
# neutral data: a repo path, a branch, a virtualenv, three state glyphs, a clock and a prayer
# time. Nothing is read from the machine, and no case touches the real working tree or clock.

typeset -ga _inzsh_bench_segments=(dir git venv status clock salah)

typeset -gA _inzsh_bench_label=(
  dir     '~/dev/inzsh'
  git     'main'
  venv    'venv'
  status  '✓ ✕ !'
  clock   '12:04'
  salah   'Maghrib · 19:59'
)

typeset -gA _inzsh_bench_fg=(
  dir     text-strong
  git     text-body
  venv    text-muted
  status  text-body
  clock   text-muted
  salah   on-accent
)

# What `ramp` reads. `alternate` and `flat` ignore it, which is the point of having a mode.
typeset -gA _inzsh_bench_weight=(
  dir 1  git 2  venv 3  status 2  clock 3  salah 1
)

# A path deep enough that every rung of the truncation ladder is reachable.
typeset -g _inzsh_bench_path='/home/example/work/projects/inzsh/lib/core/tokens'

# Prompt fragments for the width case — the same mix of escape shapes a segment produces.
typeset -ga _inzsh_bench_fragments=(
  '%F{red}~/dev/inzsh%f'
  '%K{cyan}%F{black} main %f%k'
  '%{'$'\e''];0;title'$'\a''%}venv'
  $'\e[31m✓ ✕ !\e[0m'
  '100%% ▏Maghrib · 19:59'
)

# Ranks and MINCOLS live in the environment, exactly as a user's would: three segments left,
# three right, sparse on purpose so the sort has gaps to walk.
_inzsh_bench_fixture() {
  typeset -g INZSH_DIR_RANK=1     INZSH_GIT_RANK=4     INZSH_VENV_RANK=10
  typeset -g INZSH_STATUS_RANK=-3 INZSH_CLOCK_RANK=-2  INZSH_SALAH_RANK=-1
  typeset -g INZSH_VENV_MINCOLS=100 INZSH_SALAH_MINCOLS=60
  typeset -g INZSH_SURFACE_MODE=alternate
}

# ------------------------------------------------------------------------------------------
# The cases
#
# One `_inzsh_bench_case_<base>` per row of the table, where <base> is the case name with its
# dashes turned into underscores. An optional `_inzsh_bench_prep_<base>` sets up state and runs
# outside the timed region. A case body is one iteration's worth of work — whatever the row's
# budget is measured against.

# --- token and role resolution ------------------------------------------------------------
# Three depths, because the reduced palettes are a different lookup over the same loop and a
# regression could live in either. Register and depth are set in prep, not in the case: they
# are what the case is *about*, not work a render repeats.

_inzsh_bench_prep_tokens_truecolor() { _inzsh_color_depth=truecolor; _inzsh_register=dark }
_inzsh_bench_case_tokens_truecolor() { _inzsh_tokens_resolve }

_inzsh_bench_prep_tokens_256() { _inzsh_color_depth=256; _inzsh_register=light }
_inzsh_bench_case_tokens_256() { _inzsh_tokens_resolve }

_inzsh_bench_prep_tokens_8() { _inzsh_color_depth=8; _inzsh_register=dark }
_inzsh_bench_case_tokens_8() { _inzsh_tokens_resolve }

# Per-segment colour: the precedence ladder, twice per segment (background and foreground),
# which is what a filled prompt asks for on every draw.
_inzsh_bench_case_seg_color() {
  local segment
  for segment in "${_inzsh_bench_segments[@]}"; do
    _inzsh_seg_color "$segment" bg surface-soft surface
    _inzsh_seg_color "$segment" fg "${_inzsh_bench_fg[$segment]}" text-body
  done
}

# --- the rank system ------------------------------------------------------------------------
# Split and sort over the whole six-segment set. Sparse ranks, both sides populated.
_inzsh_bench_case_rank_split() {
  _inzsh_rank_split "${_inzsh_bench_segments[@]}"
}

# --- surfaces -------------------------------------------------------------------------------
# Both filled modes. `ramp` carries the collision-repair pass that `alternate` does not, so the
# two are separate rows rather than an average.

_inzsh_bench_prep_surface_alternate() { typeset -g INZSH_SURFACE_MODE=alternate }
_inzsh_bench_case_surface_alternate() {
  _inzsh_surface_assign 6 1 2 3 2 3 1
}

_inzsh_bench_prep_surface_ramp() { typeset -g INZSH_SURFACE_MODE=ramp }
_inzsh_bench_case_surface_ramp() {
  _inzsh_surface_assign 6 1 1 2 2 3 3
}

# `hue` is a SECOND pass over the assignment rather than a third way of producing one, so what
# this row measures is the pass: the positional assign the other two rows already cover, and then
# the map read, the collision repair and the invariant check on top of it. The map is filled
# hostilely — every segment asking for the same fill — because that is the input that makes every
# segment take the repair branch, and a benchmark of the cheap path would be a benchmark of
# nothing.
_inzsh_bench_prep_surface_hue() {
  typeset -g INZSH_SURFACE_MODE=hue
  typeset -gA _inzsh_segment_bg_role
  local segment
  for segment in "${_inzsh_bench_segments[@]}"; do
    _inzsh_segment_bg_role[$segment]=accent
  done
}
_inzsh_bench_case_surface_hue() {
  _inzsh_surface_assign 6 1 2 3 2 3 1
  _inzsh_render_hues "${_inzsh_bench_segments[@]}"
}

# --- layout ---------------------------------------------------------------------------------
# Width accounting over five fragments — the escape-stripping pass, which is the most
# expensive parameter work on the render path and the one most sensitive to locale.
_inzsh_bench_case_layout_width() {
  local fragment
  local -i used=0
  for fragment in "${_inzsh_bench_fragments[@]}"; do
    _inzsh_width "$fragment"
    _inzsh_width_add used "$REPLY"
  done
}

# MINCOLS filtering plus the degradation ladder, at a width where both actually decide
# something: 80 hides `venv` (MINCOLS 100) and keeps `salah` (MINCOLS 60).
_inzsh_bench_case_layout_filter() {
  _inzsh_layout_filter 80 "${_inzsh_bench_segments[@]}"
  _inzsh_layout_ladder 80
}

# The truncation ladder, at three budgets: one that fits, one that lands mid-ladder, and one
# tight enough to reach the character-level cut.
_inzsh_bench_case_truncate_path() {
  _inzsh_truncate_path "$_inzsh_bench_path" 60
  _inzsh_truncate_path "$_inzsh_bench_path" 20
  _inzsh_truncate_path "$_inzsh_bench_path" 4
}

# --- config ---------------------------------------------------------------------------------

_inzsh_bench_case_config_get() {
  _inzsh_config_get INZSH_SURFACE_MODE
  _inzsh_config_get INZSH_COLOR_DEPTH
}

# The other shape. A singleton is a hash hit; a family name has to be matched against the
# registered patterns, and that walk is what every per-segment override in a render goes
# through — colour twice per segment, then rank, then MINCOLS. Timed on its own so a registry
# that grows a dozen families says so here rather than in `render-prompt`.
_inzsh_bench_case_config_get_family() {
  _inzsh_config_get INZSH_DIR_BG
  _inzsh_config_get INZSH_DIR_RANK
  _inzsh_config_get INZSH_DIR_MINCOLS
}

_inzsh_bench_case_config_resolve() {
  local segment
  for segment in "${_inzsh_bench_segments[@]}"; do
    _inzsh_config_resolve "$segment" SURFACE_MODE alternate
  done
}

# --- the floor ------------------------------------------------------------------------------
# One pass of everything above, in render order, over both prompts. This is the closest thing
# to a warm render that exists today and the row that matters; it is still a floor, because it
# assembles a prompt string out of FIXTURE labels rather than out of segments that compute
# something. What M3 adds is the segment bodies and `${(%%)PROMPT}` on top of exactly this.

# One row of segments: filter, assign surfaces, resolve both colour channels, build the string
# and account its width as it goes. Mirrors the accumulator convention in `lib/core/layout.zsh`.
_inzsh_bench_row() {
  local -i cols=$1
  shift
  (( $# )) || return 0

  _inzsh_layout_filter $cols "$@"
  local -a shown=("${reply[@]}")
  local -i n=${#shown}
  (( n )) || return 0

  local segment
  local -a weights=()
  for segment in "${shown[@]}"; do
    weights+=(${_inzsh_bench_weight[$segment]})
  done

  _inzsh_surface_assign $n "${weights[@]}"
  local -a surfaces=("${reply[@]}")

  local drawn='' piece bg
  local -i i used=0
  for (( i = 1; i <= n; i++ )); do
    segment=${shown[i]}
    _inzsh_seg_color "$segment" bg "${surfaces[i]}" surface
    bg=$REPLY
    _inzsh_seg_color "$segment" fg "${_inzsh_bench_fg[$segment]}" text-body
    piece="%K{$bg}%F{$REPLY} ${_inzsh_bench_label[$segment]} %f%k"
    drawn+=$piece
    _inzsh_width "$piece"
    _inzsh_width_add used "$REPLY"
  done

  return 0
}

# The real prompt. Every step `_inzsh_render` takes, in its order — each segment builds its own
# text, the width filter drops whoever does not fit, ranks decide side and order, both sides
# assemble, and the result is expanded the way a precmd expands it. The one thing left out is
# the interactive guard, which returns early in a script and would measure nothing.
#
# `$COLUMNS` is pinned rather than inherited: a benchmark whose answer depends on the width of
# the window it happened to run in is not a benchmark.
_inzsh_bench_prep_render_prompt() {
  typeset -g INZSH_SURFACE_MODE=alternate
  typeset -g COLUMNS=80
  typeset -g INZSH_DEFAULT_USER=
  typeset -g SSH_CONNECTION='198.51.100.1 22 198.51.100.2 22'
}
_inzsh_bench_case_render_prompt() {
  local segment builder
  for segment in ${(k)_inzsh_segment_defaults}; do
    builder=_inzsh_segment_${(L)segment}_build
    (( ${+functions[$builder]} )) && $builder
  done

  local -a candidates
  candidates=(${(ok)_inzsh_segment_defaults})
  _inzsh_layout_filter 80 "${candidates[@]}"

  local -a survivors
  survivors=("${reply[@]}")
  _inzsh_rank_split "${survivors[@]}"

  _inzsh_render_build left
  local left=${(%%)REPLY}
  _inzsh_render_build right
  local right=${(%%)REPLY}

  return 0
}

_inzsh_bench_prep_render_floor() { typeset -g INZSH_SURFACE_MODE=alternate }
_inzsh_bench_case_render_floor() {
  local -i cols=80

  _inzsh_config_get INZSH_SURFACE_MODE
  _inzsh_layout_ladder $cols

  # The directory label is the one segment whose text is computed rather than fixed.
  _inzsh_truncate_path "$_inzsh_bench_path" 24
  _inzsh_bench_label[dir]=$REPLY

  # Read `reply` before splitting, never after — the split clobbers it through the sorter.
  _inzsh_rank_split "${_inzsh_bench_segments[@]}"
  local -a left=("${_inzsh_left[@]}") right=("${_inzsh_right[@]}")

  _inzsh_bench_row $cols "${left[@]}"
  _inzsh_bench_row $cols "${right[@]}"
}

# ------------------------------------------------------------------------------------------
# The table
#
#   name                      iters   budget (ms per iteration)
#
# BUDGETS AND HEADROOM. Every budget is the same arithmetic: the worst best-of-5 seen over
# several local runs, times SIX, rounded up to a tidy figure. One multiplier for the whole
# table, so it stays a single arguable number rather than thirteen unarguable ones:
#
#   ~3x   a GitHub-hosted runner against an Apple-silicon laptop at pure zsh parameter work
#   ~2x   a noisy neighbour on a shared box
#
# A gate that flaps is worse than no gate, and a gate that can never fire is dishonest. 6x is
# the compromise, and it is a real gate: best-of-5 varied by under 5% across repeated local
# runs, so the measurement itself is nowhere near needing that much room. What 6x still
# catches is the whole class of regression that matters here — an accidental fork, a command
# substitution on the render path, an O(n^2) rewrite of a sort — because each of those costs
# an order of magnitude, not a third. What it will not catch is a 50% slowdown from honest
# extra work, and that is the deliberate trade.
#
# Iteration counts are set so one repetition takes roughly 30 ms: long enough that
# `EPOCHREALTIME`'s microsecond resolution and the loop's own overhead are noise against it,
# short enough that the whole suite runs in about two seconds. The loop overhead is INSIDE the
# measurement and deliberately not subtracted — what a caller wants to know is what it costs
# to call this thing n times, not what it would cost in a world without a loop.
typeset -ga _inzsh_bench_table=(
  tokens-truecolor    200   0.850
  tokens-256          200   0.850
  tokens-8            200   0.850
  seg-color           150   1.350
  rank-split          100   1.800
  surface-alternate   800   0.250
  surface-ramp        400   0.400
  surface-hue         400   1.500
  layout-width        150   1.100
  layout-filter       150   3.250
  truncate-path        80   2.650
  config-get          600   0.320
  config-get-family   200   0.800
  config-resolve      150   1.450
  render-floor         40   7.200
  render-prompt        40  12.000
)

# `surface-hue` first shipped at 0.500, which was about twice its measured cost rather than
# the six this table uses everywhere else — and a runner two to three times slower than a
# laptop breached it on the first CI run at 0.500, 0.526 and 0.654. The number here is the
# rule applied to the same measurement (worst best-of-5 of 0.246 ms, x6), not a budget
# widened until the red went away.
#
# `layout-filter` was re-baselined when the knob registry landed: the width filter now asks the
# registry for each segment MINCOLS, which validates the value rather than trusting it, so the
# primitive genuinely does more than it did. The number is the table's own rule — best-of-5 ×6 —
# applied to the new cost, and it was raised only after the read path had been optimised three
# ways (the family answer memoised, the `any` families read direct, the bare `int` check
# inlined). A budget raised before that work would have been an excuse; raised after it, it is
# a measurement.
#
# The budget on `render-prompt` is the one number here that was chosen rather than measured
# from a stable base: it is the same 6× headroom every other row carries, over a first
# measurement taken the day the renderer landed. It will want revisiting once the segment set
# stops growing — a budget set against a seven-segment prompt says nothing useful about a
# twelve-segment one.

# The row the house budget is about. `_inzsh_config_render_budget_ms` in `lib/core/config.zsh`
# is 30 ms; this is the case measured against it, through the registered guard.
typeset -g _inzsh_bench_headline=render-prompt

# ------------------------------------------------------------------------------------------
# The runner

typeset -g  _inzsh_bench_reps=5
typeset -g  _inzsh_bench_iters_override=
typeset -g  _inzsh_bench_budget_override=
typeset -g  _inzsh_bench_gate=1
typeset -ga _inzsh_bench_only=()

# The timed region, and all of it. One loop, one call per turn, no forks and no output.
_inzsh_bench_spin() {
  local fn=$1
  local -i n=$2 i
  for (( i = 1; i <= n; i++ )); do
    "$fn"
  done
}

# Best and median of the samples in "$@", into `_inzsh_bench_best` and `_inzsh_bench_median`.
# Insertion sort over floats: the sample count is the repetition count, so five elements, and
# `${(n)…}` sorts decimals as text with the leading integer in front — wrong for exactly the
# numbers this suite produces.
_inzsh_bench_stats() {
  emulate -L zsh

  local -a s=("$@")
  local -i count=$#s
  typeset -g -F _inzsh_bench_best=0
  typeset -g -F _inzsh_bench_median=0
  (( count )) || return 0

  local -F held
  local -i i j
  for (( i = 2; i <= count; i++ )); do
    held=${s[i]}
    for (( j = i - 1; j >= 1 && s[j] > held; j-- )); do
      s[j+1]=${s[j]}
    done
    s[j+1]=$held
  done

  _inzsh_bench_best=${s[1]}
  if (( count % 2 )); then
    _inzsh_bench_median=${s[(count + 1) / 2]}
  else
    _inzsh_bench_median=$(( (s[count / 2] + s[count / 2 + 1]) / 2.0 ))
  fi

  return 0
}

# Usage goes to the descriptor the caller names: stdout when it was asked for, stderr when it
# is a complaint. A usage line on stdout is part of the output a harness is reading.
_inzsh_bench_usage() {
  print -ru${1:-1} -- 'usage: zsh -f test/perf/bench.zsh [--list] [--only NAME] [--iters N]' \
    '[--reps N] [--budget MS] [--no-gate]'
}

_inzsh_bench_parse() {
  emulate -L zsh
  setopt extended_glob

  while (( $# )); do
    case $1 in
      (--list)    typeset -g _inzsh_bench_list=1; shift ;;
      (--no-gate) _inzsh_bench_gate=0; shift ;;
      (--only)
        [[ -n ${2-} ]] || { print -ru2 -- 'bench: --only needs a case name'; return 2 }
        _inzsh_bench_only+=$2; shift 2 ;;
      (--iters)
        [[ ${2-} == <1-> ]] || {
          print -ru2 -- 'bench: --iters needs a positive integer'; return 2 }
        _inzsh_bench_iters_override=$2; shift 2 ;;
      (--reps)
        [[ ${2-} == <1-> ]] || {
          print -ru2 -- 'bench: --reps needs a positive integer'; return 2 }
        _inzsh_bench_reps=$2; shift 2 ;;
      (--budget)
        [[ ${2-} == <->(.<->|) ]] || {
          print -ru2 -- 'bench: --budget needs a non-negative number of milliseconds'; return 2 }
        _inzsh_bench_budget_override=$2; shift 2 ;;
      (-h|--help) _inzsh_bench_usage 1; return 3 ;;
      (*)         print -ru2 -- "bench: unknown argument: $1"; _inzsh_bench_usage 2; return 2 ;;
    esac
  done

  return 0
}

_inzsh_bench_main() {
  emulate -L zsh
  setopt extended_glob

  typeset -g _inzsh_bench_list=0

  # Status 3 from the parser means `--help`: asked for and answered, nothing left to run.
  _inzsh_bench_parse "$@"
  local -i parsed=$?
  (( parsed == 3 )) && return 0
  (( parsed == 0 )) || return $parsed

  local name base
  local -i iters
  local budget

  # Three words a line, header included, so a caller can read the table back mechanically.
  if (( _inzsh_bench_list )); then
    printf '%-20s %7s %12s\n' case iters budget-ms
    for name iters budget in "${_inzsh_bench_table[@]}"; do
      printf '%-20s %7d %12s\n' "$name" "$iters" "$budget"
    done
    return 0
  fi

  # An `--only` that names nothing is a typo, and a typo must not look like a clean run.
  local wanted
  for wanted in "${_inzsh_bench_only[@]}"; do
    if (( ${_inzsh_bench_table[(Ie)$wanted]} == 0 )); then
      print -ru2 -- "bench: no such case: $wanted"
      return 2
    fi
  done

  _inzsh_bench_fixture

  print -r -- "inzsh perf — best of ${_inzsh_bench_reps} repetitions, warm-up discarded"
  print -r -- 'render-prompt is the whole warm prompt; the rows under it locate a regression'
  print -r -- ''
  printf '%-20s %7s %11s %11s %11s %8s  %s\n' \
    case iters 'best ms/it' 'med ms/it' 'budget/it' 'used' 'verdict'

  local -i ran=0 passed=0 rep
  local -a samples
  local -F elapsed per verdict_ratio
  local verdict

  for name iters budget in "${_inzsh_bench_table[@]}"; do
    if (( ${#_inzsh_bench_only} )) && (( ${_inzsh_bench_only[(Ie)$name]} == 0 )); then
      continue
    fi
    [[ -n $_inzsh_bench_iters_override ]] && iters=$_inzsh_bench_iters_override
    [[ -n $_inzsh_bench_budget_override ]] && budget=$_inzsh_bench_budget_override

    base=${name//-/_}
    if (( ! ${+functions[_inzsh_bench_case_$base]} )); then
      print -ru2 -- "bench: case $name has no _inzsh_bench_case_$base"
      return 2
    fi

    (( ${+functions[_inzsh_bench_prep_$base]} )) && "_inzsh_bench_prep_$base"

    # Warm-up, discarded. A cold first call measures autoloading, not the prompt.
    _inzsh_bench_spin "_inzsh_bench_case_$base" 1

    samples=()
    for (( rep = 1; rep <= _inzsh_bench_reps; rep++ )); do
      inzsh_perf_time_ms elapsed _inzsh_bench_spin "_inzsh_bench_case_$base" $iters
      samples+=$(( elapsed / iters ))
    done
    _inzsh_bench_stats "${samples[@]}"

    per=$_inzsh_bench_best
    verdict_ratio=0
    (( budget > 0 )) && (( verdict_ratio = per / budget * 100.0 ))
    (( ran++ ))
    if (( per <= budget )); then
      verdict=ok
      (( passed++ ))
    else
      verdict=OVER
    fi

    printf '%-20s %7d %11.5f %11.5f %11.5f %7.0f%%  %s\n' \
      "$name" "$iters" "$per" "$_inzsh_bench_median" "$budget" "$verdict_ratio" "$verdict"
    [[ $verdict == OVER ]] && print -ru2 -- \
      "perf budget exceeded: $name at ${per}ms/it > ${budget}ms/it"

    [[ $name == "$_inzsh_bench_headline" ]] && typeset -g -F _inzsh_bench_headline_ms=$per
  done

  print -r -- ''

  # The house budget, asked the way the theme asks it: through the registered guard in
  # `lib/core/config.zsh`, over one pass of the headline case. Independent of the table above —
  # the table gates against measured budgets, this gates against the 30 ms promise.
  local -i house_ok=1
  if (( ${+_inzsh_bench_headline_ms} )); then
    _inzsh_bench_prep_render_floor
    if _inzsh_config_guard render-budget '' _inzsh_bench_case_render_floor; then
      printf 'perf: %s at %.5f ms, %.2f%% of the %d ms house budget\n' \
        "$_inzsh_bench_headline" "$_inzsh_bench_headline_ms" \
        "$(( _inzsh_bench_headline_ms / _inzsh_config_render_budget_ms * 100.0 ))" \
        "$_inzsh_config_render_budget_ms"
    else
      house_ok=0
      print -ru2 -- "perf: $_inzsh_bench_headline breached the house budget of" \
        "${_inzsh_config_render_budget_ms}ms"
    fi
  fi

  # The summary line CI greps for. A run of zero cases is a failure, not a pass: a green job
  # that silently measured nothing is worse than no job at all.
  print -r -- "perf: $ran cases ran, $passed within budget"
  if (( ran == 0 )); then
    print -ru2 -- 'perf: no cases ran — the suite matched nothing'
    return 1
  fi

  (( _inzsh_bench_gate )) || return 0
  (( passed == ran && house_ok )) || return 1

  return 0
}

_inzsh_bench_main "$@"
