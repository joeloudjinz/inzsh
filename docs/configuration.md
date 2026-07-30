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
