#!/usr/bin/env zsh
# Every spec file must contribute at least one example.
#
# WHY THIS EXISTS. A spec file that fails to PARSE is already caught: the run aborts and
# shellspec exits non-zero. A file that parses but whose structure is broken is not — an
# unclosed quote in a `Describe`, or an apostrophe inside a single-quoted `zsh -c` string,
# leaves a file that loads fine and defines nothing. The suite then reports zero failures and
# exits zero, and the examples that file used to carry are simply gone.
#
# That is not hypothetical: it happened while the git worker was being wired in, and breaking
# one `Describe` was measured removing 301 examples from a green run. A dropping count is only
# noticed by someone who happened to read the last one. This turns it into a failure.
#
# The check is a set comparison, not a count: a file on disk that names no example is the bug,
# whatever the reason. Adding a spec file therefore needs no bookkeeping here.
emulate -L zsh
setopt err_exit no_unset pipe_fail extended_glob

typeset -g _inzsh_guard_root=${${(%):-%x}:A:h:h}
cd -- $_inzsh_guard_root

typeset -a dirs
dirs=("$@")
(( $#dirs )) || dirs=(test/unit test/render)

typeset -a specfiles
specfiles=(${^dirs}/**/*_spec.sh(N))
if (( ! $#specfiles )); then
  print -ru2 -- "spec-guard: no spec files under ${dirs[*]} — nothing to guard, which is itself wrong"
  exit 1
fi

# Asked file by file, with `--dry-run`: the structure is loaded and the bodies are not, so a
# file that cannot define its examples says so, and a file that can costs almost nothing.
#
# The whole-suite form is no good here — that is the very thing being guarded against. Run over
# every file at once, a broken one contributes nothing and the summary reports a smaller number
# with no error. One file at a time is what turns silence into an answer.
#
# Run concurrently, because one at a time is half a minute and a check that slow gets skipped.
typeset -g _inzsh_guard_tmp=${TMPDIR:-/tmp}/inzsh-spec-guard.$$
mkdir -p -- $_inzsh_guard_tmp
trap 'rm -rf -- $_inzsh_guard_tmp' EXIT INT TERM

typeset file slot
typeset -i i=0
for file in $specfiles; do
  (( ++i ))
  shellspec --dry-run -- "$file" >$_inzsh_guard_tmp/$i 2>&1 &
done
wait

typeset -a empty
typeset summary count
i=0
for file in $specfiles; do
  (( ++i ))
  summary=$(grep -E '[0-9]+ examples' $_inzsh_guard_tmp/$i 2>/dev/null | tail -1)
  if [[ $summary == *aborted* ]]; then
    empty+="$file (aborted while loading)"
    continue
  fi
  if [[ $summary != *' examples'* ]]; then
    empty+="$file (no summary line)"
    continue
  fi
  # Everything before ` examples`, then the digits at the end of that — the summary arrives
  # wrapped in colour escapes, and a greedy match would read the last digit of a count alone.
  count=${summary%% examples*}
  count=${count##*[^0-9]}
  if [[ -z $count ]] || (( count == 0 )); then
    empty+="$file (defines no examples)"
  fi
done

if (( $#empty )); then
  print -ru2 -- 'spec-guard: these files ran no examples — a spec that runs nothing passes for'
  print -ru2 -- 'the wrong reason:'
  for file in $empty; do
    print -ru2 -- "  $file"
  done
  exit 1
fi

print -r -- "spec-guard: ${#specfiles} spec files, every one defines at least one example"
