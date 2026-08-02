# The registry, checked against the two things it is supposed to be true of: the code, and the
# reference. Nothing here is `Include`d — every claim is about the WHOLE tree, so the tree is
# loaded in a fresh `zsh -f` and read back, and the source text is scanned as text.
#
# Why this file exists. A configurable theme is only configurable if the set of knobs is
# knowable, and both halves of that decay silently. A knob read inline and declared nowhere has
# no default, no stated vocabulary and no way to be listed; a knob declared and never written
# down is invisible to everyone who did not write it. Neither shows up as a failing prompt —
# they show up a milestone later as "what is this theme configurable by?" with no answer.
#
# So the two examples that matter here are the two that fail:
#
#   read but not declared      `INZSH_*` appears in the tree and nothing registered it
#   declared but not written   the registry holds a knob `docs/configuration.md` does not
#
# Both name their offenders. A failure that says only "3 != 4" is a failure somebody deletes.

# Where the scan looks and what it deliberately does not. `lib/core/config.zsh` is the registry
# itself: the names in it are declarations rather than reads, and its own generic machinery
# builds variable names out of arguments — scanning it would be asking the registry whether it
# has heard of itself.
typeset -g inzsh_spec_registry_skip='lib/core/config.zsh'

# Every `INZSH_` name the tree READS, one per line, with `*` standing in wherever the code
# interpolates. `INZSH_${(U)1}_MINCOLS` comes back as `INZSH_*_MINCOLS`, which is the family
# pattern it is a read of; a literal name comes back as itself.
#
# Comment lines are skipped, and that is the honest definition rather than a convenience: the
# prose in this tree quotes knob names constantly — placeholders like `INZSH_<SEGMENT>_RANK`
# among them — and a mention is not a read.
inzsh_spec_knob_reads() {
  setopt local_options extended_glob
  local root=$SHELLSPEC_PROJECT_ROOT
  local file line rest token
  local -A seen=()

  for file in $root/lib/**/*.zsh $root/inzsh.zsh-theme; do
    [[ ${file#$root/} == $inzsh_spec_registry_skip ]] && continue
    while IFS= read -r line; do
      [[ ${line##[[:space:]]#} == \#* ]] && continue
      rest=$line
      while [[ $rest == *INZSH_* ]]; do
        rest=${rest#*INZSH_}
        token=INZSH_
        # One character at a time, because the name is built the way the shell builds it: a
        # name character is itself, an expansion is the part the user chooses, and anything
        # else ends the name.
        while (( ${#rest} )); do
          case $rest in
            ([A-Z0-9_]*)  token+=${rest[1]}; rest=${rest[2,-1]} ;;
            ('${'*)       token+='*';       rest=${rest#*\}} ;;
            (\$*)         token+='*';       rest=${rest##\$[A-Za-z_]##[A-Za-z0-9_]#} ;;
            (\**)         token+='*';       rest=${rest[2,-1]} ;;
            (*)           break ;;
          esac
        done
        seen[$token]=1
      done
    done < $file
  done

  print -rl -- ${(ko)seen}
}

# Every name and every family pattern the registry holds once the whole library is loaded, one
# per line. In a `zsh -f` subshell because that is the only honest way to ask: the registry is
# built by sourcing, and a shell that already has one would answer about itself.
inzsh_spec_registry_names() {
  zsh -f -c '
    local root=$1 file
    source $root/lib/core/config.zsh
    for file in $root/lib/core/*.zsh $root/lib/segments/*.zsh $root/lib/salah/*.zsh; do
      [[ $file == */config.zsh ]] && continue
      source $file
    done
    _inzsh_config_absorb_all || print -ru2 -- "absorb failed"
    local -a names
    names=(${(k)_inzsh_config_validators} ${(k)_inzsh_config_family_validators})
    print -rl -- ${(o)names}
  ' inzsh-registry "$SHELLSPEC_PROJECT_ROOT"
}

# Every variable the reference documents, one per line, taken from the first cell of every
# table row that names one. `INZSH_<SEGMENT>_BG` is written back as `INZSH_*_BG`: the page
# spells a family's variable part out for a reader, the registry spells it `*`, and this is the
# one place the two notations meet.
inzsh_spec_documented_names() {
  setopt local_options extended_glob
  local line name
  local -A seen=()

  while IFS= read -r line; do
    [[ $line == \|* ]] || continue
    name=${${line#\|}%%\|*}
    name=${${name##[[:space:]]#}%%[[:space:]]#}
    [[ $name == '`INZSH_'*'`' ]] || continue
    name=${name//\`/}
    name=${name//<[^>]##>/\*}
    seen[$name]=1
  done < "$SHELLSPEC_PROJECT_ROOT/docs/configuration.md"

  print -rl -- ${(ko)seen}
}

# Does `$1` — a name or a pattern — answer for `$2`? Asked both ways round, because either side
# may be the pattern: a read of `INZSH_SALAH_OFFSET_*` is covered by the registered family, and
# a read of `INZSH_DIR_BG` is covered by one registered pattern.
inzsh_spec_covers() {
  [[ $1 == ${~2} || $2 == ${~1} ]]
}

Describe 'the registry covers the tree'
  # THE FIRST GATE. A knob read anywhere and registered nowhere is the failure — that is a knob
  # with no default to fall back to, no stated vocabulary, and no way for a `doctor` command or
  # a reader to find it. The families are what keep a per-segment override from reading as one:
  # `INZSH_DIR_BG` is not an undeclared knob, it is `INZSH_*_BG` with a segment named.
  It 'declares every INZSH_ variable the tree reads'
    undeclared() {
      local -a reads declared missing=()
      local token entry
      reads=(${(f)"$(inzsh_spec_knob_reads)"})
      declared=(${(f)"$(inzsh_spec_registry_names)"})
      (( ${#reads} )) || { print -r -- 'scanned nothing'; return }
      for token in $reads; do
        for entry in $declared; do
          inzsh_spec_covers "$token" "$entry" && continue 2
        done
        missing+=$token
      done
      print -r -- "undeclared=${missing[*]}"
    }
    When call undeclared
    The output should eq 'undeclared='
  End

  # The other direction is not a failure and must not be one: a family covers names nobody has
  # written yet, and a knob may be registered by a segment this scan reads before it is read
  # anywhere. What this asserts instead is that the scan is looking at something — an empty
  # scan would satisfy the example above for the worst possible reason.
  It 'scans a tree that actually reads knobs'
    scanned() {
      local -a reads
      reads=(${(f)"$(inzsh_spec_knob_reads)"})
      print -r -- "reads=$(( ${#reads} >= 20 ))"
    }
    When call scanned
    The output should eq 'reads=1'
  End
End

Describe 'the reference covers the registry'
  # THE SECOND GATE. `docs/configuration.md` is the answer to "what is this theme configurable
  # by", and a knob that never reached it is a knob that ships invisible. Families are compared
  # as patterns and singletons by name, so the page documents one row per SHAPE rather than one
  # per segment.
  It 'documents every registered knob'
    undocumented() {
      local -a declared documented missing=()
      local knob
      declared=(${(f)"$(inzsh_spec_registry_names)"})
      documented=(${(f)"$(inzsh_spec_documented_names)"})
      (( ${#declared} )) || { print -r -- 'registry empty'; return }
      for knob in $declared; do
        (( ${documented[(Ie)$knob]} )) || missing+=$knob
      done
      print -r -- "undocumented=${missing[*]}"
    }
    When call undocumented
    The output should eq 'undocumented='
  End

  # And the reverse, which is the same rot from the other end: a row for a knob nothing declares
  # is a row that will keep telling people about an option the theme no longer has.
  It 'documents nothing the registry has never heard of'
    stale() {
      local -a declared documented extra=()
      local knob
      declared=(${(f)"$(inzsh_spec_registry_names)"})
      documented=(${(f)"$(inzsh_spec_documented_names)"})
      (( ${#documented} )) || { print -r -- 'reference empty'; return }
      for knob in $documented; do
        (( ${declared[(Ie)$knob]} )) || extra+=$knob
      done
      print -r -- "stale=${extra[*]}"
    }
    When call stale
    The output should eq 'stale='
  End
End

Describe 'a module that may not call the registry'
  # `lib/salah/` imports nothing from the engine — that is what lets the prayer arithmetic be
  # tested standalone against a fixture oracle — so it cannot register its knobs the way a
  # segment does. It ships a table instead, and the engine absorbs it. Three things have to
  # stay true at once, and each of the three is one of the examples below.

  It 'computes with lib/salah/calc.zsh sourced alone in zsh -f'
    alone() {
      zsh -f -c '
        source $1/lib/salah/calc.zsh
        _inzsh_salah_compute 1782036000 21.4225 39.8262 fajr_angle=18 isha_angle=17 ||
          print -r -- "compute failed"
        [[ ${_inzsh_salah_reply[dhuhr]} == <-> ]] && print -r -- alone || print -r -- broken
      ' inzsh-salah-alone "$SHELLSPEC_PROJECT_ROOT"
    }
    When call alone
    The output should eq 'alone'
    The stderr should eq ''
  End

  It 'declares its knobs with methods.zsh sourced alone, and calls nothing to do it'
    declared_alone() {
      zsh -f -c '
        source $1/lib/salah/methods.zsh
        local -a leaked=()
        (( ${#_inzsh_salah_knobs} )) || leaked+=no-table
        (( ${#_inzsh_salah_knobs} % 3 == 0 )) || leaked+=ragged-table
        (( ${#${(k)functions[(I)_inzsh_config_*]}} )) && leaked+=engine-functions
        print -r -- "${leaked[*]}"
      ' inzsh-salah-decl "$SHELLSPEC_PROJECT_ROOT"
    }
    When call declared_alone
    The output should eq ''
    The stderr should eq ''
  End

  It 'is absorbed into the registry once both halves are loaded'
    absorbed() {
      zsh -f -c '
        source $1/lib/core/config.zsh
        source $1/lib/salah/methods.zsh
        _inzsh_config_absorb_all || print -r -- absorb-failed
        local -a missing=()
        local knob
        for knob in INZSH_SALAH_METHOD INZSH_SALAH_ASR INZSH_SALAH_ISHA_INTERVAL; do
          (( ${+_inzsh_config_validators[$knob]} )) || missing+=$knob
        done
        _inzsh_config_get INZSH_SALAH_METHOD
        [[ $REPLY == $_inzsh_salah_default_method ]] || missing+=default:$REPLY
        INZSH_SALAH_OFFSET_ASR=-30
        _inzsh_config_get INZSH_SALAH_OFFSET_ASR
        [[ $REPLY == -30 ]] || missing+=family:$REPLY
        INZSH_SALAH_OFFSET_ASR=-3000
        _inzsh_config_get INZSH_SALAH_OFFSET_ASR
        [[ $REPLY == 0 ]] || missing+=family-bound:$REPLY
        print -r -- "${missing[*]}"
      ' inzsh-salah-absorb "$SHELLSPEC_PROJECT_ROOT"
    }
    When call absorbed
    The output should eq ''
    The stderr should eq ''
  End
End

Describe 'defaults restated for a partial load'
  # Several files hold a copy of their own registered default, so that a file sourced without
  # the config layer — a half-assembled bundle, a spec that includes one file — still degrades
  # to the shipped behaviour rather than to nothing. Every copy is a chance for the two to
  # disagree, and a disagreement here is invisible: both values are plausible, and which one
  # you get depends on how much of the theme was loaded.
  It 'holds every restated default equal to the registered one'
    agree() {
      zsh -f -c '
        local root=$1 file
        source $root/lib/core/config.zsh
        for file in $root/lib/core/*.zsh $root/lib/segments/*.zsh $root/lib/salah/*.zsh; do
          [[ $file == */config.zsh ]] && continue
          source $file
        done
        _inzsh_config_absorb_all
        local -a bad=()
        [[ ${_inzsh_config_defaults[INZSH_TIME_FORMAT]} == $_inzsh_time_format_default ]] ||
          bad+=time-format
        [[ ${_inzsh_config_defaults[INZSH_TITLE_FORMAT]} == $_inzsh_title_format_default ]] ||
          bad+=title-format
        [[ ${_inzsh_config_defaults[INZSH_GIT_TIMEOUT]} == $_inzsh_git_timeout_default ]] ||
          bad+=git-timeout
        [[ ${_inzsh_config_defaults[INZSH_GIT_BRANCH_MAX]} == $_inzsh_git_branch_max_default ]] ||
          bad+=git-branch-max
        [[ ${_inzsh_config_defaults[INZSH_SALAH_METHOD]} == $_inzsh_salah_default_method ]] ||
          bad+=salah-method
        print -r -- "${bad[*]}"
      ' inzsh-restated "$SHELLSPEC_PROJECT_ROOT"
    }
    When call agree
    The output should eq ''
    The stderr should eq ''
  End
End
