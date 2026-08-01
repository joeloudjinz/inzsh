# InZsh — the background-jobs segment. What is this shell still holding?
#
# The question it answers is the one that catches people out: you suspended an editor with
# Ctrl-Z three commands ago, you have forgotten, and the shell will not let you exit — or worse,
# it will, and the job goes with it. A count on the prompt is the cheapest possible reminder,
# and it costs nothing at all while there is nothing to remind you of.
#
# IT SHIPS OFF, at rank 0, like the rest of the optional set. That is not a contradiction with
# the paragraph above: zsh already warns on exit, most shells hold no jobs most of the time, and
# a segment that is absent 99% of the time still has to be paid for by everyone who reads the
# prompt looking for where it would have been. The people it helps are a known group and they
# get it with one line.
#
# ---------------------------------------------------------------------------------------------
# NO SUBPROCESS, AND NOT A COMMAND SUBSTITUTION EITHER
#
# `jobs | wc -l` is two forks per prompt, and `$(jobs)` is one fork plus a subshell — a subshell
# that, being a child, has an EMPTY job table and would report 0 forever. That second failure is
# the interesting one: the obvious implementation is not slow, it is WRONG, and it is wrong
# silently.
#
# `$jobstates` is the answer instead. It comes from `zsh/parameter`, a MODULE, and it is the
# shell's own job table read directly out of the shell that owns it — an association keyed by
# job number, whose value begins with the job's state:
#
#   1  →  running:+:41234=running
#   2  →  suspended:-:41250=suspended
#
# `${#jobstates}` alone would give the count in one expansion, and it is not enough for the
# reason below. The states are taken from the first colon-separated field of each value, which
# is the job's own state and not any one process's.
#
# ACCURACY, precisely. This is read from precmd, which runs after the foreground command has
# finished and before the prompt is drawn, so what is in the table at that moment is exactly the
# set of jobs the shell is still holding: background jobs it started and jobs the user
# suspended. A job that has finished and not yet been reported reads `done` and is counted as
# neither — it is not something the shell is holding, it is something it is about to tell you
# about on its own.
#
# ---------------------------------------------------------------------------------------------
# WHY TWO NUMBERS RATHER THAN ONE
#
# `2` tells you there are two jobs. It does not tell you the thing you wanted to know, which is
# whether any of them is STOPPED — a running background job needs nothing from you and will
# finish on its own, and a suspended one is waiting for you specifically and is the one that
# blocks an exit. The two facts have different consequences, so they are drawn as two facts:
#
#   i 2        two jobs running in the background
#   — 1        one job suspended
#   i 2 — 1    both
#
# Both come out of the same single pass over the same association, so the extra fact is free —
# which is the whole test for whether it earns its columns.
#
# THE MARKS come from the token layer's glyph table and are read, never invented. `i` is the
# design system's informational mark and this is information: nothing is wrong. `—` is its mark
# for "nothing to report", which is exactly what a suspended job is doing — it is a job that has
# stopped happening. Colour is never the only signal, so the two marks are what separates the
# two counts on a monochrome terminal, where `2 1` would be unreadable.

# `jobstates` lives in `zsh/parameter`. Loaded explicitly rather than relied upon: zsh autoloads
# the module on first access in most builds, and `-i` makes asking twice free, so the explicit
# line costs nothing and removes a question about which builds those are.
zmodload -i zsh/parameter

# Declared, never assigned wholesale — `typeset -gA` over an existing association keeps what is
# in it, so re-sourcing neither empties a map nor doubles a registration, and the declaration is
# what makes this file sourceable on its own.
typeset -gA _inzsh_segment_text _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role _inzsh_segment_importance

# Registration.
#
#   rank 0       hidden until `INZSH_JOBS_RANK` asks for it.
#   info-text    the semantic role. Held jobs are information, not a fault — the segment reports
#                a fact about the shell, and `negative` would make a backgrounded build look
#                like a failed one.
#   importance 3 the bottom of the ramp. It is absent almost always; when it is there it is a
#                reminder rather than the subject of the line.
_inzsh_segment_defaults[JOBS]=0
_inzsh_segment_fg_role[JOBS]=info-text
_inzsh_segment_importance[JOBS]=3

