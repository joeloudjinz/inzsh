# InZsh — the Python environment segment. Which interpreter will `python` be?
#
# Registration at load time, one entry in `_inzsh_segment_text` at build time, nothing else. No
# colour is resolved here and no glyph invented: the renderer asks the token layer for the role
# registered below.
#
# NO SUBPROCESS. `$VIRTUAL_ENV` and `$CONDA_DEFAULT_ENV` are exported by the activation scripts
# themselves, so the answer is already in the environment — `basename`, `python -V` and `conda
# info` are all forks for a fact we were handed.
#
# THE NAME, NEVER THE PATH. `$VIRTUAL_ENV` is absolute, so drawing it would put the whole
# directory structure of whatever you are working on into a screenshot, and would take the width
# of three segments to do it. The basename is what the activation prompt shows and what the
# directory is called; anything more is either private or already on the line, since the venv
# usually lives inside the directory the dir segment is drawing.
#
# WHY THE VIRTUALENV WINS WHEN BOTH ARE SET. Both can be live at once, and it is not a tie: a
# conda base environment stays activated across a whole session, and a `venv` activated on top
# of it prepends its own `bin` to PATH. Whichever was activated last, the virtualenv is the one
# that owns `python`, so it is the one the prompt claims. Naming the environment that will not
# run is worse than naming neither.
#
# `VIRTUAL_ENV_DISABLE_PROMPT` IS DELIBERATELY NOT READ, and this is a reading rather than an
# oversight. That variable tells the ACTIVATION SCRIPT not to edit PS1 — it is how you stop a
# tool from writing `(venv) ` into a prompt it does not own. Setting it is what a theme user
# does so the theme can draw the environment properly; treating it as "hide the environment"
# would punish exactly the people who configured things correctly, and would leave them no way
# to have the segment at all. To hide this segment, set `INZSH_VENV_RANK=0` — the rank system is
# where "do not draw this" is said.

# Declared, never assigned wholesale — `typeset -gA` over an existing association keeps what is
# in it, so re-sourcing neither empties a map nor doubles a registration. The declaration is
# also what makes this file sourceable on its own.
typeset -gA _inzsh_segment_text _inzsh_segment_defaults
typeset -gA _inzsh_segment_fg_role _inzsh_segment_importance

# The registration. Rank 5 puts the environment after the directory, where it reads as a
# property of the place rather than of the machine. `info-text` because that is what it is —
# information about the tooling, not a state that can be good or bad — and importance 2, the
# middle of the ramp: it is absent most of the time, and when it is there it is worth reading.
_inzsh_segment_defaults[VENV]=5
_inzsh_segment_fg_role[VENV]=info-text
_inzsh_segment_importance[VENV]=2

# `_inzsh_segment_venv_build [venv-path] [conda-env]` — writes `_inzsh_segment_text[VENV]`.
#
# Both arguments are the injection seam: absent means "read the live shell parameter", present
# means "use this", and present-and-empty means that environment is not active. With neither
# active the entry is empty, which is absent to the renderer: no block, no separator, no
# placeholder. Always status 0.
_inzsh_segment_venv_build() {
  emulate -L zsh
  setopt extended_glob

  typeset -gA _inzsh_segment_text
  _inzsh_segment_text[VENV]=

  local venv=${1-$VIRTUAL_ENV}
  local conda=${2-$CONDA_DEFAULT_ENV}

  venv=${${venv##[[:space:]]#}%%[[:space:]]#}
  conda=${${conda##[[:space:]]#}%%[[:space:]]#}

  # The precedence, in one expansion. `$CONDA_DEFAULT_ENV` is often a bare name rather than a
  # path, which the tail modifier below leaves alone.
  local chosen=${venv:-$conda}
  [[ -n $chosen ]] || return 0

  # Trailing slashes go first, so `/opt/envs/api/` is `api` and not the empty tail of a
  # directory. A value that is nothing but slashes has no name in it at all.
  local name=${chosen%%/##}
  name=${name:t}
  [[ -n $name ]] || return 0

  # Per cent doubled — the fragment is spliced into PROMPT and expanded there, so an environment
  # called `%~` must not expand to a directory.
  _inzsh_segment_text[VENV]=${name//'%'/'%%'}

  return 0
}
