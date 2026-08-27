Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/ssh.zsh
Include lib/segments/host.zsh

# The remote-session marker — `lib/segments/ssh.zsh`. What it registers, when it draws, and how
# it differs from `lib/segments/host.zsh`, which is the segment it is most likely to be confused
# with and the one it is designed to sit beside.
#
# The marker is INJECTED. `_inzsh_segment_ssh_build '198.51.100.1 22 …'` renders a remote session
# and `_inzsh_segment_ssh_build ''` renders a local one, with no sshd anywhere near the runner —
# which is the only way to test both halves of a question whose live answer is whatever the
# machine running the suite happens to be.
#
# Neutral example data throughout: `198.51.100.0/24` is the documentation range reserved by
# RFC 5737, and no hostname in this file belongs to anyone.
#
# No glyph literal reaches this file either. Every example that asserts the mark asserts it
# through `_inzsh_glyph[warn]`, so a token layer that respells it cannot fail this spec for the
# wrong reason — and a segment that quietly stopped reading the table would fail it for the
# right one.

# Build for an injected marker and print what the segment wrote, in brackets so that an empty
# entry — the local case — is a visible result rather than a blank line.
inzsh_spec_ssh() {
  emulate -L zsh

  _inzsh_segment_text=()
  _inzsh_segment_ssh_build "$@"
  print -r -- "[${_inzsh_segment_text[SSH]-'(no entry)'}]"
}

# The segment as the renderer draws it, on a left prompt of its own.
inzsh_spec_ssh_drawn() {
  emulate -L zsh

  _inzsh_segment_text=()
  _inzsh_segment_ssh_build "$@"
  _inzsh_left=(SSH)
  _inzsh_right=()
  _inzsh_render_build left "${_inzsh_left[@]}"
  typeset -g inzsh_spec_drawn=$REPLY

  return 0
}

