Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/config.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/git.zsh

# The git segment — `lib/segments/git.zsh`. What it registers, and what fragment it writes into
# `_inzsh_segment_text[GIT]` for a given STATUS ASSOCIATION. No repository is created anywhere in
# this file and no `git` is run: the state is injected by name, which is the seam the segment is
# built on. `test/unit/git_async_spec.sh` is where real repositories appear.
#
# No palette value reaches this file either. Colour is asserted through `_inzsh_role[…]` and
# through the role NAME the segment registered, so a change of palette cannot fail an example
# here and a change of role can.
#
# THE GLYPHS ARE PRINTED AS LETTERS. Every expectation below stays ASCII, for the same two
# reasons `test/render/segment_retval_spec.sh` gives: a diff of two multibyte strings that differ
# by one invisible codepoint is unreadable, and a build that dropped a glyph shows up as a
# missing letter rather than as nothing at all. The glyphs themselves are pinned once, in their
# own group, against the bytes.
#
#   C  ✓ clean       D  — detached
#   !  ! dirty       A  ↑ ahead
#   i  i staged      B  ↓ behind

# The state association, from a flat argument list, built and reported as `[text] role`.
inzsh_spec_git() {
  emulate -L zsh

  local -A pinned
  pinned=("$@")

  _inzsh_segment_text=()
  _inzsh_segment_git_build pinned

  local text=${_inzsh_segment_text[GIT]-}
  text=${text//$_inzsh_git_glyph_clean/C}
  text=${text//$_inzsh_git_glyph_detached/D}
  text=${text//$_inzsh_git_glyph_ahead/A}
  text=${text//$_inzsh_git_glyph_behind/B}

  print -r -- "[$text] ${_inzsh_segment_fg_role[GIT]-}"
}

# The same, taking the whole association as one word so a Parameters block can carry a state in a
# single column.
inzsh_spec_git_split() {
  emulate -L zsh

  local -a args=(${=1})
  inzsh_spec_git "${args[@]}"
}

# The segment as the renderer draws it, on a left prompt of its own.
inzsh_spec_git_drawn() {
  emulate -L zsh

  local -A pinned
  pinned=("$@")

  _inzsh_segment_text=()
  _inzsh_segment_git_build pinned
  _inzsh_left=(GIT)
  _inzsh_right=()
  _inzsh_render_build left
  typeset -g inzsh_spec_drawn=$REPLY

  return 0
}

# The non-comment lines of the segment source, in `inzsh_spec_lines`, for the structural groups.
# Comments are skipped because the prose in the file names `git`, `$(` and the word "fork"
# precisely in order to say that none of them is used.
inzsh_spec_git_lines() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga inzsh_spec_lines
  inzsh_spec_lines=()

  local line bare
  while IFS= read -r line; do
    bare=${line##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    inzsh_spec_lines+=$line
  done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/git.zsh"

  return 0
}

Describe 'the git segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers rank 50, the resting foreground and the middle of the importance ramp'
      registered() {
        _inzsh_rank_of GIT
        print -r -- "$REPLY ${_inzsh_segment_fg_role[GIT]} ${_inzsh_segment_importance[GIT]}"
      }
      When call registered
      The output should eq '50 text-body 2'
    End

    It 'is a default the engine reads and a user outranks'
      # The rank is a DEFAULT, not a decision. Both directions in one example, because a
      # registration is only correct if it can be overridden.
      ranked() {
        _inzsh_rank_split GIT
        local sided="left=${_inzsh_left[*]} right=${_inzsh_right[*]}"
        local INZSH_GIT_RANK=-4
        _inzsh_rank_split GIT
        print -r -- "$sided moved=${_inzsh_right[*]}"
      }
      When call ranked
      The output should eq 'left=GIT right= moved=GIT'
    End

    Describe 'every role it can take is one the token layer carries'
      # The five the ladder can choose between. A role the token layer does not know resolves to
      # nothing, `_inzsh_render_escape` emits a bare `%f`, and the segment silently loses its
      # colour — which is exactly the failure a spec has to catch, because it looks fine.
      Parameters
        text-body
        positive-text
        negative
        info-text
        caution-text
      End

      It "carries $1"
        roled() {
          [[ -n ${_inzsh_role[$1]+set} ]] && print -r -- known || print -r -- "unknown:$1"
        }
        When call roled "$1"
        The output should eq 'known'
      End
    End

    It 'registers once however many times it is sourced'
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/git.zsh"
          source "$1/lib/segments/git.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${#_inzsh_segment_fg_role}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_defaults[GIT]}"
        ' inzsh-git-twice "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 1 1 50'
      The stderr should eq ''
    End

    It 'draws nothing at load — sourcing registers and returns'
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local before="${PROMPT-unset}|${RPROMPT-unset}"
          source "$1/lib/segments/git.zsh"
          local after="${PROMPT-unset}|${RPROMPT-unset}"
          local prompt=changed
          [[ $before == $after ]] && prompt=same
          print -r -- "texts=${#_inzsh_segment_text} prompt=$prompt"
        ' inzsh-git-load "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'texts=0 prompt=same'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the seven states'
    # One example per state named in the milestone, each pinning BOTH halves of the signal: the
    # glyph, which survives monochrome, and the role, which is never the only thing carrying it.
    #
    # $1 the injected status; $2 what is drawn and in what role.
    Parameters
      'repo 1 branch main'                            '[C main] positive-text'
      'repo 1 branch main dirty 1'                    '[! main] negative'
      'repo 1 branch main staged 1'                   '[i main] info-text'
      'repo 1 branch main ahead 2'                    '[C main A2] positive-text'
      'repo 1 branch main behind 3'                   '[C main B3] positive-text'
      'repo 1 branch main ahead 2 behind 3'           '[C main A2B3] caution-text'
      'repo 1 sha a1b2c3d4e5 detached 1'              '[C D a1b2c3d] caution-text'
    End

    It "draws ($1) as $2"
      When call inzsh_spec_git_split "$1"
      The output should eq "$2"
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the worktree'
    # `dirty`, `untracked` and `conflicts` are three porcelain columns for one question — is
    # there work here that is not committed — and they answer with one `!`. Three marks for one
    # fact would be three things to learn and no more information.
    Describe 'anything uncommitted reads as dirty'
      Parameters
        'repo 1 branch main dirty 1'
        'repo 1 branch main untracked 1'
        'repo 1 branch main conflicts 1'
        'repo 1 branch main dirty 4 untracked 2 conflicts 1'
      End

      It "is dirty for ($1)"
        When call inzsh_spec_git_split "$1"
        The output should eq '[! main] negative'
      End
    End

    It 'prefers the worktree to the index when both have changed'
      # Precedence, not a tie. Staged work is safe in the object database; unstaged work is only
      # in the filesystem, and it is the one that a checkout can lose.
      When call inzsh_spec_git_split 'repo 1 branch main dirty 1 staged 1'
      The output should eq '[! main] negative'
    End

    It 'draws the count of nothing as nothing'
      # A clean repository shows no number anywhere. `0` is not information.
      When call inzsh_spec_git_split 'repo 1 branch main dirty 0 staged 0 ahead 0 behind 0'
      The output should eq '[C main] positive-text'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'divergence'
    # The counts ARE the signal for ahead and behind, which is why neither takes a colour of its
    # own: the arrow and the number cannot be missed in monochrome, and spending `caution` on a
    # branch that is two commits ahead would leave nothing louder for the branch that is both.
    Describe 'the arrows carry the direction and the number'
      Parameters
        'repo 1 branch main ahead 1'              '[C main A1] positive-text'
        'repo 1 branch main behind 1'             '[C main B1] positive-text'
        'repo 1 branch main ahead 12 behind 34'   '[C main A12B34] caution-text'
      End

      It "draws ($1) as $2"
        When call inzsh_spec_git_split "$1"
        The output should eq "$2"
      End
    End

    It 'writes the two counts as one word, because they are one fact'
      # `↑2 ↓3` would read as two separate reports about two separate things. There is one
      # branch and it has moved both ways.
      spaced() {
        inzsh_spec_git_split 'repo 1 branch main ahead 2 behind 3'
      }
      When call spaced
      The output should eq '[C main A2B3] caution-text'
    End

    It 'is the only thing that raises a clean tree to caution'
      # The ladder, from the far end: nothing about being ahead alone, or behind alone, is a
      # decision the user has to make. Being both is.
      ladder() {
        local -a seen=()
        local args
        for args in 'ahead 2' 'behind 3' 'ahead 2 behind 3'; do
          local -A pinned=(repo 1 branch main ${=args})
          _inzsh_segment_git_build pinned
          seen+=${_inzsh_segment_fg_role[GIT]}
        done
        print -r -- "${seen[*]}"
      }
      When call ladder
      The output should eq 'positive-text positive-text caution-text'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the ref'
    It 'draws a branch name whole when it fits'
      When call inzsh_spec_git_split 'repo 1 branch release/2.1'
      The output should eq '[C release/2.1] positive-text'
    End

    It 'abbreviates the commit itself rather than trusting the writer to have done it'
      # The cache holds whatever git printed, which is the full object id. Abbreviating HERE is
      # what makes the width of this segment a property of the theme.
      When call inzsh_spec_git_split \
        'repo 1 sha 7e15bbb09b4a296b2ffbbaa8a10dac24a2b88848 detached 1'
      The output should eq '[C D 7e15bbb] caution-text'
    End

    It 'infers a detached HEAD from a commit with no branch beside it'
      # The `detached` field is a convenience, not the evidence. An entry that lost it — an older
      # cache format, a truncated write — still reads correctly, because a repository with a
      # commit and no branch name is what detached MEANS.
      When call inzsh_spec_git_split 'repo 1 sha a1b2c3d4e5'
      The output should eq '[C D a1b2c3d] caution-text'
    End

    It 'draws an unborn branch, which has a name and no commit'
      # `git init` and nothing else. porcelain v2 reports `(initial)` for the oid, the async half
      # turns that into an empty sha, and the branch is still the truth about where HEAD points.
      unborn() { inzsh_spec_git repo 1 branch main sha '' }
      When call unborn
      The output should eq '[C main] positive-text'
    End

    It 'is absent when there is neither a branch nor a readable commit'
      # Nothing left to name. A segment with nothing to say says nothing rather than drawing a
      # glyph beside an empty space.
      When call inzsh_spec_git_split 'repo 1 detached 1'
      The output should eq '[] text-body'
    End

    Describe 'a commit that is not a commit is not drawn as one'
      # The sha comes out of a file. Anything that is not lower-case hex of a plausible length is
      # not an object id, and the segment falls back to having no ref rather than printing a
      # cache artefact into the prompt.
      Parameters
        'repo 1 detached 1 sha DEADBEEF'
        'repo 1 detached 1 sha zzzzzzz'
        'repo 1 detached 1 sha abc'
        'repo 1 detached 1 sha ../../etc'
      End

      It "is absent for ($1)"
        When call inzsh_spec_git_split "$1"
        The output should eq '[] text-body'
      End
    End

    It 'elides a branch name that would take the row'
      # `INZSH_GIT_BRANCH_MAX` columns, through `_inzsh_truncate_path`'s own text ladder — the
      # eliding rule lives in `lib/core/layout.zsh` and is asked for, never restated.
      long() {
        local INZSH_GIT_BRANCH_MAX=12
        inzsh_spec_git repo 1 branch feature/PROJ-1187-rewrite-the-importer
      }
      When call long
      The output should eq '[C feature/PRO…] positive-text'
    End

    It 'draws the name whole when the limit is turned off'
      whole() {
        local INZSH_GIT_BRANCH_MAX=0
        inzsh_spec_git repo 1 branch feature/PROJ-1187-rewrite-the-importer
      }
      When call whole
      The output should eq '[C feature/PROJ-1187-rewrite-the-importer] positive-text'
    End

    It 'ignores a limit that is not a limit, rather than drawing nothing'
      # The config layer's rule, inherited: a value that fails its validator is not an error and
      # is never reported, it is simply not used.
      bad() {
        local INZSH_GIT_BRANCH_MAX=chartreuse
        inzsh_spec_git repo 1 branch main
      }
      When call bad
      The output should eq '[C main] positive-text'
    End

    It 'doubles a per cent, because the fragment is expanded as a prompt'
      # A branch may legally be called `100%`, and a bare `%` in a prompt string opens an escape
      # that eats the character after it.
      When call inzsh_spec_git_split 'repo 1 branch 100%'
      The output should eq '[C 100%%] positive-text'
    End

    It 'strips control characters, because a newline breaks the row'
      # git cannot make a ref with one in it, so this is not about git. It is about a cache file
      # truncated mid-write, and a fragment with a newline in it breaks the row the renderer has
      # already measured.
      controlled() {
        inzsh_spec_git repo 1 branch $'ma\nin\t'
      }
      When call controlled
      The output should eq '[C main] positive-text'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'absence'
    # The whole "not a repository" story, and it is the commonest state a shell is in. Absent
    # means an EMPTY entry, which every layer already reads as no block and no separator.
    Describe 'anything that is not a repository draws nothing'
      #
      # Every row carries a branch as well, so an implementation that tested `repo` for
      # PRESENCE rather than for the value 1 has something to draw and is caught. Without it
      # `repo 0` is absent for the wrong reason — there was no ref — and the guard is untested.
      Parameters
        'repo 0 branch main'
        'repo yes branch main'
        'repo 11 branch main'
        'repo 1x branch main'
        'repo 0 sha a1b2c3d4 detached 1'
        'branch main'
      End

      It "is absent for ($1)"
        When call inzsh_spec_git_split "$1"
        The output should eq '[] text-body'
      End
    End

    It 'is absent when the named association does not exist'
      missing() { inzsh_spec_git_named _inzsh_spec_no_such_map }
      inzsh_spec_git_named() {
        _inzsh_segment_text=()
        _inzsh_segment_git_build "$1"
        print -r -- "[${_inzsh_segment_text[GIT]-}] ${_inzsh_segment_fg_role[GIT]-}"
      }
      When call missing
      The output should eq '[] text-body'
      The stderr should eq ''
    End

    It 'is absent when the name refers to a scalar rather than a map'
      # `${(Pkv)}` over a scalar yields ONE element, and a one-element assignment to an
      # association is a fatal `odd number of elements` in the middle of a render. The count is
      # checked before the map is built for exactly this input.
      scalar() {
        typeset -g inzsh_spec_scalar='repo 1 branch main'
        _inzsh_segment_text=()
        _inzsh_segment_git_build inzsh_spec_scalar
        print -r -- "[${_inzsh_segment_text[GIT]-}]"
      }
      When call scalar
      The output should eq '[]'
      The stderr should eq ''
    End

    Describe 'a name that cannot form a variable is asked nothing'
      # `${(P)}` on a non-identifier is fatal mid-render — the same trap `_inzsh_mincols_of`
      # guards in `lib/core/layout.zsh`.
      Parameters
        'not a name'
        '1abc'
        'a-b'
        '$(echo hi)'
      End

      It "is absent for '$1'"
        named() {
          _inzsh_segment_text=()
          _inzsh_segment_git_build "$1"
          print -r -- "[${_inzsh_segment_text[GIT]-}]"
        }
        When call named "$1"
        The output should eq '[]'
        The stderr should eq ''
      End
    End

    It 'writes an EMPTY entry rather than a placeholder, so no separator is drawn'
      nothing() {
        inzsh_spec_git_drawn repo 0
        print -r -- "len=${#inzsh_spec_drawn} width=$_inzsh_render_width"
      }
      When call nothing
      The output should eq 'len=0 width=0'
    End

    Describe 'the fill follows the state, alongside the ink'
      # The one segment whose BACKGROUND moves while the shell is running, which is what makes
      # `INZSH_SURFACE_MODE=hue` say something rather than just look like something. The pair is
      # asserted together on purpose: the fill is the ink's DS twin, so a ladder that grew a
      # sixth state and only taught one of the two would be caught here rather than on screen.
      #
      # $1 the pinned state as one word, $2 the ink, $3 the fill.
      Describe 'the ladder'
      Parameters
        'repo 1 branch main'                       positive-text  positive
        'repo 1 branch main dirty 2'               negative       negative
        'repo 1 branch main untracked 1'           negative       negative
        'repo 1 branch main conflicts 1'           negative       negative
        'repo 1 branch main staged 3'              info-text      info
        'repo 1 sha a1b2c3d4e5 detached 1'         caution-text   caution
        'repo 1 branch main ahead 1 behind 1'      caution-text   caution
      End

      It "draws ($1) with $2 ink on the $3 fill"
        paired() {
          local -a args=(${=1})
          local -A pinned=("${args[@]}")
          _inzsh_segment_git_build pinned
          print -r -- "${_inzsh_segment_fg_role[GIT]} ${_inzsh_segment_bg_role[GIT]}"
        }
        When call paired "$1"
        The output should eq "$2 $3"
      End
      End

      It 'pairs every fill it can choose with an ink the token layer carries'
        # The renderer takes the ink from the fill — `on-<fill>` — so a fill without one would
        # leave the block drawn in the resting `text-body`, on a saturated background, which is
        # the illegible outcome this pairing exists to prevent.
        inked() {
          local -a states=(
            'repo 1 branch main'
            'repo 1 branch main dirty 2'
            'repo 1 branch main staged 3'
            'repo 1 sha a1b2c3d4e5 detached 1'
          )
          local state
          local -a bad=()
          for state in "${states[@]}"; do
            local -a args=(${=state})
            local -A pinned=("${args[@]}")
            _inzsh_segment_git_build pinned
            [[ -n ${_inzsh_role[on-${_inzsh_segment_bg_role[GIT]}]+set} ]] ||
              bad+=${_inzsh_segment_bg_role[GIT]}
          done
          print -r -- "${bad[*]}"
        }
        When call inked
        The output should eq ''
      End
    End

    It 'puts the role back when it goes absent, rather than keeping the last state colour'
      # A repository that went from dirty to gone must not leave `negative` registered: the next
      # segment to be drawn under that key would inherit a colour from a repository that is not
      # there.
      reset() {
        local -a seen=()
        local -A dirty=(repo 1 branch main dirty 1)
        local -A gone=(repo 0)
        _inzsh_segment_git_build dirty
        seen+=${_inzsh_segment_fg_role[GIT]}:${_inzsh_segment_bg_role[GIT]}
        _inzsh_segment_git_build gone
        seen+=${_inzsh_segment_fg_role[GIT]}:${_inzsh_segment_bg_role[GIT]}
        print -r -- "${seen[*]}"
      }
      When call reset
      The output should eq 'negative:negative text-body:surface-deep'
    End

    It 'rewrites the entry on every build rather than accumulating'
      rewritten() {
        local -a seen=()
        local args
        for args in 'repo 1 branch main dirty 1' 'repo 0' 'repo 1 branch main'; do
          local -A pinned=(${=args})
          _inzsh_segment_git_build pinned
          seen+="[${_inzsh_segment_text[GIT]}]"
        done
        print -r -- "${(j::)seen}"
      }
      When call rewritten
      The output should eq "[$_inzsh_git_glyph_dirty main][][$_inzsh_git_glyph_clean main]"
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'hostile counts'
    # None of this can come from a user's config — the fields come out of a cache file this
    # theme wrote — but a cache file outlives the shell that wrote it and can be truncated,
    # edited, or written by a version that is not this one.
    Describe 'a count that is not a count reads as zero'
      Parameters
        'repo 1 branch main dirty abc'
        'repo 1 branch main dirty -1'
        'repo 1 branch main dirty 1.5'
        'repo 1 branch main ahead x behind y'
      End

      It "is clean and unmarked for ($1)"
        When call inzsh_spec_git_split "$1"
        The output should eq '[C main] positive-text'
      End
    End

    It 'survives counts far larger than a prompt will ever show'
      When call inzsh_spec_git_split 'repo 1 branch main ahead 100000 behind 99999'
      The output should eq '[C main A100000B99999] caution-text'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'colour is never the only signal'
    It 'carries a glyph in every state it draws, so the segment reads in monochrome'
      # The house rule, as a property rather than as seven examples: whatever is drawn, the first
      # character of it is a mark and not a letter of the branch name.
      marked() {
        local -a bad=()
        local args
        for args in \
          'repo 1 branch main' \
          'repo 1 branch main dirty 1' \
          'repo 1 branch main staged 1' \
          'repo 1 branch main ahead 2' \
          'repo 1 branch main behind 3' \
          'repo 1 branch main ahead 2 behind 3' \
          'repo 1 sha a1b2c3d4 detached 1'
        do
          local -A pinned=(${=args})
          _inzsh_segment_git_build pinned
          local text=${_inzsh_segment_text[GIT]}
          local head=${text[1]}
          local -a marks=(
            $_inzsh_git_glyph_clean $_inzsh_git_glyph_dirty $_inzsh_git_glyph_staged
          )
          (( ${marks[(Ie)$head]} )) || bad+=$args
        done
        print -rl -- $bad
      }
      When call marked
      The output should eq ''
    End

    It 'takes a different role for each thing worth a different colour'
      # Five roles for five readings. A ladder that collapsed two of them would still pass every
      # example above and would have stopped saying anything.
      distinct() {
        local -A seen=()
        local args
        for args in \
          'repo 1 branch main' \
          'repo 1 branch main dirty 1' \
          'repo 1 branch main staged 1' \
          'repo 1 branch main ahead 2 behind 3' \
          'repo 0'
        do
          local -A pinned=(${=args})
          _inzsh_segment_git_build pinned
          seen[${_inzsh_segment_fg_role[GIT]}]=1
        done
        print -r -- ${#seen}
      }
      When call distinct
      The output should eq '5'
    End

    It 'draws the registered role and the glyph together on the finished fragment'
      # Asserted on the DRAWN string, and the colour through `_inzsh_role`, never as a value.
      both() {
        inzsh_spec_git_drawn repo 1 branch main dirty 1
        local -a missing=()
        [[ $inzsh_spec_drawn == *"%F{${_inzsh_role[negative]}}"* ]]        || missing+=role
        [[ $inzsh_spec_drawn == *"$_inzsh_git_glyph_dirty main"* ]]        || missing+=glyph
        print -r -- "${missing[*]}"
      }
      When call both
      The output should eq ''
    End

    It 'emits no colour of its own — the role it registers is the whole instruction'
      # A segment that drew `%F{…}` itself would ignore `INZSH_GIT_FG`, would survive a preset
      # change, and would be a second place colour is decided.
      uncoloured() {
        local -a found=()
        local args
        for args in \
          'repo 1 branch main' 'repo 1 branch main dirty 1' 'repo 1 branch main staged 1' \
          'repo 1 branch main ahead 2 behind 3' 'repo 1 sha a1b2c3d4 detached 1'
        do
          local -A pinned=(${=args})
          _inzsh_segment_git_build pinned
          [[ ${_inzsh_segment_text[GIT]} == *'%'[FKfk]* ]] && found+=$args
        done
        print -rl -- $found
      }
      When call uncoloured
      The output should eq ''
    End

    It 'honours a per-segment colour override, because it never resolved one itself'
      overridden() {
        local INZSH_GIT_FG=inzsh-spec-colour
        inzsh_spec_git_drawn repo 1 branch main
        [[ $inzsh_spec_drawn == *'%F{inzsh-spec-colour}'* ]] && print -r -- honoured
      }
      When call overridden
      The output should eq 'honoured'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the glyphs'
    It 'are the sanctioned marks, spelled as bytes so the file parses in any locale'
      # Pinned against the byte sequences rather than against the characters, for the same reason
      # the segment spells them that way: a `\u` escape is resolved at parse time and takes the
      # whole file with it outside a multibyte locale.
      pinned() {
        local -a wrong=()
        [[ $_inzsh_git_glyph_clean    == $'\xe2\x9c\x93' ]] || wrong+=clean
        [[ $_inzsh_git_glyph_dirty    == '!'             ]] || wrong+=dirty
        [[ $_inzsh_git_glyph_staged   == 'i'             ]] || wrong+=staged
        [[ $_inzsh_git_glyph_detached == $'\xe2\x80\x94' ]] || wrong+=detached
        [[ $_inzsh_git_glyph_ahead    == $'\xe2\x86\x91' ]] || wrong+=ahead
        [[ $_inzsh_git_glyph_behind   == $'\xe2\x86\x93' ]] || wrong+=behind
        print -r -- "${wrong[*]}"
      }
      When call pinned
      The output should eq ''
    End

    It 'each take exactly one column, so a state never costs the row two'
      wide() {
        local -a wrong=()
        local name glyph
        for name in clean dirty staged detached ahead behind; do
          local var=_inzsh_git_glyph_$name
          glyph=${(P)var}
          _inzsh_width_raw "$glyph"
          (( REPLY == 1 )) || wrong+="$name=$REPLY"
        done
        print -r -- "${wrong[*]}"
      }
      When call wide
      The output should eq ''
    End

    It 'degrades to ASCII where the locale cannot carry them'
      # The trap `lib/core/layout.zsh` fell into: under `LC_ALL=C` those bytes draw as mojibake
      # and `${(m)#…}` measures them as three. The ASCII register keeps a signal that is not
      # colour, and the file still parses — which is the part that matters, because a parse
      # failure here takes `_inzsh_segment_git_build` with it and the render path then calls a
      # function that does not exist.
      degraded() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/git.zsh"
          local -A a=(repo 1 branch main ahead 2 behind 3)
          _inzsh_segment_git_build a
          local one=${_inzsh_segment_text[GIT]}
          local -A b=(repo 1 sha a1b2c3d4 detached 1)
          _inzsh_segment_git_build b
          print -r -- "[$one] [${_inzsh_segment_text[GIT]}]"
        ' inzsh-git-c "$SHELLSPEC_PROJECT_ROOT"
      }
      When call degraded
      The output should eq '[v main +2-3] [v - a1b2c3d]'
      The stderr should eq ''
    End

    It 'never puts the detached dash and a behind count on the same row'
      # The one place the ASCII register reuses a character. A detached HEAD has no upstream, so
      # git reports no divergence beside one — asserted here as a property of what this file
      # DRAWS, since that is what would be ambiguous.
      exclusive() {
        inzsh_spec_git repo 1 sha a1b2c3d4 detached 1 ahead 2 behind 3
      }
      When call exclusive
      The output should eq '[C D a1b2c3d A2B3] caution-text'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    # The rule this whole milestone is shaped by, asserted on the TEXT of the file. A fork that
    # only fires on somebody else's network mount is a fork no run of this suite would ever see,
    # so the claim is structural: there is nothing here that COULD fork.
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/segments/git.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sources silently in a single-byte locale'
      # A `\u` escape would fail here, and the failure is not a warning: zsh abandons the rest of
      # the file, so the segment's build function would simply not exist.
      quiet() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          source "$1/lib/segments/git.zsh"
          print -r -- "built=${+functions[_inzsh_segment_git_build]}"
        ' inzsh-git-quiet "$SHELLSPEC_PROJECT_ROOT" < /dev/null
      }
      When call quiet
      The output should eq 'built=1'
      The stderr should eq ''
    End

    It 'contains no command substitution and no backtick'
      forks() {
        inzsh_spec_git_lines
        local line; local -a bad=()
        (( ${#inzsh_spec_lines} > 20 )) || bad+=no-lines-scanned
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'$('* || $line == *'`'* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call forks
      The output should eq ''
    End

    It 'never names an external command, git least of all'
      # The whole milestone in one assertion. This segment renders; something else fetches.
      external() {
        setopt local_options extended_glob
        inzsh_spec_git_lines
        local line bare; local -a bad=()
        local -a banned=(git whence command eval stat find sed awk)
        local word
        for line in "${inzsh_spec_lines[@]}"; do
          bare=${line##[[:space:]]#}
          for word in "${banned[@]}"; do
            # Braced, because `$word[` is a SUBSCRIPT and not a parameter followed by a bracket
            # expression. Unbraced, this line is a syntax error and not a failing assertion.
            [[ $bare == ${word}[[:space:]]* || $line == *[[:space:]]${word}[[:space:]]* ]] \
              && bad+="$word: $bare"
          done
        done
        print -rl -- $bad
      }
      When call external
      The output should eq ''
    End

    It 'reads no file and stats no path'
      # `lib/segments/dir.zsh` gives the reason: a `[[ -d ]]` on a dead NFS mount blocks the
      # prompt exactly as a fork would, without being one.
      unstatted() {
        setopt local_options extended_glob
        inzsh_spec_git_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'[[ -'[defghkLOprsSuwx]' '* ]] && bad+=$line
          [[ $line == *'< "$'* || $line == *'<'\$[A-Za-z_]* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call unstatted
      The output should eq ''
    End

    It 'carries no hex — colour lives in the token layer and nowhere else'
      hexed() {
        setopt local_options extended_glob
        inzsh_spec_git_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'#'[0-9A-Fa-f](#c6)* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call hexed
      The output should eq ''
    End

    It 'names no `.claude` path and no absolute path from this machine'
      neutral() {
        inzsh_spec_git_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'.claude'* || $line == *'/Users/'* || $line == *'/home/'* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call neutral
      The output should eq ''
    End
  End
End
