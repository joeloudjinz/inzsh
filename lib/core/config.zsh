# InZsh — the configuration layer. Everything the user is allowed to change passes through
# here, and it exists to make one promise keepable: options change how the prompt LOOKS, and
# nothing a user can type may stop it from drawing.
#
# Three ideas, in the order they matter.
#
#   The registry.  Every knob is declared once — name, validator, default — in
#   `_inzsh_config_defaults` and `_inzsh_config_validators`. A knob that is not in the registry
#   has no default to fall back to, so declaring it is not paperwork: it is the fallback.
#   `test/unit/config_registry_spec.sh` reads the tree back and fails on a knob that is read
#   anywhere and declared nowhere, so "declared once" is a gate rather than a habit.
#
#   Validate, then fall back.  A value that fails its validator is not an error and is never
#   reported; it is simply not used. `INZSH_SURFACE_MODE=chartreuse` draws an `alternate`
#   prompt, the same as a typo in a colour depth draws the detected one. This is the pattern
#   `lib/core/detect.zsh` and `lib/core/render.zsh` already follow by hand; this file is that
#   habit written down once so every later knob inherits it for free.
#
#   Read at render time.  Nothing here caches a user's value. `_inzsh_config_get` reads the
#   live variable on every call, so `INZSH_SURFACE_MODE=flat` at a prompt takes effect at the
#   NEXT prompt, with no re-source and no new shell. The registry is the only thing built at
#   source time, and it holds no user data.
#
# The precedence rule, everywhere: per-segment override → semantic role → default.
# `_inzsh_config_resolve` is that sentence as code. It generalises what `_inzsh_seg_color`
# already does for colour, including its one subtlety — an override that is SET BUT EMPTY
# counts as UNSET, because an `INZSH_DIR_BG=` left behind in a zshrc must fall through to the
# role rather than blank the segment. Emptiness means "no opinion" at every level here.
#
# Two SHAPES of knob, because the tree has two.
#
#   Singletons.  One name, one meaning — `INZSH_SURFACE_MODE`, `INZSH_GIT_TIMEOUT`. Registered
#   by name with `_inzsh_config_register`.
#
#   Families.  `INZSH_<SEGMENT>_RANK` is not a name, it is a SHAPE: every segment that exists
#   and every segment that ever will has one, and a registry that had to list them would be a
#   registry a new segment could not join without editing this file. So the PATTERN is
#   registered — `INZSH_*_RANK` — with one validator and one default, and a concrete name
#   resolves against it. `INZSH_SALAH_OFFSET_*` is the other one.
#
# Where a knob is declared follows where it is read: `lib/core/` knobs are registered at the
# foot of this file, a segment registers its own beside the code that reads it (see
# `lib/segments/git.zsh`), and a module that may not call this file at all ships a declaration
# table this file absorbs — see "Declaration tables" below.
#
# No forks: this layer sits on the render path, so it is parameter operations and arithmetic
# only.

# The registry. `typeset -gA` on an existing array keeps what is in it, so re-sourcing the
# theme re-registers over the same entries rather than resetting them.
typeset -gA _inzsh_config_defaults
typeset -gA _inzsh_config_validators

# The same pair for families, keyed by the pattern rather than by a name.
typeset -gA _inzsh_config_family_defaults
typeset -gA _inzsh_config_family_validators

# The families in the order they are matched: most literal first, so the first pattern that
# matches a name is the most specific one that could and the walk stops there. Rebuilt on
# registration, which happens at source time; the render path only ever reads it.
typeset -ga _inzsh_config_family_order

# --------------------------------------------------------------------------------------------
# Validators
#
# The grammar is deliberately tiny — five forms, no expressions, no callbacks. A validator that
# could run arbitrary code would be a fork on the render path waiting to happen.
#
#   any            any non-empty value
#   bool           true false yes no on off 1 0, in any case
#   int            an optionally signed run of digits
#   int:MIN:MAX    an int within inclusive bounds; either bound may be empty for unbounded
#   enum:a|b|c     exactly one of the listed alternatives, case-sensitive
#
# An EMPTY value fails every form. That is the "empty means unset" rule stated once, at the
# bottom, so no caller has to remember it.