# The non-comment lines of the segment source, for the structural groups. Comments are skipped
# because the prose names `ps`, `$(` and `\u` precisely in order to say none of them is used.
inzsh_spec_ssh_lines() {
  emulate -L zsh
  setopt extended_glob

  typeset -ga inzsh_spec_lines
  inzsh_spec_lines=()

  local line bare
  while IFS= read -r line; do
    bare=${line##[[:space:]]#}
    [[ -z $bare || $bare == \#* ]] && continue
    inzsh_spec_lines+=$line
  done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/ssh.zsh"

  return 0
}

Describe 'the remote-session marker'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers a rank default, a foreground role and an importance'
      registered() {
        local -a got=()
        got+=rank=${_inzsh_segment_defaults[SSH]-}
        got+=role=${_inzsh_segment_fg_role[SSH]-}
        got+=importance=${_inzsh_segment_importance[SSH]-}
        print -r -- "${got[*]}"
      }
      When call registered
      The output should eq 'rank=0 role=caution-text importance=2'
    End

    # THE DEFINING PROPERTY OF THIS MILESTONE, asserted through the engine rather than against
    # the number: rank 0 is what the split reads as hidden, so a remote session with the shipped
    # configuration draws no marker at all.
    It 'ships hidden — a remote session draws no block until the user asks for one'
      hidden() {
        _inzsh_segment_ssh_build '198.51.100.1 22 198.51.100.2 22'
        local text=${_inzsh_segment_text[SSH]}
        _inzsh_rank_split SSH
        print -r -- "built=[$text] left=[${_inzsh_left[*]}] right=[${_inzsh_right[*]}]"
      }
      When call hidden
      The output should eq "built=[${_inzsh_glyph[warn]} ssh] left=[] right=[]"
    End

    It 'comes out on whichever side the user ranks it'
      ranked() {
        local INZSH_SSH_RANK=2
        _inzsh_rank_split SSH
        local onleft="left=[${_inzsh_left[*]}]"
        INZSH_SSH_RANK=-2
        _inzsh_rank_split SSH
        print -r -- "$onleft right=[${_inzsh_right[*]}]"
      }
      When call ranked
      The output should eq 'left=[SSH] right=[SSH]'
    End

    It 'registers once however many times it is sourced'
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/ssh.zsh"
          source "$1/lib/segments/ssh.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${#_inzsh_segment_fg_role}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_defaults[SSH]}"
        ' inzsh-ssh-twice "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 1 1 0'
      The stderr should eq ''
    End

    It 'draws nothing at load — sourcing registers and returns'
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          local before="${PROMPT-unset}|${RPROMPT-unset}"
          source "$1/lib/segments/ssh.zsh"
          local after="${PROMPT-unset}|${RPROMPT-unset}"
          local prompt=changed
          [[ $before == $after ]] && prompt=same
          print -r -- "texts=${#_inzsh_segment_text} prompt=$prompt"
        ' inzsh-ssh-load "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'texts=0 prompt=same'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'remote and local'
    It 'draws the mark and the word for a session sshd started'
      When call inzsh_spec_ssh '198.51.100.1 52814 198.51.100.2 22'
      The output should eq "[${_inzsh_glyph[warn]} ssh]"
    End

    It 'is absent locally — no block, no separator, no placeholder'
      When call inzsh_spec_ssh ''
      The output should eq '[]'
    End

    Describe 'either variable answering yes is enough'
      # The two are concatenated rather than chosen between: `SSH_CONNECTION` is what sshd sets
      # for an interactive session, `SSH_TTY` survives setups where the former is scrubbed.
      remote() {
        local SSH_CONNECTION=$1 SSH_TTY=$2
        _inzsh_segment_text=()
        _inzsh_segment_ssh_build
        [[ -n ${_inzsh_segment_text[SSH]} ]] && print -r -- marked || print -r -- absent
      }

      Parameters
        '198.51.100.1 22 198.51.100.2 22' ''            marked
        ''                                '/dev/pts/3'  marked
        '198.51.100.1 22 198.51.100.2 22' '/dev/pts/3'  marked
        ''                                ''            absent
      End

      It "reads connection='$1' tty='$2' as $3"
        When call remote "$1" "$2"
        The output should eq "$3"
      End
    End

    It 'takes the mark from the token layer rather than a literal of its own'
      # The mark is read at source time from `_inzsh_glyph[warn]`. Asserted by respelling the
      # table and re-sourcing: a segment carrying its own literal would draw the old one.
      tabled() {
        zsh -f -c '
          source "$1/lib/core/tokens.zsh"
          _inzsh_glyph[warn]=Z
          source "$1/lib/segments/ssh.zsh"
          _inzsh_segment_ssh_build marker
          print -r -- "[${_inzsh_segment_text[SSH]}]"
        ' inzsh-ssh-glyph "$SHELLSPEC_PROJECT_ROOT"
      }
      When call tabled
      The output should eq '[Z ssh]'
      The stderr should eq ''
    End

    It 'carries a mark as well as a colour, so it reads in monochrome'
      # The house rule, as an assertion rather than as a comment: strip every escape from the
      # drawn block and there must still be something in it that says "remote".
      monochrome() {
        setopt local_options extended_glob
        inzsh_spec_ssh_drawn '198.51.100.1 22 198.51.100.2 22'
        local bare=${(%%)inzsh_spec_drawn}
        bare=${bare//$'\e'\[[0-9;]#m/}
        local -a missing=()
        [[ $bare == *"${_inzsh_glyph[warn]}"* ]] || missing+=glyph
        [[ $bare == *ssh* ]]                     || missing+=word
        print -r -- "${missing[*]}"
      }
      When call monochrome
      The output should eq ''
    End

    It 'takes the foreground role it registered'
      cautioned() {
        inzsh_spec_ssh_drawn '198.51.100.1 22 198.51.100.2 22'
        local -a missing=()
        [[ $inzsh_spec_drawn == *"%F{${_inzsh_role[caution-text]}}"* ]] || missing+=role
        print -r -- "${missing[*]}"
      }
      When call cautioned
      The output should eq ''
    End

    It 'emits no colour of its own'
      uncoloured() {
        _inzsh_segment_ssh_build marker
        local -a found=()
        [[ ${_inzsh_segment_text[SSH]} == *'%'[FKfk]* ]] && found+=escape
        print -r -- "${found[*]}"
      }
      When call uncoloured
      The output should eq ''
    End

    It 'rewrites the entry on every build rather than accumulating'
      rewritten() {
        inzsh_spec_ssh marker
        inzsh_spec_ssh ''
        inzsh_spec_ssh marker
      }
      When call rewritten
      The output should eq "[${_inzsh_glyph[warn]} ssh]
[]
[${_inzsh_glyph[warn]} ssh]"
    End

    It 'draws the same block whatever the connection string says'
      # The marker is one fixed fact. Nothing about the address, the port or the terminal reaches
      # the row — that is `host`'s question, and answering it here would spend the columns twice.
      constant() {
        local -a seen=()
        local marker
        for marker in '198.51.100.1 22 198.51.100.2 22' '/dev/pts/9' 'x' \
                      '203.0.113.7 65535 203.0.113.8 22'; do
          _inzsh_segment_ssh_build "$marker"
          seen+=${_inzsh_segment_text[SSH]}
        done
        local -a distinct=("${(@u)seen}")
        print -r -- "${#distinct} [${distinct[1]}]"
      }
      When call constant
      The output should eq "1 [${_inzsh_glyph[warn]} ssh]"
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'beside the host segment'
    # The two answer different questions and are designed to compose. This is that sentence as a
    # test: on one remote session, `host` draws the NAME and `ssh` draws the MARK, and neither
    # one is the other's substitute.
    It 'draws the mark where host draws the name'
      composed() {
        _inzsh_segment_text=()
        _inzsh_segment_host_build 'build-07.example.net' '198.51.100.1 22 198.51.100.2 22'
        _inzsh_segment_ssh_build '198.51.100.1 22 198.51.100.2 22'
        print -r -- "host=[${_inzsh_segment_text[HOST]}] ssh=[${_inzsh_segment_text[SSH]}]"
      }
      When call composed
      The output should eq "host=[build-07] ssh=[${_inzsh_glyph[warn]} ssh]"
    End

    It 'hides with host locally, and the two hide for the same reason'
      quietly() {
        _inzsh_segment_text=()
        _inzsh_segment_host_build 'laptop' ''
        _inzsh_segment_ssh_build ''
        print -r -- "host=[${_inzsh_segment_text[HOST]}] ssh=[${_inzsh_segment_text[SSH]}]"
      }
      When call quietly
      The output should eq 'host=[] ssh=[]'
    End

    It 'stays absent locally even where host has been forced on'
      # `INZSH_HOST_ALWAYS` is the host segment's knob and means "draw the name wherever I am".
      # It says nothing about being away, so it must not bring this marker out — a marker that
      # appeared on a local shell would be the one failure this segment cannot afford.
      unforced() {
        local INZSH_HOST_ALWAYS=1
        _inzsh_segment_text=()
        _inzsh_segment_host_build 'laptop' ''
        _inzsh_segment_ssh_build ''
        print -r -- "host=[${_inzsh_segment_text[HOST]}] ssh=[${_inzsh_segment_text[SSH]}]"
      }
      When call unforced
      The output should eq 'host=[laptop] ssh=[]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'as a file'
    It 'parses'
      syntax() { zsh -n "$SHELLSPEC_PROJECT_ROOT/lib/segments/ssh.zsh"; }
      When call syntax
      The status should be success
      The stderr should eq ''
    End

    It 'sources silently in a single-byte locale'
      bytes() {
        LC_ALL=C zsh -f -c '
          source "$1/lib/segments/ssh.zsh"
          (( ${+functions[_inzsh_segment_ssh_build]} )) && print -r -- loaded
        ' inzsh-ssh-bytes "$SHELLSPEC_PROJECT_ROOT" </dev/null
      }
      When call bytes
      The output should eq 'loaded'
      The stderr should eq ''
    End

    It 'builds without forking — this runs before every prompt'
      forks() {
        inzsh_spec_ssh_lines
        local line; local -a bad=()
        (( ${#inzsh_spec_lines} > 5 )) || bad+=no-lines-scanned
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'$('* || $line == *'`'* || $line == *whence* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call forks
      The output should eq ''
    End

    It 'never calls date, ps or uptime — the answer is already in the environment'
      processes() {
        inzsh_spec_ssh_lines
        local line name; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          for name in date ps uptime hostname who; do
            # `${name}` braced: `$name[` would be read as a SUBSCRIPT of the parameter.
            [[ " $line " == *[^a-zA-Z_]${name}[^a-zA-Z_]* ]] && bad+="$name: $line"
          done
        done
        print -rl -- $bad
      }
      When call processes
      The output should eq ''
    End

    It 'writes no \u escape — one would kill the file in a single-byte locale'
      escapes() {
        inzsh_spec_ssh_lines
        local line; local -a bad=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'\u'* || $line == *'\U'* ]] && bad+=$line
        done
        print -rl -- $bad
      }
      When call escapes
      The output should eq ''
    End

    It 'carries no glyph literal — the mark is read from the token table'
      tabled() {
        inzsh_spec_ssh_lines
        local line; local -a bad=()
        local -a found=()
        for line in "${inzsh_spec_lines[@]}"; do
          [[ $line == *'_inzsh_glyph[warn]'* ]] && found+=read
        done
        (( ${#found} )) || bad+=no-table-read
        print -rl -- $bad
      }
      When call tabled
      The output should eq ''
    End

    It 'carries no hex — colour lives in the token layer and nowhere else'
      hexed() {
        setopt local_options extended_glob
        inzsh_spec_ssh_lines
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
