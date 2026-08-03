#!/usr/bin/env zsh
# InZsh — run one VHS tape inside the pinned tape environment. `make demo` drives this.
#
#   zsh tools/tape-run.zsh test/tapes/default.tape
#
# The tape's shell starts with ZDOTDIR pointing at the environment `tools/tape-env.zsh`
# builds and HOME at the fixture root, so the recording shows the fixture — never this
# machine's name, path, or clock. Output lands in demo-out/ (gitignored); committing GIFs
# is #125's business, not this file's.

emulate -L zsh
setopt err_exit no_unset

_inzsh_tape_root=${0:A:h:h}
_inzsh_tape=${1:?usage: tape-run.zsh <tape-file> [fixture-state]}

# VHS resolves the recorded shell's HOME itself, so pinning by env here cannot work. The
# tapes therefore `exec` into the pinned shell from inside the recording (hidden), naming
# this FIXED staging path — fixed so the committed tapes can spell it as a literal. One
# tape renders at a time; `make demo` is a dev tool, not a parallel job.
_inzsh_tape_stage=${${TMPDIR:-/tmp}%/}/inzsh-tape
rm -rf -- $_inzsh_tape_stage
_inzsh_tape_home=$(zsh $_inzsh_tape_root/tools/tape-env.zsh ${2:-dirty})
mv $_inzsh_tape_home $_inzsh_tape_stage
trap 'rm -rf -- "$_inzsh_tape_stage"' EXIT INT TERM

mkdir -p $_inzsh_tape_root/demo-out

vhs $_inzsh_tape < /dev/null
