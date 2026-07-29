Include tools/perf.zsh

Describe 'perf harness'
  It 'writes elapsed milliseconds into the named variable'
    measure() { inzsh_perf_time_ms elapsed : && (( elapsed >= 0 )); }
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
End
