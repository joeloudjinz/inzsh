Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/user.zsh

# The user segment — `lib/segments/user.zsh`. What it REGISTERS when it loads, and what FRAGMENT
# it writes into `_inzsh_segment_text[USER]` for a given username, configured default user and
# SSH marker. Nothing about blocks, separators or colour VALUES: the foreground role is asserted
# as the role NAME registered, plus the structural fact that the token layer carries one by that
# name, so no hex and no palette value reaches this file.
#
# What is NOT here, and where it is instead:
#   how a fragment becomes a block   test/render/render_build_spec.sh
#   rank sorting and the side split  test/unit/engine_spec.sh

# Build for username $2 with `INZSH_DEFAULT_USER` set to $1 — empty for "not configured" — and
# the SSH marker in $3. The default user and the marker go through the ENVIRONMENT here rather
# than through arguments, so the table below exercises the path the prompt itself takes; the
# argument seam gets its own example. The text map is cleared first, so an entry in the answer
# was written by THIS call.
#
# `$USERNAME` is never planted: zsh's `USERNAME` is a special parameter and assigning to it is a
# request to change user, which a test may not make. The username is injected as an argument,
# and the examples that must see the live parameter compare against `$USERNAME` itself.
inzsh_spec_user() {
  emulate -L zsh

  typeset -g INZSH_DEFAULT_USER=$1
  typeset -g SSH_CONNECTION=$3
  typeset -g SSH_TTY=

  _inzsh_segment_text=()
  _inzsh_segment_user_build "$2"

  print -r -- "[${_inzsh_segment_text[USER]}]"
}

