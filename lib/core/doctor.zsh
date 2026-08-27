# InZsh — the doctor, and the public command it hangs off. A thin formatter over the capability
# detection the theme already runs, printed as one pasteable block, because "paste the output of
# `inzsh doctor`" is what `.github/ISSUE_TEMPLATE/bug.yml` asks a reporter to do.
#
# Nothing here detects anything. Every detector in `lib/core/detect.zsh` is independently
# callable and recomputes from the environment as it is NOW — that was designed in for exactly
# this caller — so the doctor re-asks each question at the moment it prints, and the block
# describes the terminal the user is looking at rather than the one the theme was loaded in.
#
# Two policies other files deferred land here, and only here:
#
#   DETECT-AND-WARN. `lib/core/detect.zsh` refuses to infer that a Nerd Font is absent, and
#   `lib/core/render.zsh` draws the powerline for `unknown` rather than degrading the majority
#   who do have the font. What to TELL the `unknown` user was left to the doctor — so the notes
#   at the foot of the block are that warning, and they are a diagnostic, never a downgrade.
#
#   COORDINATES NEVER LEAVE. The block exists to be pasted into a public issue, and
#   CONTRIBUTING.md asks reporters not to include their position. `lib/salah/location.zsh`
#   writes the PROVENANCE of the resolved position down for this reader — `config`, `cache`,
#   or nothing — and provenance is all the doctor prints. Issue #229 extends the same rule to
#   the prayer TABLE computed from that position: `lib/salah/cache.zsh` answers whether an
#   entry is cached, readable and current in words only — `none`, `stale`, `current` and the
#   rest — never a hash of the recipe. A hash of a position is not a redaction of it: the
#   coordinate space at any precision a person types is smaller than the hash space, so it is a
#   slow but complete encoding, and a stable one, which a raw coordinate at least is not. What
#   the row names instead is the method and Asr school in force — configuration, not position,
#   the same as `TERM` or the locale two rows up.
#
#   THE ROOT IS PRINTED WITH `$HOME` COLLAPSED TO `~`. Issue #245. `_inzsh_theme_root` is a
#   filesystem path, and on every platform this theme installs to, that path very often carries
#   the reporter's own account name — `/Users/jane/dev/inzsh`, `/home/jane/.oh-my-zsh/custom/
#   themes/inzsh` — inside a block whose whole purpose is to sit in a PUBLIC issue. A username is
#   not a coordinate, and this file does not pretend the two carry the same weight: it is not
#   secret, it is often already the reporter's own GitHub handle, and knowing it teaches a
#   maintainer nothing a coordinate would. But it is a piece of somebody's real identity that the
#   theme has no reason to ask them to publish, and the fix costs nothing a debugger would miss —
#   `~/dev/inzsh` says exactly as much about WHERE the checkout lives and HOW it loaded as the
#   raw path would. So the same instinct behind COORDINATES NEVER LEAVE applies one size down: not
#   a redaction, because nothing here is sensitive enough to need one, just the same collapse
#   `install.zsh` already prints every path through for the identical reason.
#
# `inzsh` is the one public command the theme defines; the playground's `inzsh-*` helpers are
# dev tooling and are not sourced by the theme. Subcommands dispatch below, so a later command
# arrives beside `doctor` rather than as a second name in the user's namespace.
#
# Not on the render path — nothing calls any of this per prompt — but it keeps the house rule
# anyway: no subprocesses, parameter expansion and arithmetic only.

# One aligned row of the block: `_inzsh_doctor_row <label> <value>`.
_inzsh_doctor_row() {
  emulate -L zsh

  printf '  %-13s %s\n' "$1" "$2"

  return 0
}

# Is a valid override in force for knob `$1`? The detectors obey a well-formed override and fall
# through on anything else, so this is the same question they asked — answered through the
# registry where it is loaded, and never vouched for where it is not.
_inzsh_doctor_overridden() {
  emulate -L zsh

  local value=${(P)1}
  [[ -n $value ]] || return 1
  (( ${+functions[_inzsh_config_validate]} )) || return 1

  _inzsh_config_validate "$1" "$value"
}

