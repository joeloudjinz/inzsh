Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/retval.zsh

# The exit-status segment — `lib/segments/retval.zsh`. What it registers, and what it writes into
# `_inzsh_segment_text[RETVAL]` for a given status and pipeline.
#
# No palette value reaches this file. The one example that pins colour pins it through
# `_inzsh_role[negative]`, so the claim is "the segment took the role it registered" and a change
# of palette cannot fail it.
#
# The glyph is printed as `G` rather than as itself, for two reasons: the expectations stay ASCII
# and legible in a diff, and a build that dropped the glyph shows up as a missing letter rather
# than as an invisible difference between two multibyte strings. The glyph itself is pinned once,
# in its own group, together with the locale it degrades in.

# The status text of the last build, with the glyph rewritten to `G`, in `inzsh_spec_retval_text`.
inzsh_spec_retval_mark() {
  emulate -L zsh

  local text=${_inzsh_segment_text[RETVAL]-'(no entry)'}
  typeset -g inzsh_spec_retval_text="[${text//$_inzsh_retval_glyph/G}]"

  return 0
}

# Build with the given arguments and print what the segment wrote, in brackets so that an empty
# entry — the absent case — is a visible result rather than a blank line.
inzsh_spec_retval() {
  emulate -L zsh

  _inzsh_segment_text=()
  _inzsh_segment_retval_build "$@"
  inzsh_spec_retval_mark
  print -r -- "$inzsh_spec_retval_text"
}

# The same, taking the whole argument list as one word so a Parameters block can carry a pipeline
# in a single column.
inzsh_spec_retval_split() {
  emulate -L zsh

  local -a args=(${=1})
  inzsh_spec_retval "${args[@]}"
}

# The segment as the renderer draws it, on a right prompt of its own.
inzsh_spec_retval_drawn() {
  emulate -L zsh

  _inzsh_segment_text=()
  _inzsh_segment_retval_build "$@"
  _inzsh_left=()
  _inzsh_right=(RETVAL)
  _inzsh_render_build right
  typeset -g inzsh_spec_drawn=$REPLY

  return 0
}

# The non-comment lines of the segment source, in `inzsh_spec_lines`, for the structural groups.
# Comments are skipped because the prose in the file names `$?` and `$(` precisely in order to
# say that neither is used.
inzsh_spec_retval_lines() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga inzsh_spec_lines
  inzsh_spec_lines=()

  local line bare
  while IFS= read -r line; do
    bare=${line##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    inzsh_spec_lines+=$line
  done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/retval.zsh"

  return 0
}

