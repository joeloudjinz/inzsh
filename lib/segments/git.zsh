# InZsh — the git segment. Which branch, and what state the work is in.
#
# THE RULE THIS FILE EXISTS TO KEEP. `git status` is the one measured bottleneck in a prompt: it
# walks the index and the worktree, and on a network filesystem or a repository with a hundred
# thousand files it can take seconds. It is also the only thing that can answer the question.
# So the segment NEVER RUNS GIT. It renders a status association that somebody else filled, and
# `lib/segments/git-async.zsh` is the somebody — a background job whose answer lands in a cache
# and repaints the prompt when it arrives. Getting this backwards is not a slow prompt, it is a
# prompt that hangs while you are typing into it.
#
# Everything below is therefore parameter expansion and arithmetic. No `$(`, no backtick, no
# `git`, no `[[ -d ]]`, no file read of any kind. `test/render/segment_git_spec.sh` asserts that
# structurally, over the text of this file, because a fork that only happens on somebody else's
# mount is a fork no test run of ours would ever see.
#
# ---------------------------------------------------------------------------------------------
# WHAT IT DRAWS
#
#   <glyph> <ref>[ <divergence>]
#
# The glyph comes first, the way `lib/segments/retval.zsh` puts `✕` before the status: the state
# is the news and the ref is the subject, and the eye reads the leftmost thing first.
#
#   ✓ main            clean, in step with the upstream
#   ! main            the worktree has changes that are not staged
#   i main            changes are staged and the worktree is clean
#   ✓ main ↑2         two commits the upstream has not got
#   ✓ main ↓3         three commits we have not got
#   ✓ main ↑2↓3       both — the histories have diverged
#   ✓ — a1b2c3d       HEAD is at a commit rather than on a branch
#
# WHY A GLYPH AND NOT ONLY A COLOUR. Every state carries a mark as well as a role, so the
# segment reads in monochrome, in a screenshot, in a terminal with eight colours, and for a
# reader who cannot separate two hues. That is the house rule and it is not negotiable — but it
# has a second effect worth naming: the divergence counts ARE the signal for ahead and behind,
# so those two states need no colour of their own and do not take one.
#
# THE MARKS. `✓` `i` `!` and `—` are from the design system's sanctioned set. The two arrows
# are not, and they are a deliberate addition: a direction has to be drawn as a direction, and
# there is no mark in the set that says "upstream" or "the other way". They are the most
# restrained thing that works — one glyph, one number, no separator, no words.
#
# THE ROLE LADDER, most urgent first, first match wins:
#
#   dirty     negative       work exists that is not even staged; losing it is losing typing
#   staged    info-text      work is prepared. Informational — nothing is wrong, something is
#                            pending
#   detached  caution-text   a commit made here belongs to no branch and is easy to lose
#   diverged  caution-text   two histories that both moved; the next push or pull is a decision
#   clean     positive-text  nothing to report
#
# Only one role can be registered per segment, so a repository that is BOTH dirty and detached
# takes `negative` — and still draws `— <sha>`, because the em dash is not the colour. That is
# the rule paying for itself: precedence costs a hue, never a fact.
#
# ---------------------------------------------------------------------------------------------
# Registration.
#
# `typeset -gA` over an existing association keeps what is in it, so this file is independently
# sourceable and re-sourcing re-registers over the same keys rather than doubling anything. The
# maps belong to `lib/core/engine.zsh` and `lib/core/render.zsh`.
#
#   rank 3        left prompt, after the user and the directory. The repository is a property of
#                 the directory, so it reads directly after it.
#   importance 2  the middle of the ramp. The directory is the row's SUBJECT and takes the top;
#                 this is a report about it. `alternate` and `flat` ignore importance entirely,
#                 and under `ramp` the middle is also what keeps this segment from fighting the
#                 directory beside it for the same surface.
#   fg text-body  the RESTING role, and the one that is registered at load. The build rewrites
#                 the entry per state from the ladder above — see `_inzsh_segment_git_build`.
#   bg text-body's own fill, likewise rewritten per state. This is the only segment whose
#                 background moves while the shell is running, and it moves because its colour is
#                 the one thing on the row that is genuinely about the moment: a clean tree is
#                 green, a dirty one madder, a staged one ink-blue, a detached head ochre. Read
#                 only by `INZSH_SURFACE_MODE=hue` — see `_inzsh_render_hues`.
typeset -gA _inzsh_segment_text _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role _inzsh_segment_bg_role _inzsh_segment_importance _inzsh_segment_priority

