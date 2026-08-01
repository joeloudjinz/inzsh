# Configuration reference

Every public variable the theme reads. Grows in the same pull request as the knob it
documents — an option missing here is a bug.

Precedence, everywhere: per-segment override → semantic role → default.

## How a value is read

**Three levels.** A per-segment override — `INZSH_<SEGMENT>_<KNOB>` — beats the semantic role
the theme picked for that segment, which beats the knob's default. Setting the plain
`INZSH_<KNOB>` moves the default for every segment at once; a role or an override still
specialises it. The rule is the same for colour, for surfaces and for everything added later,
so learning it once is enough.

**Empty means unset, at every level.** An `INZSH_DIR_BG=` left behind in a `.zshrc` falls
through to the role rather than blanking the segment. There is no value that means "nothing" —
to switch a thing off, `unset` it or use the knob's own off value.

**Validate, then fall back.** Every knob has a set of values it accepts. A value outside that
set is not an error and is never reported: it is simply not used, and the default is drawn
instead. `INZSH_SURFACE_MODE=chartreuse` gives an `alternate` prompt; a misspelled colour depth
gives the detected one. Nothing you can type into a config file can stop the prompt from
drawing.

**Read at render time.** Values are read fresh on every prompt, never cached at load. Change a
variable at the command line and the next prompt reflects it — no re-source, no new shell.

## Every knob is declared

The theme carries a registry: each option is declared once with the values it accepts and the
default it falls back to, and that declaration is what the read sites use. Two shapes of
declaration cover everything below.

**Singletons** are one name with one meaning — `INZSH_SURFACE_MODE`, `INZSH_GIT_TIMEOUT`.

**Families** are a shape rather than a name. `INZSH_<SEGMENT>_RANK` is not four variables, it is
one rule that every segment has and every segment added later will have; the registry holds the
pattern, and a concrete name resolves against it. The families are `INZSH_<SEGMENT>_RANK`,
`_BG`, `_FG` and `_MINCOLS`, and `INZSH_SALAH_OFFSET_<PRAYER>`. `<SEGMENT>` is the segment's
name in capitals; `<PRAYER>` is one of the six prayer names.

Two tests hold this page and the registry to each other: a variable the theme reads and never
declared fails the suite, and a declared variable missing from the table below fails it too. An
option missing here is a bug, and it is a bug the build finds.

## What configuration cannot change

Three properties hold whatever the configuration says. Where a setting would break one, the
theme falls back to a safe value rather than drawing the broken result:

- **Separators stay visible.** In a filled mode no two adjacent segments share a background.
  A surface assignment that would put equal backgrounds side by side is rejected and the mode
  degrades to `alternate`, which holds the property by construction. `flat` and
  `INZSH_SEPARATOR_STYLE=divider` are the exemptions, and for the same reason: neither draws a
  filled boundary, so there is none to lose.
- **Every state carries a glyph as well as a colour.** The marks come from one table in the
  token layer, each with an ASCII stand-in — `✕` becomes `x`, `…` becomes `...`, a powerline
  wedge becomes `|` — so a terminal without a UTF-8 locale or a Nerd Font loses the shape and
  keeps the signal. `INZSH_MULTIBYTE=0` selects the ASCII table outright.
- **The exit status survives.** `$?` and `$pipestatus` are captured on the first line of the
  prompt hook, above everything else, so no amount of configuration can cost you the status of
  the command you just ran.
- **The render budget holds.** The prompt renders in under 30 ms warm. The budget is not
  settable: options change what the prompt looks like, never what it is allowed to cost.

