# Configuration reference

Every public variable the theme reads. Grows in the same pull request as the knob it
documents — an option missing here is a bug.

Precedence, everywhere: per-segment override → semantic role → default.

## How a value is read

**Two levels, per segment.** A per-segment override — `INZSH_<SEGMENT>_<KNOB>`, such as
`INZSH_DIR_BG` or `INZSH_GIT_RANK` — beats whatever the theme picked for that segment: the
semantic role for a colour, the registered default for everything else. That is the whole rule
for the families below, and it is the same rule for colour, rank, priority and width.

There is no bare `INZSH_BG` or `INZSH_RANK` that moves every segment at once. Each family is
addressed one segment at a time, by name; the theme's own defaults are the global layer, and
they are changed by overriding the segments you care about.

**Empty means unset, at every level.** An `INZSH_DIR_BG=` left behind in a `.zshrc` falls
through to the role rather than blanking the segment. There is no value that means "nothing" —
to switch a thing off, `unset` it or use the knob's own off value.

**Validate, then fall back.** Every knob has a set of values it accepts. A value outside that
set is not an error and is never reported at the prompt: it is simply not used, and the default
is drawn instead. `INZSH_SURFACE_MODE=chartreuse` gives an `alternate` prompt; a misspelled
colour depth gives the detected one. Nothing you can type into a config file can stop the prompt
from drawing.

Silent is not secret. `inzsh doctor` lists every `INZSH_` value that is set, invalid and
therefore ignored, with the vocabulary it should have used:

```
ignored       INZSH_SEPARATOR_STYLE=rounded - accepts arrow · round · divider
```

That section is absent when everything you have set is valid, so a clean shell says nothing.

A misspelled variable *name* has nothing to validate against, but if it sits close enough to a
name the registry does know, `inzsh doctor` says so rather than staying silent about it:

```
ignored       INZSH_SEPARATOR_STYL=round - probably INZSH_SEPARATOR_STYLE
```

A name that is not close to anything registered stays unreported — there is still no vocabulary
to state for one this theme has never heard of — so `inzsh-knobs` in the
[playground](../tools/playground.zsh) (`make play`) is where you check a name the doctor stayed
quiet about.

**Read at render time.** Values are read fresh on every prompt, never cached at load. Change a
variable at the command line and the next prompt reflects it — no re-source, no new shell. One
knob is deliberately not like this: `INZSH_PRESET` is read once, when the theme is sourced, and
its row below says why.

## Every knob is declared

The theme carries a registry: each option is declared once with the values it accepts and the
default it falls back to, and that declaration is what the read sites use. Two shapes of
declaration cover everything below.

**Singletons** are one name with one meaning — `INZSH_SURFACE_MODE`, `INZSH_GIT_TIMEOUT`.

**Families** are a shape rather than a name. `INZSH_<SEGMENT>_RANK` is not four variables, it is
one rule that every segment has and every segment added later will have; the registry holds the
pattern, and a concrete name resolves against it. The families are `INZSH_<SEGMENT>_RANK`,
`_PRIORITY`, `_BG`, `_FG` and `_MINCOLS`, and `INZSH_SALAH_OFFSET_<PRAYER>`. `<SEGMENT>` is the
segment's name in capitals; `<PRAYER>` is one of the six prayer names.

Two tests hold this page and the registry to each other: a variable the theme reads and never
declared fails the suite, and a declared variable missing from the table below fails it too. An
option missing here is a bug, and it is a bug the build finds.

## What configuration cannot change

Three properties hold whatever the configuration says. Where a setting would break one, the
theme falls back to a safe value rather than drawing the broken result:

- **Separators stay visible.** In a filled mode no two adjacent segments share a background.
  A surface assignment that would put equal backgrounds side by side is rejected and the mode
  degrades to `alternate`, which holds the property by construction. Under `hue`, where a segment
  names its own colour and two of them may name the same one, the repair is per block: the
  declaration is given up for the surface the position would have assigned. `flat` and
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
| `INZSH_<SEGMENT>_PRIORITY` | an integer, optional leading `+`/`-` | the segment's own default | The order segments are given up in as the window narrows — **lower survives longer**. When the row will not fit, the theme takes segments in this order, measures each one as it will actually be drawn, and stops at the first that does not fit; what you keep is always a prefix of the order. Rank is *position*, priority is *survival*, and they stay independent because the segment nearest the edge is not necessarily the one you want to lose first. Negative is ordinary and means "before everything at zero". |
| `INZSH_<SEGMENT>_MINCOLS` | non-negative integer | `0` | A hard floor: the terminal width below which this segment is dropped whatever the priority order says. `0` means never drop it on width alone, which is the default because the priority pass above already guarantees the row fits. Reach for this when you want one segment gone below a width of your choosing rather than when the arithmetic says so. |

