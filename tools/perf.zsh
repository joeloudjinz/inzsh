# Perf harness — EPOCHREALTIME timing and the 30 ms render budget.
# Wired into CI at M2, per the milestone plan.

# Run "$@" and write elapsed milliseconds into the named variable.
#   inzsh_perf_time_ms elapsed some_function arg…
inzsh_perf_time_ms() {
  emulate -L zsh
  zmodload zsh/datetime
  local __out=$1; shift
  local -F __start=$EPOCHREALTIME
  "$@"
  local -F __end=$EPOCHREALTIME
  typeset -g -F "$__out"=$(( (__end - __start) * 1000.0 ))
}

# Fail (status 1) when running "$@" exceeds the budget.
#   inzsh_perf_assert_budget <budget_ms> some_function arg…
inzsh_perf_assert_budget() {
  emulate -L zsh
  zmodload zsh/datetime
  local -F budget=$1; shift
  local -F start=$EPOCHREALTIME
  "$@"
  local -F end=$EPOCHREALTIME
  local -F elapsed=$(( (end - start) * 1000.0 ))
  if (( elapsed > budget )); then
    print -u2 -- "perf budget exceeded: ${elapsed}ms > ${budget}ms"
    return 1
  fi
}