## Per-segment overrides

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_<SEGMENT>_BG` | anything `%K{…}` accepts — a hex value, a named colour, a 256 index | the segment's background role | Pins one segment's background, ahead of the palette, at every colour depth. `<SEGMENT>` is the segment's name in capitals, e.g. `INZSH_DIR_BG`. Not validated beyond non-emptiness: a colour you typed for your own terminal is your business. |
| `INZSH_<SEGMENT>_FG` | anything `%F{…}` accepts | the segment's foreground role | The same, for the text colour. Colour is never the only signal in this theme, so an override here cannot make a state unreadable — the glyph still says what the colour said. |
| `INZSH_<SEGMENT>_RANK` | an integer, optional leading `+`/`-` | the segment's own default | One number places a segment and decides whether it appears at all. Positive puts it in the left prompt counting out from the left edge (`1` is leftmost); negative puts it in the right prompt counting in from the right edge (`-1` is rightmost); `0` hides it. Ranks need not be contiguous — `1`, `4` and `10` order exactly as they read. Anything unreadable falls back to the default. |
| `INZSH_<SEGMENT>_MINCOLS` | non-negative integer | `0` | The terminal width below which this segment is dropped. `0` means never drop it on width alone. Rank is *position*, `MINCOLS` is *priority*: the segment nearest the edge is not necessarily the one you want to lose first, so the two stay independent. |

## Engine

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_SURFACE_MODE` | `alternate` · `ramp` · `flat` | `alternate` | How segment backgrounds are assigned. `alternate` swings between the two raised surfaces so every powerline separator stays visible. `ramp` assigns by per-segment importance, bumping equal neighbours apart. `flat` uses one surface for everything (no filled-powerline look). Invalid values fall back to `alternate`. |
| `INZSH_SEPARATOR_STYLE` | `arrow` · `round` · `divider` | `arrow` | Which glyph draws the boundary between two segments. `arrow` is the filled powerline wedge, `round` the same ribbon with rounded caps, `divider` a thin rule with no filled boundary at all. `arrow` and `round` need a Nerd Font; `divider` needs only box drawing. Invalid values fall back to `arrow`. Setting `INZSH_NERD_FONT=0` resolves any style to `divider`, since the powerline glyphs cannot be drawn without the font. |
| `INZSH_COLOR_DEPTH` | `truecolor` · `256` · `8` | detected | Overrides colour-depth detection for terminals that misreport. The palette degrades through hand-tuned fallback tables; invalid values are ignored and detection wins. |
| `INZSH_MULTIBYTE` | `1` · `0` | detected | Overrides the locale test that decides whether a non-ASCII glyph is safe to write. `0` selects the ASCII stand-ins for every mark the theme draws — `✕` becomes `x`, a powerline wedge becomes a thin rule — which is what a terminal outside a UTF-8 locale needs. Invalid values are ignored and the locale wins. |
| `INZSH_NERD_FONT` | `1` · `0` | detected | Whether the private-use glyphs will draw. Nothing inside a shell can prove a font is installed, so detection answers `1` only for terminals that bundle the symbol range and `unknown` otherwise — it never infers a `0`. Setting `0` is you reporting your own screen, and it resolves any separator style to `divider`. Invalid values are ignored. |

## Responsive breakpoints

The prompt adapts to the terminal width in four steps — `full`, `wide`, `narrow`, `minimal` —
and each variable below is the narrowest width that still counts as that step. Below the last
one the prompt is `minimal`. Hiding and shortening are different mechanisms: a path shortens
progressively (`~/a/b/c` → `…/b/c` → `…/c`) rather than disappearing, while `MINCOLS` decides
what disappears.