## Engine

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_PRESET` | `sharp` · `warm`, matched with case, spacing and punctuation ignored | `sharp` | Which of the two shipped looks the theme draws: `sharp` is the dark register, `warm` the light one. Both are the same design system read in a different register, so nothing but colour changes. **This one is read when the theme is sourced, not at each prompt** — set it in `.zshrc` *above* the line that sources the theme. The reason is that `PS2`, `SPROMPT` and the title are built once, from the palette resolved at that moment, and a register applied later would move the prompt and quietly leave those behind. In a shell that is already running, `inzsh preset warm` is the switch — see below. Values that are not preset names — the register names `light` and `dark` among them — leave the default in place. |
| `INZSH_SURFACE_MODE` | `alternate` · `ramp` · `flat` · `hue` | `alternate` | How segment backgrounds are assigned. The first three assign by **elevation** — how far a block sits from the base surface — and differ only in the rule that picks a level: `alternate` swings between the two ends of the surface ramp, so every powerline separator stays visible; `ramp` assigns by per-segment importance, bumping equal neighbours apart; `flat` uses one surface for everything (no filled-powerline look). `hue` changes the axis — see below. Invalid values fall back to `alternate`. |
| `INZSH_SEPARATOR_STYLE` | `arrow` · `round` · `divider` | `arrow` | Which glyph draws the boundary between two segments. `arrow` is the filled powerline wedge, `round` the same ribbon with rounded caps, `divider` a thin rule with no filled boundary at all. `arrow` and `round` need a Nerd Font; `divider` needs only box drawing. Invalid values fall back to `arrow`. Setting `INZSH_NERD_FONT=0` resolves any style to `divider`, since the powerline glyphs cannot be drawn without the font. |
| `INZSH_COLOR_DEPTH` | `truecolor` · `256` · `8` | detected | **Read when the theme loads, not at each prompt** — detection runs once and the palette is resolved from its answer, so setting this at a prompt does nothing until the theme is sourced again. Put it in `.zshrc` above the line that sources the theme, or use `INZSH_COLOR_DEPTH=8 exec zsh` to try one. Overrides colour-depth detection for terminals that misreport. The palette degrades through hand-tuned fallback tables; invalid values are ignored and detection wins. |
| `INZSH_MULTIBYTE` | `1` · `0` | detected | **Read when the theme loads, not at each prompt** — the locale test is resolved once, so set it in `.zshrc` above the source line. Overrides the locale test that decides whether a non-ASCII glyph is safe to write. `0` selects the ASCII stand-ins for every mark the theme draws — `✕` becomes `x`, a powerline wedge becomes a thin rule — which is what a terminal outside a UTF-8 locale needs. Invalid values are ignored and the locale wins. |
| `INZSH_NERD_FONT` | `1` · `0` | detected | **Read when the theme loads, not at each prompt** — the font answer is resolved once, so set it in `.zshrc` above the source line. Whether the private-use glyphs will draw. Nothing inside a shell can prove a font is installed, so detection answers `1` only for terminals that bundle the symbol range and `unknown` otherwise — it never infers a `0`. Setting `0` is you reporting your own screen, and it resolves any separator style to `divider`. Invalid values are ignored. |
| `INZSH_GLYPH_<MARK>` | a short string; a value carrying `%` or a control character is refused | the theme's own mark | Replaces one mark, for every place that draws it at once. `<MARK>` names an entry of the token layer's glyph table, uppercased with `-` as `_`: the separators `SEP_LEFT`, `SEP_RIGHT`, `SEP_LEFT_ROUND`, `SEP_RIGHT_ROUND` and `DIVIDER`; the truncation `ELLIPSIS`; the input `PROMPT` marker; and the state set `OK`, `INFO`, `ERROR`, `WARN`, `DOT`, `DASH`, `AHEAD`, `BEHIND`. So `INZSH_GLYPH_ERROR=✗` restyles the failure mark in the exit-status segment and everywhere else it appears. An override outranks the ASCII degradation — like `INZSH_NERD_FONT=0` it is you reporting your own screen. A `%` would open a prompt escape and a control character would break the row the theme just measured, so either is refused whole and the theme's own mark stands; a wider mark is fine and is measured as drawn. Set-but-empty falls through — a state may never lose its mark, because colour is never the only signal. |
| `INZSH_SEGMENT_PAD` | integer, 0–4 | `1` | How many columns of air sit either side of every block's text. `0` packs the ribbon tight against its separators, higher values spread it. Bounded above because padding is literal spaces — the one thing in a prompt that could push a row past the terminal's edge — so a value outside the bound, or anything unreadable, falls back to `1` rather than being obeyed. The width machinery books the resolved value everywhere it measures a block, so no padding can wrap the row. |
| `INZSH_PROMPT_LINES` | `1` · `2` | `2` | How many rows the prompt takes. `2` gives the segments a row of their own and puts what you type on the next one behind a short marker, so a long path never crowds the command; the right-hand side is padded onto the segment row so the clock stays where you look for it. `1` puts everything on one row. Invalid values fall back to `2`. |
| `INZSH_PROMPT_MARKER` | any prompt string | `→` | What the second row draws in front of your input, verbatim. Outside a multibyte locale the default degrades to `>`. Set-but-empty falls through rather than blanking the line you type on. Whatever it holds is coloured by whether the last command succeeded. |
| `INZSH_TRANSIENT` | `1` · `0` · `true` · `false` · `yes` · `no` · `on` · `off`, in any case | `1` | Whether a prompt collapses to its minimal form once its command has been accepted, so scrollback reads as commands and output rather than two hundred repetitions of a seven-segment ribbon. Off keeps the full prompt in the transcript. |
| `INZSH_TRANSIENT_FORMAT` | `marker` · `dir` | `marker` | What a collapsed prompt shows. `marker` is the marker alone; `dir` puts the directory, muted, in front of it — worth it if you move between trees mid-session and want scrollback to say where each command ran. Invalid values fall back to `marker`. |
| `INZSH_RESIZE` | `1` · `0` · `true` · `false` · `yes` · `no` · `on` · `off`, in any case | `1` | Whether the prompt is rebuilt and redrawn when the terminal changes size. A prompt is measured once against the width it was drawn at, and in the two-row shape the right-hand side is padded onto the segment row with real spaces — so without this a narrowed window leaves a row that is too wide, wraps, and is redrawn as several rows of the same ribbon until you press Enter. The redraw keeps whatever you were part-way through typing. Off if you have your own `TRAPWINCH`, or would rather the prompt only changed when you asked it to. |
| `INZSH_RESIZE_REFLOW` | `1` · `0` · `true` · `false` · `yes` · `no` · `on` · `off`, in any case | unset — the shorter climb | Whether this terminal RE-WRAPS the rows already on screen when the window changes size. It decides how far the resize redraw climbs before it erases: a terminal that reflows has turned the old segment row into several, and one that does not still has it as one. There is no capability string to ask, and the honest probe — reading the cursor position — would race the keys you are typing, so it is declared rather than detected: **nothing is assumed, and nothing set means the shorter climb**, which is what every terminal measured so far wants. Set `1` if your terminal re-wraps its rows and a drag leaves stale prompts behind — VS Code and Hyper do, and the taller climb is unverified there, which is why it is opt-in. See [known limitations](limitations.md). |

### Switching preset in a running shell — `inzsh preset`

`INZSH_PRESET` is read once, as the theme loads, so setting it at a prompt does nothing. The
command is the other half of it:

```zsh
inzsh preset          # what is in force, and what else there is
inzsh preset warm     # switch, from the next prompt on
```

Names are matched the way the knob matches them — case, spacing and punctuation ignored, so
`Warm` and `warm` are one request — and anything that is not a preset name is refused out loud
with the names that are. The register names `light` and `dark` are not preset names.

**What it covers.** Every colour the prompt draws, the continuation and spell-correction prompts
if the theme installed them, and `INZSH_PRESET` itself, which is left agreeing with the register
now in force. It reads no file, so it behaves identically from a clone and from the single-file
bundle, which has no `presets/` directory at all.

**What it does not.** It does not reach any other shell, and it does not persist: a new terminal
is back to whatever `.zshrc` says, which is where `INZSH_PRESET=warm` belongs if you want the
choice to stick. The prompt already on the screen is not repainted — the next one is the first
one drawn in the new register. A `PS2` you set yourself, or one the theme never installed, is
left alone.

### One colour per segment — `INZSH_SURFACE_MODE=hue`

The default tells two blocks apart by **elevation**: the ribbon alternates between two surfaces
from the same narrow family, and the boundary is a step in brightness. `hue` tells them apart by
**colour** instead. Each segment carries a background of its own, drawn from the design system's
own ramps, and the ink comes with it — every fill in the palette is paired with the text colour
that belongs on it, so a block that takes the `negative` fill takes `on-negative` for its text
without anything else being set.

What ships, out of the box:

| Segment | Fill | |
|---|---|---|
| `root` | `negative` | the block *is* the warning |
| `user` | `neutral` | an identity is neither good news nor bad |
| `host` | a surface | a third hue between two coloured blocks turns an address into a traffic light |
| `dir` | `info` | the row's subject, and information rather than a state |
| `git` | the state's own fill | clean is green, dirty madder, staged ink-blue, a detached head ochre — the one block whose colour moves while you work |
| `venv` | the info wash | the quiet half of the family the path is the loud half of |
| `retval` | `negative` | it only exists when something failed |
| `ssh` | `caution` | the one segment whose whole point is that you are somewhere else |
| `jobs` | the info wash | a held job is information, not a fault |
| `time` · `duration` · `date` | surfaces | true of every prompt equally, and next to the block that should be spending the colour |
| `salah` | `accent` | the theme has one saturated colour and this is the segment it is for |

Two things worth knowing before you switch it on.

**A segment that declares a fill gives up its own text colour**, because the fill's paired ink
replaces it. That is why `git` moves its *background* with the repository's state rather than
just its foreground, and why the segments whose text colour is doing the work — the clock, the
duration — take surfaces instead.

**It costs colour at lower depths.** At 256 colours the fills are the hand-tuned approximations
the whole palette degrades to and the mode still reads. At 8 there are five ink colours and one
background, so `hue` and `alternate` draw the same flat ribbon; the glyphs carry the state, as
they do everywhere in this theme.

`INZSH_<SEGMENT>_BG` still outranks all of it, in every mode.

## Narrow terminals

There are no width breakpoints to configure. The prompt is fitted to the terminal every time it
is drawn, from the measured widths of the blocks that are actually about to appear — so the row
never wraps, whatever you have turned on and however long your branch name is today.

Three mechanisms share the work, and they do not stand in for one another:

- **The path shortens** rather than disappearing: `~/a/b/c` → `…/b/c` → `…/c`.
- **Blocks are dropped in priority order** when shortening is not enough. `INZSH_<SEGMENT>_PRIORITY`
  is that order — lower survives longer — and what you keep is always a prefix of it.
- **The right-hand group moves** down beside the cursor when the row cannot hold both sides, which
  is why the clock and the prayer time survive much narrower windows than their width suggests.
  They are only dropped once even that has run out of room.

`INZSH_<SEGMENT>_MINCOLS` is available on top of all this, for when you want one block gone below
a width of your own choosing rather than when the arithmetic says so.

Earlier versions had four named steps — `full`, `wide`, `narrow`, `minimal` — behind three
`INZSH_LADDER_*_COLS` variables. Nothing ever read the step, and fitting from real measurements
turned out to be both simpler and exact, so they were removed rather than tuned.

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
| `INZSH_DIR_COMPONENTS` | non-negative integer | `0` | How the path shortens before the terminal even asks it to: keep at most this many trailing components, the truncation marker standing for the rest — `2` draws `~/w/p/src/lib` as `…/src/lib` at any width. `0` is the whole path, shortened only when the row runs out of room; that narrow-terminal ladder still applies below the kept tail either way, so this caps a shape and never overflows a row. The marker itself is `INZSH_GLYPH_ELLIPSIS`. Anything unreadable means no cap — a typo shows a longer path, where obeying it could hide one. |
| `INZSH_DEFAULT_USER` | a username | unset | The account whose name is not worth drawing. Set it and the user segment becomes a difference detector: absent while you are that user, present the moment you are not — `sudo -s`, a service account, someone else's shell. Unset, the name is always drawn. Compared as text and never as a pattern, so a `*` here matches the user called `*` and nobody else. |
| `INZSH_HOST_ALWAYS` | `1` · `0` | `0` | Forces the host segment on for a local session. The default draws it only over SSH, where the hostname is the answer to "am I about to run this on production" and changes as you hop; locally it is a constant, and a constant spends width without carrying information. `1` is for people who split panes across machines and want the block in a fixed place. |
| `INZSH_TIME_FORMAT` | a `strftime` format | `%H:%M` | The clock segment's format. Not validated against a list of conversions — `strftime` is the only authority on what one means and the set differs between platforms — so it is tried, and judged on what came back: a format that renders nothing, or renders a control character, falls back to `%H:%M` rather than breaking the row. |
| `INZSH_DATE_FORMAT` | a `strftime` format | `%A, %-d %B %Y` | The date segment's format, judged the same way the clock's is: tried, and rejected only if it renders nothing or renders a control character, which would break the row the prompt just measured. The default spells the day and month out because the segment sits beside the clock, where a second run of digits reads as one number. The segment ships hidden — give it a rank to see it. |
| `INZSH_RETVAL_SIGNAL` | `name` · `number` | `name` | How a status above 128 is written. `name` draws the fact — `✕ SIGINT` — because the number is an encoding the reader has to undo: 128 + n, and then which signal n is. `number` keeps the encoded status — `✕ 130` — for whoever greps logs by code and would rather undo it themselves. A genuine exit code above 128 is misread either way; the ambiguity is in the shells' convention, not in the rendering. Invalid values fall back to `name`. |
| `INZSH_RETVAL_PIPELINE` | `1` · `0` · `true` · `false` · `yes` · `no` · `on` · `off`, in any case | `1` | Whether a failed pipeline is written as its whole chain — `✕ 1\|0\|127`, every stage in the order they ran — or judged by `$?` alone. The chain exists because `$?` is only the last stage: `grep x missing \| wc -l` prints `0` and returns 0, and only the chain can say so. Off is choosing to trust `$?` after all, which also means a pipeline whose last stage succeeded draws nothing. Anything unreadable keeps the chain — a typo may not silently hide a failed stage. |
| `INZSH_DURATION_MIN` | non-negative integer, in seconds | `3` | How long a command must have run before the duration segment reports it. Below the floor the segment is absent: a prompt that says `0s` after every command has stopped telling you anything. `0` reports everything. The segment ships hidden — give it a rank to see it. |

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

**Nothing on the render path can reach it.** The lookup runs only when you run it, through the
`inzsh locate` command — from your `.zshrc` detached, from a timer, or by hand after you move:

```zsh
INZSH_SALAH_AUTOLOCATE=1
(inzsh locate &!)     # in .zshrc: fire and forget, login does not wait
```

`inzsh locate` looks the position up only when the stored one is older than the TTL, so it is
safe to run on every login. `inzsh locate --force` looks it up regardless — the one for just
after you move. Either way the command says what it did: current, refreshed, or failed with the
previous answer kept.

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
| `INZSH_SALAH_AUTOLOCATE` | `1` · `0` · `true` · `false` · `yes` · `no` · `on` · `off`, in any case | `0` | Whether the lookup is permitted at all. Anything unreadable is **off** — a typo may not switch a network call on. Setting it permits the lookup and nothing more: run `inzsh locate` to make one. `INZSH_SALAH_LAT`/`LON` still win when they are set, so turning this on and then setting the coordinates by hand does the obvious thing. |
| `INZSH_SALAH_AUTOLOCATE_TTL` | integer, at least `300` | `86400` | Seconds before a refresh is considered due. It bounds a refresh and never a read: an older answer is still used, because a stale city beats no prayer times. |
| `INZSH_SALAH_AUTOLOCATE_TIMEOUT` | integer, 1–60 | `5` | The hard ceiling on the request, passed to `curl --max-time` or `wget --timeout`. Chosen against a person waiting for a terminal, not against a slow network. |
| `INZSH_SALAH_AUTOLOCATE_URL` | an `http://` or `https://` URL returning JSON with `latitude`/`longitude` (or `lat`/`lon`) | `https://ipapi.co/json/` | Where to ask. Point it at your own service and that is where the request goes; anything that is not one of those two schemes falls back to the default, since the value reaches an external command's argument list. |