# Edit distance between `$1` and `$2`, in REPLY. Plain Levenshtein — insert, delete, substitute,
# each costing one — with a single generalisation: a literal `*` in `$1` matches a run of ZERO OR
# MORE characters of `$2` for no cost at all, the same as it does as a glob. That is what lets one
# function serve both shapes of registered knob: pass a plain name and it is ordinary Levenshtein;
# pass a family pattern such as `INZSH_*_RANK` and the wildcard absorbs whatever segment name sits
# where it does in the real registry, so a typo in the SEGMENT never counts against the match — a
# typo in `_RANK` itself is the only thing this distance can report for that family.
#
# The wildcard is only honoured in `$1`. A knob name can never contain `*` — it would not pass
# `_inzsh_config_register`'s own identifier check — so `$2` is always a plain string here, and the
# function does not need to reason about a wildcard on both sides at once.
#
# Two rows, `prev` and `cur`, rather than a full table. The one departure from textbook
# Levenshtein is the wildcard row: `dp[i][j] = min(dp[i-1][j], dp[i][j-1])` rather than the usual
# insert/delete/substitute triple, because finishing the wildcard here costs whatever finishing
# everything BEFORE it already cost (`dp[i-1][j]`), or one more character of `$2` absorbed into it
# for free (`dp[i][j-1]`) — never a real edit.
#
# `test/unit/doctor_spec.sh` greps this file for `$(` and a backtick outside a comment, so the
# house rule at the top of this file holds here without restating it.
_inzsh_doctor_distance() {
  emulate -L zsh

  typeset -g REPLY=0
  local a=$1 b=$2
  local -i la=${#a} lb=${#b}

  local -a prev cur
  local -i i j cost del ins sub best
  local ai bj

  prev=(0)
  for (( j = 1; j <= lb; j++ )); do
    prev+=$j
  done

  for (( i = 1; i <= la; i++ )); do
    ai=$a[$i]
    if [[ $ai == '*' ]]; then
      cur=(${prev[1]})
      for (( j = 1; j <= lb; j++ )); do
        best=$(( prev[j+1] < cur[j] ? prev[j+1] : cur[j] ))
        cur+=$best
      done
    else
      # `dp[i][0]` is not always `$i`: that is only true when nothing before position `i` was a
      # wildcard, since every literal character deleted so far costs one. A wildcard earlier in
      # `$a` can have made `dp[i-1][0]` cheaper than `i - 1` for free, and this row must build on
      # THAT, not on the position count — `prev[1]` is `dp[i-1][0]`, so one more deletion is
      # `prev[1] + 1`, which is `$i` exactly when no wildcard preceded and something smaller
      # otherwise.
      cur=($(( prev[1] + 1 )))
      for (( j = 1; j <= lb; j++ )); do
        bj=$b[$j]
        [[ $ai == $bj ]] && cost=0 || cost=1
        del=$(( prev[j+1] + 1 ))
        ins=$(( cur[j] + 1 ))
        sub=$(( prev[j] + cost ))
        best=$del
        (( ins < best )) && best=$ins
        (( sub < best )) && best=$sub
        cur+=$best
      done
    fi
    prev=("${cur[@]}")
  done

  REPLY=${prev[$(( lb + 1 ))]}

  return 0
}

# How close is `$1` allowed to sit to a registered shape before `_inzsh_doctor_near_miss` will
# say so? Two, chosen against the registry a REPORTER actually has — the bug template this block
# exists for (see the top of this file) asks for `inzsh doctor` pasted from the live shell that
# hit the bug, where the whole theme is loaded and every segment has registered its own knobs —
# `INZSH_TIME_FORMAT`, `INZSH_GIT_BRANCH_MAX`, `INZSH_RETVAL_SIGNAL`, `INZSH_DIR_COMPONENTS` and
# the rest, plus the glyph family `INZSH_GLYPH_*`. Sourcing `inzsh.zsh-theme` itself and counting
# comes to 43 names and 7 families today — not against an abstract worst case. (`tools/doctor.zsh`
# loads a narrower slice — config, detect and the salah library, no segments, no token layer — so
# `make doctor` and this file's own test suite both run against 23 names and 6 families; a
# smaller pool the threshold is measured to still hold against, not the one it is chosen for.)
#
#   INZSH_SEPARATOR_STYL   -> INZSH_SEPARATOR_STYLE   distance 1 (one letter short)
#   INZSH_GIT_RANNK        -> INZSH_*_RANK            distance 1 (one letter too many)
#   INZSH_DIR_MINCOL       -> INZSH_*_MINCOLS         distance 1 (one letter short)
#   INZSH_COLOUR_DEPTH     -> INZSH_COLOR_DEPTH       distance 1 (the British spelling)
#
# every one of those is a single slipped key, and 2 leaves room for a transposition (two
# substitutions in plain Levenshtein) without opening the door much wider. `INZSH_MY_OWN_THING`,
# the example the issue asks to stay silent for, sits 10 away from its nearest registered NAME
# (`INZSH_COLOR_DEPTH`) — comes nowhere close. A flat number this small still over-reaches on a
# SHORT name, which `_inzsh_doctor_cap`, right below, exists to bound properly rather than wave
# off.
typeset -g _inzsh_doctor_near_miss_threshold=2

# The flat threshold above is too generous once a candidate's DISCRIMINATING length — what is
# left once `INZSH_` and, for a family, its one `*` are set aside — gets short. Every candidate
# here already starts with `INZSH_` by construction (`_inzsh_doctor_near_misses` only ever calls
# in on names `${(I)INZSH_*}` matched first), so those six characters do no discriminating at
# all; a family's wildcard does none either, since it is credited for swallowing whatever sits
# there for free. `INZSH_*_BG` is left with `_BG`, three characters, to tell it apart from
# anything else. Measured against the real registry: `INZSH_MY_OWN_THING`, the name the issue
# asks to stay silent for, sat exactly 2 from `INZSH_*_BG` under the flat threshold — the
# wildcard swallowed the rest of it for free, and what was left half-rhymed with `_BG` under
# substitution. The same failure reaches PLAIN names too, not only families, once they are this
# short: `INZSH_PS2` is discriminated by `PS2` alone, and `INZSH_SSH`, `INZSH_ZSH`, `INZSH_OS`
# all sat within a flat 2 of it despite naming nothing this theme has ever registered — and
# `INZSH_SSH` is the sharp case, because the theme SHIPS an `ssh` segment, so a user disabling it
# is not a typo of anything, and being told they misspelled `INZSH_PS2` is simply wrong.
#
# So the cap is the SHORTER of the house threshold and half the discriminating length: `_BG` (3
# characters) and `PS2` (3, once the shared prefix is set aside) both cap at 1; `_RANK` (5) and
# most ordinary names stay at the house threshold of 2.
#
# The trade-off this buys is worth stating rather than hiding: a transposition costs 2 in plain
# Levenshtein, so a cap of 1 refuses one — `INZSH_DIR_GB` for `INZSH_DIR_BG`, `INZSH_SP2` for
# `INZSH_PS2`. Measured against the full registry, every miss this cap introduces is exactly that
# shape — a transposed three-character discriminant — and nothing broader. The alternative was a
# demonstrated false positive on a name the theme ships, so this is accepted on purpose: a
# transposed three-letter tail going unreported is a narrower loss than the diagnostic getting a
# user's own segment knob wrong.
_inzsh_doctor_cap() {
  emulate -L zsh

  local -i threshold=${_inzsh_doctor_near_miss_threshold:-2}
  local -i literal=$(( ${#1} - 6 ))
  [[ $1 == *'*'* ]] && (( literal-- ))
  local -i cap=$(( (literal - 1) / 2 ))

  (( cap > threshold )) && cap=$threshold
  typeset -g REPLY=$cap

  return 0
}

# The registered name or family PATTERN closest to `$1`, in REPLY, when it is close enough to be
# worth a guess; status 1 with REPLY empty otherwise. `$1` is never itself a registered knob —
# `_inzsh_doctor_near_misses` only calls this once `_inzsh_config_spec_of` has already said no —
# so every candidate here is a real alternative, never the name confirming itself.
#
# One loop over both shapes of candidate, singleton names and family patterns together, because
# `_inzsh_doctor_distance` and `_inzsh_doctor_cap` already read either kind without being told
# which they were handed — a `*` in the candidate is all the branching either of them needs.
#
# A family's suggestion is the pattern itself — `INZSH_*_RANK`, verbatim — rather than a guessed
# concrete name such as `INZSH_GIT_RANK`. This file cannot know which segment the user meant any
# more than the registry can: the wildcard stands for a segment, a prayer name, a glyph key,
# whichever family it is, and `_inzsh_config_family_of` never resolved it to one because there
# WAS no clean match. `INZSH_*_RANK` is not a downgrade from a concrete guess — it is the exact
# vocabulary `lib/core/config.zsh`'s own comments already use to describe the family, so this file
# adds no second name for the same shape.
#
# The closest candidate wins outright; ties fall to whichever sorted key the loop reaches first,
# which is deterministic and not worth breaking further — this is a hint, not an authority.
_inzsh_doctor_near_miss() {
  emulate -L zsh

  typeset -g REPLY=
  local name=$1
  [[ -n $name ]] || return 1
  (( ${+_inzsh_config_validators} )) || return 1

  local -i threshold=${_inzsh_doctor_near_miss_threshold:-2}
  local -i namelen=${#name}
  local -i best=$(( threshold + 1 )) dist cap lendiff
  local candidate best_name=

  for candidate in ${(ko)_inzsh_config_validators} ${(ko)_inzsh_config_family_validators}; do
    # A PLAIN name's distance can never be smaller than the gap between its length and `$1`'s —
    # nothing closes a length gap for free — so a candidate too far off in length is skipped
    # before the DP runs at all. This is where the cost in issue #228's review actually was: most
    # `INZSH_*` variables anyone sets are unrelated to the registry, so the expensive path was
    # the COMMON one. A FAMILY pattern gets no such shortcut — its wildcard absorbs any amount of
    # extra length for nothing, so `INZSH_GIT_RANK` (14 characters) is 0 away from `INZSH_*_RANK`
    # (12) despite a length gap this check would otherwise refuse on sight. There are only 6
    # families against 43 names in a loaded shell, so paying the DP for all of them costs little.
    if [[ $candidate != *'*'* ]]; then
      lendiff=$(( ${#candidate} - namelen ))
      (( lendiff < 0 )) && lendiff=$(( -lendiff ))
      (( lendiff > threshold )) && continue
    fi

    _inzsh_doctor_distance "$candidate" "$name"
    dist=$REPLY
    _inzsh_doctor_cap "$candidate"
    cap=$REPLY
    (( dist <= cap && dist < best )) || continue
    best=dist
    best_name=$candidate
  done

  # `REPLY` is a shared name — `_inzsh_doctor_distance` and `_inzsh_doctor_cap` both write it on
  # every call inside the loop above, so by the time the loop is done it holds whatever the LAST
  # candidate left there, not this function's own answer. It is set explicitly here either way
  # rather than trusted to still hold the empty string from the top of this function.
  typeset -g REPLY=
  (( best <= threshold )) || return 1
  typeset -g REPLY=$best_name

  return 0
}

# Every `INZSH_` variable that is SET to something the registry refuses, sorted, in `reply`.
#
# Issue #210. "Validate, then fall back" is the rule that stops a typo breaking the prompt: a
# value that fails its validator is not an error, it is simply not used. The cost is that a NEAR
# MISS is invisible — `INZSH_SEPARATOR_STYLE=rounded` does nothing at all, and the word is
# `round`. The registry already holds every validator, so answering this is a read over what the
# user has actually set rather than a second table.
#
# Three things are deliberately NOT listed:
#
#   an empty value        set-but-empty is UNSET at every level of this theme, so an
#                         `INZSH_DIR_BG=` left in a zshrc is falling through by design.
#   an unregistered name  there is no vocabulary to state FOR THIS FUNCTION — this list stays
#                         exactly what its name says, values the registry recognises and
#                         refuses. Issue #228 closes the harder half of that gap without
#                         widening this one: `_inzsh_doctor_near_misses`, below, answers the
#                         separate question of whether an unregistered name sits close enough
#                         to a registered one to be worth a guess, and prints its own rows
#                         immediately after this list's.
#   a valid value         the whole section is absent when everything is valid.
#
# `${parameters[(I)…]}` is the same listing `_inzsh_config_absorb_all` uses, so a knob added
# tomorrow appears here without this file moving. Not on the render path — nothing calls it per
# prompt — and no subprocesses all the same.
_inzsh_doctor_ignored() {
  emulate -L zsh

  typeset -ga reply
  reply=()

  (( ${+functions[_inzsh_config_spec_of]} )) || return 0

  local knob value spec
  for knob in ${(ko)parameters[(I)INZSH_*]}; do
    value=${(P)knob}
    [[ -n $value ]] || continue
    _inzsh_config_spec_of "$knob"
    spec=$REPLY
    [[ -n $spec ]] || continue
    _inzsh_config_check "$spec" "$value" && continue
    reply+=$knob
  done

  return 0
}

# Every `INZSH_` variable that is SET, that the registry has never heard of, and that sits close
# enough to a registered name or family to be worth a guess — `knob` then `suggestion`, one pair
# per row, in `reply`. The other half of issue #228, and deliberately a SEPARATE list from
# `_inzsh_doctor_ignored`'s rather than a widening of it: that function answers "the registry
# recognised this and refused it", this one answers "the registry never recognised this at all,
# but it looks like it meant to" — two different diagnoses, so two different reads over the same
# `INZSH_*` listing.
#
# The pair, not the bare name, is the point: `_inzsh_doctor_near_miss` runs a full edit-distance
# scan of the registry per candidate, and `_inzsh_doctor`'s render loop needs the very suggestion
# this walk already computed. Handing back only the name would make the caller run that scan a
# second time purely to recover an answer this function already had and threw away — the same
# cost paid twice for one result.
#
# An empty value is skipped for the same reason `_inzsh_doctor_ignored` skips one: set-but-empty
# is unset at every level of this theme, and a blank left in a zshrc is not a typo to chase.
_inzsh_doctor_near_misses() {
  emulate -L zsh

  typeset -ga reply
  reply=()

  (( ${+functions[_inzsh_config_spec_of]} )) || return 0
  (( ${+functions[_inzsh_doctor_near_miss]} )) || return 0

  local knob value spec
  for knob in ${(ko)parameters[(I)INZSH_*]}; do
    value=${(P)knob}
    [[ -n $value ]] || continue
    _inzsh_config_spec_of "$knob"
    spec=$REPLY
    [[ -z $spec ]] || continue
    _inzsh_doctor_near_miss "$knob" || continue
    reply+=("$knob" "$REPLY")
  done

  return 0
}

# The knobs a past release removed outright, and what replaced each one.
#
# Issue #242. A retired knob is the one case the two walks above are structurally unable to
# reach. `_inzsh_doctor_ignored` reports a name the registry RECOGNISES and refuses, and
# `_inzsh_doctor_near_misses` reports one it has never heard of that LOOKS like one it has —
# but a retired name is neither. Removing the registration is exactly what makes the first
# walk blind to it, and a deliberate old name is not a typo, so the second walk finds nothing
# close enough to guess at either. Measured, not assumed: `INZSH_PROMPT_LINES` is 8 edits from
# the nearest registered name, well past the threshold, so a `.zshrc` that still sets it draws
# correctly and says nothing at all about why. A silent no-op is the one outcome a retired
# knob must not have — the shape is right, the line is dead, and nothing on screen connects
# the two.
#
# This is a table here rather than a `retired` spec in `lib/core/config.zsh` on purpose. The
# registry is the theme's VOCABULARY — `inzsh-knobs` prints it, `_inzsh_config_absorb_all`
# walks it, `_inzsh_doctor_near_miss` suggests from it — and re-registering a name the release
# removed would put it back in all three, which is the opposite of retiring it. The diagnostic
# layer is where a name that no longer exists belongs: known to the thing that explains the
# theme, unknown to the thing that reads it.
#
# NOT NAMED `_inzsh_doctor_retired_knobs`, and the near miss is the point. `_inzsh_config_
# absorb_all` walks `${(ko)parameters[(I)_inzsh_*_knobs]}` and treats every parameter it finds
# as a REGISTRATION TABLE — that suffix is a reserved convention, not a description — so a
# table of retired names spelled that way would be handed straight back to the registry that
# just dropped them. It is refused today only because `INZSH_MARKER_ROW` is not a valid spec
# string; a retired knob whose replacement happened to read as one would be silently
# re-registered by the very table written to declare it dead. `test/unit/config_registry_spec.sh`
# holds the namespace rather than this comment.
typeset -gA _inzsh_doctor_retired_replacement=(
  INZSH_PROMPT_LINES INZSH_MARKER_ROW
)

# `<retired knob> <its old value>` -> the replacement's value meaning the same thing. Only the
# values the retired knob actually accepted appear; anything else was already falling through
# before the removal, so there is no old behaviour to name a new spelling for.
typeset -gA _inzsh_doctor_retired_values=(
  'INZSH_PROMPT_LINES 1' inline
  'INZSH_PROMPT_LINES 2' own
)

# Every retired `INZSH_` variable that is still SET — `knob` then the replacement to use, one
# pair per row, in `reply`. Same pair shape as `_inzsh_doctor_near_misses`, and for the same
# reason: the caller wants the advice this walk already worked out, not a second lookup.
#
# The advice carries a VALUE when the old one maps — `INZSH_MARKER_ROW=own` — and only the
# name when it does not. The distinction is not cosmetic. `INZSH_PROMPT_LINES=2` was a working
# setting whose shape has an exact new spelling, and printing it is the difference between
# "look this up" and "paste this". `INZSH_PROMPT_LINES=9` never did anything even while the
# knob existed, so naming a replacement value would be inventing an intent the user never
# expressed; the replacement NAME is the whole of what this file honestly knows there.
#
# A name the registry has somehow taken back is skipped. That cannot happen in a release as
# shipped, but a table of names deleted from the registry and a registry are two facts that
# could drift, and of the two the registry is the one that decides what the theme actually
# reads. If both claim a name, the live one wins and this walk stays quiet rather than
# telling a user to stop setting a knob that is working.
#
# Set-but-empty is skipped for the third time in this file and for the third identical reason:
# set-but-empty is unset at every level of this theme, so a bare `INZSH_PROMPT_LINES=` left in
# a zshrc is not a setting anybody is waiting on.
_inzsh_doctor_retired() {
  emulate -L zsh

  typeset -ga reply
  reply=()

  local knob value spec advice mapped
  for knob in ${(ko)_inzsh_doctor_retired_replacement}; do
    value=${(P)knob}
    [[ -n $value ]] || continue

    if (( ${+functions[_inzsh_config_spec_of]} )); then
      _inzsh_config_spec_of "$knob"
      spec=$REPLY
      [[ -z $spec ]] || continue
    fi

    advice=${_inzsh_doctor_retired_replacement[$knob]}
    mapped=${_inzsh_doctor_retired_values[$knob $value]-}
    [[ -n $mapped ]] && advice+="=$mapped"
    reply+=("$knob" "$advice")
  done

  return 0
}

# The install method — `clone`, `bundle`, `manual`, `oh-my-zsh`, or a combination of the last
# with one of the first three — in REPLY. Issue #245. No subprocess: every signal below is a
# filesystem test or a parameter read, because this is reachable from the exact broken
# environment where a `git` or `uname` on `$PATH` could be the very thing that is broken.
#
# OH-MY-ZSH IS CHECKED FIRST, code shape second, and the two are independent rather than a
# ladder of exclusive cases. `_inzsh_theme_root` is resolved through `:A` at the entry point —
# `${${(%):-%x}:A:h}` — which follows symlinks, and `install.zsh`'s omz path IS a symlink: it
# links `$ZSH_CUSTOM/themes/inzsh.zsh-theme` back at the real checkout, so by the time this runs
# the root has already been walked back to that checkout and looks exactly like a clone loaded
# plainly. The one signal that still tells the two apart is the framework itself — oh-my-zsh
# exports `$ZSH` to its own root and reads `$ZSH_THEME` to decide what to source, so `$ZSH_THEME`
# reading `inzsh` while `$ZSH` is set is proof the framework did the sourcing, symlink or not.
# It is asked independently of the shape below, and combined with it when both answer, because a
# bundle can be oh-my-zsh's target too — `tools/bundle.zsh`'s own emitted header says as much:
# "drop it into an oh-my-zsh themes directory" is a supported way to arrive here, not a fluke.
#
# BUNDLE is the one shape provable from the fact this code is running at all, not guessed from
# a path. The entry point sources `lib/core/*.zsh` and the rest as separate files; a bundle
# inlines all of it into the one file it ships. So if `_inzsh_doctor` exists to be called and
# there is no `lib/` sitting beside `_inzsh_theme_root`, the only way that could be true is that
# everything this file needed was already in the file that got sourced — which is what a bundle
# IS, by `tools/bundle.zsh`'s own construction, not a shape that merely looks like one.
#
# CLONE vs MANUAL is the one genuine judgment call here, and it is narrower than it looks: both
# are a full source tree (`lib/` present) sourced directly, and this function cannot see whether
# a human ran `install.zsh --plain` or typed the `source` line into their own `.zshrc` — the two
# leave an identical shell behind. What it CAN check is whether the tree is a git checkout:
# `.git` beside the root is real evidence, not a guess dressed up as one, so its presence is
# called `clone`; its absence — a zip extraction, a copied directory, anything that carries the
# source without git's own evidence of it — is called `manual` rather than assumed to be a clone
# it cannot prove.
#
# `unknown` is left for the one case that cannot even ask the question: no theme root to look
# beside, and no oh-my-zsh signal either. That is not a hypothetical — `tools/doctor.zsh` (`make
# doctor`) sources this file directly without ever setting `_inzsh_theme_root`, on purpose (see
# its own header), and this function has to keep working for that caller exactly as it does for
# the shipped command.
_inzsh_doctor_install_method() {
  emulate -L zsh

  typeset -g REPLY=unknown
  local root=${_inzsh_theme_root-}
  local -i omz=0
  [[ -n ${ZSH:-} && ${ZSH_THEME:-} == inzsh ]] && omz=1

  if [[ -z $root || ! -d $root ]]; then
    (( omz )) && REPLY=oh-my-zsh
    return 0
  fi

  local shape
  if [[ ! -d $root/lib ]]; then
    shape=bundle
  elif [[ -e $root/.git ]]; then
    shape=clone
  else
    shape=manual
  fi

  if (( omz )); then
    REPLY="oh-my-zsh ($shape)"
  else
    REPLY=$shape
  fi

  return 0
}

# `$1` seconds as a coarse age — minutes, then hours, then days. A bug reader needs "about a
# day", never the arithmetic.
_inzsh_doctor_age() {
  emulate -L zsh

  typeset -g REPLY=
  local -i seconds=$1

  if (( seconds < 3600 )); then
    REPLY="$(( seconds / 60 ))m"
  elif (( seconds < 172800 )); then
    REPLY="$(( seconds / 3600 ))h"
  else
    REPLY="$(( seconds / 86400 ))d"
  fi

  return 0
}

# The resolved SHAPE of the prompt — never the knob, the render's own answer to it. Issue #227:
# `INZSH_SEPARATOR_STYLE=arrow` with no Nerd Font draws `divider`, and a row that printed `arrow`
# because that is what the variable says would be describing a prompt nobody is looking at. Every
# fact below is read the same way the render core reads it, at the moment doctor asks —
# recompute-never-cache, the same rule every row above already keeps.
#
# Omitted whole when `lib/core/rows.zsh` and `lib/core/render.zsh` are not both loaded: a partial
# load has nothing honest to compute a row count or a fit from, and `_inzsh_doctor_segments`
# right below needs exactly the same two files, so the two sections share one guard.
_inzsh_doctor_shape() {
  emulate -L zsh
  setopt extended_glob

  (( ${+functions[_inzsh_rows_resolve]} && ${+functions[_inzsh_render_row]} )) || return 0

  local -i cols=${COLUMNS:-0}
  local value

  # The separator. `sep_intended` is resolved through the identical case-match `_inzsh_sep_style`
  # itself applies, BEFORE its own Nerd Font check — so the two can only ever disagree for the one
  # reason that check exists, and the note below is never wrong about why.
  local sep_raw=${INZSH_SEPARATOR_STYLE-}
  (( ${+functions[_inzsh_config_get]} )) && { _inzsh_config_get INZSH_SEPARATOR_STYLE; sep_raw=$REPLY }
  local sep_intended=arrow
  case $sep_raw in (arrow|round|divider) sep_intended=$sep_raw ;; esac
  _inzsh_sep_style
  value=$_inzsh_sep_style_resolved
  [[ $value != $sep_intended ]] && value+=" (would be $sep_intended with a Nerd Font)"
  _inzsh_doctor_row shape "separator: $value"

  # The surface mode. Nothing transforms it further the way the separator is, so the resolved
  # value is the whole answer — an invalid `INZSH_SURFACE_MODE` already has its own row in the
  # `ignored` section below, and repeating that note here would be the same fact said twice.
  _inzsh_surface_mode
  _inzsh_doctor_row shape "surface: $_inzsh_surface_mode_resolved"

  # The marker row. `INZSH_PROMPT_LINES` was the deprecated alias through v1.x; `v2.0.0` retired
  # it, so the resolved value is the whole answer now — there is nothing left to attribute it to.
  # Reporting a still-set `INZSH_PROMPT_LINES` as retired is issue #242, not this function's job.
  if (( ${+functions[_inzsh_marker_row_resolved]} )); then
    _inzsh_marker_row_resolved
    _inzsh_doctor_row shape "marker: $REPLY"
  fi

  # The padding. Bounded by its own validator, so an out-of-range value already has an `ignored`
  # row of its own — this is only ever the number actually spent on either side of a block.
  _inzsh_render_pad
  _inzsh_doctor_row shape "padding: $_inzsh_render_pad_resolved"

  # The row count, resolved fresh against every registered segment and the terminal width right
  # now — the same call `_inzsh_render` itself makes on every precmd, not a second opinion of it.
  local -a shape_candidates=(${(ok)_inzsh_segment_defaults})
  _inzsh_rows_resolve "$cols" "${shape_candidates[@]}"
  _inzsh_doctor_row shape "rows: $_inzsh_row_count"

  return 0
}

# `_inzsh_doctor_row_survivors <cols> <left-array-name> <right-array-name>` — the segments from
# both sides that would actually be DRAWN if this row were rendered right now, in `reply`.
#
# Issue #227. `_inzsh_render_row` in `lib/core/render.zsh` is the one place that answers this for
# real, and its own comment says outright that publishing a survivor list was tried and dropped —
# nothing needed one until now. Calling it directly here was considered and rejected: its last
# pass, `dir` truncation, calls the real `_inzsh_segment_dir_build` with a tightened budget, which
# OVERWRITES `_inzsh_segment_text[DIR]`. That self-heals at the next real prompt — every candidate
# segment is rebuilt from scratch on every precmd — but a doctor that changes what the NEXT prompt
# draws, even harmlessly, is not the recompute-never-cache, side-effect-free diagnostic the rest
# of this file is.
#
# So this mirrors `_inzsh_render_row`'s own first two passes — the per-side `_inzsh_layout_fit`
# and the drop-walk that narrows the right side when the two sides together will not fit — and
# stops exactly where its third pass, `dir` truncation, begins. That is a safe place to stop:
# truncation only ever shortens `dir`'s own TEXT, it never adds or removes a segment from either
# list, so leaving it out changes nothing about which segments this function reports as drawn.
# If `_inzsh_render_row`'s first two passes ever change shape, this needs the same change.
_inzsh_doctor_row_survivors() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga reply
  reply=()

  local -i cols=0
  [[ $1 == <-> ]] && cols=$1
  local left_name=$2 right_name=$3

  local -a left_list=("${(@P)left_name}") right_list=("${(@P)right_name}")

  # Without the render core this cannot answer at all, and "I could not check" reads as "assume
  # it draws" — the same rule `_inzsh_render_row_fits` states for itself, so a partial load never
  # invents an absence nobody here can prove.
  (( ${+functions[_inzsh_render_row]} )) || {
    reply=("${left_list[@]}" "${right_list[@]}")
    return 0
  }

  local -i budget=$(( cols - 1 ))
  local -i sep_width=0
  if (( ${+functions[_inzsh_width]} )); then
    _inzsh_separators
    _inzsh_width "$_inzsh_sep_left"
    (( sep_width = REPLY + 1 ))
  fi

  _inzsh_render_fit_args "${left_list[@]}"
  _inzsh_layout_fit "$budget" "$sep_width" "${reply[@]}"
  left_list=("${reply[@]}")

  _inzsh_render_fit_args "${right_list[@]}"
  _inzsh_layout_fit "$budget" "$sep_width" "${reply[@]}"
  right_list=("${reply[@]}")

  _inzsh_render_build right "${right_list[@]}"
  local right_str=$REPLY
  local -i right_width=$_inzsh_render_width

  _inzsh_render_build left "${left_list[@]}"
  local left_str=$REPLY
  local -i left_width=$_inzsh_render_width

  # The drop-walk, unchanged from `_inzsh_render_row`: propose a gap, accept it once the measured
  # row fits, and otherwise narrow the right side by priority at a tighter budget and try again.
  while (( ${#right_list} )); do
    _inzsh_render_gap "$cols" "$left_width" "$right_width"
    if (( REPLY >= 1 )); then
      local candidate_row=$left_str${(l:REPLY:):-}$right_str
      _inzsh_render_row_fits "$candidate_row" "$cols" && break
    fi

    local -i right_budget=$(( cols - left_width - 2 ))
    (( right_budget < 0 )) && right_budget=0

    _inzsh_render_fit_args "${right_list[@]}"
    _inzsh_layout_fit "$right_budget" "$sep_width" "${reply[@]}"
    (( ${#reply} == ${#right_list} )) && break

    right_list=("${reply[@]}")
    _inzsh_render_build right "${right_list[@]}"
    right_str=$REPLY
    right_width=$_inzsh_render_width
  done

  typeset -ga reply
  reply=("${left_list[@]}" "${right_list[@]}")

  return 0
}

# Per segment: where it landed, what governs its survival, and — when it did not survive — WHY.
# Issue #227, covering #246 and #247. "Why is my segment not showing" is unanswerable from a
# segment's own rank alone once rows exist: a segment can be placed and still not draw, for
# reasons that live in three different files and are not interchangeable — naming the wrong one
# sends a reader to fix something that was never broken.
#
# The four causes this reports, in the order they are actually checked, because each one can only
# be asked once the ones before it are ruled out:
#
#   RANK 0, UNCLAIMED   `lib/core/rows.zsh` step 2's own drop — `_inzsh_rows_hidden` is exactly
#                       this set, already computed by the resolve this function calls, so it is
#                       read rather than re-derived.
#   MINCOLS             the same resolve's step 3, over whatever stood after the rank check —
#                       claimed or not. A candidate that is not in `_inzsh_rows_hidden` and still
#                       did not land on any row can only have failed here: `_inzsh_rows_resolve`'s
#                       own contract (see its header) has no third way off a row it draws.
#   NO TEXT             a segment placed on a row that built nothing this render — a clean
#                       repository's `git`, an inactive `venv`. Checked before the fit, because
#                       `_inzsh_render_fit_args` already skips text-less segments on its own, and
#                       asking the fit about a segment it never considered would misname this as
#                       "dropped by the fit" instead.
#   THE ROW'S FIT       placed, built real text, and still not among what `_inzsh_render_row`
#                       would actually draw — the per-row priority walk, or the drop-walk when a
#                       row could not hold both sides. One label for both:
#                       `_inzsh_doctor_row_survivors` mirrors the MECHANISM, not which half of it
#                       fired, and a reader who needs to know which can narrow the terminal and
#                       watch which one moves.
#
# Entry-VALIDATION drops — a name that never became a candidate because it could not spell a
# variable, or named no segment this build has — are issue #243's, not this one's: this function
# only ever sees `${(k)_inzsh_segment_defaults}`, the real registered segments, so a typo in a row
# array is invisible here exactly as `_inzsh_rows_entries` already made it invisible to the
# resolve.
_inzsh_doctor_segments() {
  emulate -L zsh
  setopt extended_glob

  (( ${+functions[_inzsh_rows_resolve]} && ${+functions[_inzsh_render_row]} )) || return 0
  (( ${#_inzsh_segment_defaults} )) || return 0

  local -i cols=${COLUMNS:-0}
  local -a candidates=(${(ok)_inzsh_segment_defaults})

  _inzsh_rows_resolve "$cols" "${candidates[@]}"
  local -i row_count=$_inzsh_row_count

  local -A is_hidden=()
  local h
  for h in "${_inzsh_rows_hidden[@]}"; do is_hidden[$h]=1; done

  local -A placed_row=() placed_side=() survives=()
  local -i n
  local seg lname rname
  for (( n = 1; n <= row_count; n++ )); do
    lname="_inzsh_row${n}_left"
    rname="_inzsh_row${n}_right"

    for seg in "${(@P)lname}"; do placed_row[$seg]=$n; placed_side[$seg]=left; done
    for seg in "${(@P)rname}"; do placed_row[$seg]=$n; placed_side[$seg]=right; done

    _inzsh_doctor_row_survivors "$cols" "$lname" "$rname"
    for seg in "${reply[@]}"; do survives[$seg]=1; done
  done

  local -i rank priority mincols
  local reason value
  for seg in "${candidates[@]}"; do
    _inzsh_rank_of "$seg"
    rank=$REPLY
    _inzsh_priority_of "$seg"
    priority=$REPLY
    _inzsh_mincols_of "$seg"
    mincols=$REPLY

    reason=
    if (( ${+placed_row[$seg]} )); then
      value="row=${placed_row[$seg]} side=${placed_side[$seg]} rank=$rank priority=$priority mincols=$mincols"
      if [[ -z ${_inzsh_segment_text[$seg]-} ]]; then
        reason='built no text this render'
      elif (( ! ${+survives[$seg]} )); then
        reason="dropped by the row's fit"
      fi
    else
      value="row=- side=- rank=$rank priority=$priority mincols=$mincols"
      if (( ${+is_hidden[$seg]} )); then
        reason='rank 0, not named in any row'
      else
        reason="dropped by MINCOLS ($mincols > $cols)"
      fi
    fi

    [[ -n $reason ]] && value+=" - $reason"
    _inzsh_doctor_row segment "$seg $value"
  done

  return 0
}

# The block itself. Always status 0: a diagnostic that can fail is a diagnostic nobody can run
# in the broken environment it exists for, so every line degrades to an honest word — `unknown`,
# `none` — rather than to an error.
#
# `[now]` is the injected clock every salah function under `lib/salah/` takes, threaded through
# here for the same reason: a fixture pins the instant and asks what the block says, and no
# example in the suite can be affected by what the sun is doing while it runs. Unset, the wall
# clock answers, which is the one property that makes this a diagnostic of the terminal you are
# looking at right now rather than a memory of source time.
_inzsh_doctor() {
  emulate -L zsh

  local now=${1:-${EPOCHSECONDS-}}
  # A malformed clock is not the fixture seam misused, it is `inzsh doctor` reachable through
  # `inzsh()`'s `"$@"` forwarding from anyone who types a second word — and the wall clock is the
  # one thing here that is always right, so a value that cannot be an epoch falls back to it
  # rather than reaching `_inzsh_salah_location` and `_inzsh_salah_cache_health` as a clock that
  # makes the position line say `config` beside a table line that says `no position`.
  [[ $now == <-> ]] || now=${EPOCHSECONDS-}

  # Re-ask every question. Recompute-never-cache is each detector's own contract; calling them
  # here is what makes the block current rather than a memory of source time.
  (( ${+functions[_inzsh_detect_color_depth]} )) && _inzsh_detect_color_depth
  (( ${+functions[_inzsh_detect_multibyte]} ))   && _inzsh_detect_multibyte
  (( ${+functions[_inzsh_detect_nerd_font]} ))   && _inzsh_detect_nerd_font
  (( ${+functions[_inzsh_detect_tmux]} ))        && _inzsh_detect_tmux

  local -a notes=()
  local value

  print -r -- 'InZsh doctor'

  # What is running, how it got here, and from where — issue #245. `_inzsh_version` and
  # `_inzsh_theme_root` are the entry point's own globals (`inzsh.zsh-theme`, stamped over by
  # `tools/bundle.zsh` for a release build — see docs/releasing.md), read here rather than
  # recomputed: there is nothing to detect, only to report, and `${VAR-}` rather than `${VAR}`
  # because a narrower harness than the shipped command — `tools/doctor.zsh` (`make doctor`) —
  # never sets either one, on purpose, and this block still has to degrade to an honest word
  # instead of an unset-variable error.
  _inzsh_doctor_row version "${_inzsh_version:-unknown}"

  _inzsh_doctor_install_method
  _inzsh_doctor_row install "$REPLY"

  # `$HOME` collapsed to `~` — see THE ROOT IS PRINTED WITH `$HOME` COLLAPSED at the top of this
  # file for why. Guarded on `$HOME` being set at all, because an empty pattern in `${x/#$y/z}`
  # matches the start of EVERY string, which would prepend `~` to the whole path rather than
  # leave it alone. The whole substitution is quoted, not just handed to `value=`: an UNQUOTED
  # `~` in the replacement is itself a filename expansion in zsh, so it would resolve to `$HOME`
  # a second time before it ever became the literal character — replacing the matched prefix
  # with itself and silently undoing the entire collapse this line exists to do.
  value=${_inzsh_theme_root:-unknown}
  [[ -n ${HOME:-} ]] && value="${value/#$HOME/~}"
  _inzsh_doctor_row 'theme root' "$value"

  _inzsh_doctor_row zsh "${ZSH_VERSION:-unknown}"

  # The terminal names itself in one of three places — `TERM_PROGRAM` is the usual one,
  # `LC_TERMINAL` is what ssh forwards, `TERMINAL_EMULATOR` is the JetBrains spelling — and a
  # terminal that names itself usually versions itself beside it.
  if [[ -n ${TERM_PROGRAM-} ]]; then
    value="$TERM_PROGRAM${TERM_PROGRAM_VERSION:+ $TERM_PROGRAM_VERSION}"
  elif [[ -n ${LC_TERMINAL-} ]]; then
    value="$LC_TERMINAL${LC_TERMINAL_VERSION:+ $LC_TERMINAL_VERSION}"
  elif [[ -n ${TERMINAL_EMULATOR-} ]]; then
    value=$TERMINAL_EMULATOR
  else
    value=unknown
  fi
  _inzsh_doctor_row terminal "$value"

  _inzsh_doctor_row TERM "${TERM:-unset}"

  value=${_inzsh_color_depth:-unknown}
  _inzsh_doctor_overridden INZSH_COLOR_DEPTH && value+=' (INZSH_COLOR_DEPTH)'
  _inzsh_doctor_row 'colour depth' "$value"

  # The locale as zsh itself resolves it — `LC_ALL`, then `LC_CTYPE`, then `LANG` — beside the
  # verdict the theme drew from it.
  value=${LC_ALL:-${LC_CTYPE:-${LANG:-none}}}
  case ${_inzsh_multibyte-} in
    (1) value+=' (multibyte: yes' ;;
    (0) value+=' (multibyte: no' ;;
    (*) value+=' (multibyte: unknown' ;;
  esac
  _inzsh_doctor_overridden INZSH_MULTIBYTE && value+=', INZSH_MULTIBYTE'
  value+=')'
  _inzsh_doctor_row locale "$value"

  case ${_inzsh_nerd_font-} in
    (1) value=yes ;;
    (0) value=no
        notes+='without a Nerd Font, separator styles resolve to divider' ;;
    (*) value=unknown
        notes+='a font cannot be proven from a shell - if separators draw as boxes, set INZSH_NERD_FONT=0' ;;
  esac
  _inzsh_doctor_overridden INZSH_NERD_FONT && value+=' (INZSH_NERD_FONT)'
  _inzsh_doctor_row 'nerd font' "$value"

  if [[ ${_inzsh_tmux-} == 1 ]]; then
    _inzsh_doctor_row tmux yes
    [[ ${_inzsh_tmux_rgb-} == 1 ]] ||
      notes+='tmux may be flattening 24-bit colour - see the README for RGB passthrough'
  else
    _inzsh_doctor_row tmux no
  fi
  case ${_inzsh_tmux_rgb-} in
    (1) value=yes ;;
    (0) value=no ;;
    (*) value=unknown ;;
  esac
  _inzsh_doctor_row 'tmux rgb' "$value"

  # The registered invariants, straight out of the registry — the listing
  # `_inzsh_config_guard_names` exists to make cheap.
  if (( ${+functions[_inzsh_config_guard_names]} )); then
    _inzsh_config_guard_names
    (( ${#reply} )) && _inzsh_doctor_row invariants "${(j:, :)reply}"
  fi

  # The resolved prompt shape, and where every registered segment landed and why — issue #227,
  # covering #246 and #247. Both are omitted whole when `lib/core/rows.zsh` and
  # `lib/core/render.zsh` are not loaded; see `_inzsh_doctor_shape`'s own header for why they
  # share one guard.
  _inzsh_doctor_shape
  _inzsh_doctor_segments

  # What the user set and the theme is not using — one row per value, with the vocabulary it
  # should have used, rendered from the registered spec by `_inzsh_config_accepts` so the words
  # here and the words `inzsh-knobs` prints are the same words.
  #
  # NOTHING IS PRINTED WHEN EVERYTHING IS VALID. A clean shell does not grow a section telling it
  # so; the rows exist to be noticed.
  #
  # The value is flattened and clipped before it is shown. This block is pasted into an issue, so
  # a newline in a value would end the row early, a control character would move somebody's
  # cursor, and a format string long enough to be a config file in its own right would push the
  # block off the screen. Where it came from is the diagnostic; reading the whole value back is
  # what the variable itself is for.
  # Issue #242. A knob a past release removed, still set. These lead the section rather than
  # follow it, because of the three tails printed under `ignored` this is the only one that is
  # a FACT: `accepts X` infers what a refused value was reaching for and `probably X` guesses
  # which name a stray one slipped from, while `retired, use X` is the release note, and the
  # theme is not speculating about it. The certain row goes first so the reader who has one
  # never has to scan past two guesses to reach it.
  #
  # Filed under `ignored` alongside them all the same. The label answers the question the
  # reader is asking of every row in this section — "what did I set that is not doing
  # anything?" — and a retired knob is the purest example of it. The tail is where the three
  # diagnoses part company, which is the same split `probably X` already made against
  # `accepts X`.
  local knob
  local -a retired
  _inzsh_doctor_retired
  retired=("${reply[@]}")
  local advice
  local -i ridx
  for (( ridx = 1; ridx <= ${#retired}; ridx += 2 )); do
    knob=${retired[ridx]}
    advice=${retired[ridx + 1]}
    value=${${(P)knob}//[[:cntrl:]]/ }
    (( ${#value} > 24 )) && value="${value[1,23]}…"
    _inzsh_doctor_row ignored "$knob=$value - retired, use $advice"
  done

  local -a ignored
  _inzsh_doctor_ignored
  ignored=("${reply[@]}")
  for knob in $ignored; do
    value=${${(P)knob}//[[:cntrl:]]/ }
    (( ${#value} > 24 )) && value="${value[1,23]}…"
    _inzsh_config_spec_of "$knob"
    _inzsh_config_accepts "$REPLY"
    _inzsh_doctor_row ignored "$knob=$value - accepts $REPLY"
  done

  # Issue #228. The other half of the same section: a name the registry has never heard of, close
  # enough to one it has that it is almost certainly the same slipped key rather than a variable
  # that was never ours. Printed as more `ignored` rows, straight after the ones above — same
  # value-flattening, same clipping, same reason for both — because the reader pasting this block
  # is asking the same question of every row here: "what did I set that is not doing anything?".
  # The tail differs on purpose: `accepts X` names a whole vocabulary the value could have been
  # from; `probably X` names one specific name the KNOB itself could have been, which is the more
  # honest claim this function is actually able to make.
  #
  # `reply` is read here as `knob` `suggestion` pairs, not re-derived — `_inzsh_doctor_near_miss`
  # is not called again. It already ran once inside `_inzsh_doctor_near_misses`, and that walk is
  # the expensive one; asking it a second time per row would double the cost of this section for
  # nothing it does not already know.
  local -a misses
  _inzsh_doctor_near_misses
  misses=("${reply[@]}")
  local suggestion
  local -i idx
  for (( idx = 1; idx <= ${#misses}; idx += 2 )); do
    knob=${misses[idx]}
    suggestion=${misses[idx+1]}
    value=${${(P)knob}//[[:cntrl:]]/ }
    (( ${#value} > 24 )) && value="${value[1,23]}…"
    _inzsh_doctor_row ignored "$knob=$value - probably $suggestion"
  done

  # Issue #243. The `ignored` rows above cover a KNOB whose VALUE the registry recognised and
  # refused; they cannot cover a row array, because `INZSH_ROW<N>_LEFT`/`_RIGHT` are registered as
  # `any` purely so their names appear in the vocabulary, and `any` accepts whatever a segment name
  # happens to be spelled as — the VALUE is not wrong, the NAME inside it is. `_inzsh_rows_diagnose`
  # is where that question is actually answered — see its own header in `lib/core/rows.zsh` for
  # why a typo here would otherwise be a segment that silently never draws.
  #
  # Guarded on the function existing, the same reason the `salah` rows below are: `tools/
  # doctor.zsh` (`make doctor`) never sources `lib/core/rows.zsh`, and a partial load has nothing
  # honest to report here either. `$COLUMNS` is read fresh, the same width the render path itself
  # would see right now, rather than injected — this is the one caller of `_inzsh_rows_diagnose`
  # that is not a unit test and has a real terminal to ask.
  #
  # Same flattening and clipping as the `ignored` rows above, and for the identical reason: an
  # array entry is text a user typed, this block is pasted into a public issue, and a newline or
  # an escape sequence in one must not end a row early, move a cursor, or forge a line that was
  # never actually printed. An entry dropped for being unreadable as an identifier is exactly the
  # kind of value most likely to hold one, so the flattening runs before it, never after.
  if (( ${+functions[_inzsh_rows_diagnose]} )); then
    local -a dropped
    _inzsh_rows_diagnose "${COLUMNS:-0}"
    dropped=("${reply[@]}")
    local drow dside dentry dreason
    local -i didx
    for (( didx = 1; didx <= ${#dropped}; didx += 4 )); do
      drow=${dropped[didx]}
      dside=${dropped[didx + 1]}
      dentry=${dropped[didx + 2]}
      dreason=${dropped[didx + 3]}
      value=${dentry//[[:cntrl:]]/ }
      (( ${#value} > 24 )) && value="${value[1,23]}…"
      if [[ -z $dentry ]]; then
        _inzsh_doctor_row 'row entry' "INZSH_ROW${drow}_${(U)dside} - $dreason"
      else
        _inzsh_doctor_row 'row entry' "INZSH_ROW${drow}_${(U)dside}=$value - $dreason"
      fi
    done
  fi

  # Where the prayer segment's position came from, and the state of the table computed from
  # it — never the numbers behind either. Omitted entirely when the salah library is not
  # loaded: a partial load has nothing honest to say here.
  if (( ${+functions[_inzsh_salah_location]} )); then
    if _inzsh_salah_location "$now"; then
      value=$_inzsh_salah_location_source
      if [[ $value == cache ]] && (( _inzsh_salah_location_age >= 0 )); then
        _inzsh_doctor_age $_inzsh_salah_location_age
        value+=" (refreshed ${REPLY} ago)"
      fi
    else
      value=none
    fi
    _inzsh_doctor_row salah "location: $value"

    # Issue #229. `_inzsh_salah_cache_health` never returns an error, so this always has a word
    # to report — the same "recompute-never-cache" habit every other row in this block keeps.
    #
    # `recipe` names the METHOD AND ASR SCHOOL, never a hash of the position: see
    # `lib/salah/cache.zsh` for why a hash of a coordinate is a slow encoding of it rather than a
    # redaction. The method and school are configuration a reader can act on, and doubly
    # defaulted — the knob, then the compiled-in default — so the row never goes empty even where
    # `lib/salah/methods.zsh` was sourced without ever having read a config file.
    #
    # THE NAME IS RESOLVED, NEVER ECHOED. Printing `$INZSH_SALAH_METHOD` straight would make this
    # row wrong in two ways at once: it would say a value is the recipe IN FORCE while the
    # `ignored` section a few rows up says the same value is not in force at all, and — the one
    # that matters more — a config value would reach a block whose whole purpose is to be
    # trustworthy evidence in a public issue, unsanitised. `_inzsh_salah_method_key` maps
    # whatever was typed onto one of six literal table keys or falls back to the default, and the
    # Asr line is matched against its own three-word vocabulary directly — so what lands in
    # `recipe` is always one of a closed, hand-written set of words, never a byte of user input,
    # which is what actually being SANITISED as text can never fully be.
    if (( ${+functions[_inzsh_salah_cache_health]} )); then
      _inzsh_salah_cache_health "$now"
      # Captured immediately: `_inzsh_salah_method_key` below answers in REPLY too, and this
      # function has already been caught once by exactly this — a later call quietly discarding
      # an earlier one's word before anything read it.
      local state=$REPLY

      local method=${_inzsh_salah_default_method:-MWL}
      if (( ${+functions[_inzsh_salah_method_key]} )); then
        _inzsh_salah_method_key "${INZSH_SALAH_METHOD-}"
        [[ -n ${_inzsh_salah_methods[$REPLY]-} ]] && method=$REPLY
      fi
      local asr=standard
      [[ ${(L)INZSH_SALAH_ASR-} == (standard|shafi|hanafi) ]] && asr=${(L)INZSH_SALAH_ASR}
      local recipe="method $method, asr $asr"

      case $state in
        (none)       value='none (no position)' ;;
        (nodir)      value='no cache directory (recomputed every shell)' ;;
        (missing)    value="not cached yet ($recipe)" ;;
        (denied)     value="unreadable, permission denied ($recipe)" ;;
        (future)     value="unreadable, written by a newer InZsh ($recipe)" ;;
        (unreadable) value="unreadable ($recipe)" ;;
        (stale)      value="stale, computed for a day that is not today ($recipe)" ;;
        (current)    value="current, covers today ($recipe)" ;;
        (*)          value=unknown ;;
      esac
      _inzsh_doctor_row salah "table: $value"
    fi
  fi

  local note
  for note in $notes; do
    _inzsh_doctor_row note "$note"
  done

  return 0
}

# `inzsh locate [--force] [--now epoch]` — refresh the stored position, on purpose. The public
# face of `INZSH_SALAH_AUTOLOCATE` (issue #186): the knob PERMITS the theme's one network call,
# and this command is the only shipped way to MAKE it. It is typed by a person — never reached
# from a hook, the segment, or the render path — which is the whole safety story of
# `lib/salah/location.zsh` kept intact with a name you can find.
#
#   inzsh locate            look the position up if the stored one is older than the TTL
#   inzsh locate --force    look it up now, whatever the stored one's age — for after you move
#   (inzsh locate &!)       from `.zshrc`, detached, so login does not wait
#
# `--now <epoch>` is the injected clock every salah function takes, for the suite that pins
# time; unset, the wall clock answers. Issue #251: this used to be a bare trailing positional,
# which CONVENTIONS.md's Commands section rules out on sight — the digit names nothing a reader
# could recover unaided. `--now` matches `inzsh salah`'s own flag of the same name, one idiom
# for the same seam rather than two.
#
# The TTL gate is the same one `_inzsh_salah_locate_refresh` keeps, restated here for one
# reason: the command has to be able to SAY which side of it you are on — "current, refreshed
# 2h ago, --force to insist" is the answer somebody who just moved actually needs — and to step
# over it when told to. Outcomes go to stdout; refusals and failures go to stderr with status 1.
_inzsh_locate() {
  emulate -L zsh

  local -i force=0
  local now=
  while (( $# )); do
    case $1 in
      (-f|--force)
        force=1
        shift
        ;;
      (--now)
        shift
        if [[ ${1-} != <-> ]]; then
          print -ru2 -- 'inzsh locate: --now wants an epoch - whole seconds since 1970'
          return 1
        fi
        now=$1
        shift
        ;;
      (*)
        print -ru2 -- \
          "inzsh locate: unknown argument '$1' - usage: inzsh locate [--force] [--now epoch]"
        return 1
        ;;
    esac
  done

  if ! (( ${+functions[_inzsh_salah_locate_fetch]} )); then
    print -ru2 -- 'inzsh locate: the prayer library is not loaded'
    return 1
  fi

  if ! _inzsh_salah_autolocate_on; then
    print -ru2 -- 'inzsh locate: the lookup is off - set INZSH_SALAH_AUTOLOCATE=1 to permit it'
    return 1
  fi

  [[ -n $now ]] || now=${EPOCHSECONDS-}
  if [[ $now != <-> ]]; then
    print -ru2 -- 'inzsh locate: no clock to age the stored position against'
    return 1
  fi

  if (( ! force )); then
    _inzsh_salah_autolocate_ttl
    local -i ttl=$REPLY
    if _inzsh_salah_location_read "$now" &&
       (( _inzsh_salah_location_age >= 0 && _inzsh_salah_location_age < ttl )); then
      _inzsh_doctor_age $_inzsh_salah_location_age
      print -r -- "position current (refreshed $REPLY ago) - 'inzsh locate --force' looks it up anyway"
      return 0
    fi
  fi

  if _inzsh_salah_locate_fetch "$now"; then
    print -r -- 'position refreshed'
    return 0
  fi

  # The lookup did not work, and the two aftermaths deserve different sentences: a stale answer
  # still on disk is what the segment keeps running on, and no answer at all means the segment
  # stays absent until one arrives.
  if _inzsh_salah_location_read "$now"; then
    print -ru2 -- 'inzsh locate: the lookup failed - the previously stored position is kept'
  else
    print -ru2 -- 'inzsh locate: the lookup failed and no position is stored'
  fi

  return 1
}

# `inzsh salah [--days N] [--now epoch]` — issue #230. The library that computes a prayer table
# has never had a way to ask it by hand: `lib/segments/salah.zsh` only ever shows the ONE moment
# next on the clock, and `inzsh doctor`'s `salah` rows only ever say whether a table is cached,
# never what is in it — deliberately, since a doctor block is meant to be pasted into a public
# issue. This command is the missing third reader: the whole day, or several of them, printed on
# request by someone who typed for it.
#
#   inzsh salah                 today
#   inzsh salah --days 7        today and the next six
#   inzsh salah --now <epoch>   the injected clock the pinned suite pins
#
# EVERY ARGUMENT IS A FLAG, on purpose. `--days 7` and not a bare `7`: CONVENTIONS.md's Commands
# section states the rule outright — a positional is only allowed when the value names itself,
# and "seven what" is not recoverable from the digit alone. `--now` gets the same treatment even
# though it exists purely for a test seam: `inzsh locate --now <epoch>` (issue #251) is the other
# command with the identical seam, and the two share the flag rather than drifting into separate
# idioms for the same clock.
#
# THE HEADER NAMES THE METHOD, THE ASR SCHOOL AND THE ZONE — never the position, and never
# anything derived from it. The method and school are `inzsh doctor`'s own `recipe` line, read
# the identical way for the identical reason stated at the top of this file: a method name is
# configuration a reader can act on, and a hash of a coordinate is not a redaction of it, merely
# a slow encoding — issue #229 learned that the hard way, and this command reuses the fix rather
# than re-inventing a narrower one.
#
# THE ZONE IS JUDGED THE SAME WAY, DELIBERATELY, RATHER THAN ASSUMED SAFE. What is printed is the
# AMBIENT zone the numbers were actually rendered in — `%Z %z` read once, at the instant this
# command runs — and it is never read from `INZSH_SALAH_LAT`/`LON` or from
# `_inzsh_salah_location`'s answer. A shell can have its coordinates configured for Mecca and its
# system clock set to `America/New_York` at the same moment — logged into a machine on the other
# side of the planet from where the position was configured — and this header would print the
# New York zone regardless, which is the proof the two are independent rather than one leaking
# through the other. It is also categorically coarser than a coordinate: a zone names a country
# or a slice of one, `Africa/Algiers` tells a reader nothing a stranger glancing at the same
# terminal's own clock could not already see, and it sits in exactly the same bucket `inzsh
# doctor` already prints as `locale` a few rows up — environment a reader needs to make sense of
# the numbers, not a position anyone gave away.
#
# THE COORDINATES ARE READ AND NEVER PRINTED. `$lat`/`$lon` below reach exactly one place, the
# argument list of `_inzsh_salah_times`, and nothing else in this function ever reads them again.
#
# DAY ITERATION NEVER ADDS 86400 SECONDS TO A WALL-CLOCK INSTANT. `lib/salah/cache.zsh` names the
# failure this avoids: an instant late in the evening before a spring-forward, plus 24 hours,
# lands on the day AFTER tomorrow, because the clock only advanced 23 hours where the arithmetic
# assumed 24. This function asks `_inzsh_salah_day_origin` for "today" exactly once, against the
# injected instant in the AMBIENT zone — the one place a civil day is allowed to depend on a zone
# at all, and the same rule `lib/salah/calc.zsh`'s own header states. Every day after that is
# reached by asking `_inzsh_salah_day_origin` again, in `UTC`, for an instant thirty-six hours
# past the previous day's own origin. UTC never observes a daylight-saving transition, so that
# second call can never skip a day or repeat one, and feeding its answer straight back to
# `_inzsh_salah_times` with `tz=UTC` reproduces exactly the origin it was built from —
# self-consistent by construction, and proved in the unit spec across the same United States
# spring-forward date `lib/salah/cache.zsh`'s own comment describes.
#
# ABSENT PRAYERS ARE MARKED, NEVER BLANK. Where `_inzsh_salah_format` cannot draw a time — the
# sentinel `_inzsh_salah_absent` from `lib/salah/calc.zsh`, at a latitude the sun will not
# cooperate with — the row prints that same word, `none`, rather than leaving a gap a reader
# could mistake for a rendering accident.
#
# Outcomes go to stdout; refusals go to stderr with status 1, exactly as `_inzsh_locate` above.
_inzsh_salah_command() {
  emulate -L zsh

  if (( ! ${+functions[_inzsh_salah_location]} )); then
    print -ru2 -- 'inzsh salah: the prayer library is not loaded'
    return 1
  fi

  local -i days=1
  local now=
  while (( $# )); do
    case $1 in
      (--days)
        shift
        if [[ ${1-} != <1-366> ]]; then
          print -ru2 -- 'inzsh salah: --days wants a whole number from 1 to 366'
          return 1
        fi
        days=$1
        shift
        ;;
      (--now)
        shift
        if [[ ${1-} != <-> ]]; then
          print -ru2 -- 'inzsh salah: --now wants an epoch - whole seconds since 1970'
          return 1
        fi
        now=$1
        shift
        ;;
      (*)
        print -ru2 -- \
          "inzsh salah: unknown flag '$1' - usage: inzsh salah [--days N] [--now epoch]"
        return 1
        ;;
    esac
  done

  [[ -n $now ]] || now=${EPOCHSECONDS-}
  if [[ $now != <-> ]]; then
    print -ru2 -- 'inzsh salah: no clock to compute against'
    return 1
  fi

  if ! _inzsh_salah_location "$now"; then
    print -ru2 -- \
      "inzsh salah: no position configured - set INZSH_SALAH_LAT/INZSH_SALAH_LON, or 'inzsh locate' once INZSH_SALAH_AUTOLOCATE is on"
    return 1
  fi
  local -a where=(${=REPLY})
  if (( ${#where} != 2 )); then
    print -ru2 -- \
      "inzsh salah: no position configured - set INZSH_SALAH_LAT/INZSH_SALAH_LON, or 'inzsh locate' once INZSH_SALAH_AUTOLOCATE is on"
    return 1
  fi
  local lat=${where[1]} lon=${where[2]}

  if ! _inzsh_salah_day_origin "$now" ''; then
    print -ru2 -- 'inzsh salah: could not place that clock on a calendar'
    return 1
  fi
  local -i origin=$REPLY

  local method=${_inzsh_salah_default_method:-MWL}
  if (( ${+functions[_inzsh_salah_method_key]} )); then
    _inzsh_salah_method_key "${INZSH_SALAH_METHOD-}"
    [[ -n ${_inzsh_salah_methods[$REPLY]-} ]] && method=$REPLY
  fi
  local asr=standard
  [[ ${(L)INZSH_SALAH_ASR-} == (standard|shafi|hanafi) ]] && asr=${(L)INZSH_SALAH_ASR}

  local zone_disp=unknown
  strftime -s zone_disp '%Z %z' "$now" 2>/dev/null || zone_disp=unknown

  print -r -- 'InZsh prayer times'
  _inzsh_doctor_row method "$method, asr $asr"
  _inzsh_doctor_row zone "$zone_disp"

  local -i i epoch
  local name day_label clock
  local -a date pairs
  for (( i = 0; i < days; i++ )); do
    epoch=$(( origin + 43200 ))

    if ! _inzsh_salah_civil_date "$epoch" UTC; then
      print -ru2 -- 'inzsh salah: could not place a day on the calendar'
      return 1
    fi
    date=(${=REPLY})
    printf -v day_label '%04d-%02d-%02d' "${date[1]}" "${date[2]}" "${date[3]}"

    _inzsh_salah_times "$epoch" "$lat" "$lon" UTC

    pairs=()
    for name in "${_inzsh_salah_prayers[@]}"; do
      if _inzsh_salah_format "${_inzsh_salah_reply[$name]}" '' '%H:%M'; then
        clock=$REPLY
      else
        clock=$_inzsh_salah_absent
      fi
      pairs+="$name $clock"
    done
    _inzsh_doctor_row "$day_label" "${(j:  :)pairs}"

    (( i + 1 < days )) || break

    if ! _inzsh_salah_day_origin $(( origin + 129600 )) UTC; then
      print -ru2 -- 'inzsh salah: could not advance to the next day'
      return 1
    fi
    origin=$REPLY
  done

  return 0
}

# `inzsh preset [name]` — the register, switched in the shell you are already typing in.
#
# The other half of `INZSH_PRESET` (issue #211). That knob is read at SOURCE time, and correctly
# so: `PS2`, `SPROMPT` and the title are built once from the roles resolved then, so a register
# applied later would move the ribbon and quietly leave those behind. Setting the knob at a
# prompt therefore does nothing, and the only live switch was `source <install>/presets/
# inzsh-warm.zsh` — a path nobody remembers, and one that does not exist in a bundle at all.
#
#   inzsh preset          the register in force, and the names there are
#   inzsh preset warm     switch, now, for every prompt after this one
#
# It reads NO FILE. `_inzsh_preset_registers` in `lib/core/tokens.zsh` is the whole vocabulary —
# a preset is a name for a register and nothing more — which is what makes this work identically
# from a clone with a `presets/` directory and from the single-file bundle without one.
#
# What it covers, and it is deliberately the whole of what the load-time knob covers: the roles,
# the knob itself, and the secondary prompts the theme owns. What it cannot do is reach a shell
# that is not this one, or the prompt already on the screen — the next one is drawn from the new
# roles. Outcomes go to stdout; refusals go to stderr with status 1.
_inzsh_preset() {
  emulate -L zsh

  if (( ! ${+_inzsh_preset_registers} )); then
    print -ru2 -- 'inzsh preset: the token layer is not loaded'
    return 1
  fi

  local -a names=(${(ko)_inzsh_preset_registers})
  local offer="${(j: · :)names}"

  if (( $# > 1 )); then
    print -ru2 -- "inzsh preset: one name at a time - $offer"
    return 1
  fi

  # Nothing typed: what is in force and what else there is. The REGISTER is the truth rather than
  # the knob — somebody who sourced a preset file by hand moved one and not the other — so the
  # name is read back OUT of the table, and a register the table cannot name is printed as itself
  # rather than guessed at. Empty is unset at every level of this theme, so an argument that
  # expanded to nothing is this case too and not a refusal.
  if [[ -z ${1-} ]]; then
    local current=${(k)_inzsh_preset_registers[(r)${_inzsh_register-}]}
    print -r -- "preset: ${current:-${_inzsh_register:-unknown}}"
    print -r -- "available: $offer"
    return 0
  fi

  _inzsh_preset_normalize "$1"
  local name=$REPLY
  if [[ -z ${_inzsh_preset_registers[$name]-} ]]; then
    print -ru2 -- "inzsh preset: '$1' is not a preset - $offer"
    return 1
  fi

  # The knob is set to the canonical name and the applier reads it, so this command and the
  # entry point run the same code to reach the same register. Setting it is not bookkeeping: a
  # shell whose knob disagreed with the register it is drawing would be lying to everything that
  # reads it back — `inzsh doctor`, the report above, a plugin manager that re-sources the theme.
  typeset -g INZSH_PRESET=$name
  _inzsh_preset_apply

  # And the part the load-time rule exists for. The secondary prompts are built once, at install,
  # so a switch has to rebuild them or the continuation prompt stays in the register the shell
  # started in. Only when the theme OWNS them: `_inzsh_prompts_saved` holds what install found,
  # so its absence means somebody else's `PS2` is in force and it is none of our business.
  if (( ${+_inzsh_prompts_saved} && ${+functions[_inzsh_prompts_ps2]} )); then
    _inzsh_prompts_ps2
    typeset -g PS2=$REPLY
    _inzsh_prompts_sprompt
    typeset -g SPROMPT=$REPLY
  fi

  print -r -- "preset: $name"

  return 0
}

# The public command. One name in the user's namespace, subcommands under it, so what the theme
# offers to be TYPED stays one word wide however many verbs it grows.
inzsh() {
  emulate -L zsh

  case ${1-} in
    (doctor)
      shift
      _inzsh_doctor "$@"
      ;;
    (locate)
      shift
      _inzsh_locate "$@"
      ;;
    (preset)
      shift
      _inzsh_preset "$@"
      ;;
    (salah)
      shift
      _inzsh_salah_command "$@"
      ;;
    (*)
      print -ru2 -- \
        'usage: inzsh doctor | inzsh locate [--force] [--now epoch] | inzsh preset [name] | inzsh salah [--days N] [--now epoch]'
      return 1
      ;;
  esac
}
