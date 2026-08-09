Include lib/core/config.zsh
Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/dir.zsh

# The `dir` segment — `lib/segments/dir.zsh`. Two claims, and everything below is one of them:
# the segment REGISTERS itself and nothing more at load time, and it BUILDS a fragment from the
# path it is handed rather than from the shell it happens to be running in.
#
# Nothing here moves the shell. Every example passes a path, which is the injection seam the
# segment exists to have; the one example that does move a shell is the deleted-`$PWD` case,
# and it moves a `zsh -f` in a temp directory rather than this one.
#
# No hex, and no palette value: the one example that pins colour reads the role the segment
# registered back out of `_inzsh_role`, so a palette change cannot fail it and a change of role
# can.
#
# What is NOT here, and where it is instead:
#   the truncation ladder itself   test/unit/layout_spec.sh
#   the chaining and the widths    test/render/render_build_spec.sh
#   rank sorting                   test/unit/engine_spec.sh

# A neutral home directory throughout — nothing here reads the machine. `$@` is passed through
# untouched so that "no argument" stays distinguishable from "an empty argument".
inzsh_spec_dir() {
  local HOME=/spec/home
  _inzsh_segment_dir_build "$@"
  print -r -- "${_inzsh_segment_text[DIR]}"
}

# What sourcing the segment file changes, as a sorted list of parameter names. $1 is how many
# times it has already been sourced when the first snapshot is taken, so 0 asks what
# REGISTRATION touches and 1 asks what a RE-SOURCE touches — which must be nothing at all.
#
# Snapshots go to files rather than to locals, so that holding one cannot perturb the other.
# RANDOM and SECONDS move between any two snapshots on their own; they are the only volatile
# names zsh reports here.
# The five maps registration writes, in the sorted order the snapshot reports them. Assembled
# rather than wrapped: the matcher takes one argument, and a continuation would make it two.
inzsh_spec_dir_maps='_inzsh_segment_bg_role _inzsh_segment_defaults _inzsh_segment_fg_role'
inzsh_spec_dir_maps+=' _inzsh_segment_importance _inzsh_segment_priority'