Describe 'the exit-status segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers a rank default, a foreground role and an importance'
      registered() {
        local -a got=()
        got+=rank=${_inzsh_segment_defaults[RETVAL]-}
        got+=role=${_inzsh_segment_fg_role[RETVAL]-}
        got+=importance=${_inzsh_segment_importance[RETVAL]-}
        print -r -- "${got[*]}"
      }
      When call registered
      The output should eq 'rank=-1 role=negative importance=1'
    End

    It 'is read by the engine as the rightmost segment, and is still only a default'
      # The rank is a DEFAULT, not a decision: the engine reads it through `_inzsh_rank_of`, and a
      # user's `INZSH_RETVAL_RANK` outranks it. Both directions in one example, because the
      # registration is only correct if it can be overridden.
      ranked() {
        _inzsh_rank_of RETVAL
        local shipped=$REPLY
        _inzsh_rank_split RETVAL
        local sided="right=${_inzsh_right[*]} left=${_inzsh_left[*]}"
        local INZSH_RETVAL_RANK=3
        _inzsh_rank_split RETVAL
        print -r -- "$shipped $sided moved=${_inzsh_left[*]}"
      }
      When call ranked
      The output should eq '-1 right=RETVAL left= moved=RETVAL'
    End

    It 'registers once however many times it is sourced'
      # Re-sourcing happens: a plugin manager pass, a bundle, a user reloading their zshrc. Three
      # associations that grew a second RETVAL entry would be a theme that doubled its own row.
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/retval.zsh"
          source "$1/lib/segments/retval.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${#_inzsh_segment_fg_role}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_defaults[RETVAL]}"
        ' inzsh-retval-twice "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 1 1 -1'
      The stderr should eq ''
    End

    It 'draws nothing at load — sourcing registers and returns'
      # A segment that built at source time would report the status of the source itself, and
      # would do it in whatever shell happened to read the file.
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local before="${PROMPT-unset}|${RPROMPT-unset}"
          source "$1/lib/segments/retval.zsh"
          local after="${PROMPT-unset}|${RPROMPT-unset}"
          local prompt=changed
          [[ $before == $after ]] && prompt=same
          print -r -- "texts=${#_inzsh_segment_text} prompt=$prompt"
        ' inzsh-retval-load "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'texts=0 prompt=same'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'success'
    # The calm-prompt rule, and the reason there is no `✓` anywhere in the segment: a prompt that
    # reports success on every line reports nothing at all, and the failure then has to compete
    # with it for attention.
    Describe 'a status of zero writes nothing'
      Parameters
        '0'
        '0 0'
        '0 0 0 0'
      End

      It "is absent for ($1)"
        When call inzsh_spec_retval_split "$1"
        The output should eq '[]'
      End
    End

    It 'writes an EMPTY entry rather than a placeholder, so no separator is drawn'
      # `_inzsh_render_build` reads an empty entry as absent. A segment that wrote a space, a dash
      # or a zero would take a block, a surface and a separator to say nothing.
      nothing() {
        inzsh_spec_retval_drawn 0
        print -r -- "len=${#inzsh_spec_drawn} width=$_inzsh_render_width"
      }
      When call nothing
      The output should eq 'len=0 width=0'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'failure'
    Describe 'the glyph and the number'
      Parameters
        1   '[G 1]'
        2   '[G 2]'
        42  '[G 42]'
        126 '[G 126]'
        127 '[G 127]'
      End

      It "draws status $1 as $2"
        When call inzsh_spec_retval "$1"
        The output should eq "$2"
      End
    End

    It 'carries the glyph as well as the colour, so it reads in monochrome'
      # The hard rule, stated on the DRAWN string: the negative role is there, and so is a glyph
      # that survives a screenshot in greyscale. The colour is asserted through `_inzsh_role`,
      # never as a value.
      both() {
        inzsh_spec_retval_drawn 1
        local -a missing=()
        [[ $inzsh_spec_drawn == *"%F{${_inzsh_role[negative]}}"* ]] || missing+=role
        [[ $inzsh_spec_drawn == *"$_inzsh_retval_glyph 1"* ]]       || missing+=glyph
        print -r -- "${missing[*]}"
      }
      When call both
      The output should eq ''
    End

    It 'emits no colour of its own — the role it registered is the whole instruction'
      # A segment that drew `%F{…}` itself would ignore `INZSH_RETVAL_FG`, would survive a preset
      # change, and would be a second place colour is decided.
      uncoloured() {
        local -a found=()
        local code
        for code in 1 130 0; do
          _inzsh_segment_retval_build "$code" 1 0
          [[ ${_inzsh_segment_text[RETVAL]} == *'%'[FKfk]* ]] && found+=$code
        done
        print -r -- "${found[*]}"
      }
      When call uncoloured
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'pipelines'
    # `$?` is the LAST stage only, and under `pipefail` it is not even that. A pipeline whose
    # final command succeeded can still have failed meaningfully — `grep x missing | wc -l` prints
    # 0 and returns 0 — so what is drawn is the whole chain, in the order the stages ran.
    Describe 'every stage zero is still success'
      Parameters
        '0 0 0'
        '0 0 0 0'
        '0 0 0 0 0 0'
      End

      It "is absent for the pipeline ($1)"
        When call inzsh_spec_retval_split "$1"
        The output should eq '[]'
      End
    End

    Describe 'any stage non-zero shows the chain'
      # $1 the arguments — the status first, then the stages; $2 what is drawn.
      Parameters
        '0 1 0'     '[G 1|0]'
        '0 1 0 0'   '[G 1|0|0]'
        '127 0 127' '[G 0|127]'
        '0 0 0 5'   '[G 0|0|5]'
        '1 1 1'     '[G 1|1]'
      End

      It "draws ($1) as $2"
        When call inzsh_spec_retval_split "$1"
        The output should eq "$2"
      End
    End

    It 'separates stages with a character the ribbon never uses'
      # The separator is the pipe the user typed. A powerline glyph here would read as a block
      # boundary that is not there, in a colour that belongs to a neighbour.
      separated() {
        _inzsh_segment_retval_build 0 1 0 127
        local text=${_inzsh_segment_text[RETVAL]}
        local -a wrong=()
        [[ $text == *'|'* ]]               || wrong+=missing
        [[ $text == *$_inzsh_sep_left* ]]  && wrong+=powerline-left
        [[ $text == *$_inzsh_sep_right* ]] && wrong+=powerline-right
        print -r -- "${wrong[*]}"
      }
      When call separated
      The output should eq ''
    End

    It 'draws the status alone when the pipeline has only one stage'
      # One stage says nothing `$?` does not, and `G 1|` would be a chain with a phantom in it.
      When call inzsh_spec_retval_split '1 1'
      The output should eq '[G 1]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'signals'
    # THE DECISION: a status above 128 is drawn as the signal NAME and never as the number, and
    # never as both. `130` is an encoding the reader has to undo — 128 + 2, and then which signal
    # 2 is — while `SIGINT` is the fact itself. The number is recoverable from the name; the name
    # is not recoverable from the number without a table the reader has to be carrying.
    Describe 'a status above 128 is named'
      Parameters
        129 '[G SIGHUP]'
        130 '[G SIGINT]'
        131 '[G SIGQUIT]'
        137 '[G SIGKILL]'
        139 '[G SIGSEGV]'
        141 '[G SIGPIPE]'
        143 '[G SIGTERM]'
      End

      It "draws status $1 as $2"
        When call inzsh_spec_retval "$1"
        The output should eq "$2"
      End
    End

    It 'shows the name only — never the name and the number together'
      # The other half of the decision, written as a property: whatever the name is on this
      # platform, no digit of the encoded status survives beside it.
      named() {
        _inzsh_segment_retval_build 130
        local text=${_inzsh_segment_text[RETVAL]}
        local -a wrong=()
        [[ $text == *SIG* ]]   || wrong+=unnamed
        [[ $text == *[0-9]* ]] && wrong+=numbered
        print -r -- "${wrong[*]}"
      }
      When call named
      The output should eq ''
    End

    Describe 'a status no signal answers to stays a number'
      # The table's bounds, from both ends. 128 is not a signal; a status far above the highest
      # one is an exit code that merely looks like a signal; and the pseudo-traps zsh keeps in
      # `$signals` — `EXIT` at the front, `ZERR` and `DEBUG` at the back — are never named.
      Parameters
        128 '[G 128]'
        200 '[G 200]'
        255 '[G 255]'
        300 '[G 300]'
      End

      It "draws status $1 as $2"
        When call inzsh_spec_retval "$1"
        The output should eq "$2"
      End
    End

    It 'names signals inside a chain too, so one rule reads both ways'
      When call inzsh_spec_retval_split '0 0 141'
      The output should eq '[G 0|SIGPIPE]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the injected status'
    # The seam. With no arguments the values come from `lib/core/hooks.zsh`'s capture; with
    # arguments they are the caller's, which is how every example above pins a command that never
    # ran.
    It 'reads the capture when it is given no arguments'
      captured() {
        local _inzsh_last_status=3
        local -a _inzsh_last_pipestatus=(3)
        inzsh_spec_retval
      }
      When call captured
      The output should eq '[G 3]'
    End

    It 'reads the captured pipeline, not just the captured status'
      # `_inzsh_last_status` is 0 here — the pipeline's last stage succeeded — and the failure is
      # visible only in `_inzsh_last_pipestatus`.
      piped() {
        local _inzsh_last_status=0
        local -a _inzsh_last_pipestatus=(2 0)
        inzsh_spec_retval
      }
      When call piped
      The output should eq '[G 2|0]'
    End

    It 'never reads $? — a failing command just before the build changes nothing'
      # The bug this prevents: by the time a segment runs, `$?` is the status of whatever the
      # render path did last. A build that read it would report the theme's own success forever.
      own() {
        false
        inzsh_spec_retval 0 0
      }
      When call own
      The output should eq '[]'
    End

    It 'contains no `$?` anywhere in the source'
      # Structural, and deliberately so: the rule is about the TEXT of the file. A read guarded by
      # a condition that is false today is still a read waiting to fire.
      unread() {
        setopt local_options extended_glob
        inzsh_spec_retval_lines
        local line; local -a bad=()
        (( ${#inzsh_spec_lines} > 10 )) || bad+=no-lines-scanned
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'$?'* ]] && bad+=${line##[[:space:]]#}
        done
        print -rl -- $bad
      }
      When call unread
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'hostile input'
    # None of this can come from a user's config — the arguments are the theme's own — but a
    # segment is the last thing between a mistake upstream and the line the user is typing.
    Describe 'a status that is not a status leaves the segment absent'
      # Absent rather than drawn as it stands: painting a failure out of a value that could not be
      # read is the one outcome worse than saying nothing.
      Parameters
        abc
        ''
        -1
        1.5
        +1
        ' 1'
      End

      It "is absent for a status of '$1'"
        When call inzsh_spec_retval "$1"
        The output should eq '[]'
      End
    End

    It 'falls back to the status alone when a stage is unreadable'
      When call inzsh_spec_retval_split '1 x y'
      The output should eq '[G 1]'
    End

    It 'drops a corrupt chain whole rather than drawing the half of it that parsed'
      # The status is 0 and the second stage is not a number, so there is no chain that can be
      # trusted and no failure the status admits to. `G 1|x` would be worse than silence: it
      # reads as a pipeline that returned `x`, which nothing ever does.
      When call inzsh_spec_retval_split '0 1 x'
      The output should eq '[]'
    End

    It 'survives a very long pipeline'
      When call inzsh_spec_retval_split '1 0 0 0 0 0 0 0 0 0 1'
      The output should eq '[G 0|0|0|0|0|0|0|0|0|1]'
    End

    It 'rewrites the entry on every build rather than accumulating'
      # The entry is assigned, never appended to, so a prompt that failed and then succeeded goes
      # back to silent instead of keeping the last failure on screen.
      rewritten() {
        local -a seen=()
        local code
        for code in 1 0 2; do
          _inzsh_segment_retval_build "$code"
          inzsh_spec_retval_mark
          seen+=$inzsh_spec_retval_text
        done
        print -r -- "${(j::)seen}"
      }
      When call rewritten
      The output should eq '[G 1][][G 2]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the glyph'
    It 'is the multiplication X, spelled as bytes so the file parses in any locale'
      # Pinned against the byte sequence rather than against the character, for the same reason
      # the segment spells it that way: a `\u` escape is resolved at parse time and fails outside
      # a multibyte locale.
      pinned() {
        [[ $_inzsh_retval_glyph == $'\xe2\x9c\x95' ]] && print -r -- exact
      }
      When call pinned
      The output should eq 'exact'
    End

    It 'degrades to ASCII where the locale cannot carry it'
      # The trap `lib/core/layout.zsh` fell into: under `LC_ALL=C` those bytes draw as mojibake.
      # An `x` stands in, so the segment still carries a signal that is not colour.
      degraded() {
        LC_ALL=C LC_CTYPE= LANG= zsh -f -c '
          source "$1/lib/core/detect.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/retval.zsh"
          _inzsh_segment_retval_build 130
          print -r -- "[$_inzsh_retval_glyph] ${_inzsh_segment_text[RETVAL]}"
        ' inzsh-retval-c "$SHELLSPEC_PROJECT_ROOT"
      }
      When call degraded
      The output should eq '[x] x SIGINT'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/segments/retval.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'builds without forking — this runs before every prompt'
      forks() {
        inzsh_spec_retval_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'$('* || $line == *'`'* || $line == *whence* ]] && bad+=$line
        done
        print -r -- "${#bad}"
      }
      When call forks
      The output should eq '0'
    End

    It 'carries no hex — colour lives in the token layer and nowhere else'
      hexed() {
        setopt local_options extended_glob
        inzsh_spec_retval_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'#'[0-9A-Fa-f](#c6)* ]] && bad+=$line
        done
        print -r -- "${#bad}"
      }
      When call hexed
      The output should eq '0'
    End
  End
End
