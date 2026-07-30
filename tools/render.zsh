#!/usr/bin/env zsh
# InZsh — the M1 demonstration renderer. NOT the engine.
#
# There are no segments yet; the renderer proper lands at M2. What exists today is the surface
# assignment machinery and the role palette, and the only way to judge either is to look at
# them, so this file draws a fixed sample prompt out of both. Its entire purpose is to produce
# an artifact a human can review: does the 256-colour fallback still look like the theme, and
# does the dark register's negative read as pink rather than as an alarm?
#
# Every label below is made up. No segment computes anything, nothing here is on a prompt's
# render path, and none of this code survives M2 — the engine will draw from real segments and
# this file becomes a thin wrapper around it.
#
# Run it, never source it into a live shell:
#
#   zsh -f tools/render.zsh                     # defaults: sharp, detected depth, alternate
#   INZSH_PRESET=warm zsh -f tools/render.zsh   # the other register
#   zsh -f tools/render.zsh --labels            # just the segment labels, one per line
#
# Honours INZSH_PRESET (sharp|warm), INZSH_COLOR_DEPTH (truecolor|256|8, passed straight
# through to detection) and INZSH_SURFACE_MODE (alternate|ramp|flat). Each falls back the way
# the library does — an unreadable value degrades, it never fails.

_inzsh_demo_root=${${(%):-%x}:A:h:h}

# Dependency order, the same one `inzsh.zsh-theme` uses. The theme file itself is not sourced
# here: it no-ops in a non-interactive shell, which is exactly what this is.
source $_inzsh_demo_root/lib/core/detect.zsh
source $_inzsh_demo_root/lib/core/tokens-256.zsh
source $_inzsh_demo_root/lib/core/tokens.zsh
source $_inzsh_demo_root/lib/core/render.zsh

# The powerline separator, U+E0B0. Defined once, here, because the token layer has no glyph
# entry yet — separator glyphs belong to the token layer and move there with the engine at M2.
# A segment may never carry its own; this variable is the M1 stand-in for that rule, not an
# exception to it.
_inzsh_demo_sep=$'\ue0b0'

# The sample prompt, as four parallel arrays. Neutral data only: a repo path, a branch name, a
# virtualenv, three state glyphs, a clock and a prayer time. Nothing is read from the machine.
_inzsh_demo_names=(DIR GIT VENV STATUS CLOCK SALAH)
_inzsh_demo_labels=('~/dev/inzsh' 'main' 'venv' '✓ ✕ !' '12:04' 'Maghrib · 19:59')
_inzsh_demo_fgroles=(text-strong text-body text-muted text-body text-muted on-accent)
# What `ramp` reads. `alternate` and `flat` ignore them, which is the point of having a mode.
_inzsh_demo_weights=(1 2 3 2 3 1)

# The reserved accent: exactly one segment in the prompt may take the accent fill, and it takes
# `on-accent` for its text. Caramel is the theme's single saturated colour in both registers —
# spend it twice and it stops meaning anything.
_inzsh_demo_accent_at=6

_inzsh_demo_render() {
  emulate -L zsh

  local preset=${INZSH_PRESET:-sharp}
  case $preset in
    (sharp|warm) ;;
    (*) preset=sharp ;;  # config never breaks the render — same rule as the library's
  esac
  source $_inzsh_demo_root/presets/inzsh-$preset.zsh

  # Two flags, both for the harnesses rather than for a human: `--labels` lets a test derive
  # what it should be looking at instead of hardcoding it, and `--prompt-only` drops the legend
  # so the render is exactly one terminal row.
  local legend=1 arg
  for arg in "$@"; do
    case $arg in
      (--labels)      print -rl -- "${_inzsh_demo_labels[@]}"; return 0 ;;
      (--prompt-only) legend=0 ;;
      (*)             print -ru2 -- "render.zsh: unknown argument: $arg"; return 2 ;;
    esac
  done

  local -i n=${#_inzsh_demo_names}

  # One call, for the whole visible run — adjacency is a property of the sequence, so no
  # segment gets to choose its own surface.
  _inzsh_surface_assign $n "${_inzsh_demo_weights[@]}"
  local -a surfaces=("${reply[@]}")
  local mode=$_inzsh_surface_mode_resolved
  local verdict=ok
  _inzsh_surfaces_valid $mode "${surfaces[@]}" || verdict=ADJACENT-COLLISION

  # The accent fill replaces the assigned surface for its one segment. It is not a surface and
  # cannot collide with one, so the invariant above is still checked against what was assigned.
  surfaces[$_inzsh_demo_accent_at]=accent

  # Resolve both channels through `_inzsh_seg_color`, the same entry point a real segment will
  # use — so INZSH_DIR_BG and friends already work here, and the demo exercises the precedence
  # rather than reimplementing it.
  local -a bg fg
  local -i i
  for (( i = 1; i <= n; i++ )); do
    _inzsh_seg_color ${_inzsh_demo_names[i]} bg ${surfaces[i]} surface
    bg[i]=$REPLY
    _inzsh_seg_color ${_inzsh_demo_names[i]} fg ${_inzsh_demo_fgroles[i]} text-body
    fg[i]=$REPLY
  done

  local -a body
  for (( i = 1; i <= n; i++ )); do
    body[i]="%F{${fg[i]}}${_inzsh_demo_labels[i]}"
  done

  # The state glyphs, the one segment with three foregrounds: positive, negative, caution, each
  # with its own glyph so the colour is never the only signal. This is what D7 is judged on —
  # in the dark register `negative` is madder-bright, a dusty rose, and the question the artifact
  # answers is whether that reads as a state or as decoration.
  body[4]="%F{${_inzsh_role[positive-text]}}✓ %F{${_inzsh_role[negative]}}✕ "
  body[4]+="%F{${_inzsh_role[caution]}}!"

  # Chain the blocks. Each separator is drawn in the PREVIOUS segment's background over the
  # NEXT one's, which is what makes a filled prompt read as one ribbon rather than as a row of
  # chips; the last one is drawn over the terminal's own background.
  local drawn=''
  for (( i = 1; i <= n; i++ )); do
    drawn+="%K{${bg[i]}} ${body[i]} "
    if (( i < n )); then
      drawn+="%K{${bg[i+1]}}%F{${bg[i]}}${_inzsh_demo_sep}"
    else
      drawn+="%k%F{${bg[i]}}${_inzsh_demo_sep}"
    fi
  done
  drawn+='%f%k'

  print -r -- "${(%%)drawn}"
  if (( legend )); then
    print -r -- "legend: preset=$preset register=$_inzsh_register depth=$_inzsh_color_depth" \
      "mode=$mode surfaces=${(j:,:)surfaces} adjacency=$verdict"
  fi
}

_inzsh_demo_render "$@"