_inzsh_segment_defaults[GIT]=50
_inzsh_segment_fg_role[GIT]=text-body
_inzsh_segment_bg_role[GIT]=surface-deep
_inzsh_segment_importance[GIT]=2
_inzsh_segment_priority[GIT]=40

# ---------------------------------------------------------------------------------------------
# The glyphs, taken from the token layer's glyph table — `_inzsh_glyph` in
# `lib/core/tokens.zsh` — which is where every glyph the theme draws now lives. The locals
# below are a read of that table, not a second copy of it: the byte spellings, the ASCII
# register and the locale switch are all decided there, once, for the separators, the ellipsis,
# the failure mark and these six alike.
#
# The fallbacks after `:-` are for a segment sourced without a token layer — a half-assembled
# bundle, or a spec that Includes this file alone. They keep the segment drawable rather than
# letting it emit an empty mark, and they are ASCII because a file that has no table has no
# answer about the locale either.
typeset -g _inzsh_git_glyph_clean=${_inzsh_glyph[ok]:-v}
typeset -g _inzsh_git_glyph_dirty=${_inzsh_glyph[warn]:-!}
typeset -g _inzsh_git_glyph_staged=${_inzsh_glyph[info]:-i}
typeset -g _inzsh_git_glyph_detached=${_inzsh_glyph[dash]:--}
typeset -g _inzsh_git_glyph_ahead=${_inzsh_glyph[ahead]:-+}
typeset -g _inzsh_git_glyph_behind=${_inzsh_glyph[behind]:--}

# How many columns the ref may take before it is elided. Branch names are as long as whoever
# named the ticket felt like — `feature/PROJ-1187-rewrite-the-importer` is a real shape — and
# a prompt that gives half its row to one is a prompt that has stopped being a prompt.
#
# Registered as a knob rather than a constant so a wide terminal can raise it. `0` means no
# limit, which is why the validator's floor is 0 rather than 1.
if (( ${+functions[_inzsh_config_register]} )); then
  _inzsh_config_register INZSH_GIT_BRANCH_MAX 'int:0:200' 24
fi

# The registered default, restated here so the segment still elides sensibly when
# `lib/core/config.zsh` is not loaded — a bundle sourced out of order, a spec that loads this
# file on its own. Same reason `lib/segments/time.zsh` keeps `_inzsh_time_format_default`.
typeset -gi _inzsh_git_branch_max_default=24

# The status association the build reads when it is given no name. `lib/segments/git-async.zsh`
# fills it from the cache; declared here so a shell that never loaded the async half reads an
# empty map — which the build already treats as "no repository" — rather than an error.
typeset -gA _inzsh_git_status

# `$1` as a count, in REPLY, or 0. Digits and nothing else: no sign, no spaces, no float. A
# field that is not a number is not a count, and the segment draws 0 rather than drawing
# whatever a corrupt cache put there.
#
# REPLY is assigned as a STRING, deliberately. `typeset -gi REPLY` would make the shell's shared
# reply parameter an integer for the rest of the session, and the next function to write a name
# into it — `_inzsh_truncate_text`, three lines below the caller — would silently get a 0.
_inzsh_git_count() {
  emulate -L zsh

  typeset -g REPLY=0
  [[ $1 == <-> ]] && REPLY=$1

  return 0
}

