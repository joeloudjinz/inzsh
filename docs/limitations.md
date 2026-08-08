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

**Fonts.** The separators are private-use glyphs and want a [Nerd Font](https://nerdfonts.com).
Nothing inside a shell can prove a font is installed, so the theme does not guess: without one,
and unless you say so, it keeps drawing them — and they arrive as empty boxes. Telling it
(`INZSH_NERD_FONT=0`) resolves any separator style to the thin `divider` rule, which needs no
special font. The ASCII register — `v x i !` instead of `✓ ✕ i !` — is a separate axis
altogether, chosen by your LOCALE rather than by your font: it appears outside a UTF-8 locale,
or when you set `INZSH_MULTIBYTE=0`.

The line-gap variant matters too. Meslo ships in three (`MesloLGS`, `LGM`, `LGL`); the
small-gap one stacks filled blocks without seams, and the large-gap one leaves the ribbon
looking broken. Terminals that draw powerline glyphs themselves — Ghostty, kitty, WezTerm —
sidestep the whole question.

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

**Configuration.** Every knob takes effect at the next prompt, with four exceptions.
`INZSH_PRESET` and the three detection overrides — `INZSH_COLOR_DEPTH`, `INZSH_MULTIBYTE`,
`INZSH_NERD_FONT` — are read when the theme LOADS, because detection runs once and the palette
is resolved from its answer. Setting any of them at a prompt does nothing. Put them in
`.zshrc` above the line that sources the theme, or try one with
`INZSH_COLOR_DEPTH=8 exec zsh`; for the preset there is also `inzsh preset warm`, which
switches a running shell.

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

The claim is scoped to colour, and it is worth being exact about which parts of it a machine
checks and which parts a person did:

- **Colour is never the only signal** — and this one is enforced. Every state carries a glyph
  — `✓ i ✕ ! · —` — so a state readable in full colour is the same state readable in
  monochrome. The glyph table and the segments that draw from it are covered by the suite,
  which fails if a state loses its mark.
- **Contrast was designed to WCAG AA**, pair by pair, when the palette was built. The ratios
  are written down beside the colours in `lib/core/tokens.zsh` and `tokens-256.zsh` — including
  the ones that decided a token, such as the info ink landing at 3.97:1 on a surface that was
  dropped for it. This was done by hand and is recorded, not recomputed: **no test measures
  contrast**, so treat it as a documented design intent rather than a gate.
- **Colour-vision deficiency was considered** in the same way — the notes name protan and
  deutan separation where it drove a choice — but there is no simulation step in the repo, by
  hand or otherwise, and no claim here that the palette has been systematically tested under
  protanopia, deuteranopia or tritanopia.

What this is not: a general accessibility statement. Nothing here speaks to screen readers,
motion sensitivity, or cognitive load — a prompt lives inside a terminal, and most of that
surface belongs to the terminal emulator. And of what is above, one line is a guarantee the
suite keeps — a state never loses its glyph — while the contrast and colour-vision notes are
design work recorded in the source. An automated contrast check is the obvious next step and
is not written yet.
