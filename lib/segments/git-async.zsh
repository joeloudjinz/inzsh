# InZsh — the git status worker. THE ONLY ASYNCHRONOUS CODE IN THIS REPOSITORY, and that is an
# architectural rule rather than a coincidence: `CONVENTIONS.md` names this file by path. If a
# second one ever appears, one of the two is in the wrong place.
#
# It exists because of a single measurement. `git status` is the slowest thing a prompt can ask
# for — it walks the index and stats the worktree — and on a network filesystem, a repository
# with a hundred thousand files, or a lock held by an editor's background fetch, it takes
# SECONDS. A prompt that waited for it would freeze the line you are typing into. So nothing
# waits for it:
#
#   precmd      reads a CACHE. Parameter expansion and one file read, no fork, no git.
#   a job       runs git in the background, off the render path, under a hard timeout.
#   zle -F      wakes the shell when the answer lands, and the prompt is redrawn IN PLACE.
#
# `lib/segments/git.zsh` never learns any of this. It renders an association, and this file is
# what fills it — the same injected-state seam every other segment has, with a background job on
# the far side of it.
#
# ---------------------------------------------------------------------------------------------
# THE CACHE IS KEYED BY `$PWD`, AND THAT IS THE WHOLE DESIGN
#
# The classic bug in an async git prompt: you `cd` from repository A to repository B, the job
# launched in A lands, and B's prompt shows A's branch. It is not a rare race — it is what
# happens every time a job outlives the directory that started it, which on a slow repository is
# every time.
#
# Three things stop it, and all three are needed:
#
#   the key       every cache entry is keyed by the absolute path it describes, so an answer for
#                 A can only ever be read back as an answer for A.
#   the payload   the entry also CONTAINS that path, and a read that finds a different one
#                 treats the entry as a miss. The key is a 32-bit hash; two paths that collide
#                 are improbable and are still handled, rather than being handled by hoping.
#   chpwd         a job in flight is abandoned when the directory changes. Its answer is about
#                 somewhere else and is only ever written into that somewhere else's entry.
#
# ---------------------------------------------------------------------------------------------
# WHY THERE IS NO `lib/core/cache.zsh` UNDER THIS
#
# There is no shared cache layer in the tree yet — `lib/salah/` is listed as growing one, and it
# has not. So the atomic write is HERE, and it is the ordinary one: write a uniquely named
# temporary beside the target and `mv` it over. `mv` within a directory is a rename, and rename
# is atomic, so a reader sees either the whole previous entry or the whole new one and never
# half of either. Two shells refreshing the same directory at the same time write two different
# temporaries and the later rename wins; neither can corrupt what the other is reading. When a
# core cache layer lands, `_inzsh_git_cache_write` and `_inzsh_git_cache_read` are the two
# functions that move.
#
# `zsh/files` supplies `mkdir`, `mv` and `rm` as BUILTINS, so none of the three costs a fork
# even though two of them are reached from precmd. Where the module is missing they fall back to
# the external commands, which is a fork we would rather not make and much better than a cache
# that cannot be written.
#
# Loaded under the module's OWN `zf_` names and never under the bare ones. `zmodload -F
# zsh/files b:rm` would replace the user's `rm` with a reduced implementation for the rest of
# the session — a theme that draws a prompt has no business changing what `rm` means, and
# `zsh/files`'s version does not take `-i`. Global state is the user's.

zmodload -i zsh/datetime 2>/dev/null

typeset -gi _inzsh_git_zf=0
zmodload -F zsh/files b:zf_mkdir b:zf_mv b:zf_rm 2>/dev/null && _inzsh_git_zf=1

# `zsh/system`, for `$sysparams[pid]` — the real pid of whichever fork is asking, where `$$` is
# the pid of the shell that was FIRST started and stays that way through every fork. The job
# below already reached for it inline to publish its own pid; issue #266 moved the load up here
# so the JOB TOKEN can use it too, and so the cost is paid once at source time rather than per
# job. `lib/salah/cache.zsh` carries the long-form reasoning for the whole class.
typeset -gi _inzsh_git_zsys=0
zmodload -i zsh/system 2>/dev/null && _inzsh_git_zsys=1

# The three file operations, builtin where the module loaded and external where it did not. The
# choice is made ONCE, at load, and read as a flag: asking `whence` per call would be a lookup
# per prompt, and trying the builtin and falling through on failure would fork on every genuine
# error as well as every missing module.
_inzsh_git_mkdir() {
  emulate -L zsh
  (( _inzsh_git_zf )) && { zf_mkdir "$@" 2>/dev/null; return $? }
  command mkdir "$@" 2>/dev/null
}