The defaults are deliberate placeholders, to be tuned against real segment widths once the
segments exist.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_LADDER_FULL_COLS` | non-negative integer | `120` | At or above this width, everything is drawn. |
| `INZSH_LADDER_WIDE_COLS` | non-negative integer | `80` | At or above this width, the step is `wide`. |
| `INZSH_LADDER_NARROW_COLS` | non-negative integer | `60` | At or above this width, the step is `narrow`; below it, `minimal`. |

A value that is not a non-negative integer falls back to its own default. If the three end up
out of order — a `wide` wider than `full`, say — the whole set reverts to 120 / 80 / 60 rather
than producing a ladder that cannot be climbed.

## Secondary prompts and the title

The parts of a theme nobody notices until they are missing: the continuation prompt you meet
the first time a quote is left open, the spell-correction prompt, and the text in the tab. The
two prompt strings are replaced whole rather than tuned — they are one line each, and a
grammar for editing them would be more to learn than to rewrite them.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_PS2` | any prompt string | the theme's own | Replaces the continuation prompt verbatim. The theme's own draws zsh's parser state (`then`, `do`, `quote`) muted, then one accented marker, which is what makes a continued line legible as one. Setting this to empty is not "no prompt" — it falls through to the theme's, like every other knob here. |
| `INZSH_SPROMPT` | any prompt string | the theme's own | Replaces the spell-correction prompt verbatim. The theme's own marks the mistyped word with `✕` and the suggestion with `✓` and lists all four keys zsh accepts — `y n a e` — rather than the usual two. |
| `INZSH_TITLE` | `1` · `0` · `true` · `false` · `yes` · `no` · `on` · `off`, in any case | `1` | Whether the terminal title is set at all. Off values switch it off; anything unreadable leaves it on, because a typo may not disable a feature silently. The title is never written to a non-interactive shell, to `TERM=dumb` or to the kernel console, whatever this says. |
| `INZSH_TITLE_FORMAT` | a template over `%d`, `%c` and `%%` | `%d %c` | The title text. `%d` is the current directory collapsed to `~`, `%c` the running command — empty at a prompt, so an idle title is just the directory. The grammar is deliberately these three and nothing else: the command line is pasted into the result, so a format handed to prompt expansion would let a directory name become an instruction. An unknown `%x` is kept literally, and a format that produces nothing falls back to the directory. |

## Segments