# The two marks, read from `_inzsh_glyph` in `lib/core/tokens.zsh` — where every glyph the theme
# draws lives, with its byte spelling and its ASCII fallback. No literal is invented here and no
# `\u` escape is written: that escape is resolved when the file is PARSED, and outside a
# multibyte locale zsh cannot resolve one and abandons the rest of the file, functions included.
#
# The fallbacks after `:-` are for a segment sourced without a token layer — a half-assembled
# bundle, or a spec that Includes this file alone. They keep the marks drawable rather than
# empty, and they are ASCII because a file with no table has no answer about the locale either.
typeset -g _inzsh_jobs_glyph_running=${_inzsh_glyph[info]:-i}
typeset -g _inzsh_jobs_glyph_suspended=${_inzsh_glyph[dash]:--}

# The live tally, into `_inzsh_jobs_running` and `_inzsh_jobs_suspended`. Named globals rather
# than `reply`, deliberately: `reply` is the channel `_inzsh_rank_split` and `_inzsh_layout_
# filter` answer on, and a build function that clobbered it would be a trap laid for whoever
# reorders the render one day.
#
# One pass, parameter expansion and arithmetic only. An absent module leaves both at 0, which
# the build already reads as "nothing to report" — a job table that cannot be read is a segment
# that is not drawn, never an error.
typeset -gi _inzsh_jobs_running=0
typeset -gi _inzsh_jobs_suspended=0

_inzsh_jobs_tally() {
  emulate -L zsh

  _inzsh_jobs_running=0
  _inzsh_jobs_suspended=0

  (( ${+jobstates} )) || return 0

  local state
  for state in "${(@v)jobstates}"; do
    case ${state%%:*} in
      (running)   (( _inzsh_jobs_running++ ))   ;;
      (suspended) (( _inzsh_jobs_suspended++ )) ;;
    esac
  done

  return 0
}

# `_inzsh_segment_jobs_build [running] [suspended]` — writes `_inzsh_segment_text[JOBS]`.
#
# Both arguments are the injection seam, the same shape `lib/segments/host.zsh` uses: absent
# means "use the live tally", present means "use this". `_inzsh_segment_jobs_build 3` pins the
# running count and leaves the suspended one live, which is what makes the common single-number
# case a single argument.
#
# The tally runs before the arguments are read rather than instead of them. It is one pass over
# an association that is empty in almost every shell, so the branch that would skip it costs
# about what it saves and buys a second way for the two paths to disagree.
#
# A count that is not a count reads as 0 — the segment draws nothing rather than drawing
# whatever was passed. Zero of both is ABSENT: no block, no separator, no `0`. The entry is
# written on every path, so a prompt that hid the block never inherits the previous one's
# number. Always status 0.
_inzsh_segment_jobs_build() {
  emulate -L zsh

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[JOBS]=

  _inzsh_jobs_tally

  local running=${1-$_inzsh_jobs_running}
  local suspended=${2-$_inzsh_jobs_suspended}

  [[ $running == <-> ]]   || running=0
  [[ $suspended == <-> ]] || suspended=0

  local -i r=running s=suspended
  (( r || s )) || return 0

  local text=
  (( r )) && text="$_inzsh_jobs_glyph_running $r"
  if (( s )); then
    [[ -n $text ]] && text+=' '
    text+="$_inzsh_jobs_glyph_suspended $s"
  fi

  # Per cent doubled, as everywhere: the fragment is spliced into PROMPT and prompt expansion
  # runs over it. Nothing here can produce one today — digits and two table glyphs — so this is
  # defence rather than repair.
  _inzsh_segment_text[JOBS]=${text//'%'/'%%'}

  return 0
}