_inzsh_git_mv() {
  emulate -L zsh
  (( _inzsh_git_zf )) && { zf_mv "$@" 2>/dev/null; return $? }
  command mv "$@" 2>/dev/null
}

_inzsh_git_rm() {
  emulate -L zsh
  (( _inzsh_git_zf )) && { zf_rm "$@" 2>/dev/null; return $? }
  command rm "$@" 2>/dev/null
}

# The knobs. Registered through `lib/core/config.zsh` where it is loaded, so a bad value falls
# back to the default rather than reaching a `kill` or a path.
#
#   INZSH_GIT_ASYNC      1 to run the worker at all. 0 makes the segment render whatever is
#                        already cached and never launch anything — the escape hatch for a
#                        machine where a background git is the wrong trade at any timeout.
#   INZSH_GIT_TIMEOUT    seconds before the git call is killed. Two is chosen against the
#                        keystroke, not against git: a status that has not answered in two
#                        seconds will not answer before you have finished typing the next
#                        command either.
#   INZSH_GIT_CACHE_DIR  where the entries live. Under `$XDG_CACHE_HOME` by default because
#                        they are derived data with no value once the repository moves on.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_GIT_ASYNC     'bool'      1
  _inzsh_config_register INZSH_GIT_TIMEOUT   'int:1:60'  2
  _inzsh_config_register INZSH_GIT_CACHE_DIR 'any'       ''
fi

typeset -gi _inzsh_git_timeout_default=2

# In-flight job state. One job per shell at a time — a second would race the first onto the same
# cache entry to no purpose, and a repository slow enough to need one is exactly the repository
# where they would pile up.
#
#   fd     the read end of the job's pipe, registered with `zle -F`. 0 when nothing is running.
#   pwd    the directory the running job was launched for, so its answer is filed correctly and
#          discarded when it is no longer about anywhere we are.
#   pids   the file the job writes its own pid and git's into, for reaping.
#   token  the unique suffix on this job's temporary files.
typeset -gi _inzsh_git_job_fd=0
typeset -g  _inzsh_git_job_pwd=
typeset -g  _inzsh_git_job_pids=
typeset -g  _inzsh_git_job_token=

# The directory the last cache read was for, so precmd can tell a miss from "already loaded".
typeset -g _inzsh_git_loaded_pwd=

# The two maps this file writes into and `lib/segments/git.zsh` reads out of. Declared here as
# well as there — `typeset -gA` keeps what is already in an association — so either file can
# be sourced on its own without creating a plain array by accident under `warn_create_global`.
typeset -gA _inzsh_git_status
typeset -gA _inzsh_segment_text


# ---------------------------------------------------------------------------------------------
# Configuration readers. Each one answers with the registered default when `lib/core/config.zsh`
# is not loaded, so this file works on its own.

# Is the worker allowed to launch? `bool` in the config layer's vocabulary, which is wider than
# 1 and 0 because a user writes `false` and means it.
_inzsh_git_async_enabled() {
  emulate -L zsh

  local value=1
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_GIT_ASYNC
    value=$REPLY
  else
    value=${INZSH_GIT_ASYNC:-1}
  fi

  [[ ${(L)value} == (true|yes|on|1) ]]
}

# The timeout, in whole seconds, in REPLY. Never zero and never negative: a timeout of 0 would
# kill git before it started and a negative one would be handed straight to `sleep`.
_inzsh_git_timeout() {
  emulate -L zsh

  typeset -g REPLY=$_inzsh_git_timeout_default

  local value=
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_GIT_TIMEOUT
    value=$REPLY
  else
    value=${INZSH_GIT_TIMEOUT-}
  fi

  [[ $value == <1-60> ]] && typeset -g REPLY=$value

  return 0
}

# The cache directory, in REPLY, created if it is not there. Status 1 when it cannot be made —
# a read-only home, a `$HOME` that is not set — and every caller treats that as "no cache",
# which degrades to a segment that never appears rather than to an error on the prompt line.
#
# The directory is checked on every call rather than remembered. A remembered answer is wrong
# the moment somebody cleans their cache out from under a running shell, and the check is one
# `stat` on a local path — cheaper than the branch that would avoid it.
_inzsh_git_cache_dir() {
  emulate -L zsh

  typeset -g REPLY=

  local dir=
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_GIT_CACHE_DIR
    dir=$REPLY
  else
    dir=${INZSH_GIT_CACHE_DIR-}
  fi

  if [[ -z $dir ]]; then
    local base=${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}
    [[ -n $base ]] || return 1
    dir=$base/inzsh/git
  fi

  [[ -d $dir ]] || _inzsh_git_mkdir -p -- "$dir" || return 1

  typeset -g REPLY=$dir

  return 0
}

