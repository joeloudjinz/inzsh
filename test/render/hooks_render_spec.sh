# The hook layer, run rather than read — `lib/core/hooks.zsh`.
#
# Nothing here is `Include`d. Every example runs in a fresh `zsh` of its own, because what is
# under test is what INSTALLING does to a shell: the hook array, the exit status, the options
# and the environment. A spec that installed a precmd into its own runner would be testing a
# shell that already had one, and would be sourcing work in progress into a live shell besides.
#
# Two harnesses, and the difference matters:
#
#   `-i -s`   a genuinely interactive shell reading its script from a pipe. zsh runs precmd
#             between the lines exactly as it does between commands at a terminal, so the
#             status capture is asserted against the real hook mechanism rather than against a
#             hand call. Each input LINE is one prompt, which is what the counting below uses.
#   `-i -c`   interactive, one command, no prompt drawn. Used where a prompt would be noise:
#             the purity snapshot and the deleted-directory case, both of which want stderr to
#             be empty and mean it.
#
# `PROMPT=`, `nopromptcr` and `nopromptsp` are about the harness, not the theme: an interactive
# zsh writes its prompt and its partial-line marker to stderr, and this suite asserts on stderr.

# Runs $1 in a genuinely interactive zsh with no startup files. The project root arrives as $1
# inside the script.
inzsh_spec_live() {
  print -r -- "$1" |
    PROMPT= RPROMPT= PS1= zsh -f -i -o nopromptcr -o nopromptsp -s "$SHELLSPEC_PROJECT_ROOT"
}