### Reading the table by hand — `inzsh salah`

The segment only ever draws the next moment. `inzsh salah` prints the whole day, or several:

```zsh
inzsh salah                 # today
inzsh salah --days 7        # today and the next six
```

The header names the calculation method, the Asr school and the zone the times are shown in —
never your position, and never anything derived from it. A prayer with no time at your latitude
today (see *When the sun will not cooperate* in `docs/prayer-times.md`) prints `none` rather than
a blank. With no position configured it refuses, on stderr, pointing at `INZSH_SALAH_LAT`/`LON`
or `inzsh locate`.

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

**The accent.** This is the segment the theme's one saturated colour is meant for, and under
[`INZSH_SURFACE_MODE=hue`](#one-colour-per-segment--inzsh_surface_modehue) it takes it: the
segment asks for the `accent` fill and the renderer gives it, along with the ink the design system
pairs with that fill. The other modes assign backgrounds positionally, so there the accent is two
lines in your own config — written as roles rather than colour values, so a palette change still
reaches them:

```zsh
INZSH_SALAH_BG=${_inzsh_role[accent]}
INZSH_SALAH_FG=${_inzsh_role[on-accent]}
```

One caveat, recorded rather than hidden: caramel is the same value in both registers by design and
its paired ink is not, and neither of the two clears WCAG AA on it — 3.79:1 in the dark register,
3.07:1 in the light, both AA-large. It is the theme's one sub-AA pairing, and it is the design
system's rather than the prompt's. The block still says what it means as words — a prayer name and
a time — so the shortfall costs contrast and not information.

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
| `INZSH_SALAH_METHOD` | `MWL` · `ISNA` · `UmmAlQura` · `Egyptian` · `Karachi` · `Algeria`, plus the aliases `Makkah`, `Mecca`, `Egypt`, `MuslimWorldLeague`, `UmmAlQuraUniversity` | `MWL` | The calculation authority. Matched with case, spacing and punctuation ignored, so `Umm al-Qura`, `umm_al_qura` and `ummalqura` are one request. Each entry is a fajr angle plus either an isha angle or a fixed interval after maghrib; both forms are first-class. |
| `INZSH_SALAH_ASR` | `standard` · `shafi` · `hanafi`, in any case | `standard` | Which shadow length starts asr. `hanafi` is twice the object's length plus its noon shadow; the other two are once. |
| `INZSH_SALAH_HIGHLAT` | `angle` · `seventh` · `middle` · `none`, in any case | `angle` | What to do at a latitude where the sun never reaches the depression angle and fajr or isha would otherwise not exist. `none` leaves the prayer absent rather than inventing one. |
| `INZSH_SALAH_FAJR_ANGLE` | a number above `0` and no higher than `30` | the method's | The sun's depression below the horizon at fajr, in degrees. Overrides whatever the named method said. |
| `INZSH_SALAH_ISHA_ANGLE` | a number above `0` and no higher than `30` | the method's | The same for isha. Setting it clears any interval in play — an angle and an interval are two answers to one question. |
| `INZSH_SALAH_ISHA_INTERVAL` | integer, 1–240 | the method's, where it has one | Minutes after maghrib, for the authorities that fix isha that way rather than by an angle. Setting it clears the isha angle, for the same reason. |
| `INZSH_SALAH_OFFSET_<PRAYER>` | integer, −180 to 180 | `0` | Minutes to nudge one prayer's displayed time. `<PRAYER>` is `FAJR`, `SUNRISE`, `DHUHR`, `ASR`, `MAGHRIB` or `ISHA`. This calibrates a display against a local masjid, so it never feeds back into the arithmetic: moving maghrib does not move an isha measured as an interval from it. |
