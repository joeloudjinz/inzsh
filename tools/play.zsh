#!/usr/bin/env zsh
# InZsh — the playground launcher. `make play` runs this.
#
# THE SAFETY, WHICH IS THE WHOLE POINT OF A SEPARATE LAUNCHER. This theme draws the prompt you
# are typing into, so work in progress never gets sourced into a shell you were already using.
# What happens instead:
#
#   ZDOTDIR   points at a temporary directory holding one `.zshrc`, so the shell reads OUR
#             startup file and never `~/.zshrc`. Your own configuration is not loaded, not
#             read, and cannot be written to.
#   -d        skips the global startup files (`/etc/zshrc` and friends) as well.
#   temp dir  removed when the shell exits, whatever it exits from.
#
# The result is an ordinary interactive zsh that knows about this theme and nothing else. Break
# it however you like; `exit` and it is gone.

emulate -L zsh
setopt err_exit no_unset

_inzsh_play_root=${0:A:h:h}

# A subprocess, and entirely fine: this is a developer tool, not the render path. The rule about
# forks is about what happens between you pressing return and seeing a prompt.
_inzsh_play_dir=$(mktemp -d "${TMPDIR:-/tmp}/inzsh-play.XXXXXX")

# Quoted so a repository checked out under a path with a space in it still starts.
print -r -- "source ${(q)_inzsh_play_root}/tools/playground.zsh" > $_inzsh_play_dir/.zshrc

# Not `exec`: the shell has to come back here so the directory can be removed. A trap as well as
# the line after it, so an interrupt during startup cleans up too.
trap 'rm -rf -- "$_inzsh_play_dir"' EXIT INT TERM

ZDOTDIR=$_inzsh_play_dir zsh -d -i

rm -rf -- "$_inzsh_play_dir"
