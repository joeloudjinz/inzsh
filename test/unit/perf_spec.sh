Include tools/perf.zsh

# The perf harness and the suite built on it. Two groups, and the split matters: the harness is
# pure and is tested directly; the suite is a script, is tested by running it, and every example
# that runs it either pins a NUMBER-FREE property or overrides the budget outright.
#
# No example here asserts that something was fast. A unit suite that gates on wall-clock time
# fails on a loaded laptop for a reason that is not the code's, and this file runs in the same
# job as 850 other examples. Timing verdicts belong to the `perf` CI job, which is the only
# place a measured budget is a verdict.

Describe 'perf harness'
  It 'writes elapsed milliseconds into the named variable'
    measure() { inzsh_perf_time_ms elapsed : && (( elapsed >= 0 )); }
    When call measure
    The status should be success
  End

  # The variable is chosen by the caller, so the name in the signature is not privileged.
  It 'writes into whichever variable it was named'
    measure() { inzsh_perf_time_ms inzsh_spec_took : && print -r -- "${inzsh_spec_took:+set}"; }
    When call measure
    The output should equal 'set'
  End

  # Arguments after the function name are the function's, not the harness's.
  It 'forwards its arguments to the command it times'
    record() { typeset -g inzsh_spec_seen="$*"; }
    measure() { inzsh_perf_time_ms elapsed record one two three; print -r -- "$inzsh_spec_seen"; }
    When call measure
    The output should equal 'one two three'
  End

  # Not "it was fast" — "it measured something at all". A harness that always answered zero
  # would pass every budget forever, which is the failure this example exists for.
  It 'measures the work rather than answering a constant'
    spin() { local -i i; for (( i = 1; i <= 20000; i++ )); do :; done; }
    measure() { inzsh_perf_time_ms elapsed spin && (( elapsed > 0 )); }
    When call measure
    The status should be success
  End

  It 'passes a trivial command within a generous budget'
    When call inzsh_perf_assert_budget 1000 :
    The status should be success
  End

  It 'fails when the budget is exceeded'
    When call inzsh_perf_assert_budget 0 :
    The status should be failure
    The stderr should include 'budget'
  End

  # The diagnostic has to carry both numbers or a red CI log says nothing actionable.
  It 'names the elapsed time and the budget when it fails'
    When call inzsh_perf_assert_budget 0 :
    The status should be failure
    The stderr should include 'ms > '
  End

  It 'forwards its arguments through the budget check too'
    record() { typeset -g inzsh_spec_seen="$*"; }
    measure() { inzsh_perf_assert_budget 1000 record four five; print -r -- "$inzsh_spec_seen"; }
    When call measure
    The output should equal 'four five'
  End

  # A budget check answers about TIME. The command's own status is not its business — a caller
  # that cares about both asks twice. Pinned because it is surprising, not because it is ideal.
  It 'judges time rather than the timed command status'
    When call inzsh_perf_assert_budget 1000 false
    The status should be success
  End

  # Both entry points run on a render path one day, where a leaked `start` or `elapsed` would
  # land in whatever scope called them.
  It 'leaves no scratch variables behind in the caller'
    leaks() {
      inzsh_perf_time_ms elapsed :
      inzsh_perf_assert_budget 1000 :
      print -r -- "${+budget}${+start}${+end}${+__out}${+__start}${+__end}"
    }
    When call leaks
    The output should equal '000000'
  End
End

Describe 'perf suite'
  # The table is the whole point of the file: a case that is not in it is not gated, and an
  # entry with a missing function or a missing budget is a case that silently never ran.
  #
  # `bench.zsh` refuses a single-byte locale by design — a width measured in bytes is not a
  # measurement — so every example that runs it is skipped there. Every invocation below is
  # `zsh -f -i` for the reason the next example pins.
  Skip if 'the benchmark refuses a single-byte locale' inzsh_spec_bytes_not_cells

  # THE PRECONDITION THAT KEEPS THE GATE HONEST. The headline row calls `_inzsh_render`, and
  # `_inzsh_render` returns early in a shell that is not interactive — so a suite run from a
  # script would time that early return, read a hundredth of a millisecond, and pass every budget
  # having drawn nothing. A green run that measured nothing is the one outcome a gate may never
  # produce, so the suite refuses the shell rather than reporting the number. Pinned here because
  # `make perf` passing `-i` is a line in a Makefile, and a line in a Makefile is not a promise.
  It 'refuses to benchmark from a shell that is not interactive'
    When run command zsh -f test/perf/bench.zsh --only render-prompt --iters 1 --reps 1
    The status should be failure
    The stderr should include 'interactive'
    The stdout should equal ''
  End

  It 'lists a table with at least one case in it'
    When run command zsh -f -i test/perf/bench.zsh --list
    The status should be success
    The output should include 'render-floor'
  End

  It 'gives every listed case a positive iteration count and a budget'
    inzsh_spec_table_sane() {
      # Three words a line, header included, so the whole listing is one flat word list.
      local -a fields=(${=$(zsh -f -i test/perf/bench.zsh --list)})
      (( ${#fields} > 3 && ${#fields} % 3 == 0 )) || return 1
      local -i i
      for (( i = 4; i <= ${#fields}; i += 3 )); do
        [[ ${fields[i + 1]} == <1-> ]] || return 1
        [[ ${fields[i + 2]} == <->.<-> ]] || return 1
      done
      return 0
    }
    When call inzsh_spec_table_sane
    The status should be success
  End

  It 'has a case function behind every name in the table'
    inzsh_spec_cases_defined() {
      zsh -f -i test/perf/bench.zsh --iters 1 --reps 1 --no-gate >/dev/null
    }
    When call inzsh_spec_cases_defined
    The status should be success
  End

  # The gate, proved rather than asserted: an impossible budget must turn a green run red.
  It 'exits non-zero when a case breaches its budget'
    When run command zsh -f -i test/perf/bench.zsh --only surface-alternate --iters 20 --reps 1 \
      --budget 0
    The status should be failure
    The stderr should include 'perf budget exceeded'
    The stdout should include 'OVER'
  End

  # The contract between the suite and `.github/workflows/ci.yml`: the CI job's no-silent-skip
  # guard greps for this exact shape, so the pattern lives in a test rather than only in YAML.
  It 'prints the summary line the CI skip-guard greps for'
    inzsh_spec_summary_guard() {
      zsh -f -i test/perf/bench.zsh --only surface-alternate --iters 20 --reps 1 --no-gate |
        grep -Eq '^perf: [1-9][0-9]* cases ran'
    }
    When call inzsh_spec_summary_guard
    The status should be success
  End

  It 'refuses a case name it does not have'
    When run command zsh -f -i test/perf/bench.zsh --only no-such-case
    The status should be failure
    The stderr should include 'no such case'
  End

  It 'refuses an argument it does not understand'
    When run command zsh -f -i test/perf/bench.zsh --faster
    The status should be failure
    The stderr should include 'unknown argument'
    The stderr should include 'usage:'
    The stdout should equal ''
  End

  # Usage asked for is usage on stdout, and it runs nothing.
  It 'answers --help without benchmarking anything'
    When run command zsh -f -i test/perf/bench.zsh --help
    The status should be success
    The stdout should include 'usage:'
    The stdout should not include 'cases ran'
  End
End