# `_inzsh_segment_git_build [state-assoc-name]` → `_inzsh_segment_text[GIT]`, and the role for
# the state into `_inzsh_segment_fg_role[GIT]`.
#
# THE ARGUMENT IS THE INJECTION SEAM. It NAMES an association — the name, not the contents, so a
# spec builds `local -A pinned=(repo 1 branch main …)` and calls `_inzsh_segment_git_build
# pinned` without a repository existing anywhere. With no argument the source is
# `_inzsh_git_status`, which the async half wrote. Nothing in this function reaches for state of
# its own under any circumstance.
#
# THE ASSOCIATION'S SHAPE. Every key is optional and every one has a safe reading when it is
# missing, so a cache written by an older version degrades rather than breaks:
#
#   repo       1 when this is a repository. ANYTHING ELSE, INCLUDING MISSING, MEANS ABSENT —
#              this is the "not a repository" case, and the whole segment is the empty string.
#   branch     the branch name. Empty means detached.
#   sha        the commit id. Abbreviated here, not by the writer, so the width is ours.
#   detached   1 when HEAD is not on a branch. Also inferred from an empty branch with a sha.
#   dirty      how many paths the worktree changed
#   untracked  how many paths git does not track
#   conflicts  how many paths are unmerged
#   staged     how many paths the index changed
#   ahead      commits the upstream has not got
#   behind     commits we have not got
#
# `dirty`, `untracked` and `conflicts` are three columns of one question — is there work here
# that is not committed — and they are added together into one `!`. Splitting them would be
# three marks for one fact, and the fact the prompt is answering is "can I switch branches".
#
# BOTH roles are written on EVERY build, including the absent one, so a repository that went
# clean does not keep the colour of the last one that was not. The background is the FILL twin of
# the foreground — `positive-text` and `positive` are the same statement at two elevations, and
# the DS names them that way — so the two can never disagree about what state the tree is in.
#
# Always status 0: an unreadable state is an absent segment, never an error and never a prompt
# that fails to draw.
_inzsh_segment_git_build() {
  emulate -L zsh
  setopt extended_glob

  # The six marks, re-read from the table on every build so an `INZSH_GLYPH_*` override set at
  # one prompt has moved by the next. The source-time copies above stay as the fallback for a
  # shell with no table at all.
  if [[ ${(t)_inzsh_glyph} == association* ]]; then
    [[ -n ${_inzsh_glyph[ok]} ]]     && typeset -g _inzsh_git_glyph_clean=${_inzsh_glyph[ok]}
    [[ -n ${_inzsh_glyph[warn]} ]]   && typeset -g _inzsh_git_glyph_dirty=${_inzsh_glyph[warn]}
    [[ -n ${_inzsh_glyph[info]} ]]   && typeset -g _inzsh_git_glyph_staged=${_inzsh_glyph[info]}
    [[ -n ${_inzsh_glyph[dash]} ]]   && typeset -g _inzsh_git_glyph_detached=${_inzsh_glyph[dash]}
    [[ -n ${_inzsh_glyph[ahead]} ]]  && typeset -g _inzsh_git_glyph_ahead=${_inzsh_glyph[ahead]}
    [[ -n ${_inzsh_glyph[behind]} ]] && typeset -g _inzsh_git_glyph_behind=${_inzsh_glyph[behind]}
  fi

  typeset -gA _inzsh_segment_text _inzsh_segment_fg_role _inzsh_segment_bg_role
  _inzsh_segment_text[GIT]=
  _inzsh_segment_fg_role[GIT]=text-body
  _inzsh_segment_bg_role[GIT]=surface-deep

  # `${(P)}` on something that is not an identifier is a fatal error mid-render, the same trap
  # `_inzsh_mincols_of` guards in `lib/core/layout.zsh`. A name that cannot form a variable is
  # read as no state at all.
  local src=${1:-_inzsh_git_status}
  [[ $src == [A-Za-z_][A-Za-z0-9_]# ]] || return 0

  # Copied through a flat array first. `${(Pkv)}` on a SCALAR yields one element, and a
  # one-element assignment to an association is a fatal `odd number of elements` — so the count
  # is checked before the map is built rather than after.
  local -a flat
  flat=("${(@Pkv)src}")
  (( ${#flat} && ${#flat} % 2 == 0 )) || return 0

  local -A state
  state=("${flat[@]}")

  [[ ${state[repo]-} == 1 ]] || return 0

  # ------------------------------------------------------------------------------------------
  # The ref. A branch name, or the abbreviated commit behind the detached marker.
  #
  # Control characters are stripped before anything else. git cannot create a ref with one in
  # it, so this is not about git — it is about a cache file that was truncated mid-write or
  # written by something else, and a newline in a prompt fragment breaks the row the renderer
  # just measured.
  local branch=${state[branch]-}
  branch=${branch//[[:cntrl:]]/}

  local sha=${state[sha]-}
  [[ $sha == [0-9a-f](#c4,64) ]] || sha=
  sha=${sha[1,7]}

  local -i detached=0
  [[ ${state[detached]-} == 1 ]] && detached=1
  [[ -z $branch && -n $sha ]] && detached=1

  local ref=$branch
  (( detached )) && ref=$sha

  # An unborn branch — `git init` with no commit yet — has a branch and no sha, and draws as
  # the branch. A detached HEAD with no readable sha has nothing left to name, and a segment
  # with nothing to say says nothing.
  [[ -n $ref ]] || return 0

  # The ladder in `lib/core/layout.zsh` owns eliding, so this asks rather than cuts. Looked up
  # at call time, like `lib/segments/dir.zsh` does: without the layout layer the ref draws whole,
  # which is a longer prompt and never no prompt.
  local -i cap=$_inzsh_git_branch_max_default
  if (( ${+functions[_inzsh_config_get]} )); then
    _inzsh_config_get INZSH_GIT_BRANCH_MAX
    [[ $REPLY == <-> ]] && cap=$REPLY
  fi
  if (( cap > 0 )) && (( ${+functions[_inzsh_truncate_text]} )); then
    _inzsh_truncate_text "$ref" $cap
    ref=$REPLY
  fi
  [[ -n $ref ]] || return 0

  (( detached )) && ref="$_inzsh_git_glyph_detached $ref"

  # ------------------------------------------------------------------------------------------
  # The state. Counts first, then the ladder, so the glyph and the role are chosen from the same
  # three booleans and cannot disagree.
  local -i changed=0 staged=0 ahead=0 behind=0

  _inzsh_git_count "${state[dirty]-}";     (( changed += REPLY ))
  _inzsh_git_count "${state[untracked]-}"; (( changed += REPLY ))
  _inzsh_git_count "${state[conflicts]-}"; (( changed += REPLY ))
  _inzsh_git_count "${state[staged]-}";    staged=$REPLY
  _inzsh_git_count "${state[ahead]-}";     ahead=$REPLY
  _inzsh_git_count "${state[behind]-}";    behind=$REPLY

  local glyph=$_inzsh_git_glyph_clean
  local role=positive-text

  if (( changed )); then
    glyph=$_inzsh_git_glyph_dirty
    role=negative
  elif (( staged )); then
    glyph=$_inzsh_git_glyph_staged
    role=info-text
  elif (( detached )); then
    role=caution-text
  elif (( ahead && behind )); then
    role=caution-text
  fi

  # The divergence, drawn after the ref and never instead of it. No separator between the two
  # counts: `↑2↓3` is one fact about one branch, and a space would read as two.
  local divergence=
  (( ahead ))  && divergence+="$_inzsh_git_glyph_ahead$ahead"
  (( behind )) && divergence+="$_inzsh_git_glyph_behind$behind"
  [[ -n $divergence ]] && divergence=" $divergence"

  # `%` doubled LAST, over the finished fragment. The fragment is spliced into PROMPT and prompt
  # expansion runs over it, so a branch called `100%` would otherwise open an escape and eat the
  # character after it. `_inzsh_width` already reads `%%` as the one column it draws, and the
  # eliding above has already happened, so no `%%` can be cut in half.
  local text="$glyph $ref$divergence"
  _inzsh_segment_text[GIT]=${text//'%'/'%%'}
  _inzsh_segment_fg_role[GIT]=$role

  # The fill twin, spelled off the text role rather than tabulated beside it: the DS's five slots
  # per state are `X`, `on-X`, `X-text`, `X-wash`, `X-edge`, so stripping `-text` turns the ink
  # into the fill it belongs to and `negative` — which the ladder above names without the suffix,
  # because on a surface the fill IS the right ink for a failure — is already the fill. A second
  # table here would be a second place the state ladder is written down, and the copy that drifts
  # is always the one further from the ladder.
  _inzsh_segment_bg_role[GIT]=${role%-text}

  return 0
}
