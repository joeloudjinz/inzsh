#!/usr/bin/env zsh
# InZsh — the tape environment. `tools/tape-run.zsh` launches VHS inside this.
#
# A tape is a golden render that moves, so it lives under the golden harness's rules: every
# source of nondeterminism is pinned, through the same seams `tools/golden.py` documents at
# its head — fixture repository, injected clock epoch 978352440 (2001-01-01 12:34 UTC),
# user `spec` via the segment's injection args, host `spec-host` via env, HOME at the fixture
# root so the path draws as `~/work`. One divergence and the two harnesses have drifted;
# `tools/golden.py` is the reference copy.
#
# This file builds a throwaway HOME holding the fixture and a ZDOTDIR rc, prints the
# directory, and leaves cleanup to the caller. Nothing here touches the real $HOME.

emulate -L zsh
setopt err_exit no_unset

_inzsh_tape_root=${0:A:h:h}
_inzsh_tape_state=${1:-dirty}

_inzsh_tape_home=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-tape.XXXXXX")

# The fixture repository, in the requested state, checked out as ~/work.
_inzsh_tape_repo=$(zsh $_inzsh_tape_root/tools/fixture-repo.zsh $_inzsh_tape_state $_inzsh_tape_home)
mv $_inzsh_tape_repo $_inzsh_tape_home/work

# The rc the recorded shell reads. Same pins as the golden snippet, in rc form.
cat > $_inzsh_tape_home/.zshrc <<EOF
unset -m 'INZSH_*' 2>/dev/null
unset -m 'SSH_*' VIRTUAL_ENV 2>/dev/null
export TZ=UTC
export INZSH_HOST_ALWAYS=1
source ${(q)_inzsh_tape_root}/inzsh.zsh-theme
functions[_inzsh_tape_time_build]=\$functions[_inzsh_segment_time_build]
_inzsh_segment_time_build() { _inzsh_tape_time_build 978352440 }
functions[_inzsh_tape_date_build]=\$functions[_inzsh_segment_date_build]
_inzsh_segment_date_build() { _inzsh_tape_date_build 978352440 }
functions[_inzsh_tape_user_build]=\$functions[_inzsh_segment_user_build]
_inzsh_segment_user_build() { _inzsh_tape_user_build spec '' '' }
cd ~/work
clear
EOF

print -r -- $_inzsh_tape_home