Each segment declares its own knobs beside the code that reads them. Rank, colour and
`MINCOLS` are the same for every segment and live under [per-segment
overrides](#per-segment-overrides); what follows is what one segment alone asks about.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_DEFAULT_USER` | a username | unset | The account whose name is not worth drawing. Set it and the user segment becomes a difference detector: absent while you are that user, present the moment you are not — `sudo -s`, a service account, someone else's shell. Unset, the name is always drawn. Compared as text and never as a pattern, so a `*` here matches the user called `*` and nobody else. |
| `INZSH_HOST_ALWAYS` | `1` · `0` | `0` | Forces the host segment on for a local session. The default draws it only over SSH, where the hostname is the answer to "am I about to run this on production" and changes as you hop; locally it is a constant, and a constant spends width without carrying information. `1` is for people who split panes across machines and want the block in a fixed place. |
| `INZSH_TIME_FORMAT` | a `strftime` format | `%H:%M` | The clock segment's format. Not validated against a list of conversions — `strftime` is the only authority on what one means and the set differs between platforms — so it is tried, and judged on what came back: a format that renders nothing, or renders a control character, falls back to `%H:%M` rather than breaking the row. |

## Git

The git segment is the theme's one background worker. It never runs git on the render path: a
worker fills a cache and the segment draws whatever is in it, so a slow repository costs a
stale segment rather than a slow prompt.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_GIT_ASYNC` | `1` · `0` · `true` · `false` · `yes` · `no` · `on` · `off`, in any case | `1` | Whether the worker runs at all. Off, the segment renders whatever is already cached and launches nothing — the escape hatch for a machine where a background git is the wrong trade at any timeout. |
| `INZSH_GIT_TIMEOUT` | integer, 1–60 | `2` | Seconds before the git call is killed. Two is chosen against the keystroke rather than against git: a status that has not answered in two seconds will not answer before you have finished typing the next command either. |
| `INZSH_GIT_BRANCH_MAX` | integer, 0–200 | `24` | How many columns the ref may take before it is elided. `0` means no limit. Branch names are as long as whoever named the ticket felt like, and a prompt that gives half its row to one has stopped being a prompt. |
| `INZSH_GIT_CACHE_DIR` | a directory path | `$XDG_CACHE_HOME/inzsh/git`, or `~/.cache/inzsh/git` | Where the cache entries live. Derived data with no value once the repository moves on, which is why it defaults under the cache directory rather than under a config one. A directory that cannot be created means no cache, which means the segment simply does not appear. |

## Prayer times

Local arithmetic over a timestamp and a location — no network, no fork, no calendar file. Name
the authority your masjid follows, or set the two angles off its noticeboard; the angles win
over the named method, so an authority the theme does not ship is a two-variable configuration
rather than a feature request.

Every value here is validated by the prayer module itself, which computes without loading any
part of the prompt engine. Unreadable values fall back the same way everything else does: an
unrecognised method computes MWL, and an angle of `banana` computes the method's own.

The shortest working configuration is two numbers:

```zsh
INZSH_SALAH_LAT=21.4225
INZSH_SALAH_LON=39.8262
```

Without a location the segment is **absent** — no block, no separator, nothing. It cannot
invent one, and it will not guess one from your time zone.

### Where you are

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_SALAH_LAT` | decimal degrees, −90 to 90, north positive | unset | Your latitude. Set both this and the longitude and the segment works offline, privately and deterministically — this is the documented path, and the one everything else here falls back to. A value that is not a number in range is treated as unset, so a typo hides the segment rather than moving you. |
| `INZSH_SALAH_LON` | decimal degrees, −180 to 180, east positive | unset | Your longitude. |

### Looking it up

Off by default. This is the **only network call in the theme**, and it exists so that people who
would rather not look their own coordinates up have a way not to. Everything about it is arranged
so that it cannot cost you a prompt.

**Nothing on the render path can reach it.** The lookup lives in one function,
`_inzsh_salah_locate_refresh`, and the theme never calls it. You call it — from your `.zshrc`
detached, from a timer, or by hand after you move:

```zsh
INZSH_SALAH_AUTOLOCATE=1
(_inzsh_salah_locate_refresh &!)     # in .zshrc: fire and forget, login does not wait
```

**What leaves the machine.** One HTTPS `GET` to `INZSH_SALAH_AUTOLOCATE_URL`, made by `curl` or,
failing that, `wget`. It carries what any HTTP request carries — a method, a path, a `Host`
header, the client's own user agent — and nothing the theme adds: no coordinates, no hostname, no
username, no shell state, no identifier of any kind. The service learns your public IP address,
which is the thing it is being asked to turn into a position. The response is read for two
numbers and the body is deleted.

**Failure is never visible.** The answer is cached, and the cached answer never expires: the TTL
says when a refresh is *due*, not when the last one stops being usable. A machine that has been
offline for a week is still almost certainly in the same city. With the lookup switched on, no
coordinates set and nothing ever cached, the segment is simply absent.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_SALAH_AUTOLOCATE` | `1` · `0` · `true` · `false` · `yes` · `no` · `on` · `off`, in any case | `0` | Whether the lookup is permitted at all. Anything unreadable is **off** — a typo may not switch a network call on. `INZSH_SALAH_LAT`/`LON` still win when they are set, so turning this on and then setting the coordinates by hand does the obvious thing. |
| `INZSH_SALAH_AUTOLOCATE_TTL` | integer, at least `300` | `86400` | Seconds before a refresh is considered due. It bounds a refresh and never a read: an older answer is still used, because a stale city beats no prayer times. |
| `INZSH_SALAH_AUTOLOCATE_TIMEOUT` | integer, 1–60 | `5` | The hard ceiling on the request, passed to `curl --max-time` or `wget --timeout`. Chosen against a person waiting for a terminal, not against a slow network. |
| `INZSH_SALAH_AUTOLOCATE_URL` | an `http://` or `https://` URL returning JSON with `latitude`/`longitude` (or `lat`/`lon`) | `https://ipapi.co/json/` | Where to ask. Point it at your own service and that is where the request goes; anything that is not one of those two schemes falls back to the default, since the value reaches an external command's argument list. |

### What it draws

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_SALAH_FORMAT` | `clock` · `countdown` · `window` · `full`, in any case | `clock` | Which reading of the next moment to draw. `clock` is `Maghrib · 19:59` — a time you can compare against a clock. `countdown` is `Maghrib in 24m` — no arithmetic for the reader, and meaningless in a screenshot an hour later. `window` is `Asr · until 19:59` — which prayer is due now and how long it stays due. `full` is `Maghrib · 19:59 · 24m`, for a wide terminal. Anything unrecognised draws `clock`. |

`window` names the window it is inside. Between sunrise and dhuhr, and between isha and the next
fajr, no window is open, and there it falls back to the `clock` reading rather than going blank
for a third of the day or asserting that isha's window runs to fajr — where isha's window ends is
a question of fiqh, and this theme computes the sun's position and rules on nothing else.

A prayer with no astronomical time — a polar night, a midnight sun — is skipped on the way to the
next real moment, and never drawn as `00:00`. Where every moment of the day is absent, so is the
segment.

**The accent.** This is the segment the theme's one saturated colour is meant for, and it cannot
claim it by itself: backgrounds are assigned positionally so that no two adjacent blocks share
one. Two lines in your own config give it the accent today, written as roles so that a palette
change still reaches them:

```zsh
INZSH_SALAH_BG=${_inzsh_role[accent]}
INZSH_SALAH_FG=${_inzsh_role[on-accent]}
```

### Where the day is kept

A day's six prayers cost a few milliseconds of trigonometry, which is far too much to pay on
every prompt, so the answer is computed once and written down. An entry holds **twelve** moments —
today's six and tomorrow's — so that after isha the next prayer is a lookup rather than a second
computation, and midnight is not an event anything has to handle.

The entry is keyed by **date, position, UTC offset and calculation parameters**. Change any of
them — cross a time zone, change methods at the prompt, wait until tomorrow — and the key changes
and the table is rebuilt. A laptop that travels does not show yesterday's city. The write is a
temporary file renamed over the target, so several shells waking up on the same morning cannot
show each other half an entry, and a truncated or edited entry is a miss, which recomputes.

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_SALAH_CACHE_DIR` | a directory path | `$XDG_CACHE_HOME/inzsh/salah`, or `~/.cache/inzsh/salah` | Where the day table and the looked-up position live. Derived data with no value once tomorrow arrives, which is why it defaults under the cache directory rather than under a config one. A directory that cannot be created means no file cache: the table is then held in memory for the life of the shell, and the segment still draws. |

### Calculating

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_SALAH_METHOD` | `MWL` · `ISNA` · `UmmAlQura` · `Egyptian` · `Karachi` · `Algeria`, plus the aliases `Makkah`, `Mecca`, `Egypt`, `MuslimWorldLeague` | `MWL` | The calculation authority. Matched with case, spacing and punctuation ignored, so `Umm al-Qura`, `umm_al_qura` and `ummalqura` are one request. Each entry is a fajr angle plus either an isha angle or a fixed interval after maghrib; both forms are first-class. |
| `INZSH_SALAH_ASR` | `standard` · `shafi` · `hanafi`, in any case | `standard` | Which shadow length starts asr. `hanafi` is twice the object's length plus its noon shadow; the other two are once. |
| `INZSH_SALAH_HIGHLAT` | `angle` · `seventh` · `middle` · `none`, in any case | `angle` | What to do at a latitude where the sun never reaches the depression angle and fajr or isha would otherwise not exist. `none` leaves the prayer absent rather than inventing one. |
| `INZSH_SALAH_FAJR_ANGLE` | a number above `0` and no higher than `30` | the method's | The sun's depression below the horizon at fajr, in degrees. Overrides whatever the named method said. |
| `INZSH_SALAH_ISHA_ANGLE` | a number above `0` and no higher than `30` | the method's | The same for isha. Setting it clears any interval in play — an angle and an interval are two answers to one question. |
| `INZSH_SALAH_ISHA_INTERVAL` | integer, 1–240 | the method's, where it has one | Minutes after maghrib, for the authorities that fix isha that way rather than by an angle. Setting it clears the isha angle, for the same reason. |
| `INZSH_SALAH_OFFSET_<PRAYER>` | integer, −180 to 180 | `0` | Minutes to nudge one prayer's displayed time. `<PRAYER>` is `FAJR`, `SUNRISE`, `DHUHR`, `ASR`, `MAGHRIB` or `ISHA`. This calibrates a display against a local masjid, so it never feeds back into the arithmetic: moving maghrib does not move an isha measured as an interval from it. |