# ---------------------------------------------------------------------------------------------
# Keys and entries

# A filesystem-safe key for path `$1`, in REPLY: FNV-1a, 32 bits, eight lower-case hex digits.
#
# A hash rather than an encoding of the path, for two reasons that both bite in practice. A
# percent-encoded path exceeds `NAME_MAX` on any repository nested more than a few levels down,
# and the encoding has to survive every character a path may legally contain — which on this
# platform is everything except `/` and NUL. Eight hex digits have neither problem, and the
# collision they admit is caught on read by the path stored inside the entry.
#
# The character code is taken through a NAMED parameter — `#c`, never `##${…}`. The literal
# form takes the character that follows it in the SOURCE, so a path with a space or a closing
# parenthesis in it would be an arithmetic syntax error at the worst possible moment.
# Arithmetic and `printf -v` throughout: this is reached from precmd, and precmd does not fork.
_inzsh_git_cache_key() {
  emulate -L zsh

  typeset -g REPLY=

  local s=$1 c
  local -i h=2166136261 i n=${#s}
  for (( i = 1; i <= n; i++ )); do
    c=${s[i]}
    (( h = ((h ^ #c) * 16777619) & 0xFFFFFFFF ))
  done

  printf -v REPLY '%08x' $h

  return 0
}

# The cache entry path for directory `$1`, in REPLY. Status 1 when there is no cache directory.
_inzsh_git_cache_path() {
  emulate -L zsh

  typeset -g REPLY=

  local dir=$1
  [[ -n $dir ]] || return 1

  _inzsh_git_cache_dir || return 1
  local base=$REPLY

  _inzsh_git_cache_key "$dir"
  typeset -g REPLY=$base/$REPLY

  return 0
}

# The entry format: one `key<TAB>value` line each, TAB because it is the one character a git ref
# name may not contain and a value therefore cannot smuggle a field boundary into the file.
# Written by `_inzsh_git_cache_write`, read by `_inzsh_git_cache_read`, and understood nowhere
# else.
typeset -g _inzsh_git_cache_version=1

# `_inzsh_git_cache_write <pwd> <entry-path> <token> <key> <value> …` — the entry, atomically.
#
# The temporary carries the job's token so two shells refreshing the same directory cannot pick
# the same name, and it is created BESIDE the target so the rename is within one filesystem and
# is therefore a rename rather than a copy. A failed write removes its own temporary: a cache
# directory that fills with half-written entries is worse than one that is empty.
_inzsh_git_cache_write() {
  emulate -L zsh

  local pwd_=$1 file=$2 token=$3
  shift 3

  [[ -n $file ]] || return 1

  local tmp=$file.$token.tmp
  local tab=$'\t'

  # TWO nested blocks, and the outer one is the point. A redirection that cannot be OPENED —
  # the cache directory removed out from under a job that is still running — is reported by the
  # shell BEFORE the redirection takes effect, so `{ … } > "$tmp" 2>/dev/null` still writes the
  # diagnostic to wherever stderr was. The outer block silences the inner block's own failure.
  {
    {
      print -r -- "version$tab$_inzsh_git_cache_version"
      print -r -- "pwd$tab$pwd_"
      print -r -- "epoch$tab${EPOCHSECONDS-0}"
      local k v
      for k v in "$@"; do
        print -r -- "$k$tab$v"
      done
    } > "$tmp"
  } 2>/dev/null || {
    _inzsh_git_rm -f -- "$tmp"
    return 1
  }

  _inzsh_git_mv -f -- "$tmp" "$file" || {
    _inzsh_git_rm -f -- "$tmp"
    return 1
  }

  return 0
}

# `_inzsh_git_cache_read [pwd]` — the entry for that directory into `_inzsh_git_status`.
#
# EVERY FIELD IS VALIDATED, and this is the whole of the corrupt-cache story. The file is on
# disk, it outlives the shell that wrote it, it can be truncated by a full filesystem or a
# machine losing power mid-rename, and a user can open it in an editor. So:
#
#   the version must be the one this file writes    — an entry from a future format is a miss
#   the path must be the one being asked about      — a hash collision is a miss
#   every count must be digits                      — anything else reads as 0
#   `repo` must be exactly 1 or 0                   — anything else is a miss
#   the ref loses its control characters            — a newline would break the row
#
# A miss leaves `_inzsh_git_status` EMPTY and returns 1, which the segment already reads as "no
# repository": no block, no separator, nothing on the prompt. Never an error, never a partial
# state, and never a diagnostic — a prompt is not a place to report that a cache file was odd.
#
# No fork: `read` is a builtin and `<` is a redirection. The stat and the open are syscalls, on a
# local cache directory, and they are the only two this file makes on the way to a prompt.
_inzsh_git_cache_read() {
  emulate -L zsh
  setopt extended_glob

  typeset -gA _inzsh_git_status
  _inzsh_git_status=()

  local dir=${1:-$PWD}
  _inzsh_git_cache_path "$dir" || return 1
  local file=$REPLY

  [[ -f $file && -r $file ]] || return 1

  local -A raw
  local line k v
  while IFS= read -r line; do
    [[ $line == *$'\t'* ]] || continue
    k=${line%%$'\t'*}
    v=${line#*$'\t'}
    [[ $k == [a-z][a-z0-9_]# ]] || continue
    raw[$k]=$v
  done < "$file" 2>/dev/null

  [[ ${raw[version]-} == $_inzsh_git_cache_version ]] || return 1
  [[ ${raw[pwd]-} == $dir ]]                          || return 1
  [[ ${raw[repo]-} == (0|1) ]]                        || return 1

  local -A state
  state[repo]=${raw[repo]}

  local field
  for field in dirty untracked conflicts staged ahead behind; do
    state[$field]=0
    [[ ${raw[$field]-} == <-> ]] && state[$field]=${raw[$field]}
  done

  state[detached]=0
  [[ ${raw[detached]-} == 1 ]] && state[detached]=1

  state[branch]=${${raw[branch]-}//[[:cntrl:]]/}
  state[sha]=${${raw[sha]-}//[[:cntrl:]]/}

  state[timeout]=0
  [[ ${raw[timeout]-} == 1 ]] && state[timeout]=1

  state[epoch]=0
  [[ ${raw[epoch]-} == <-> ]] && state[epoch]=${raw[epoch]}

  _inzsh_git_status=("${(@kv)state}")

  return 0
}

# ---------------------------------------------------------------------------------------------
# Parsing
#
# `git status --porcelain=v2 --branch` is ONE invocation that answers every question the segment
# asks: the branch, the commit, whether HEAD is detached, the divergence from the upstream, and
# a line per changed path. That is not a convenience — it is what makes the timeout possible.
# One command is one process, and one process has one pid that a watchdog can kill. A probe made
# of four `git` calls would be four pids, three of which nothing is holding.
#
# The format, as much of it as matters here:
#
#   # branch.oid <sha> | (initial)     the commit, or the marker for a branch with no commits
#   # branch.head <name> | (detached)  the branch, or the marker for a HEAD that is not on one
#   # branch.ab +<n> -<n>              ahead and behind. ABSENT when there is no upstream.
#   1 <XY> …                           a changed path; X is the index column, Y the worktree
#   2 <XY> …                           the same, renamed or copied
#   u <XY> …                           unmerged
#   ? <path>                           untracked
#   ! <path>                           ignored — never emitted, we do not ask for them
#
# `.` in a column means unmodified, so `X != .` is staged and `Y != .` is dirty, and one path
# can legitimately be both.

# `_inzsh_git_parse <raw-file>` — the fields as a flat key/value list, in `reply`.
#
# Reads a file rather than taking the text, because the job wrote the text to a file: capturing
# git's output into a parameter would mean a command substitution, and this function is also
# called from the specs, where a fork in the middle of an assertion is a fork that gets copied.
# Always status 0 and always a complete field list — a raw file that is empty parses as a
# repository with nothing to report, which is what an empty status output means.
_inzsh_git_parse() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga reply
  reply=()

  local file=$1
  local -i staged=0 dirty=0 untracked=0 conflicts=0 ahead=0 behind=0 detached=0
  local branch= sha= line ab a b xy

  while IFS= read -r line; do
    case $line in
      ('# branch.oid '*)
        sha=${line#'# branch.oid '}
        [[ $sha == '(initial)' ]] && sha=
        ;;

      ('# branch.head '*)
        branch=${line#'# branch.head '}
        if [[ $branch == '(detached)' ]]; then
          detached=1
          branch=
        fi
        ;;

      ('# branch.ab '*)
        ab=${line#'# branch.ab '}
        a=${ab%% *}
        b=${ab##* }
        [[ ${a#+} == <-> ]] && ahead=${a#+}
        [[ ${b#-} == <-> ]] && behind=${b#-}
        ;;

      ('# '*)
        ;;

      ([12]' '??' '*)
        xy=${line[3,4]}
        [[ ${xy[1]} == '.' ]] || (( staged++ ))
        [[ ${xy[2]} == '.' ]] || (( dirty++ ))
        ;;

      ('u '*)
        (( conflicts++ ))
        ;;

      ('? '*)
        (( untracked++ ))
        ;;
    esac
  done < "$file" 2>/dev/null

  reply=(
    repo      1
    branch    "$branch"
    sha       "$sha"
    detached  $detached
    staged    $staged
    dirty     $dirty
    untracked $untracked
    conflicts $conflicts
    ahead     $ahead
    behind    $behind
    timeout   0
  )

  return 0
}

# ---------------------------------------------------------------------------------------------
# The job
#
# Runs in a subshell of ours, launched by `<( … )`, so it has every function this file defines
# and none of the shell's terminal. Its stdout is the pipe the parent watches: exactly one byte
# goes down it, at the very end, and everything else — git's output, git's diagnostics, the
# temporaries — goes to files or to `/dev/null`. A stray `print` here would arrive at a `zle -F`
# handler as a status update.
#
# THE TIMEOUT. git is started in the BACKGROUND so that `$!` is git's own pid — zsh runs a
# backgrounded external command directly, with no intervening subshell, which is the whole
# reason the probe is a single `git` invocation. A watchdog child sleeps and then sends it a
# TERM. Whichever finishes first, `wait` returns: 0 for a clean status, 128 for "not a
# repository", and 128+15 for a status that ran out of time. Those three are the only outcomes
# and each has a cache entry.
#
# `--no-optional-locks` is not decoration. Without it `git status` refreshes the index on disk,
# which takes a lock — so a status run from a prompt can block, and can be blocked BY, whatever
# the user is doing in that repository in another window.
#
# THE JOB HAS NO VOICE. Everything the work does is wrapped in one `2>/dev/null`, once here
# rather than at each call site, because the failures that matter are the ones nobody predicted:
# a cache directory removed while the job runs, a `$PWD` deleted between the launch and the
# chdir, a `git` earlier on `$PATH` that writes to stderr for reasons of its own. Any of them
# would otherwise arrive on the terminal of a shell that is drawing a prompt, out of nowhere,
# with no command in front of it to blame.
#
# The wakeup is OUTSIDE the silence, on stdout, which is the pipe the parent watches.
_inzsh_git_async_job() {
  emulate -L zsh
  setopt no_monitor

  _inzsh_git_async_work "$@" 2>/dev/null

  # The wakeup. One byte, and then the pipe closes when this shell exits — the handler fires on
  # either, and the CLOSE is the one that cannot be skipped. A job killed part way through never
  # writes the byte, and a parent that waited for one would wait for a byte that is not coming,
  # with `zle -F` still registered on a descriptor nothing will ever write to.
  print -n x

  return 0
}

# The work itself. Split from the wakeup above so that no failure inside it can stop the parent
# being told the job is over — a shell waiting forever on a descriptor that will never be
# written is a shell whose prompt never updates again.
_inzsh_git_async_work() {
  emulate -L zsh
  setopt no_monitor

  local dir=$1 file=$2 token=$3 pids=$4
  local -i timeout=$5

  local raw=$file.$token.raw

  git -C "$dir" --no-optional-locks status --porcelain=v2 --branch \
    --untracked-files=normal > "$raw" 2>/dev/null &
  local -i gpid=$!

  # Both pids, for the reaper in the parent: line one is this job, line two is git. Written
  # before the wait, because a job that hangs is a job whose pids were never published.
  local -i self=0
  zmodload -i zsh/system 2>/dev/null && self=${sysparams[pid]:-0}
  print -rl -- $self $gpid > "$pids" 2>/dev/null

  # `&!` so the watchdog is disowned: it must not appear in a job table, and nothing waits for
  # it. Both output channels go to `/dev/null` and stdin is CLOSED — a background process that
  # can read the terminal is a background process that will one day steal a keystroke.
  #
  # When git wins the race the watchdog subshell is killed below, and its `sleep` is left to
  # expire on its own. That is deliberate rather than sloppy: without a controlling terminal
  # `setopt monitor` fails, so the watchdog has no process group of its own to kill, and the
  # only alternative is polling — a fork every tenth of a second, on every prompt, to save a
  # `sleep` that holds nothing and is gone within the timeout.
  { sleep $timeout; kill -TERM $gpid } >/dev/null 2>&1 <&- &!
  local -i wpid=$!

  wait $gpid
  local -i rc=$?
  kill -TERM $wpid >/dev/null 2>&1

  local -a fields
  if (( rc == 0 )); then
    _inzsh_git_parse "$raw"
    fields=("${reply[@]}")
  elif (( rc > 128 )); then
    # Killed. There is a repository here — or there may be — and we cannot say anything about
    # it. Recorded as "not a repository" so the segment stays absent, with the timeout flag set
    # so the fact is not lost: an entry that claimed a clean tree here would be a lie about
    # uncommitted work.
    fields=(repo 0 timeout 1)
  else
    # git said no. Not a repository, no git installed, a `$PWD` that no longer exists — all of
    # them are the same answer to the prompt's question, and none of them is an error.
    fields=(repo 0 timeout 0)
  fi

  _inzsh_git_cache_write "$dir" "$file" "$token" "${fields[@]}"

  _inzsh_git_rm -f -- "$raw" "$pids"

  return 0
}

# ---------------------------------------------------------------------------------------------
# The parent side

# Forget the job in flight, killing it and its git if the pids were published. Called on chpwd,
# on shell exit, and by the handler once an answer has been taken.
#
# REAPING ON EXIT IS NOT HOUSEKEEPING. A `git status` blocked on an unreachable NFS mount does
# not care that the shell that asked has gone; it sits in uninterruptible sleep holding the
# mount until the mount answers. Killing it on the way out is the difference between closing a
# terminal and leaving a process behind for every window ever opened in that directory.
#
# Order matters: the handler is removed before the fd is closed, because a `zle -F` registration
# on a closed descriptor is a handler zle will call forever.
_inzsh_git_async_reap() {
  emulate -L zsh

  if (( _inzsh_git_job_fd )); then
    zle -F $_inzsh_git_job_fd 2>/dev/null
    # The close is wrapped in a BLOCK so its `2>/dev/null` belongs to the block and not to the
    # shell. `exec {fd}<&- 2>/dev/null` is `exec` with a redirection and no command, which is
    # the form that redirects the SHELL — permanently, for the rest of the session. Every
    # diagnostic the user would ever have seen would go to `/dev/null`, and the first symptom
    # would be a command that fails without saying why, months later.
    { exec {_inzsh_git_job_fd}<&- } 2>/dev/null
  fi
  _inzsh_git_job_fd=0

  if [[ -n $_inzsh_git_job_pids && -r $_inzsh_git_job_pids ]]; then
    # Nested, for the same reason `_inzsh_git_cache_write` nests: a redirection that cannot be
    # OPENED is reported before the redirection applies, so the file disappearing between the
    # test above and the read here would print to whatever stderr the shell has.
    local pid
    {
      while IFS= read -r pid; do
        [[ $pid == <1-> ]] && kill -TERM $pid 2>/dev/null
      done < "$_inzsh_git_job_pids"
    } 2>/dev/null
    _inzsh_git_rm -f -- "$_inzsh_git_job_pids"
  fi

  _inzsh_git_job_pids=
  _inzsh_git_job_pwd=
  _inzsh_git_job_token=

  return 0
}

# `_inzsh_git_async_start [dir]` — launch a refresh for that directory, at most one at a time.
#
# Status 1 and nothing launched when the worker is disabled, when a job is already running, or
# when there is no cache directory to write into. None of those is an error: the segment simply
# keeps rendering whatever the last answer was, which for a directory that has not changed is
# still true.
_inzsh_git_async_start() {
  emulate -L zsh

  _inzsh_git_async_enabled || return 1
  (( _inzsh_git_job_fd )) && return 1

  local dir=${1:-$PWD}
  [[ -n $dir ]] || return 1

  _inzsh_git_cache_path "$dir" || return 1
  local file=$REPLY

  _inzsh_git_timeout
  local -i timeout=$REPLY

  # Unique per job and per shell: two shells starting a job for the same directory in the same
  # second must not share a temporary.
  #
  # Issue #266. `${EPOCHSECONDS-0}.$$.$RANDOM` did not separate FORKS: `$$` is the pid of the
  # shell that was FIRST started, so every subshell forked from one parent reports it unchanged,
  # and a fork inherits the parent's `$RANDOM` state rather than reseeding — so the draw that
  # would otherwise have broken the tie matches across siblings too. Twenty forks, one token,
  # deterministically. `$sysparams[pid]` is read from the kernel per reference and fixes it.
  #
  # `$EPOCHREALTIME` IS NOT DECORATION, and swapping in the pid alone would trade one collision
  # for another. `$RANDOM` was doing real work that a pid cannot do: separating two jobs started
  # by the SAME process, where the pid is by definition constant. That case is ordinary here —
  # `precmd` fires on every accepted line, an empty one included — so dropping to a bare pid
  # would make sequential jobs in one shell collide where they never used to. Microseconds
  # restore it, and the spec pins both halves separately so a half-fix cannot pass.
  local token
  if (( _inzsh_git_zsys )); then
    token=${EPOCHREALTIME-0}.${sysparams[pid]}
  else
    token=${EPOCHREALTIME-0}.$$.$RANDOM
  fi
  local pids=$file.$token.pid

  local -i fd=0
  # No `2>/dev/null` on this line, and that is not an oversight: `exec` with a redirection and
  # no command applies it to the SHELL, permanently. Silencing a failure here would silence
  # every diagnostic the user's session ever produced afterwards.
  exec {fd}< <( _inzsh_git_async_job "$dir" "$file" "$token" "$pids" "$timeout" )
  (( fd )) || return 1

  _inzsh_git_job_fd=$fd
  _inzsh_git_job_pwd=$dir
  _inzsh_git_job_pids=$pids
  _inzsh_git_job_token=$token

  # The repaint hook. `zle -F` is the only mechanism zsh has for "run this when a descriptor has
  # something on it", and it is what makes the prompt update WITHOUT the user pressing a key.
  # It fails outside an interactive shell, which is fine — `_inzsh_git_async_collect` is the
  # other way in, and it is what the specs and the demos use.
  zle -F $fd _inzsh_git_async_ready 2>/dev/null

  return 0
}

# Take the answer a finished job left: load its entry, rebuild the segment, and say whether the
# prompt changed. Shared by the `zle -F` handler and by the synchronous drain below, so there is
# one definition of "an answer arrived" rather than two that can drift.
#
# Status 0 only when the GIT FRAGMENT IS DIFFERENT from the one already drawn. A repaint costs a
# full render and a screen write; doing it when nothing changed is a flicker for no information.
_inzsh_git_async_collect() {
  emulate -L zsh

  local before=${_inzsh_segment_text[GIT]-}
  local for_=$_inzsh_git_job_pwd

  _inzsh_git_async_reap

  # An answer about a directory we have left is filed, not drawn. It is already in its own cache
  # entry — the job wrote it there — so returning to that directory picks it up.
  [[ -n $for_ && $for_ == $PWD ]] || return 1

  _inzsh_git_cache_read "$PWD"
  _inzsh_git_loaded_pwd=$PWD

  (( ${+functions[_inzsh_segment_git_build]} )) || return 1
  _inzsh_segment_git_build

  [[ ${_inzsh_segment_text[GIT]-} != $before ]]
}

# The `zle -F` handler. Called by zle, in a widget context, when the job's pipe has something on
# it or has closed — which for this job are the same instant.
#
# `zle reset-prompt` is what redraws the line the user is already typing on, in place, with the
# cursor where they left it. Rebuilding PROMPT without it would show the new status only after
# the next Enter, which is the whole thing this file exists to avoid.
_inzsh_git_async_ready() {
  emulate -L zsh

  _inzsh_git_async_collect || return 0

  (( ${+functions[_inzsh_render]} )) && _inzsh_render
  zle reset-prompt 2>/dev/null

  return 0
}

# `_inzsh_git_async_wait [seconds]` — block until the job in flight answers, then take it.
#
# The synchronous door into an asynchronous file, and it exists for two callers that both need
# one: a spec, which has to assert on a status that has actually arrived, and a demo recording,
# which has to render a finished prompt rather than a frame of one. Nothing on the render path
# calls it and nothing ever should.
#
# `read -t` on the job's own pipe, so the wait costs no polling and no forks — the descriptor
# becoming readable IS the job finishing. Status 0 when an answer was taken and the fragment
# changed, matching `_inzsh_git_async_collect`.
_inzsh_git_async_wait() {
  emulate -L zsh

  (( _inzsh_git_job_fd )) || return 1

  local -i limit=5
  [[ ${1-} == <1-> ]] && limit=$1

  local byte
  read -t $limit -k 1 -u $_inzsh_git_job_fd byte 2>/dev/null

  _inzsh_git_async_collect
}

# ---------------------------------------------------------------------------------------------
# Hooks
#
# All three go through `add-zsh-hook`. Assigning `precmd_functions` or `chpwd_functions`
# directly would discard every registration any other plugin had made — the rule
# `lib/core/hooks.zsh` states, applied here rather than restated.

# chpwd. The directory changed, so three things are true at once: the job in flight is about
# somewhere else, the loaded status is about somewhere else, and there may be an answer already
# cached for where we now are.
#
# Loading here rather than only in precmd is what makes `cd` into a repository show its status on
# the FIRST prompt: chpwd runs before precmd, so an entry that already exists is in the map by
# the time the renderer asks for it.
_inzsh_git_async_chpwd() {
  emulate -L zsh

  _inzsh_git_async_reap

  # The status map is NOT emptied here. `_inzsh_git_cache_read` clears it as its first act,
  # whether it goes on to find an entry or not, so a second clear would be a second place the
  # rule "the map describes `$PWD` and nowhere else" is written down — and the copy that drifts
  # is always the one that is not the implementation.
  _inzsh_git_loaded_pwd=

  _inzsh_git_cache_read "$PWD" && _inzsh_git_loaded_pwd=$PWD
  _inzsh_git_async_start "$PWD"

  return 0
}

# precmd. Registered AFTER `_inzsh_precmd`, which is the only order `add-zsh-hook` can produce
# for a file loaded after `lib/core/hooks.zsh` — and it is the order that works, for a reason
# worth writing down: precmd functions all run BEFORE zsh expands PROMPT, so a later hook that
# reassigns PROMPT still reaches this prompt and not the next one.
#
# So the sequence per prompt is: `_inzsh_precmd` renders from the state as it stands, this hook
# loads any newer entry, and the prompt is re-rendered only if that changed the fragment. The
# re-render is the exception rather than the rule — in a repository nothing has changed between
# most pairs of prompts — and the cost when nothing changed is one file read and one segment
# build.
_inzsh_git_async_precmd() {
  emulate -L zsh

  [[ -o interactive ]] || return 0

  local before=${_inzsh_segment_text[GIT]-}

  if [[ $_inzsh_git_loaded_pwd != $PWD ]]; then
    _inzsh_git_cache_read "$PWD"
    _inzsh_git_loaded_pwd=$PWD
  fi

  if (( ${+functions[_inzsh_segment_git_build]} )); then
    _inzsh_segment_git_build
    if [[ ${_inzsh_segment_text[GIT]-} != $before ]] &&
       (( ${+functions[_inzsh_render]} )); then
      _inzsh_render
    fi
  fi

  _inzsh_git_async_start "$PWD"

  return 0
}

# Shell exit. The last chance to kill a git that is still walking somebody's filesystem.
_inzsh_git_async_exit() {
  emulate -L zsh

  _inzsh_git_async_reap

  return 0
}

# Attach. Idempotent by delegation, exactly as `lib/core/hooks.zsh` is: `add-zsh-hook` refuses
# to register a function that is already in the array, so installing twice registers once and
# repairs a registration something else removed.
_inzsh_git_async_install() {
  emulate -L zsh

  [[ -o interactive ]] || return 0

  autoload -Uz add-zsh-hook
  add-zsh-hook precmd  _inzsh_git_async_precmd
  add-zsh-hook chpwd   _inzsh_git_async_chpwd
  add-zsh-hook zshexit _inzsh_git_async_exit

  return 0
}

# Let go, and take the job with us. Unguarded on purpose, like the hook layer's: a shell that
# somehow acquired these must be able to shed them.
_inzsh_git_async_uninstall() {
  emulate -L zsh

  autoload -Uz add-zsh-hook
  add-zsh-hook -d precmd  _inzsh_git_async_precmd
  add-zsh-hook -d chpwd   _inzsh_git_async_chpwd
  add-zsh-hook -d zshexit _inzsh_git_async_exit

  _inzsh_git_async_reap

  return 0
}