inzsh_spec_dir_touches() {
  local snap=${SHELLSPEC_TMPBASE:-${TMPDIR:-/tmp}}/inzsh-dir-registration
  mkdir -p $snap
  zsh -f -c '
    local root=$1 snap=$2; local -i pre=$3 i
    for (( i = 1; i <= pre; i++ )); do source $root/lib/segments/dir.zsh; done
    typeset -p >| $snap/before
    source $root/lib/segments/dir.zsh
    typeset -p >| $snap/after
    local -a before=("${(f)$(<$snap/before)}") after=("${(f)$(<$snap/after)}")
    local line; local -a touched=()
    (( ${#before} > 1 && ${#after} > 1 )) || touched+=snapshot-empty
    for line in $after;  do (( ${before[(Ie)$line]} )) || touched+=${${line%%=*}##* }; done
    for line in $before; do (( ${after[(Ie)$line]} ))  || touched+=${${line%%=*}##* }; done
    touched=(${(ou)touched})
    # `functions` is zsh/parameter surfacing on its first reference — the guarded knob
    # registration at the foot of the file asks `${+functions[...]}` — not state the segment
    # wrote. RANDOM and SECONDS move between any two snapshots on their own.
    touched=(${touched:#(RANDOM|SECONDS|functions)})
    print -r -- "${touched[*]}"
  ' inzsh-dir-registration "$SHELLSPEC_PROJECT_ROOT" "$snap" "$1"
}

Describe 'the dir segment'
  # ------------------------------------------------------------------------------------------
  Describe 'registration'
    # Three writes and a rank default, done at load time, and the file may do nothing else.
    Describe 'the maps it fills'
      # $1 the map, $2 what DIR must be worth in it.
      Parameters
        _inzsh_segment_defaults    40
        _inzsh_segment_fg_role     text-body
        _inzsh_segment_importance  1
      End

      It "registers $2 in $1"
        registered() {
          local -A map=("${(@Pkv)1}")
          print -r -- "${map[DIR]-<unset>}"
        }
        When call registered "$1"
        The output should eq "$2"
      End
    End

    It 'registers a rank the engine can read back, and one a user still outranks'
      # The default is only a default: `INZSH_DIR_RANK` wins over it, and a rank of 0 hides the
      # segment like any other. The registry is the last word, never the first.
      ranked() {
        local -a seen=()
        _inzsh_rank_of dir;  seen+=$REPLY
        _inzsh_rank_of DIR;  seen+=$REPLY
        local INZSH_DIR_RANK=9
        _inzsh_rank_of DIR;  seen+=$REPLY
        INZSH_DIR_RANK=0
        _inzsh_rank_of DIR;  seen+=$REPLY
        INZSH_DIR_RANK=nonsense
        _inzsh_rank_of DIR;  seen+=$REPLY
        print -r -- "${seen[*]}"
      }
      When call ranked
      The output should eq '40 40 9 0 40'
    End

    It 'registers a foreground role the token layer actually carries'
      # A role name with a typo in it costs the segment its colour at draw time and nothing
      # says so. Asked here instead, and asked by NAME so no palette value appears.
      real() {
        print -r -- "${+_inzsh_role[${_inzsh_segment_fg_role[DIR]}]}"
      }
      When call real
      The output should eq '1'
    End

    It 'writes the five maps and nothing else — no text, no state, no side effect'
      When call inzsh_spec_dir_touches 0
      The output should eq "$inzsh_spec_dir_maps"
      The stderr should eq ''
    End

    It 'draws nothing at load time — the text map stays untouched until a build'
      # A segment that registered a fragment would draw the directory it was SOURCED in, which
      # is the wrong one from the first prompt onwards.
      silent() {
        zsh -f -c '
          source "$1/lib/segments/dir.zsh"
          print -r -- "${+_inzsh_segment_text[DIR]} ${+functions[_inzsh_segment_dir_build]}"
        ' inzsh-dir-silent "$SHELLSPEC_PROJECT_ROOT"
      }
      When call silent
      The output should eq '0 1'
      The stderr should eq ''
    End

    It 'is idempotent — a second source changes nothing at all'
      # Bundling, a reload, a plugin manager that sources twice. Anything that DOUBLED — an
      # appended array element, a second registration under another key — shows up here as a
      # parameter that differs between the two snapshots.
      When call inzsh_spec_dir_touches 1
      The output should eq ''
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the path it draws'
    # $1 the path handed in, $2 the fragment. Absolute, relative, bare root, a trailing slash
    # and a doubled one — the normalisation is the layout layer's and this is the contract that
    # it is reached.
    Parameters
      /                     /
      /tmp                  /tmp
      /tmp/                 /tmp
      /usr/local/bin        /usr/local/bin
      //usr//local//        /usr/local
      single                single
      single/               single
      rel/path              rel/path
      '/a b/c d'            '/a b/c d'
      /spec/homely/x        /spec/homely/x
    End

    It "draws $1 as $2"
      When call inzsh_spec_dir "$1"
      The output should eq "$2"
    End
  End

  Describe '$HOME'
    # The collapse that costs the reader nothing, and the three near-misses that must not get
    # it: a prefix that is not a component boundary, a home with a trailing slash of its own,
    # and no home at all.
    Parameters
      /spec/home            '~'
      /spec/home/           '~'
      /spec/home/dev        '~/dev'
      /spec/home/dev/inzsh  '~/dev/inzsh'
      /spec/homely          /spec/homely
      /spec/homeless/x      /spec/homeless/x
      /spec                 /spec
    End

    It "collapses $1 to $2"
      When call inzsh_spec_dir "$1"
      The output should eq "$2"
    End

    It 'draws the whole path when there is no home to collapse'
      homeless() {
        local HOME=
        _inzsh_segment_dir_build /spec/home/dev
        print -r -- "${_inzsh_segment_text[DIR]}"
        unset HOME
        _inzsh_segment_dir_build /spec/home/dev
        print -r -- "${_inzsh_segment_text[DIR]}"
      }
      When call homeless
      The line 1 should eq '/spec/home/dev'
      The line 2 should eq '/spec/home/dev'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the budget'
    # The ladder itself is `test/unit/layout_spec.sh`'s subject. What is asserted here is that
    # the segment REACHES it — same path, several budgets, each rung in turn — and that it adds
    # no shortening of its own.
    Describe 'each rung, through the segment'
      # $1 the budget, $2 the fragment for ~/a/bb/ccc/dddd.
      Parameters
        30 '~/a/bb/ccc/dddd'
        16 '~/a/bb/ccc/dddd'
        15 '~/a/bb/ccc/dddd'
        14 '…/bb/ccc/dddd'
        13 '…/bb/ccc/dddd'
        12 '…/ccc/dddd'
        10 '…/ccc/dddd'
        9  '…/dddd'
        6  '…/dddd'
        5  'dddd'
        4  'dddd'
        3  'dd…'
        1  '…'
      End

      It "fits /spec/home/a/bb/ccc/dddd into $1 columns as $2"
        Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
        When call inzsh_spec_dir /spec/home/a/bb/ccc/dddd "$1"
        The output should eq "$2"
      End
    End

    Describe 'how the path shortens — INZSH_DIR_COMPONENTS'
      # The knob for the SHAPE of the shortening rather than its trigger: keep at most this many
      # trailing components, ellipsis in front, before any budget is even asked. `0` — the
      # default — is the whole path. The ladder below the kept tail is unchanged, so a narrow
      # terminal can still shorten further.
      Describe 'what a value keeps of /spec/home/a/bb/ccc/dddd'
        # $1 the knob, $2 the fragment.
        Parameters
          2    '…/ccc/dddd'
          1    '…/dddd'
          4    '~/a/bb/ccc/dddd'
          0    '~/a/bb/ccc/dddd'
          -1   '~/a/bb/ccc/dddd'
          abc  '~/a/bb/ccc/dddd'
          2.5  '~/a/bb/ccc/dddd'
          ''   '~/a/bb/ccc/dddd'
        End

        It "draws '$2' when the knob is '$1'"
          Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
          kept() {
            local INZSH_DIR_COMPONENTS=$1
            inzsh_spec_dir /spec/home/a/bb/ccc/dddd
          }
          When call kept "$1"
          The output should eq "$2"
        End
      End

      It 'is registered with the config layer, validator and default'
        registered() {
          print -r -- "${_inzsh_config_validators[INZSH_DIR_COMPONENTS]-missing}"
          print -r -- "[${_inzsh_config_defaults[INZSH_DIR_COMPONENTS]-missing}]"
        }
        When call registered
        The line 1 of output should eq 'int:0:'
        The line 2 of output should eq '[0]'
      End

      It 'still obeys the budget below the kept tail'
        Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
        both() {
          local INZSH_DIR_COMPONENTS=2
          inzsh_spec_dir /spec/home/a/bb/ccc/dddd 9
        }
        When call both
        The output should eq '…/dddd'
      End

      It 'reads the knob fresh on every build rather than caching the first answer'
        Skip if 'the locale is not multibyte' inzsh_spec_bytes_not_cells
        live() {
          local -a seen=()
          local INZSH_DIR_COMPONENTS=1
          seen+="[$(inzsh_spec_dir /spec/home/a/bb/ccc/dddd)]"
          INZSH_DIR_COMPONENTS=0
          seen+="[$(inzsh_spec_dir /spec/home/a/bb/ccc/dddd)]"
          print -r -- "${seen[*]}"
        }
        When call live
        The output should eq '[…/dddd] [~/a/bb/ccc/dddd]'
      End

      It 'shortens with the marker the glyph knob chose'
        # Item 5 of #176 in one example: the HOW is this knob, the MARKER is the glyph family's
        # `INZSH_GLYPH_ELLIPSIS`, and the two compose because both are read at build time.
        marked() {
          local INZSH_DIR_COMPONENTS=1 INZSH_GLYPH_ELLIPSIS='>>'
          _inzsh_glyphs_resolve
          local out=$(inzsh_spec_dir /spec/home/a/bb/ccc/dddd)
          unset INZSH_GLYPH_ELLIPSIS
          _inzsh_glyphs_resolve
          print -r -- "$out"
        }
        When call marked
        The output should eq '>>/dddd'
      End
    End

    Describe 'a budget that is not a budget'
      # Unknown width means assume room, the same rule every other layer follows. An empty
      # budget is an unset one, as emptiness is everywhere else in the tree.
      Parameters
        ''
        ' '
        x
        -1
        '3.5'
        ' 4'
        '+4'
        4x
      End

      It "ignores the budget '$1' and draws the whole path"
        When call inzsh_spec_dir /spec/home/a/bb/ccc/dddd "$1"
        The output should eq '~/a/bb/ccc/dddd'
      End
    End

    It 'hands the path and the budget to the layout layer verbatim, and truncates nothing itself'
      # The delegation, proved rather than inferred: `_inzsh_truncate_path` is replaced by a
      # stub that reports its arguments, and whatever it says is what the segment draws. A
      # segment carrying a second copy of the ladder — its own `$HOME` collapse, its own
      # ellipsis — would show up as a difference from the stub's answer.
      delegated() {
        zsh -f -c '
          source "$1/lib/segments/dir.zsh"
          _inzsh_truncate_path() { typeset -g REPLY="<$1|$2>" }
          HOME=/spec/home
          _inzsh_segment_dir_build /spec/home/a/b 9
          print -r -- "${_inzsh_segment_text[DIR]}"
          _inzsh_segment_dir_build /spec/home/a/b
          print -r -- "${_inzsh_segment_text[DIR]}"
        ' inzsh-dir-delegate "$SHELLSPEC_PROJECT_ROOT"
      }
      When call delegated
      The line 1 should eq '</spec/home/a/b|9>'
      The line 2 should eq '</spec/home/a/b|>'
      The stderr should eq ''
    End

    It 'draws the raw path when the layout layer is not loaded at all'
      # The lookup is at call time, so a half-sourced theme draws a longer prompt rather than no
      # prompt. Uncollapsed and unshortened is a worse prompt; an error is not a prompt.
      standalone() {
        zsh -f -c '
          source "$1/lib/segments/dir.zsh"
          HOME=/spec/home
          _inzsh_segment_dir_build /spec/home/a/b 4
          print -r -- "${_inzsh_segment_text[DIR]}"
        ' inzsh-dir-standalone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call standalone
      The output should eq '/spec/home/a/b'
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'presence'
    # `dir` has no absent case. Whatever it is handed, there is a directory to name and the
    # segment names it — it shortens rather than disappearing, which is the whole reason
    # truncation and MINCOLS are separate mechanisms.
    It 'draws something for every path and every budget on the ladder'
      always() {
        local path; local -i budget
        local -a paths=(/ /tmp /spec/home /spec/home/a/bb/ccc/dddd rel/path 'x' '/a b/c')
        local -a empty=()
        for path in "${paths[@]}"; do
          for (( budget = 1; budget <= 24; budget++ )); do
            inzsh_spec_dir "$path" $budget >/dev/null
            [[ -n ${_inzsh_segment_text[DIR]} ]] || empty+=$path:$budget
          done
        done
        print -r -- "${empty[*]}"
      }
      When call always
      The output should eq ''
    End

    It 'is absent at a budget of zero, and only there'
      # The one exception, and it is the layout layer's documented answer to "no room": a caller
      # with no columns to spend should have hidden the segment on MINCOLS instead of asking for
      # a path drawn in none of them. The renderer reads the empty fragment as absent, so the
      # result is a missing block rather than a stray separator.
      When call inzsh_spec_dir /spec/home/a/b 0
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'hostile input'
    It 'reads $PWD when the path is absent, and again when it is empty'
      # Empty means unset, as it does at every other level in the tree. Asserted as an
      # AGREEMENT rather than against a literal, so the example says nothing about which
      # directory the suite happens to run in.
      defaulted() {
        inzsh_spec_dir >/dev/null
        local absent=${_inzsh_segment_text[DIR]}
        inzsh_spec_dir '' >/dev/null
        local blank=${_inzsh_segment_text[DIR]}
        local -a wrong=()
        [[ -n $absent ]]        || wrong+=empty
        [[ $absent == $blank ]] || wrong+=disagree
        print -r -- "${wrong[*]}"
      }
      When call defaulted
      The output should eq ''
    End

    Describe 'paths nobody meant to create'
      # $1 the path, $2 the fragment. Spaces, glob characters, a newline, a component that is
      # longer than any terminal — none of them may error and none may be quietly re-globbed.
      Parameters
        '   '                        '   '
        '/spec/h[o]me/x'             '/spec/h[o]me/x'
        '/spec/home/*'               '~/*'
        '/spec/home/?'               '~/?'
        '/spec/home/~'               '~/~'
        '/tmp/-'                     '/tmp/-'
        '/tmp/--help'                '/tmp/--help'
      End

      It "draws [$1] as [$2] without interpreting it"
        When call inzsh_spec_dir "$1"
        The output should eq "$2"
      End
    End

    It 'survives a $PWD that has been deleted out from under the shell'
      # The parameter still holds the path; the segment never asks the filesystem whether it is
      # still there. A `stat` here would be a fork, a failure, or both — and a prompt that
      # cannot draw because a directory went away is a prompt that fails exactly when its user
      # most needs to see where they are.
      deleted() {
        local base=${SHELLSPEC_TMPBASE:-${TMPDIR:-/tmp}}/inzsh-dir-deleted
        rm -rf $base
        mkdir -p $base/gone
        zsh -f -c '
          source "$1/lib/core/layout.zsh"
          source "$1/lib/segments/dir.zsh"
          HOME=/spec/home
          cd -- "$2/gone" || print -r -- cd-failed
          rmdir -- "$2/gone"
          _inzsh_segment_dir_build
          print -r -- "${_inzsh_segment_text[DIR]//$2/<tmp>}"
        ' inzsh-dir-deleted "$SHELLSPEC_PROJECT_ROOT" "$base"
        rm -rf $base
      }
      When call deleted
      The output should eq '<tmp>/gone'
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'in the prompt'
    # The fragment is a PROMPT string, not plain text, and the two differ in exactly one place:
    # a directory may legally be called `100%`, and a bare `%` opens an escape.
    It 'doubles a per cent so the directory survives prompt expansion'
      percent() {
        local HOME=/spec/home
        _inzsh_segment_dir_build '/spec/home/100%/x'
        local fragment=${_inzsh_segment_text[DIR]}
        _inzsh_width "$fragment"
        print -r -- "raw=[$fragment] drawn=[${(%%)fragment}] cols=$REPLY"
      }
      When call percent
      The output should eq 'raw=[~/100%%/x] drawn=[~/100%/x] cols=8'
    End

    It 'truncates the path before escaping it, so no escape is ever cut in half'
      # `%%` is one column on the screen and two characters in the string. Escaping first would
      # hand the ladder a string two columns wider than the one it is fitting, and a cut between
      # the halves would leave a `%` looking for something to swallow.
      ordered() {
        local HOME=/spec/home
        local -a wrong=(); local -i budget
        for (( budget = 1; budget <= 12; budget++ )); do
          _inzsh_segment_dir_build '/spec/home/pct%%%dir' $budget
          local fragment=${_inzsh_segment_text[DIR]}
          _inzsh_width "$fragment"
          (( REPLY <= budget )) || wrong+=$budget:wide=$REPLY
          [[ ${fragment//'%%'/} != *'%'* ]] || wrong+=$budget:odd
        done
        print -r -- "${wrong[*]}"
      }
      When call ordered
      The output should eq ''
    End

    It 'is drawn in the face it registered, on the surface the renderer chose'
      # The registration read back out of the finished string. The colour is named through
      # `_inzsh_role` and the role through the segment's own map, so a palette change cannot
      # fail this and a change of role can.
      drawn() {
        local HOME=/spec/home
        _inzsh_segment_text=()
        _inzsh_left=(DIR)
        _inzsh_right=()
        _inzsh_segment_dir_build /spec/home/dev
        _inzsh_render_build left
        local face=${_inzsh_role[${_inzsh_segment_fg_role[DIR]}]}
        local -a wrong=()
        [[ $REPLY == *"%F{$face} ~/dev "* ]] || wrong+=face
        [[ $REPLY == '%K{'* ]]               || wrong+=fill
        print -r -- "${wrong[*]}"
      }
      When call drawn
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the render path'
    # Structural, and deliberately so: the rule is about the TEXT of the file. A fork that only
    # runs on some paths is still a fork, and a prompt that shells out is a prompt that can hang
    # on somebody else's filesystem.
    It 'contains no command substitution and no process substitution'
      forkfree() {
        setopt local_options extended_glob
        local line bare backtick=$'\x60'
        local -a found=()
        while IFS= read -r line; do
          bare=${line##[[:space:]]#}
          [[ -z $bare || $bare == \#* ]] && continue
          [[ $bare == *'$('* || $bare == *$backtick* ]] && found+=$bare
          [[ $bare == *'<('* || $bare == *'>('* ]] && found+=$bare
        done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/dir.zsh"
        print -r -- "${found[*]}"
      }
      When call forkfree
      The output should eq ''
    End

    It 'emulates zsh in every function it defines'
      # `emulate -L zsh` is what makes the segment behave the same under a user's `setopt
      # shwordsplit`, `nounset`, `ksharrays` — any of which would otherwise reach in here.
      emulated() {
        setopt local_options extended_glob
        local body
        local -a missing=()
        for body in "${(k)functions[(I)_inzsh_segment_dir_*]}"; do
          [[ ${functions[$body]} == *'emulate -L zsh'* ]] || missing+=$body
        done
        print -r -- "${#missing} ${missing[*]}"
      }
      When call emulated
      The output should eq '0 '
    End
  End
End