# Is `$1` a validator spec this file understands? Registry hygiene: a misspelled spec is a bug
# in the theme, not in the user's config, and `_inzsh_config_register` refuses it out loud.
_inzsh_config_spec_valid() {
  emulate -L zsh

  local spec=$1 rest bound
  case $spec in
    (any|bool|int) return 0 ;;
    (enum:?*)      return 0 ;;
    (int:*:*)
      rest=${spec#int:}
      for bound in ${rest%%:*} ${rest#*:}; do
        [[ -z $bound || $bound == (|-|+)<-> ]] || return 1
      done
      return 0
      ;;
  esac

  return 1
}

# The workhorse: does value `$2` satisfy spec `$1`? An unrecognised spec accepts nothing, so a
# registry typo degrades to "always fall back to the default" rather than to "never validate".
_inzsh_config_check() {
  emulate -L zsh

  local spec=$1 value=$2
  [[ -n $value ]] || return 1

  local -a allowed
  local rest min max
  case $spec in
    (any)  return 0 ;;
    (bool) [[ ${(L)value} == (true|false|yes|no|on|off|1|0) ]] && return 0 ;;
    (int)  [[ $value == (|-|+)<-> ]] && return 0 ;;

    (enum:*)
      allowed=(${(s:|:)spec#enum:})
      (( ${allowed[(Ie)$value]} )) && return 0
      ;;

    (int:*:*)
      [[ $value == (|-|+)<-> ]] || return 1
      rest=${spec#int:}
      min=${rest%%:*}
      max=${rest#*:}
      [[ -z $min ]] || (( value >= min )) || return 1
      [[ -z $max ]] || (( value <= max )) || return 1
      return 0
      ;;
  esac

  return 1
}

# --------------------------------------------------------------------------------------------
# Resolving a name against the registry
#
# Every lookup below answers for a family as readily as for a name, so a caller never has to
# know which shape the knob it is holding has. That is the whole point of resolving the pattern
# here rather than at each read site: `_inzsh_mincols_of` asks for `INZSH_DIR_MINCOLS` and is
# answered, without knowing that nothing under that name was ever registered.

# Rebuild `_inzsh_config_family_order`: every registered pattern, longest first. Length is
# specificity — a pattern carries one wildcard, so the longer one spells more of the name out —
# and the order is what lets the lookup stop at its first match instead of scanning for a better
# one. Ties are broken by name, so the walk is deterministic whatever order registration ran in.
#
# Called from registration only. The padded key is built and thrown away here rather than on the
# render path, which is the whole point of keeping the order in a variable.
_inzsh_config_family_reorder() {
  emulate -L zsh

  local -a ranked
  local pattern
  local -i len

  for pattern in ${(k)_inzsh_config_family_validators}; do
    len=${#pattern}
    ranked+=("${(l:4::0:)len} $pattern")
  done

  typeset -ga _inzsh_config_family_order
  _inzsh_config_family_order=(${${(O)ranked}#* })

  return 0
}

# The most specific registered family matching `$1`, in REPLY; empty when none does. The walk
# is over the ordered list above, so the first hit is the answer.
_inzsh_config_family_of() {
  emulate -L zsh

  typeset -g REPLY=
  local pattern

  for pattern in $_inzsh_config_family_order; do
    if [[ $1 == ${~pattern} ]]; then
      typeset -g REPLY=$pattern
      return 0
    fi
  done

  return 0
}

# The validator spec for knob `$1`, in REPLY: its own if it was registered by name, its
# family's if it matches one, empty if the registry has never heard of it.
_inzsh_config_spec_of() {
  emulate -L zsh

  typeset -g REPLY=${_inzsh_config_validators[$1]-}
  [[ -n $REPLY ]] && return 0

  _inzsh_config_family_of "$1"
  [[ -n $REPLY ]] && typeset -g REPLY=${_inzsh_config_family_validators[$REPLY]}

  return 0
}

# The registered default for knob `$1`, in REPLY, by the same ladder. An empty answer covers
# both "registered with no default" and "not registered", which read the same to a caller: there
# is nothing to fall back to.
_inzsh_config_default_of() {
  emulate -L zsh

  if (( ${+_inzsh_config_defaults[$1]} )); then
    typeset -g REPLY=${_inzsh_config_defaults[$1]}
    return 0
  fi

  _inzsh_config_family_of "$1"
  [[ -n $REPLY ]] && typeset -g REPLY=${_inzsh_config_family_defaults[$REPLY]}

  return 0
}

# Public form of the check: is `$2` a value knob `$1` may take? Status 0 or 1, nothing printed.
# A knob that was never registered has no opinion, so it validates as `any` — the config system
# never blocks a value it was not told about.
#
# REPLY is clobbered — `_inzsh_config_spec_of` answers there — so read it before validating.
_inzsh_config_validate() {
  emulate -L zsh

  _inzsh_config_spec_of "$1"
  _inzsh_config_check "${REPLY:-any}" "$2"
}

# Declare a knob: `_inzsh_config_register INZSH_SURFACE_MODE 'enum:alternate|ramp|flat' alternate`
#
# Idempotent — the same call twice lands on the same registry, and a later call with different
# arguments replaces the earlier one, which is what makes re-sourcing safe.
#
# Three ways to be refused, all of them theme bugs rather than user ones: a name that is not a
# public `INZSH_` variable, a spec this file does not understand, and a default that fails its
# own validator. An EMPTY default is allowed and means "no default" — the knob's absence is
# meaningful to whoever reads it, as with `INZSH_COLOR_DEPTH`, where nothing set means the
# detected depth wins.
_inzsh_config_register() {
  emulate -L zsh

  local knob=$1 spec=$2 default=$3

  [[ $knob == INZSH_?* && $knob != *[^A-Z0-9_]* ]] || return 1
  _inzsh_config_spec_valid "$spec" || return 1
  [[ -z $default ]] || _inzsh_config_check "$spec" "$default" || return 1

  _inzsh_config_validators[$knob]=$spec
  _inzsh_config_defaults[$knob]=$default

  return 0
}

# Declare a family: `_inzsh_config_register_family 'INZSH_*_MINCOLS' int:0: 0`
#
# The pattern carries exactly one `*`, standing for the part the user chooses — a segment name,
# a prayer name — and the rest is literal. Everything else is `_inzsh_config_register`'s rules,
# for the same reasons.
#
# `INZSH_*` itself is refused. A family that matches every knob in the theme would silently
# become the default answer for names nobody declared, which is precisely the invisibility this
# registry exists to end; a family has to spell out what it is a family OF.
_inzsh_config_register_family() {
  emulate -L zsh

  local pattern=$1 spec=$2 default=$3

  [[ $pattern == INZSH_?* && $pattern != *[^A-Z0-9_*]* ]] || return 1
  [[ ${#${pattern//[^*]/}} == 1 ]] || return 1
  [[ ${pattern//\*/} != INZSH_ ]] || return 1
  _inzsh_config_spec_valid "$spec" || return 1
  [[ -z $default ]] || _inzsh_config_check "$spec" "$default" || return 1

  _inzsh_config_family_validators[$pattern]=$spec
  _inzsh_config_family_defaults[$pattern]=$default
  _inzsh_config_family_reorder

  return 0
}

# --------------------------------------------------------------------------------------------
# Declaration tables
#
# A module that may not call this file still has knobs, and a knob nobody declared is a knob
# nobody can find. `lib/salah/` is the case: it imports nothing from the engine — that is what
# lets the prayer maths be tested standalone against a fixture oracle — so it cannot call
# `_inzsh_config_register` even guardedly.
#
# So the declaration is turned around. The module ships a flat array named
# `_inzsh_<module>_knobs`, three words per knob — name, spec, default, with a name containing a
# `*` registered as a family — and this file absorbs it wherever both are loaded. The table is
# DATA: a module that declares one and is sourced on its own is a module carrying an array
# nothing reads, and NOTHING IN IT NAMES THIS FILE — not even the `_inzsh_config_` prefix, which
# `test/unit/salah_calc_spec.sh` refuses to find anywhere in `lib/salah/`. Discovery here is by
# parameter name, so this file names no module either. The coupling is the convention, in both
# directions, and it is the only thing crossing the line.
#
# Absorbing is idempotent, because registration is.

# Absorb the table named `$1`. Status 1 if the name is not a readable table or if any triple in
# it was refused — a malformed declaration is a bug in the module, and it says so.
_inzsh_config_absorb() {
  emulate -L zsh
  setopt local_options extended_glob

  local table=$1
  [[ $table == [A-Za-z_][A-Za-z0-9_]# ]] || return 1
  (( ${+parameters[$table]} )) || return 1

  local -a triples
  triples=("${(@P)table}")
  (( ${#triples} && ${#triples} % 3 == 0 )) || return 1

  local -i i failed=0
  for (( i = 1; i <= ${#triples}; i += 3 )); do
    if [[ ${triples[i]} == *\** ]]; then
      _inzsh_config_register_family "${triples[i]}" "${triples[i+1]}" "${triples[i+2]}" ||
        (( failed++ ))
    else
      _inzsh_config_register "${triples[i]}" "${triples[i+1]}" "${triples[i+2]}" || (( failed++ ))
    fi
  done

  (( failed == 0 ))
}

# Absorb every declaration table that exists right now. Called by the entry point once the whole
# library is loaded, which is the one moment "both are loaded" is guaranteed to be true.
_inzsh_config_absorb_all() {
  emulate -L zsh

  local table
  local -i failed=0

  for table in ${(ko)parameters[(I)_inzsh_*_knobs]}; do
    _inzsh_config_absorb "$table" || (( failed++ ))
  done

  (( failed == 0 ))
}

# --------------------------------------------------------------------------------------------
# Reading

# The value of knob `$1`, in REPLY. The live variable if it is set, non-empty and valid;
# otherwise the registered default — its own, or its family's.
#
# The name is checked as the VARIABLE it is, not as a knob in the abstract. Callers reading a
# family build the name from a segment name they were handed, and `${(P)}` on something that
# cannot spell a variable is an error mid-render. A name that cannot name a variable simply has
# no value, which is the same guard `_inzsh_mincols_of` already keeps.
#
# Never errors and always returns 0: there is no failure mode a prompt could usefully react to,
# and a caller that has to check a status before drawing is a caller that will forget. A knob
# with a registered default never comes back empty.
_inzsh_config_get() {
  emulate -L zsh

  typeset -g REPLY=
  local knob=$1

  # The identifier test, written without `extended_glob` so that this function needs no
  # `setopt` at all: not empty, does not start with a digit, holds nothing that is not a name
  # character. Same set of names, one option-setting call cheaper per read.
  [[ -n $knob && $knob != [0-9]* && $knob != *[^A-Za-z0-9_]* ]] || return 0

  # Spec and default together, out of ONE lookup. This is the theme's hottest read — every
  # segment asks it twice for colour alone — and asking `_inzsh_config_validate` and then
  # `_inzsh_config_default_of` would walk the families twice for an answer that cannot have
  # changed in between. A knob registered by name is a hash hit and no walk at all.
  local spec=${_inzsh_config_validators[$knob]-}
  local default=${_inzsh_config_defaults[$knob]-}
  if [[ -z $spec ]] && (( ! ${+_inzsh_config_defaults[$knob]} )); then
    _inzsh_config_family_of "$knob"
    if [[ -n $REPLY ]]; then
      spec=${_inzsh_config_family_validators[$REPLY]}
      default=${_inzsh_config_family_defaults[$REPLY]}
    fi
  fi

  # `any` is inlined for the same reason: it is what both colour families are, so the common
  # case must not cost a call to find out that any non-empty value will do.
  local live=${(P)knob}
  if [[ -n $live ]]; then
    if [[ ${spec:-any} == any ]] || _inzsh_config_check "$spec" "$live"; then
      typeset -g REPLY=$live
      return 0
    fi
  fi

  typeset -g REPLY=$default

  return 0
}

# The precedence rule: `_inzsh_config_resolve <SEGMENT> <KNOB-SUFFIX> [role-value]` → REPLY.
#
#   1. the per-segment override — `INZSH_<SEGMENT>_<SUFFIX>`, e.g. INZSH_DIR_SURFACE_MODE
#   2. the role value handed in by the caller — the theme's semantic answer
#   3. the knob itself — `_inzsh_config_get INZSH_<SUFFIX>`, which is the user's global setting
#      when it is valid and the registered default otherwise
#
# Every level is subject to the base knob's validator, so a mistyped per-segment override falls
# through to the role exactly as an unset one does, and set-but-empty is unset at every level.
# Status 1 with an empty REPLY when no level had anything to say — the same shape as
# `_inzsh_seg_color`, so callers treat the two the same way.
_inzsh_config_resolve() {
  emulate -L zsh

  typeset -g REPLY=

  local suffix=${(U)2}
  local knob=INZSH_$suffix
  local var=INZSH_${(U)1}_$suffix

  local override=${(P)var}
  if [[ -n $override ]] && _inzsh_config_validate "$knob" "$override"; then
    REPLY=$override
    return 0
  fi

  if [[ -n $3 ]] && _inzsh_config_validate "$knob" "$3"; then
    REPLY=$3
    return 0
  fi

  _inzsh_config_get "$knob"
  [[ -n $REPLY ]]
}

# --------------------------------------------------------------------------------------------
# Invariant guards
#
# Validation says a value is well-formed. A guard says a whole SITUATION is still safe — the
# properties no configuration may break, whatever it sets. They are predicates and nothing
# else: status 0 or 1, no output, no side effects, so a guard can be asked on the render path.
#
# A guard that cannot answer says no. Its delegate may not be loaded — a partial source, an old
# bundle — and "I could not check" must read as "do not trust this", because the caller's
# response to a failed guard is to fall back to something safe. Refusing to vouch costs a
# fallback; vouching wrongly costs an unreadable prompt.
#
# The registry is open: `_inzsh_config_guard_register <invariant> <function>` adds one, and the
# three below are registered at the foot of this file.
typeset -gA _inzsh_config_guards

# Add or replace an invariant. Idempotent, same as knob registration.
_inzsh_config_guard_register() {
  emulate -L zsh

  [[ -n $1 && -n $2 ]] || return 1
  _inzsh_config_guards[$1]=$2

  return 0
}

# Ask an invariant: `_inzsh_config_guard <invariant> <args…>`. An unknown invariant, or one
# whose function is not loaded, fails — see the note above on refusing to vouch.
_inzsh_config_guard() {
  emulate -L zsh

  local fn=${_inzsh_config_guards[$1]-}
  [[ -n $fn ]] || return 1
  (( ${+functions[$fn]} )) || return 1
  shift

  "$fn" "$@"
}

# Every registered invariant, sorted, in `reply`. Cheap enough for a doctor command to print.
_inzsh_config_guard_names() {
  emulate -L zsh

  typeset -ga reply
  reply=(${(ko)_inzsh_config_guards})

  return 0
}

# Separator visibility. `_inzsh_surfaces_valid` in `lib/core/render.zsh` is the invariant
# written down as code, so this delegates to it rather than restating it — two copies of a
# rule is one copy too many, and the copy that drifts is always the one in the guard.
#
# `render.zsh` is sourced BELOW this file, so the delegate is looked up at call time and never
# at source time; the dependency points downward on paper and does not exist at load.
_inzsh_config_guard_separators() {
  emulate -L zsh

  (( ${+functions[_inzsh_surfaces_valid]} )) || return 1

  _inzsh_surfaces_valid "$@"
}

# Exit-code capture. The contract is positional: `$?` and `$pipestatus` must be read on the
# FIRST line of precmd, because anything running above that — an assignment, a `local`, a
# hook of someone else's — has already replaced them.
#
# The guard is input-driven: hand it the precmd body as one statement per argument and it says
# whether the first statement that does anything captures the status. It owns no hook and reads
# no file, so the hook layer can compose it later against whatever it actually installs, and a
# spec can compose it now against a hostile ordering.
#
# Blank arguments and comments are skipped — they run nothing, so they destroy nothing. An
# ordering with no capture in it at all fails: the contract is not vacuously satisfied by never
# reading the status, it is unmet.
_inzsh_config_guard_exit_capture() {
  emulate -L zsh
  setopt local_options extended_glob

  local statement bare
  for statement in "$@"; do
    bare=${statement##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    [[ $bare == *'$?'* || $bare == *pipestatus* ]] && return 0
    return 1
  done

  return 1
}

# The house render budget, in milliseconds. Not a knob on purpose: configuration may change
# what the prompt looks like, never what it is allowed to cost.
typeset -g _inzsh_config_render_budget_ms=30

# Render budget. `tools/perf.zsh` already owns the timing, so this delegates to
# `inzsh_perf_assert_budget` rather than timing anything itself.
#
#   _inzsh_config_guard render-budget '' _inzsh_render_function args…
#
# The first argument is the budget in milliseconds; empty, or not a positive integer, means the
# house budget. The delegate's diagnostic is swallowed — a guard answers with its status, and a
# check that can run at prompt time may not write to the terminal.
_inzsh_config_guard_budget() {
  emulate -L zsh

  (( ${+functions[inzsh_perf_assert_budget]} )) || return 1
  (( $# >= 2 )) || return 1

  local budget=$1
  shift
  _inzsh_config_check int:1: "$budget" || budget=$_inzsh_config_render_budget_ms

  inzsh_perf_assert_budget "$budget" "$@" 2>/dev/null
}

# Config that survives its own guard: `_inzsh_config_guarded <KNOB> <invariant> <args…>` puts
# the knob's value in REPLY when the invariant holds under it, and the registered default when
# it does not. The candidate value is passed to the guard as its FIRST argument, ahead of
# `<args…>`.
#
# This is the degradation path in one place. Always returns 0 and always leaves REPLY usable —
# a hostile config comes back as the default, not as an error the caller has to handle. The
# candidate is held in a local across the call: a guard is a predicate, but the registry is
# open, and an added one that writes REPLY must not be able to answer the question as well.
_inzsh_config_guarded() {
  emulate -L zsh

  local knob=$1 invariant=$2
  shift 2

  _inzsh_config_get "$knob"
  local candidate=$REPLY

  if _inzsh_config_guard "$invariant" "$candidate" "$@"; then
    typeset -g REPLY=$candidate
  else
    _inzsh_config_default_of "$knob"
  fi

  return 0
}

# --------------------------------------------------------------------------------------------
# The registry itself. Knobs first, then invariants. Both are re-runnable.

_inzsh_config_guard_register separator-visibility _inzsh_config_guard_separators
_inzsh_config_guard_register exit-code-capture    _inzsh_config_guard_exit_capture
_inzsh_config_guard_register render-budget        _inzsh_config_guard_budget

# The families. Four of them, and every one is a knob that belongs to a SEGMENT rather than to
# the theme: whichever segments exist, each has a rank, two colours and a width below which it
# is not worth drawing. Registering the shape rather than the names is what lets a segment
# added at M5 arrive configurable without this file moving.
#
# `INZSH_*_RANK` registers an EMPTY default on purpose. Nothing set is not a missing answer
# there — the segment's own registration in `_inzsh_segment_defaults` is the default, and the
# knob's absence is the instruction to use it. `_BG` and `_FG` do the same for the semantic
# role. `_MINCOLS` is the one with a real default: 0 means "never hide on width alone".
_inzsh_config_register_family 'INZSH_*_RANK'     int      ''
_inzsh_config_register_family 'INZSH_*_BG'       any      ''
_inzsh_config_register_family 'INZSH_*_FG'       any      ''
_inzsh_config_register_family 'INZSH_*_MINCOLS'  int:0:   0

# The knobs `lib/core/` reads. Segments register their own beside the code that reads them, and
# `lib/salah/` declares a table this file absorbs, so what is left here is the engine's own.
#
# The three detection overrides register an EMPTY default for the reason `INZSH_*_RANK` does:
# nothing set is not a missing answer, it is the instruction to trust `lib/core/detect.zsh`.
# `INZSH_SEPARATOR_STYLE`, by contrast, has a real default — `arrow` is what an unset, empty or
# misspelled value gives.
_inzsh_config_register INZSH_SURFACE_MODE     'enum:alternate|ramp|flat'   alternate
_inzsh_config_register INZSH_SEPARATOR_STYLE  'enum:arrow|round|divider'   arrow
_inzsh_config_register INZSH_COLOR_DEPTH      'enum:truecolor|256|8'       ''
_inzsh_config_register INZSH_MULTIBYTE        'enum:1|0'                   ''
_inzsh_config_register INZSH_NERD_FONT        'enum:1|0'                   ''

# The responsive ladder. `lib/core/layout.zsh` restates these three numbers in
# `_inzsh_ladder_defaults` so that it degrades sensibly when sourced without this file; the two
# copies are held equal by `test/unit/config_registry_spec.sh`.
_inzsh_config_register INZSH_LADDER_FULL_COLS   int:0:  120
_inzsh_config_register INZSH_LADDER_WIDE_COLS   int:0:  80
_inzsh_config_register INZSH_LADDER_NARROW_COLS int:0:  60

# The secondary prompts and the title, from `lib/core/prompts.zsh`. `INZSH_PS2` and
# `INZSH_SPROMPT` replace a whole prompt string verbatim, so their default is empty: there is no
# value that means "the theme's own", there is only not setting them.
_inzsh_config_register INZSH_PS2          any   ''
_inzsh_config_register INZSH_SPROMPT      any   ''
_inzsh_config_register INZSH_TITLE        bool  1
_inzsh_config_register INZSH_TITLE_FORMAT any   '%d %c'
