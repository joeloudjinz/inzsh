Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/host.zsh

# The host segment — `lib/segments/host.zsh`. Two claims and no more: what it REGISTERS when it
# loads, and what FRAGMENT it writes into `_inzsh_segment_text[HOST]` for a given pair of inputs.
#
# No hex and no palette value reaches this file. The foreground role is asserted as the role NAME
# the segment registered, plus the structural fact that the token layer carries a role by that
# name — a palette change cannot fail either.
#
# What is NOT here, and where it is instead:
#   how a fragment becomes a block   test/render/render_build_spec.sh
#   rank sorting and the side split  test/unit/engine_spec.sh

# Build with `INZSH_HOST_ALWAYS` set to $1 — empty for "the user has not set it" — and the
# remaining arguments handed to the build verbatim. The text map is cleared first, so an entry
# in the answer was written by THIS call.
inzsh_spec_host() {
  emulate -L zsh

  typeset -g INZSH_HOST_ALWAYS=$1
  shift

  _inzsh_segment_text=()
  _inzsh_segment_host_build "$@"

  print -r -- "[${_inzsh_segment_text[HOST]}]"
}

Describe 'the host segment'
  # --------------------------------------------------------------------------------------------
  Describe 'registration'
    # Loading a segment file fills three maps and nothing else. The rank is read back through
    # `_inzsh_rank_of` rather than out of the map, because the default only means anything if the
    # engine finds it.
    It 'registers rank 30, a muted foreground and the bottom of the importance ramp'
      registered() {
        _inzsh_rank_of HOST
        print -r -- "$REPLY ${_inzsh_segment_fg_role[HOST]} ${_inzsh_segment_importance[HOST]}"
      }
      When call registered
      The output should eq '30 text-muted 3'
    End

    It 'registers a foreground role the token layer actually carries'
      roled() {
        local role=${_inzsh_segment_fg_role[HOST]}
        [[ -n ${_inzsh_role[$role]+set} ]] && print -r -- known || print -r -- "unknown:$role"
      }
      When call roled
      The output should eq 'known'
    End

    It 'writes no text at load — registering is not drawing'
      # A segment that filled its text map on the way in would draw a stale hostname at the first
      # prompt, before any build ran.
      quiet() {
        zsh -f -c '
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/host.zsh"
          print -r -- "entries=${#_inzsh_segment_text} host=${_inzsh_segment_text[HOST]+set}"
        ' inzsh-host-quiet "$SHELLSPEC_PROJECT_ROOT"
      }
      When call quiet
      The output should eq 'entries=0 host='
      The stderr should eq ''
    End

    It 're-sources without doubling a registration or clearing a written fragment'
      # `typeset -gA` over an existing association keeps what is in it. A plugin manager that
      # sources the tree twice, or a bundle loaded over a live theme, must not empty the map.
      twice() {
        zsh -f -c '
          source "$1/lib/core/engine.zsh"
          source "$1/lib/core/render.zsh"
          source "$1/lib/segments/host.zsh"
          _inzsh_segment_text[HOST]=keep
          source "$1/lib/segments/host.zsh"
          print -r -- "${#_inzsh_segment_defaults} ${_inzsh_segment_defaults[HOST]}" \
            "${#_inzsh_segment_fg_role} ${_inzsh_segment_fg_role[HOST]}" \
            "${#_inzsh_segment_importance} ${_inzsh_segment_importance[HOST]}" \
            "${_inzsh_segment_text[HOST]}"
        ' inzsh-host-idempotent "$SHELLSPEC_PROJECT_ROOT"
      }
      When call twice
      The output should eq '1 30 1 text-muted 1 3 keep'
      The stderr should eq ''
    End

    It 'is sourceable on its own, with no core loaded at all'
      # The maps are declared in the segment file for this reason: without the declaration a
      # build would be writing a subscript on a name that is not an association.
      alone() {
        zsh -f -c '
          source "$1/lib/segments/host.zsh"
          _inzsh_segment_host_build box "10.0.0.1 22"
          print -r -- "[${_inzsh_segment_text[HOST]}]"
        ' inzsh-host-alone "$SHELLSPEC_PROJECT_ROOT"
      }
      When call alone
      The output should eq '[box]'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the fragment'
    # $1 the hostname, $2 the SSH marker, $3 what must land in the text map. `INZSH_HOST_ALWAYS`
    # is unset throughout, so every row here is the DEFAULT judgment: informative when remote.
    Parameters
      box                'ssh'   '[box]'
      box.example.com    'ssh'   '[box]'
      box.example.com    ''      '[]'
      box                ''      '[]'
      ''                 'ssh'   '[]'
      '   '              'ssh'   '[]'
      '  box  '          'ssh'   '[box]'
      .example.com       'ssh'   '[]'
      '%m'               'ssh'   '[%%m]'
      '%'                'ssh'   '[%%]'
      'a%mb%'            'ssh'   '[a%%mb%%]'
      'BOX-01_prod'      'ssh'   '[BOX-01_prod]'
    End

    It "draws ($1) with marker ($2) as $3"
      When call inzsh_spec_host '' "$1" "$2"
      The output should eq "$3"
    End
  End

  Describe 'hiding where it carries no information'
    # The judgment, stated in both directions rather than in one: the same hostname is absent
    # locally and present over SSH, and nothing else about the call changes between the two.
    It 'shows over SSH and hides locally, from one hostname'
      both() {
        local shown hidden
        inzsh_spec_host '' box 'ssh' >/dev/null
        shown=${_inzsh_segment_text[HOST]}
        inzsh_spec_host '' box '' >/dev/null
        hidden=${_inzsh_segment_text[HOST]}
        print -r -- "ssh=[$shown] local=[$hidden]"
      }
      When call both
      The output should eq 'ssh=[box] local=[]'
    End

    Describe 'either SSH variable is enough on its own'
      # `SSH_CONNECTION` is what sshd sets; `SSH_TTY` survives setups that scrub the former. The
      # build reads the two concatenated, so this is the table that says so.
      Parameters
        connection '[box]'
        tty        '[box]'
        both       '[box]'
        neither    '[]'
      End

      It "reads $1 as $2"
        live() {
          zsh -f -c '
            source "$1/lib/segments/host.zsh"
            HOST=box.example.com
            SSH_CONNECTION=
            SSH_TTY=
            case $2 in
              (connection) SSH_CONNECTION="10.0.0.1 51000 10.0.0.2 22" ;;
              (tty)        SSH_TTY=/dev/pts/3 ;;
              (both)       SSH_CONNECTION="10.0.0.1 51000 10.0.0.2 22"; SSH_TTY=/dev/pts/3 ;;
            esac
            _inzsh_segment_host_build
            print -r -- "[${_inzsh_segment_text[HOST]}]"
          ' inzsh-host-live "$SHELLSPEC_PROJECT_ROOT" "$1"
        }
        When call live "$1"
        The output should eq "$2"
        The stderr should eq ''
      End
    End

    It 'takes the hostname from $HOST when no argument is given, shortened the same way'
      # The seam has to behave like the thing it stands in for: an injected FQDN and a live one
      # are both cut at the first dot.
      defaulted() {
        zsh -f -c '
          source "$1/lib/segments/host.zsh"
          HOST=box.example.com
          SSH_TTY=/dev/pts/3
          SSH_CONNECTION=
          _inzsh_segment_host_build
          print -r -- "[${_inzsh_segment_text[HOST]}]"
        ' inzsh-host-default "$SHELLSPEC_PROJECT_ROOT"
      }
      When call defaulted
      The output should eq '[box]'
      The stderr should eq ''
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'INZSH_HOST_ALWAYS'
    # Validate, then obey or ignore — never half-obey. `1` forces the block on locally; `0` is
    # the default said out loud; everything else is a typo, and a typo falls through to the
    # default rather than being guessed at.
    Describe 'the settings it understands, and the ones it refuses'
      # $1 the setting, $2 the marker, $3 the expected fragment.
      Parameters
        1     ''      '[box]'
        1     'ssh'   '[box]'
        0     ''      '[]'
        0     'ssh'   '[box]'
        ''    ''      '[]'
        yes   ''      '[]'
        true  ''      '[]'
        ' 1'  ''      '[]'
        01    ''      '[]'
        2     ''      '[]'
        -1    ''      '[]'
      End

      It "reads INZSH_HOST_ALWAYS=($1) with marker ($2) as $3"
        When call inzsh_spec_host "$1" box "$2"
        The output should eq "$3"
      End
    End

    It 'is the default when the variable was never set at all'
      # Set-but-empty is covered in the table above; this is the genuinely-unset case, which
      # only a fresh shell can show.
      unset_knob() {
        zsh -f -c '
          source "$1/lib/segments/host.zsh"
          _inzsh_segment_host_build box ""
          local hidden=${_inzsh_segment_text[HOST]}
          INZSH_HOST_ALWAYS=1
          _inzsh_segment_host_build box ""
          print -r -- "unset=[$hidden] one=[${_inzsh_segment_text[HOST]}]"
        ' inzsh-host-knob "$SHELLSPEC_PROJECT_ROOT"
      }
      When call unset_knob
      The output should eq 'unset=[] one=[box]'
      The stderr should eq ''
    End

    It 'clears the fragment it wrote at an earlier prompt'
      # The map outlives the prompt. A build that only wrote on the visible path would leave the
      # last hostname it drew sitting there, and the segment would go on drawing it after the
      # reason to draw it had gone — a stale block nothing can clear.
      stale() {
        _inzsh_segment_text=()
        _inzsh_segment_host_build box ssh
        local first=${_inzsh_segment_text[HOST]}
        _inzsh_segment_host_build box ''
        print -r -- "first=[$first] second=[${_inzsh_segment_text[HOST]}]"
      }
      When call stale
      The output should eq 'first=[box] second=[]'
    End

    It 'still hides a hostname that is empty, however the knob is set'
      # The knob answers "is this worth drawing", not "draw something". There is no placeholder.
      forced() {
        inzsh_spec_host 1 '' ''
      }
      When call forced
      The output should eq '[]'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'in the prompt'
    # The fragment is only a claim until the renderer draws it. Both directions, end to end.
    It 'puts the hostname in the ribbon when it has something to say'
      drawn() {
        _inzsh_segment_text=()
        _inzsh_segment_host_build box ssh
        _inzsh_left=(HOST)
        _inzsh_render_build left "${_inzsh_left[@]}"
        [[ $REPLY == *' box '* ]] && print -r -- drawn || print -r -- "missing:$REPLY"
      }
      When call drawn
      The output should eq 'drawn'
    End

    It 'leaves no block and no separator when it has not'
      undrawn() {
        _inzsh_segment_text=()
        _inzsh_segment_host_build box ''
        _inzsh_left=(HOST)
        _inzsh_render_build left "${_inzsh_left[@]}"
        print -r -- "len=${#REPLY} width=$_inzsh_render_width"
      }
      When call undrawn
      The output should eq 'len=0 width=0'
    End

    It 'is not re-expanded as a prompt escape'
      # `%m` in a hostname is the trap: spliced raw into PROMPT it would expand to the hostname
      # a second time. Doubled, it reaches the screen as the two characters it is.
      literal() {
        _inzsh_segment_text=()
        _inzsh_segment_host_build '%m' ssh
        _inzsh_left=(HOST)
        _inzsh_render_build left "${_inzsh_left[@]}"
        local expanded=${(%%)REPLY}
        [[ $expanded == *'%m'* ]] && print -r -- literal || print -r -- "expanded:$expanded"
      }
      When call literal
      The output should eq 'literal'
    End

    It 'measures as the characters a reader sees, not as the escaped ones'
      # A doubled per cent is one column. A width that counted the escape would reserve two.
      measured() {
        _inzsh_segment_text=()
        _inzsh_segment_host_build '%' ssh
        _inzsh_width "${_inzsh_segment_text[HOST]}"
        print -r -- "$REPLY"
      }
      When call measured
      The output should eq '1'
    End
  End

  # --------------------------------------------------------------------------------------------
  Describe 'the no-fork rule'
    # Structural, and deliberately so: the rule is about the TEXT of the file. A fork guarded by
    # a condition that is false today is still a fork waiting for the render path. Comments are
    # skipped — they name `hostname` precisely to say it is not called.
    It 'contains no command substitution and no external command'
      grepped() {
        setopt local_options extended_glob
        local line bare; local -a found=()
        while IFS= read -r line; do
          bare=${line##[[:space:]]#}
          [[ -z $bare || $bare == \#* ]] && continue
          [[ $bare == *'$('* ]]  && found+="subst:$bare"
          [[ $bare == *'`'* ]]   && found+="backtick:$bare"
          [[ $bare == (*[^A-Za-z0-9_]|)(hostname|whoami|uname|id|getent)([^A-Za-z0-9_]*|) ]] &&
            found+="fork:$bare"
        done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/host.zsh"
        print -r -- "${found[*]}"
      }
      When call grepped
      The output should eq ''
    End
  End
End
