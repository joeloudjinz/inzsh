Include lib/core/tokens.zsh
Include lib/core/layout.zsh
Include lib/core/engine.zsh
Include lib/core/render.zsh
Include lib/segments/root.zsh

# The `root` segment — `lib/segments/root.zsh`. A safety feature, so the examples below are
# about a promise rather than about an appearance: the badge appears when the effective user is
# root, it does not appear when they are not, and no third thing can happen.
#
# A spec cannot become root, which is exactly why the build takes the uid as an ARGUMENT. Every
# example hands it one. The two that touch the live shell only assert that the injected path and
# the live path AGREE, so the suite passes whether it is run as root or not — a CI job in a
# container is root often enough that pinning `$EUID` would be a spec that fails for a reason
# that is not the code's.
#
# No hex: the one example that pins colour reads the role the segment registered back out of
# `_inzsh_role`.
#
# What is NOT here, and where it is instead:
#   the chaining and the widths   test/render/render_build_spec.sh
#   rank sorting                  test/unit/engine_spec.sh
#   the glyph vocabulary          test/unit/layout_spec.sh

inzsh_spec_root() {
  _inzsh_segment_root_build "$@"
  print -r -- "[${_inzsh_segment_text[ROOT]}]"
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
inzsh_spec_root_maps='_inzsh_segment_bg_role _inzsh_segment_defaults _inzsh_segment_fg_role'
inzsh_spec_root_maps+=' _inzsh_segment_importance _inzsh_segment_priority'

inzsh_spec_root_touches() {
  local snap=${SHELLSPEC_TMPBASE:-${TMPDIR:-/tmp}}/inzsh-root-registration
  mkdir -p $snap
  zsh -f -c '
    local root=$1 snap=$2; local -i pre=$3 i
    for (( i = 1; i <= pre; i++ )); do source $root/lib/segments/root.zsh; done
    typeset -p >| $snap/before
    source $root/lib/segments/root.zsh
    typeset -p >| $snap/after
    local -a before=("${(f)$(<$snap/before)}") after=("${(f)$(<$snap/after)}")
    local line; local -a touched=()
    (( ${#before} > 1 && ${#after} > 1 )) || touched+=snapshot-empty
    for line in $after;  do (( ${before[(Ie)$line]} )) || touched+=${${line%%=*}##* }; done
    for line in $before; do (( ${after[(Ie)$line]} ))  || touched+=${${line%%=*}##* }; done
    touched=(${(ou)touched})
    touched=(${touched:#(RANDOM|SECONDS)})
    print -r -- "${touched[*]}"
  ' inzsh-root-registration "$SHELLSPEC_PROJECT_ROOT" "$snap" "$1"
}

Describe 'the root segment'
  # ------------------------------------------------------------------------------------------
  Describe 'registration'
    Describe 'the maps it fills'
      # $1 the map, $2 what ROOT must be worth in it. The lowest positive rank shipped, so this
      # is the leftmost block on the left prompt: whatever else the row says, it is read first.
      Parameters
        _inzsh_segment_defaults    10
        _inzsh_segment_fg_role     negative-text
        _inzsh_segment_bg_role     negative
        _inzsh_segment_importance  1
      End

      It "registers $2 in $1"
        registered() {
          local -A map=("${(@Pkv)1}")
          print -r -- "${map[ROOT]-<unset>}"
        }
        When call registered "$1"
        The output should eq "$2"
      End
    End

    It 'registers a rank the engine can read back, and one a user still outranks'
      ranked() {
        local -a seen=()
        _inzsh_rank_of root; seen+=$REPLY
        _inzsh_rank_of ROOT; seen+=$REPLY
        local INZSH_ROOT_RANK=6
        _inzsh_rank_of ROOT; seen+=$REPLY
        INZSH_ROOT_RANK=0
        _inzsh_rank_of ROOT; seen+=$REPLY
        INZSH_ROOT_RANK=nonsense
        _inzsh_rank_of ROOT; seen+=$REPLY
        print -r -- "${seen[*]}"
      }
      When call ranked
      The output should eq '10 10 6 0 10'
    End

    It 'registers both colour roles the token layer actually carries, in both registers'
      # `negative-text` is the ink on a SURFACE and `negative` the fill the segment asks for, and
      # both have to exist in whichever register the user chose — a warm prompt that lost the
      # root badge's colour would lose half of a two-signal warning.
      real() {
        local -a missing=()
        local role
        for role in ${_inzsh_segment_fg_role[ROOT]} ${_inzsh_segment_bg_role[ROOT]}; do
          [[ -n ${_inzsh_roles_dark[$role]+set} ]]  || missing+=dark:$role
          [[ -n ${_inzsh_roles_light[$role]+set} ]] || missing+=light:$role
          [[ -n ${_inzsh_role[$role]+set} ]]        || missing+=resolved:$role
        done
        print -r -- "${missing[*]}"
      }
      When call real
      The output should eq ''
    End

    It 'registers an ink that is legible on every surface the renderer can assign it'
      # The reason the registered ink is not `on-negative`: that is the face for text sitting ON
      # the negative fill, and in a positional mode there is no negative fill under it. This
      # example is the rule rather than the numbers — the badge's ink must not be a role the DS
      # pairs with a FILL, because a fill is exactly what a positional mode will not give it.
      paired() {
        local ink=${_inzsh_segment_fg_role[ROOT]}
        local -a bad=()
        [[ $ink == on-* ]] && bad+=on-fill-ink
        [[ -n ${_inzsh_role[on-$ink]+set} ]] && bad+=is-a-fill
        print -r -- "${bad[*]}"
      }
      When call paired
      The output should eq ''
    End

    It 'writes the five maps and nothing else — no text, no state, no side effect'
      When call inzsh_spec_root_touches 0
      The output should eq "$inzsh_spec_root_maps"
      The stderr should eq ''
    End

    It 'draws nothing at load time — the text map stays untouched until a build'
      # Registration that wrote a fragment would decide the question at SOURCE time, and the
      # answer would then survive an `exec sudo -s` or a change of effective uid.
      silent() {
        zsh -f -c '
          source "$1/lib/segments/root.zsh"
          print -r -- "${+_inzsh_segment_text[ROOT]} ${+functions[_inzsh_segment_root_build]}"
        ' inzsh-root-silent "$SHELLSPEC_PROJECT_ROOT"
      }
      When call silent
      The output should eq '0 1'
      The stderr should eq ''
    End

    It 'is idempotent — a second source changes nothing at all'
      When call inzsh_spec_root_touches 1
      The output should eq ''
      The stderr should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the badge'
    # Present at uid 0 and at nothing else. `000` is zero however it is spelled; `007` is seven,
    # because zsh reads a leading zero as octal, and seven is not root.
    Describe 'the truth table'
      # $1 the effective uid, $2 the fragment it produces.
      Parameters
        0      '[! root]'
        00     '[! root]'
        000    '[! root]'
        1      '[]'
        2      '[]'
        7      '[]'
        007    '[]'
        501    '[]'
        1000   '[]'
        65534  '[]'
      End

      It "draws $2 at euid $1"
        When call inzsh_spec_root "$1"
        The output should eq "$2"
      End
    End

    It 'carries a glyph as well as a colour — colour is never the only signal'
      # The fragment is plain text with no escapes of its own, so everything it says survives a
      # screenshot, a hostile palette and a reader who cannot see the colour at all. `!` is the
      # design system's caution mark; the vocabulary is fixed and this segment does not invent.
      signalled() {
        _inzsh_segment_root_build 0
        local fragment=${_inzsh_segment_text[ROOT]}
        local -a wrong=()
        [[ $fragment == *'!'* ]]     || wrong+=glyph
        [[ $fragment != *'%'* ]]     || wrong+=escapes
        [[ $fragment == *[a-z]* ]]   || wrong+=word
        _inzsh_width "$fragment"
        print -r -- "${wrong[*]} cols=$REPLY [$fragment]"
      }
      When call signalled
      The output should eq ' cols=6 [! root]'
    End

    It 'clears a badge the moment the shell stops being root'
      # A stale badge is worse than a missing one: it teaches its reader that the badge means
      # nothing. The text is cleared on every call before anything else is decided, so the
      # absent case is WRITTEN rather than merely not written.
      cleared() {
        local -a seen=()
        _inzsh_segment_root_build 0;   seen+="[${_inzsh_segment_text[ROOT]}]"
        _inzsh_segment_root_build 501; seen+="[${_inzsh_segment_text[ROOT]}]"
        _inzsh_segment_root_build 0;   seen+="[${_inzsh_segment_text[ROOT]}]"
        print -r -- "${seen[*]}"
      }
      When call cleared
      The output should eq '[! root] [] [! root]'
    End

    It 'reads $EUID when the argument is absent, and again when it is empty'
      # Empty means unset, as it does at every other level in the tree. Asserted as an
      # AGREEMENT with the injected answer rather than against a literal, so the example holds
      # whether the suite is run as root or not.
      defaulted() {
        _inzsh_segment_root_build "$EUID"
        local injected=${_inzsh_segment_text[ROOT]}
        _inzsh_segment_root_build
        local absent=${_inzsh_segment_text[ROOT]}
        _inzsh_segment_root_build ''
        local blank=${_inzsh_segment_text[ROOT]}
        local -a wrong=()
        [[ $absent == $injected ]] || wrong+=absent
        [[ $blank  == $injected ]] || wrong+=empty
        # And the live answer is the right one, whichever shell this is.
        if (( EUID == 0 )); then
          [[ -n $absent ]] || wrong+=missing-as-root
        else
          [[ -z $absent ]] || wrong+=present-as-user
        fi
        print -r -- "${wrong[*]}"
      }
      When call defaulted
      The output should eq ''
    End

    It 'lands an empty euid on the same parameter an absent one lands on'
      # The example above cannot see this one on its own: on a machine that is not root both
      # the empty case and the live case answer "no badge", so a fallback that had been deleted
      # would look identical. It is only visible when the suite runs AS root, which is exactly
      # when nobody is watching. So the claim is made structurally instead — two reads of
      # `$EUID`, one per level — the same way the render core's "no PROMPT assignment anywhere"
      # is a claim about the text of a file rather than about one run of it.
      fallback() {
        local body=${functions[_inzsh_segment_root_build]}
        local -a wrong=()
        [[ $body == *'${1-$EUID}'* ]] || wrong+=absent
        [[ $body == *'euid=$EUID'* ]] || wrong+=empty
        [[ $body != *'id -u'* ]]      || wrong+=fork
        print -r -- "${wrong[*]}"
      }
      When call fallback
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'hostile input'
    # `$EUID` is an integer parameter, so none of this can come from the shell. It can come from
    # a caller's bug, and the rule is that only a value that is unambiguously zero earns the
    # badge — a mark that also appears when something went wrong is a mark people learn to
    # ignore, and that is how a safety signal dies.
    Describe 'a uid that is not a uid'
      Parameters
        root
        hello
        '0x0'
        '+0'
        '-0'
        ' 0'
        '0 '
        '0.0'
        'O'
        '0|0'
        '$(echo 0)'
      End

      It "is absent for the euid '$1'"
        When call inzsh_spec_root "$1"
        The output should eq '[]'
      End
    End

    It 'never evaluates the uid as an arithmetic expression'
      # The trap the `<->` guard exists for. zsh's `(( ))` resolves a bare word as a PARAMETER
      # NAME, so `(( euid == 0 ))` on the word `hello` reads `$hello`, finds it unset or empty,
      # calls it zero and reports a root shell. Every one of these is a normal user.
      arithmetic() {
        local hello=0 zero=0 euid=0 nested='1 - 1'
        local -a wrong=() words=(hello zero euid nested 'zero + 1' '1 - 1' 'euid')
        local word
        for word in "${words[@]}"; do
          _inzsh_segment_root_build "$word"
          [[ -z ${_inzsh_segment_text[ROOT]} ]] || wrong+="[$word]"
        done
        print -r -- "${wrong[*]}"
      }
      When call arithmetic
      The output should eq ''
    End

    It 'is absent for every uid a shell can actually report except zero'
      swept() {
        local -a wrong=(); local -i uid
        for (( uid = 0; uid <= 64; uid++ )); do
          _inzsh_segment_root_build $uid
          if (( uid == 0 )); then
            [[ -n ${_inzsh_segment_text[ROOT]} ]] || wrong+=$uid:missing
          else
            [[ -z ${_inzsh_segment_text[ROOT]} ]] || wrong+=$uid:present
          fi
        done
        print -r -- "${wrong[*]}"
      }
      When call swept
      The output should eq ''
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'in the prompt'
    It 'draws a block in the face it registered when the shell is root'
      # The registration read back out of the finished string. The colour is named through
      # `_inzsh_role` and the role through the segment's own map, so a palette change cannot
      # fail this and a change of role can.
      drawn() {
        setopt local_options extended_glob
        _inzsh_segment_text=(OTHER other)
        _inzsh_segment_root_build 0
        _inzsh_left=(ROOT OTHER)
        _inzsh_right=()
        _inzsh_render_build left
        local face=${_inzsh_role[${_inzsh_segment_fg_role[ROOT]}]}
        local stripped=${REPLY//$_inzsh_sep_left/}
        local bare=${REPLY//(%[KF]\{[^\}]#\}|%[fk]|$_inzsh_sep_left)/}
        local -a wrong=()
        [[ $REPLY == *"%F{$face} ! root "* ]] || wrong+=face
        print -r -- "${wrong[*]} seps=$(( ${#REPLY} - ${#stripped} )) bare=[${bare//  / }]"
      }
      When call drawn
      The output should eq ' seps=2 bare=[ ! root other ]'
    End

    It 'leaves no block and no separator behind when the shell is not root'
      # The classic artefact this segment is most exposed to: it is ranked on every prompt and
      # absent on almost all of them, so a fragment that came back as a space, a dash or a
      # placeholder would put a permanent empty block at the left edge of everyone's prompt.
      quiet() {
        setopt local_options extended_glob
        _inzsh_segment_text=(OTHER other)
        _inzsh_segment_root_build 501
        _inzsh_left=(ROOT OTHER)
        _inzsh_right=()
        _inzsh_render_build left
        local stripped=${REPLY//$_inzsh_sep_left/}
        local bare=${REPLY//(%[KF]\{[^\}]#\}|%[fk]|$_inzsh_sep_left)/}
        print -r -- "seps=$(( ${#REPLY} - ${#stripped} )) bare=[${bare//  / }]"
      }
      When call quiet
      The output should eq 'seps=1 bare=[ other ]'
    End

    It 'sits at the left edge, ahead of every other segment, when it is drawn'
      # The lowest shipped rank is not decoration: a warning read after the directory and the
      # branch has already been read too late.
      first() {
        _inzsh_segment_text=(DIR dir GIT git)
        _inzsh_segment_root_build 0
        local INZSH_DIR_RANK=40 INZSH_GIT_RANK=60
        _inzsh_rank_split ROOT DIR GIT
        print -r -- "${_inzsh_left[*]}"
      }
      When call first
      The output should eq 'ROOT DIR GIT'
    End
  End

  # ------------------------------------------------------------------------------------------
  Describe 'the render path'
    It 'contains no command substitution and no process substitution'
      # No `id -u`, no `whoami`, ever. A fork that decides whether to warn you about root is a
      # fork that can fail quietly, and this one runs before every prompt.
      forkfree() {
        setopt local_options extended_glob
        local line bare backtick=$'\x60'
        local -a found=()
        while IFS= read -r line; do
          bare=${line##[[:space:]]#}
          [[ -z $bare || $bare == \#* ]] && continue
          [[ $bare == *'$('* || $bare == *$backtick* ]] && found+=$bare
          [[ $bare == *'<('* || $bare == *'>('* ]] && found+=$bare
        done < "$SHELLSPEC_PROJECT_ROOT/lib/segments/root.zsh"
        print -r -- "${found[*]}"
      }
      When call forkfree
      The output should eq ''
    End

    It 'emulates zsh in every function it defines'
      emulated() {
        setopt local_options extended_glob
        local body
        local -a missing=()
        for body in "${(k)functions[(I)_inzsh_segment_root_*]}"; do
          [[ ${functions[$body]} == *'emulate -L zsh'* ]] || missing+=$body
        done
        print -r -- "${#missing} ${missing[*]}"
      }
      When call emulated
      The output should eq '0 '
    End
  End
End