Describe 'the hook layer'
  Describe 'the exit status'
    # The bug this prevents is silent: with anything above the capture, `$?` reads 0 forever
    # and a prompt that has never shown a failure looks exactly like a prompt that has never
    # seen one. Here `false` is a whole command line, and the precmd that fires before the next
    # one is the real thing — zsh's, not ours.
    It 'survives a real precmd firing between two command lines'
      plain() {
        inzsh_spec_live '
          source "$1/lib/core/hooks.zsh"
          _inzsh_hooks_install
          false
          print -r -- "status=$_inzsh_last_status pipes=${(j:,:)_inzsh_last_pipestatus}"
        '
      }
      When call plain
      The output should eq 'status=1 pipes=1'
      The stderr should eq ''
    End

    # `$?` alone cannot answer "which stage failed" — and under `pipefail` it is not even the
    # last stage's status — so `$pipestatus` is captured in the same breath. A capture split
    # across two commands reads the second value off the first and answers `0` here.
    #
    # A foreign precmd is registered as well, and registered AFTER ours, which is the order a
    # theme loaded from an rc file actually sees. It is also the only order in which any theme
    # can be right: precmd functions run left to right, each one seeing the status the previous
    # one returned, so a hook registered ahead of ours would overwrite `$?` before we ever ran.
    It 'captures every stage of a pipeline, with a foreign hook registered alongside'
      pipeline() {
        inzsh_spec_live '
          source "$1/lib/core/hooks.zsh"
          _inzsh_hooks_install
          autoload -Uz add-zsh-hook; foreign() { : }; add-zsh-hook precmd foreign
          true | false | (exit 7)
          out="status=$_inzsh_last_status pipes=${(j:,:)_inzsh_last_pipestatus}"
          print -r -- "$out hooks=${#precmd_functions}"
        '
      }
      When call pipeline
      The output should eq 'status=7 pipes=0,1,7 hooks=2'
      The stderr should eq ''
    End

    It 'reports success as readily as failure — a clean line leaves a clean status'
      clean() {
        inzsh_spec_live '
          source "$1/lib/core/hooks.zsh"
          _inzsh_hooks_install
          true
          print -r -- "status=$_inzsh_last_status pipes=${(j:,:)_inzsh_last_pipestatus}"
        '
      }
      When call clean
      The output should eq 'status=0 pipes=0'
      The stderr should eq ''
    End
  End

  Describe 'registration'
    # Idempotence by delegation: `add-zsh-hook` refuses to add a function the array already
    # holds. Installing three times is what a reload, a second plugin manager and a bundled
    # copy of the same theme add up to, and it has to land on one entry, not three.
    It 'installs once however many times it is asked'
      twice() {
        inzsh_spec_live '
          source "$1/lib/core/hooks.zsh"
          _inzsh_hooks_install; _inzsh_hooks_install; _inzsh_hooks_install
          print -r -- "count=${#precmd_functions} list=${precmd_functions[*]}"
        '
      }
      When call twice
      The output should eq 'count=1 list=_inzsh_precmd'
      The stderr should eq ''
    End

    # The regression the add-zsh-hook rule exists to prevent, written out in full. A foreign
    # hook is registered first; installing must leave it in place and still firing, and
    # uninstalling must take ours away and leave theirs — both its registration and its
    # execution. `x1` and `x2` count the prompts a foreign hook saw across one input line
    # either side, so a hook that survived the array but stopped running still fails here.
    It 'leaves a foreign hook registered and firing, through install and uninstall'
      foreign() {
        inzsh_spec_live '
          source "$1/lib/core/hooks.zsh"
          autoload -Uz add-zsh-hook; typeset -gi seen=0
          alien() { (( seen++ )) }; add-zsh-hook precmd alien
          _inzsh_hooks_install
          typeset -gi f1=$seen; typeset -g l1=${precmd_functions[*]}
          typeset -gi x1=$(( seen - f1 ))
          _inzsh_hooks_uninstall
          typeset -gi f2=$seen; typeset -g l2=${precmd_functions[*]}
          typeset -gi x2=$(( seen - f2 ))
          print -r -- "during=\"$l1\" x1=$x1 after=\"$l2\" x2=$x2"
        '
      }
      When call foreign
      The output should eq 'during="alien _inzsh_precmd" x1=1 after="alien" x2=1'
      The stderr should eq ''
    End

    # Uninstall from a shell that never installed is a no-op, not an error — a user may call it
    # from an rc file that runs before the theme, or twice.
    It 'uninstalls cleanly when there is nothing to uninstall'
      idle() {
        inzsh_spec_live '
          source "$1/lib/core/hooks.zsh"
          _inzsh_hooks_uninstall; _inzsh_hooks_uninstall
          print -r -- "status=$? registered=${+precmd_functions}"
        '
      }
      When call idle
      The output should eq 'status=0 registered=0'
      The stderr should eq ''
    End
  End

  # The entry point guards on `-o interactive` already. This is the second lock: a user who
  # sources `lib/core/hooks.zsh` directly, a bundle loaded by a script, a `zsh -c` in an
  # editor. Nothing may be registered, nothing printed, and PROMPT left where it was found.
  Describe 'a non-interactive shell'
    It 'registers nothing, prints nothing and leaves PROMPT alone'
      inert() {
        zsh -f -c '
          local before=$PROMPT
          source "$1/lib/core/hooks.zsh"
          _inzsh_hooks_install
          local -a leaked=()
          [[ $PROMPT == $before ]]     || leaked+=PROMPT
          (( ${+precmd_functions} ))   && leaked+=precmd:${precmd_functions[*]}
          (( ${+preexec_functions} ))  && leaked+=preexec:${preexec_functions[*]}
          print -r -- "${leaked[*]}"
        ' inzsh-hooks-inert "$SHELLSPEC_PROJECT_ROOT"
      }
      When call inert
      The output should eq ''
      The stderr should eq ''
    End

    # And the hook itself, called directly rather than through the array. `_inzsh_render` here
    # is a tripwire standing in for the renderer: if precmd reaches its dispatch in a shell
    # with no prompt, it says so. The status capture above the guard still runs — recording a
    # number is not writing to somebody's pipeline — so the assertion is on the OUTPUT.
    It 'no-ops when the hook is called directly — nothing renders, nothing is written'
      silent() {
        zsh -f -c '
          source "$1/lib/core/hooks.zsh"
          _inzsh_render() { print -r -- "RENDERED" }
          false
          _inzsh_precmd
          print -r -- "status=$?"
        ' inzsh-hooks-silent "$SHELLSPEC_PROJECT_ROOT"
      }
      When call silent
      The output should eq 'status=0'
      The stderr should eq ''
    End
  End

  # The user's environment is theirs. Snapshot every parameter with `typeset -p`, every option
  # with `setopt`, and the three locale variables by name, either side of the whole lifecycle —
  # source, install, two precmd runs, uninstall — and compare line by line. Only our own names
  # may differ.
  #
  # Snapshots go to files rather than to variables, so that holding one cannot itself perturb
  # the next; `$snap` is assigned before either and never changes, so it reads identically in
  # both. Options are included because a stray `setopt` is exactly the kind of global mutation
  # a variable diff cannot see — `emulate -L zsh` is local, and this is what proves it.
  Describe 'purity'
    It 'leaves parameters, options and locale exactly as it found them'
      untouched() {
        zsh -f -i -c '
          # Touch $functions first: reading it lazily loads zsh/parameter, a module load rather
          # than anything the hook layer owns, and it would otherwise show up as a difference.
          : ${+functions[_inzsh_precmd]}
          snap=${TMPDIR:-/tmp}/inzsh-hooks-purity.$$
          mkdir -p $snap
          {
            typeset -p >| $snap/before
            setopt     >| $snap/before-opts
            print -r -- "${LC_ALL-unset}|${LANG-unset}|${LC_CTYPE-unset}" >| $snap/before-loc

            source "$1/lib/core/hooks.zsh"
            _inzsh_hooks_install
            false
            _inzsh_precmd
            _inzsh_precmd
            _inzsh_hooks_uninstall

            typeset -p >| $snap/after
            setopt     >| $snap/after-opts
            print -r -- "${LC_ALL-unset}|${LANG-unset}|${LC_CTYPE-unset}" >| $snap/after-loc

            local -a before=("${(f)$(<$snap/before)}") after=("${(f)$(<$snap/after)}")
            local line; local -a touched=()
            # A snapshot that failed to write would compare equal to anything and pass silently.
            (( ${#before} > 1 && ${#after} > 1 )) || touched+=snapshot-empty
            for line in $after; do
              (( ${before[(Ie)$line]} )) || touched+=${${line%%=*}##* }
            done
            for line in $before; do
              (( ${after[(Ie)$line]} )) || touched+=${${line%%=*}##* }
            done
            # RANDOM and SECONDS move on their own between any two snapshots — reading one is
            # what changes it — and the harness names above were assigned before the first
            # snapshot, so they read identically in both. Everything else that moved, moved
            # because something assigned to it.
            touched=(${(ou)touched})
            touched=(${touched:#(_inzsh_*|RANDOM|SECONDS)})
            [[ $(<$snap/before-opts) == $(<$snap/after-opts) ]] || touched+=setopt
            [[ $(<$snap/before-loc)  == $(<$snap/after-loc)  ]] || touched+=locale
            print -r -- "${touched[*]}"
          } always {
            rm -rf $snap
          }
        ' inzsh-hooks-purity "$SHELLSPEC_PROJECT_ROOT"
      }
      When call untouched
      The output should eq ''
      The stderr should eq ''
    End
  End

  # A directory can be removed out from under a shell at any moment — a branch switch, a build
  # that cleans its own tree, a colleague's `rm -rf`. The prompt drawn from there has to be a
  # prompt, not an error message, and this is the case where a fork on the render path shows
  # itself: a subprocess started from a directory that no longer exists is where other themes
  # spill `getcwd` failures across the line the user is typing.
  #
  # Really removed, not simulated. `zsh/files` provides mkdir and rm as builtins, so the setup
  # never forks either and the removal cannot be the thing that fails. The `always` block runs
  # whether the body succeeded or not, and it cds out first — a removed cwd is not somewhere to
  # leave a shell, even a dying one.
  Describe 'a working directory that has been deleted'
    It 'captures, renders and returns cleanly from a $PWD that no longer exists'
      deleted() {
        zsh -f -i -c '
          zmodload -F zsh/files b:mkdir b:rm
          source "$1/lib/core/hooks.zsh"
          gone=${TMPDIR:-/tmp}/inzsh-hooks-gone.$$
          {
            mkdir -p $gone/here || print -r -- "setup: mkdir failed"
            cd $gone/here       || print -r -- "setup: cd failed"
            rm -rf $gone/here   || print -r -- "setup: rm failed"
            [[ -d $PWD ]]       && print -r -- "setup: directory still there"

            _inzsh_hooks_install
            false
            _inzsh_precmd
            rc=$?
            local -a wrong=()
            (( rc == 0 ))                  || wrong+=status:$rc
            [[ $_inzsh_last_status == 1 ]] || wrong+=capture:$_inzsh_last_status
            [[ -n ${(%%):-%~} ]]           || wrong+=prompt-expansion
            print -r -- "${wrong[*]}"
          } always {
            cd /
            rm -rf $gone
          }
        ' inzsh-hooks-deleted "$SHELLSPEC_PROJECT_ROOT"
      }
      When call deleted
      The output should eq ''
      The stderr should eq ''
    End
  End
End
