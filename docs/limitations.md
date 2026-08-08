# Known limitations, privacy, and colour accessibility

Three honest statements. Everything here is deliberate — either a trade-off the design chose,
or a boundary it refuses to blur — and each section says only what the code actually does.

## Known limitations

**Terminals.** The design target is a full-colour terminal (Ghostty, iTerm2, kitty, Alacritty,
WezTerm). macOS Terminal.app shows 256 colours; the palette is hand-tuned for that case and
keeps the theme's shape, but it is close rather than identical — the README pictures it
deliberately. On an 8-colour terminal the theme stays legible but pays stated costs: some
nearby tones share one of the eight slots, and the light register's cream ramp flattens.
Linux TTY and other bare consoles are not supported.

**Fonts.** The powerline separators and state marks want a [Nerd Font](https://nerdfonts.com).
Without one the theme falls back to an ASCII register — bars instead of wedges, letters
instead of marks. Readable, but the two sides of the prompt lose their mirrored shapes.

**Resizing in a terminal that reflows.** Dragging a window narrower rebuilds the prompt and
erases the old one first. In a terminal that RE-WRAPS the rows already on screen — xterm.js,
which is VS Code's and Hyper's — the old row becomes several, the erase reaches only the last
of them, and each drag leaves stale ribbons behind. `INZSH_RESIZE_REFLOW=1` switches on
arithmetic that should handle it and is unverified; `INZSH_RESIZE=0` turns the redraw off
altogether and leaves a stale prompt until the next Enter, which is untidy in one place rather
than many. Native terminals — Ghostty, Terminal.app, kitty, iTerm2, Alacritty, WezTerm — are
unaffected.

**tmux.** Full colour requires RGB passthrough (`set -sa terminal-features ',*:RGB'`).
Without it colours are downgraded to what tmux forwards.

**Configuration.** Every knob takes effect at the next prompt, with one exception:
`INZSH_PRESET` is read when the theme loads, so changing it in a running shell does nothing
until the theme is sourced again — the configuration reference explains why and shows the
switch for a live shell.

**Git.** The segment reports a state glyph, the branch (or detached commit), and ahead/behind
counts. It does not count changed files, and it never runs git on the prompt's critical path —
status arrives from a background worker, so a just-changed repository can show its previous
state for one paint.

**Prayer times.** ([How they are calculated](prayer-times.md), with sources.) Times are computed astronomically from your coordinates with published
method parameters; they are calculations, not announcements from your masjid. The offset
knobs exist precisely to calibrate the display against a local timetable. At extreme
latitudes, where fajr or isha may not astronomically exist, the configured high-latitude
convention decides — and `none` honestly leaves the prayer absent.

## Privacy

**What leaves the machine: nothing, by default.** No telemetry, no update checks, no network
calls. Prayer times are computed locally.

**The one exception is opt-in twice over.** `INZSH_SALAH_AUTOLOCATE=1` permits — but does not
perform — a location lookup. The request happens only when *you* run `inzsh locate`. It is a
single HTTPS GET to a URL you can read and change (`INZSH_SALAH_AUTOLOCATE_URL`), made by curl
or wget. It carries what any HTTP request carries — and nothing the theme adds: no
coordinates, no hostname, no username, no shell state. The service learns your public IP
address, which is exactly what it is being asked to turn into a position. The answer is
cached; the last good answer never expires; a failed lookup never costs you a prompt.
Setting `INZSH_SALAH_LAT`/`INZSH_SALAH_LON` by hand avoids all of this entirely.

**Diagnostics stay clean.** `inzsh doctor` prints where your position came from and how old
it is — never the coordinates themselves — so its output is safe to paste into a public
issue.

## Colour accessibility

The claim is scoped to colour, and within that scope it is checked, not hoped:

- Every foreground/background pairing the theme can draw is verified against **WCAG AA**
  contrast, in both presets, at full colour and at 256 colours.
- The palette is reviewed under **protanopia, deuteranopia and tritanopia** simulation.
- **Colour is never the only signal.** Every state carries a glyph — `✓ i ✕ ! · —` — so a
  state readable in full colour is the same state readable in monochrome.

What this is not: a general accessibility statement. Nothing here speaks to screen readers,
motion sensitivity, or cognitive load — a prompt lives inside a terminal, and most of that
surface belongs to the terminal emulator. Within what a theme controls — colour and glyphs —
the guarantees above hold, and the test suite enforces them.