Describe 'the user segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    It 'registers rank 2, a muted foreground and the bottom of the importance ramp'
      registered() {
        _inzsh_rank_of USER
        print -r -- "$REPLY ${_inzsh_segment_fg_role[USER]} ${_inzsh_segment_importance[USER]}"
      }
      When call registered
      The output should eq '2 text-muted 3'
    End

    It 'registers a foreground role the token layer actually carries'
      roled() {
        local role=${_inzsh_segment_fg_role[USER]}
        [[ -n ${_inzsh_role[$role]+set} ]] && print -r -- known || print -r -- "unknown:$role"
      }
      When call roled
      The output should eq 'known'
    End

    It 'writes no text at load — registering is not drawing'
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/user.zsh"
          print -r -- "entries=${#_inzsh_segment_text} user=${_inzsh_segment_text[USER]+set}"
        ' inzsh-user-quiet "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'entries=0 user='
      The stderr should eq ''
    End

    It 're-sources without doubling a registration or clearing a written fragment'
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/user.zsh"
          _inzsh_segment_text[USER]=keep
          source "$1/lib/segments/user.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${_inzsh_segment_defaults[USER]}" \
            "${#_inzsh_segment_fg_role} ${_inzsh_segment_fg_role[USER]}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_importance[USER]}" \
            "${_inzsh_segment_text[USER]}"
        ' inzsh-user-idempotent "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 2 1 text-muted 1 3 keep'
      The stderr should eq ''
    End

    It 'is sourceable on its own, with no core loaded at all'
      alone() {
        zsh -f -c '
          source "$1/lib/segments/user.zsh"
          _inzsh_segment_user_build deploy ""  "10.0.0.1 22"
          print -r -- "[${_inzsh_segment_text[USER]}]"
        ' inzsh-user-alone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call alone
      The output should eq '[deploy]'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the fragment'
    # $1 the configured default user, $2 the username, $3 the SSH marker, $4 what must land in
    # the text map.
    Parameters
      ''     joe        'ssh'  '[joe]'
      ''     joe        ''     '[]'
      joe    joe        ''     '[]'
      joe    joe        'ssh'  '[]'
      joe    root       ''     '[root]'
      joe    root       'ssh'  '[root]'
      joe    Joe        'ssh'  '[Joe]'
      joe    jo         'ssh'  '[jo]'
      joe    joey       'ssh'  '[joey]'
      joe    ''         'ssh'  '[]'
      joe    '   '      'ssh'  '[]'
      joe    '  joe  '  'ssh'  '[]'
      '  joe  ' joe     'ssh'  '[]'
      '   '  joe        'ssh'  '[joe]'
      '*'    joe        ''     '[joe]'
      'j*'   joe        ''     '[joe]'
      ''     '%n'       'ssh'  '[%%n]'
      ''     '%'        'ssh'  '[%%]'
      ''     'a%nb%'    'ssh'  '[a%%nb%%]'
      ''     'svc_01-x' 'ssh'  '[svc_01-x]'
    End

    It "draws ($2) against default ($1) with marker ($3) as $4"
      When call inzsh_spec_user "$1" "$2" "$3"
      The output should eq "$4"
    End
  End

  Describe 'the argument seam'
    # Every environmental input has an argument in front of it, and the argument wins. This is
    # what the table above rides on, so it is stated once rather than assumed.
    It 'prefers the arguments to the live parameters, in both positions'
      injected() {
        # Each case is set up so the ENVIRONMENT would answer the other way round: an argument
        # that was quietly ignored would show where this expects hidden, and the reverse.
        typeset -g SSH_CONNECTION=ssh
        typeset -g SSH_TTY=
        local -a wrong=()

        typeset -g INZSH_DEFAULT_USER=root
        _inzsh_segment_user_build root someone-else ''
        [[ ${_inzsh_segment_text[USER]} == root ]] || wrong+=default-arg-shows

        typeset -g INZSH_DEFAULT_USER=someone-else
        _inzsh_segment_user_build root root ''
        [[ ${_inzsh_segment_text[USER]} == '' ]]   || wrong+=default-arg-hides

        typeset -g INZSH_DEFAULT_USER=
        _inzsh_segment_user_build root '' ''
        [[ ${_inzsh_segment_text[USER]} == '' ]]   || wrong+=marker-arg

        print -r -- "${wrong[*]}"
      }
      When call injected
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'hiding where it carries no information'
    It 'is absent as the configured user and present as anyone else'
      # The judgment in both directions, one variable moving: the segment is a difference
      # detector, so the same call with a different username must flip it.
      both() {
        local expected other
        inzsh_spec_user joe joe '' >/dev/null
        expected=${_inzsh_segment_text[USER]}
        inzsh_spec_user joe root '' >/dev/null
        other=${_inzsh_segment_text[USER]}
        print -r -- "default=[$expected] other=[$other]"
      }
      When call both
      The output should eq 'default=[] other=[root]'
    End

    It 'shows an unexpected user locally — a difference is worth drawing anywhere'
      # The one place this segment differs from the host segment. With an expectation
      # configured, SSH stops being the question.
      surprising() {
        inzsh_spec_user joe root ''
      }
      When call surprising
      The output should eq '[root]'
    End

    It 'falls back to the SSH rule when no default user is configured'
      unconfigured() {
        local remote local_
        inzsh_spec_user '' joe ssh >/dev/null
        remote=${_inzsh_segment_text[USER]}
        inzsh_spec_user '' joe '' >/dev/null
        local_=${_inzsh_segment_text[USER]}
        print -r -- "ssh=[$remote] local=[$local_]"
      }
      When call unconfigured
      The output should eq 'ssh=[joe] local=[]'
    End

    Describe 'either SSH variable is enough on its own'
      # `SSH_CONNECTION` is what sshd sets; `SSH_TTY` survives setups that scrub the former. The
      # build reads the two concatenated, so this is the table that says so.
      Parameters
        connection shown
        tty        shown
        both       shown
        neither    hidden
      End

      It "reads $1 as $2"
        live() {
          typeset -g INZSH_DEFAULT_USER=
          typeset -g SSH_CONNECTION=
          typeset -g SSH_TTY=
          case $1 in
            (connection) SSH_CONNECTION='10.0.0.1 51000 10.0.0.2 22' ;;
            (tty)        SSH_TTY=/dev/pts/3 ;;
            (both)       SSH_CONNECTION='10.0.0.1 51000 10.0.0.2 22'; SSH_TTY=/dev/pts/3 ;;
          esac
          _inzsh_segment_text=()
          _inzsh_segment_user_build joe
          [[ ${_inzsh_segment_text[USER]} == joe ]] && print -r -- shown || print -r -- hidden
        }
        When call live "$1"
        The output should eq "$2"
      End
    End

    It 'takes the username from $USERNAME when no argument is given'
      # No argument at all: the live parameter, which is how the prompt calls it. `USERNAME` is
      # zsh's own and cannot be planted — assigning to it is a request to change user — so the
      # claim is that the fragment IS it, whatever it happens to be here.
      defaulted() {
        zsh -f -c '
          source "$1/lib/segments/user.zsh"
          SSH_TTY=/dev/pts/3
          SSH_CONNECTION=
          INZSH_DEFAULT_USER=
          _inzsh_segment_user_build
          local none=${_inzsh_segment_text[USER]}
          INZSH_DEFAULT_USER=$USERNAME
          _inzsh_segment_user_build
          local matched=${_inzsh_segment_text[USER]}
          INZSH_DEFAULT_USER=nobody-by-that-name
          _inzsh_segment_user_build
          local other=${_inzsh_segment_text[USER]}
          local -a wrong=()
          [[ -n $USERNAME && $none == $USERNAME ]] || wrong+=live
          [[ -z $matched ]]                        || wrong+=default-hides
          [[ $other == $USERNAME ]]                || wrong+=default-differs
          print -r -- "${wrong[*]}"
        ' inzsh-user-default "$SHELLSPEC_PROJECT_ROOT"
      }
      When call defaulted
      The output should eq ''
      The stderr should eq ''
    End

    It 'reads a set-but-empty INZSH_DEFAULT_USER as no configuration at all'
      # `INZSH_DEFAULT_USER=` left behind in a zshrc must fall through to the SSH rule, the same
      # way an `INZSH_DIR_BG=` falls through to the role. Empty means "no opinion" everywhere.
      emptied() {
        local remote local_
        inzsh_spec_user '' joe ssh >/dev/null
        remote=${_inzsh_segment_text[USER]}
        inzsh_spec_user '' joe '' >/dev/null
        local_=${_inzsh_segment_text[USER]}
        print -r -- "ssh=[$remote] local=[$local_]"
      }
      When call emptied
      The output should eq 'ssh=[joe] local=[]'
    End

    It 'clears the fragment it wrote at an earlier prompt'
      # The map outlives the prompt. A build that only wrote on the visible path would leave the
      # last username it drew sitting there, and the segment would go on drawing `root` after
      # the `sudo -s` shell had exited.
      stale() {
        _inzsh_segment_text=()
        _inzsh_segment_user_build root joe
        local first=${_inzsh_segment_text[USER]}
        _inzsh_segment_user_build joe joe
        print -r -- "first=[$first] second=[${_inzsh_segment_text[USER]}]"
      }
      When call stale
      The output should eq 'first=[root] second=[]'
    End

    It 'compares the default user exactly rather than as a pattern'
      # `INZSH_DEFAULT_USER=*` is the trap: matched as a glob it would equal every user alive
      # and hide the segment for good, with no way to tell why.
      globbed() {
        local -a wrong=()
        inzsh_spec_user '*' joe ssh >/dev/null
        [[ ${_inzsh_segment_text[USER]} == joe ]] || wrong+=star
        inzsh_spec_user 'j?e' joe ssh >/dev/null
        [[ ${_inzsh_segment_text[USER]} == joe ]] || wrong+=question
        inzsh_spec_user '*' '*' ssh >/dev/null
        [[ ${_inzsh_segment_text[USER]} == '' ]] || wrong+=literal
        print -r -- "${wrong[*]}"
      }
      When call globbed
      The output should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'in the prompt'
    It 'puts the username in the ribbon when it has something to say'
      drawn() {
        _inzsh_segment_text=()
        _inzsh_segment_user_build root joe
        _inzsh_left=(USER)
        _inzsh_render_build left
        [[ $REPLY == *' root '* ]] && print -r -- drawn || print -r -- "missing:$REPLY"
      }
      When call drawn
      The output should eq 'drawn'
    End

    It 'leaves no block and no separator when it has not'
      undrawn() {
        _inzsh_segment_text=()
        _inzsh_segment_user_build joe joe
        _inzsh_left=(USER)
        _inzsh_render_build left
        print -r -- "len=${#REPLY} width=$_inzsh_render_width"
      }
      When call undrawn
      The output should eq 'len=0 width=0'
    End

    It 'is not re-expanded as a prompt escape'
      literal() {
        _inzsh_segment_text=()
        _inzsh_segment_user_build '%n' '' ssh
        _inzsh_left=(USER)
        _inzsh_render_build left
        local expanded=${(%%)REPLY}
        [[ $expanded == *'%n'* ]] && print -r -- literal || print -r -- "expanded:$expanded"
      }
      When call literal
      The output should eq 'literal'
    End

    It 'measures as the characters a reader sees, not as the escaped ones'
      measured() {
        _inzsh_segment_text=()
        _inzsh_segment_user_build '%' '' ssh
        _inzsh_width "${_inzsh_segment_text[USER]}"
        print -r -- "$REPLY"
      }
      When call measured
      The output should eq '1'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the no-fork rule'
    # Structural: the rule is about the TEXT of the file. Comments are skipped — they name
    # `whoami` precisely to say it is not called.
    It 'contains no command substitution and no external command'
      grepped() {
        setopt local_options extended_glob
        local line bare; local -a found=()
        while IFS= read -r line; do
          bare=${line##[[:space:]]#}
          [[ -z $bare || $bare == \#* ]] && continue
          [[ $bare == *'$('* ]]  && found+="subst:$bare"
          [[ $bare == *'`'* ]]   && found+="backtick:$bare"
          [[ $bare == (*[^A-Za-z0-9_]|)(whoami|id|logname|getent|hostname)([^A-Za-z0-9_]*|) ]] &&
            found+="fork:$bare"
        done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/user.zsh"
        print -r -- "${found[*]}"
      }
      When call grepped
      The output should eq ''
    End
  End
End
