Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/venv.zsh

# The Python environment segment — `lib/segments/venv.zsh`. What it REGISTERS when it loads, and
# what FRAGMENT it writes into `_inzsh_segment_text[VENV]` for a given `$VIRTUAL_ENV` and
# `$CONDA_DEFAULT_ENV`. The foreground role is asserted as the role NAME registered, plus the
# structural fact that the token layer carries one by that name — no hex and no palette value
# reaches this file.
#
# What is NOT here, and where it is instead:
#   how a fragment becomes a block   test/render/render_build_spec.sh
#   rank sorting and the side split  test/unit/engine_spec.sh

# Build with the two environments injected as arguments. The text map is cleared first, so an
# entry in the answer was written by THIS call.
inzsh_spec_venv() {
  emulate -L zsh

  _inzsh_segment_text=()
  _inzsh_segment_venv_build "$@"

  print -r -- "[${_inzsh_segment_text[VENV]}]"
}

Describe 'the venv segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers rank 60, an informational foreground and the middle of the importance ramp'
      registered() {
        _inzsh_rank_of VENV
        print -r -- "$REPLY ${_inzsh_segment_fg_role[VENV]} ${_inzsh_segment_importance[VENV]}"
      }
      When call registered
      The output should eq '60 info-text 2'
    End

    It 'registers a foreground role the token layer actually carries'
      roled() {
        local role=${_inzsh_segment_fg_role[VENV]}
        [[ -n ${_inzsh_role[$role]+set} ]] && print -r -- known || print -r -- "unknown:$role"
      }
      When call roled
      The output should eq 'known'
    End

    It 'writes no text at load — registering is not drawing'
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/venv.zsh"
          print -r -- "entries=${#_inzsh_segment_text} venv=${_inzsh_segment_text[VENV]+set}"
        ' inzsh-venv-quiet "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'entries=0 venv='
      The stderr should eq ''
    End

    It 're-sources without doubling a registration or clearing a written fragment'
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/venv.zsh"
          _inzsh_segment_text[VENV]=keep
          source "$1/lib/segments/venv.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${_inzsh_segment_defaults[VENV]}" \
            "${#_inzsh_segment_fg_role} ${_inzsh_segment_fg_role[VENV]}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_importance[VENV]}" \
            "${_inzsh_segment_text[VENV]}"
        ' inzsh-venv-idempotent "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 60 1 info-text 1 2 keep'
      The stderr should eq ''
    End

    It 'is sourceable on its own, with no core loaded at all'
      alone() {
        zsh -f -c '
          source "$1/lib/segments/venv.zsh"
          _inzsh_segment_venv_build /opt/envs/api ""
          print -r -- "[${_inzsh_segment_text[VENV]}]"
        ' inzsh-venv-alone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call alone
      The output should eq '[api]'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the fragment'
    # $1 the virtualenv path, $2 the conda environment, $3 what must land in the text map.
    Parameters
      /home/dev/project/.venv  ''                   '[.venv]'
      /opt/envs/api            ''                   '[api]'
      /opt/envs/api/           ''                   '[api]'
      /opt/envs/api///         ''                   '[api]'
      relative/path/api        ''                   '[api]'
      api                      ''                   '[api]'
      ''                       base                 '[base]'
      ''                       /opt/conda/envs/ml   '[ml]'
      ''                       'ml/'                '[ml]'
      ''                       ''                   '[]'
      '   '                    ''                   '[]'
      ''                       '   '                '[]'
      '  /opt/envs/api  '      ''                   '[api]'
      ''                       '  ml  '             '[ml]'
      /                        ''                   '[]'
      ///                      ''                   '[]'
      '/opt/en vs/my env'      ''                   '[my env]'
      '/opt/envs/%'            ''                   '[%%]'
      '/opt/envs/%~'           ''                   '[%%~]'
      '%'                      ''                   '[%%]'
      '/opt/envs/py3.12-api'   ''                   '[py3.12-api]'
    End

    It "draws venv ($1) and conda ($2) as $3"
      When call inzsh_spec_venv "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe 'the name, never the path'
    # A full path is both too wide for a block and a directory structure nobody asked to
    # publish. Whatever comes in, what goes out is one component.
    Parameters
      /home/dev/deeply/nested/project/.venv
      /Users/dev/Library/Caches/pypoetry/virtualenvs/api-x9-py3.12
      /opt/envs/api/
    End

    It "keeps no separator from ($1)"
      pathless() {
        _inzsh_segment_text=()
        _inzsh_segment_venv_build "$1" ''
        local text=${_inzsh_segment_text[VENV]}
        local -a wrong=()
        [[ -n $text ]]      || wrong+=empty
        [[ $text != */* ]]  || wrong+=slash
        [[ $1 == *"$text"* ]] || wrong+=not-a-component
        print -r -- "${wrong[*]}"
      }
      When call pathless "$1"
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'when both are active'
    # Not a tie. A conda base environment stays activated across a whole session and a `venv`
    # activated over it prepends its own `bin` to PATH, so the virtualenv is the one that owns
    # `python` — and the prompt names the interpreter that will actually run.
    It 'names the virtualenv and not the conda environment'
      When call inzsh_spec_venv /home/dev/project/.venv datascience
      The output should eq '[.venv]'
    End

    It 'falls through to conda when the virtualenv is set but empty'
      # Set-but-empty is unset everywhere else in this tree, and it is unset here too: an
      # exported `VIRTUAL_ENV=` left behind by a broken deactivate must not hide a live conda.
      When call inzsh_spec_venv '' datascience
      The output should eq '[datascience]'
    End

    It 'falls through to conda when the virtualenv is nothing but whitespace'
      When call inzsh_spec_venv '   ' datascience
      The output should eq '[datascience]'
    End

    It 'clears the fragment it wrote at an earlier prompt'
      # The map outlives the prompt. A build that only wrote on the visible path would leave the
      # last environment it drew sitting there, and the prompt would go on naming an interpreter
      # that was deactivated two commands ago.
      stale() {
        _inzsh_segment_text=()
        _inzsh_segment_venv_build /opt/envs/api ''
        local first=${_inzsh_segment_text[VENV]}
        _inzsh_segment_venv_build '' ''
        print -r -- "first=[$first] second=[${_inzsh_segment_text[VENV]}]"
      }
      When call stale
      The output should eq 'first=[api] second=[]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the live parameters'
    It 'reads $VIRTUAL_ENV and $CONDA_DEFAULT_ENV when no argument is given'
      defaulted() {
        zsh -f -c '
          source "$1/lib/segments/venv.zsh"
          local -a wrong=()
          VIRTUAL_ENV=/opt/envs/api
          CONDA_DEFAULT_ENV=
          _inzsh_segment_venv_build
          [[ ${_inzsh_segment_text[VENV]} == api ]] || wrong+=virtualenv
          VIRTUAL_ENV=
          CONDA_DEFAULT_ENV=datascience
          _inzsh_segment_venv_build
          [[ ${_inzsh_segment_text[VENV]} == datascience ]] || wrong+=conda
          VIRTUAL_ENV=/opt/envs/api
          CONDA_DEFAULT_ENV=datascience
          _inzsh_segment_venv_build
          [[ ${_inzsh_segment_text[VENV]} == api ]] || wrong+=both
          VIRTUAL_ENV=
          CONDA_DEFAULT_ENV=
          _inzsh_segment_venv_build
          [[ -z ${_inzsh_segment_text[VENV]} ]] || wrong+=neither
          print -r -- "${wrong[*]}"
        ' inzsh-venv-default "$SHELLSPEC_PROJECT_ROOT"
      }
      When call defaulted
      The output should eq ''
      The stderr should eq ''
    End

    It 'draws the environment even with VIRTUAL_ENV_DISABLE_PROMPT set'
      # A deliberate reading. That variable tells the ACTIVATION SCRIPT to stop editing PS1; it
      # is what a theme user sets so the theme can draw the environment itself. Treating it as
      # "hide the environment" would punish exactly the people who configured things correctly.
      # `INZSH_VENV_RANK=0` is where "do not draw this" is said.
      disabled() {
        zsh -f -c '
          source "$1/lib/segments/venv.zsh"
          VIRTUAL_ENV_DISABLE_PROMPT=1
          VIRTUAL_ENV=/opt/envs/api
          CONDA_DEFAULT_ENV=
          _inzsh_segment_venv_build
          print -r -- "[${_inzsh_segment_text[VENV]}]"
        ' inzsh-venv-disable-prompt "$SHELLSPEC_PROJECT_ROOT"
      }
      When call disabled
      The output should eq '[api]'
      The stderr should eq ''
    End

    It 'prefers the arguments to the live parameters'
      injected() {
        typeset -g VIRTUAL_ENV=/opt/envs/live
        typeset -g CONDA_DEFAULT_ENV=live-conda
        local -a wrong=()
        _inzsh_segment_venv_build /opt/envs/argument ''
        [[ ${_inzsh_segment_text[VENV]} == argument ]] || wrong+=venv-arg
        _inzsh_segment_venv_build '' argument-conda
        [[ ${_inzsh_segment_text[VENV]} == argument-conda ]] || wrong+=conda-arg
        _inzsh_segment_venv_build '' ''
        [[ ${_inzsh_segment_text[VENV]} == '' ]] || wrong+=absent
        print -r -- "${wrong[*]}"
      }
      When call injected
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'in the prompt'
    It 'puts the environment name in the ribbon when one is active'
      drawn() {
        _inzsh_segment_text=()
        _inzsh_segment_venv_build /opt/envs/api ''
        _inzsh_left=(VENV)
        _inzsh_render_build left
        [[ $REPLY == *' api '* ]] && print -r -- drawn || print -r -- "missing:$REPLY"
      }
      When call drawn
      The output should eq 'drawn'
    End

    It 'leaves no block and no separator when none is'
      undrawn() {
        _inzsh_segment_text=()
        _inzsh_segment_venv_build '' ''
        _inzsh_left=(VENV)
        _inzsh_render_build left
        print -r -- "len=${#REPLY} width=$_inzsh_render_width"
      }
      When call undrawn
      The output should eq 'len=0 width=0'
    End

    It 'is not re-expanded as a prompt escape'
      # `%~` as an environment name is the trap: spliced raw into PROMPT it would expand to the
      # working directory. Doubled, it reaches the screen as the two characters it is.
      literal() {
        _inzsh_segment_text=()
        _inzsh_segment_venv_build '/opt/envs/%~' ''
        _inzsh_left=(VENV)
        _inzsh_render_build left
        local expanded=${(%%)REPLY}
        [[ $expanded == *'%~'* ]] && print -r -- literal || print -r -- "expanded:$expanded"
      }
      When call literal
      The output should eq 'literal'
    End

    It 'measures as the characters a reader sees, not as the escaped ones'
      measured() {
        _inzsh_segment_text=()
        _inzsh_segment_venv_build '/opt/envs/%' ''
        _inzsh_width "${_inzsh_segment_text[VENV]}"
        print -r -- "$REPLY"
      }
      When call measured
      The output should eq '1'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the no-fork rule'
    # Structural: the rule is about the TEXT of the file. Comments are skipped — they name
    # `basename` precisely to say it is not called.
    It 'contains no command substitution and no external command'
      grepped() {
        setopt local_options extended_glob
        local line bare; local -a found=()
        local forks='basename|dirname|readlink|realpath|python|python3'
        while IFS= read -r line; do
          bare=${line##[[:space:]]#}
          [[ -z $bare || $bare == \#* ]] && continue
          [[ $bare == *'$('* ]]  && found+="subst:$bare"
          [[ $bare == *'`'* ]]   && found+="backtick:$bare"
          [[ $bare == (*[^A-Za-z0-9_]|)(${~forks})([^A-Za-z0-9_]*|) ]] && found+="fork:$bare"
        done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/venv.zsh"
        print -r -- "${found[*]}"
      }
      When call grepped
      The output should eq ''
    End
  End
End
