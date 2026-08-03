# InZsh

*(“in-zee-shell”)*

A calm, configurable zsh prompt — built from a design system, with an optional prayer-times
segment.

> **Status: pre-release.** Not yet installable. Development is in progress and the interface
> may change without notice until 1.0.

## Why another zsh theme

- **Built from a design system**, not assembled from colours that happened to look nice. Every
  colour is a semantic role with a verified contrast ratio in both light and dark.
- **Prayer times in the prompt** — computed locally, no network, no dependencies beyond zsh.
- **Actually tested.** Unit, render, terminal-grid and visual-regression suites, across zsh
  versions and colour depths.

## Requirements

- zsh **5.8+**
- A [Nerd Font](https://nerdfonts.com) — the prompt uses powerline separators
- A supported terminal (below)

Optional: [oh-my-zsh](https://ohmyz.sh). The theme works with or without it.

## Presets

| Preset | Mode | For |
|---|---|---|
| `inzsh-sharp` | dark | the default |
| `inzsh-warm` | light | warmer, editorial |

## Supported terminals

| Environment | Notes |
|---|---|
| Ghostty · iTerm2 · kitty · Alacritty · WezTerm | Full colour. The design target. |
| macOS Terminal.app | 256 colours only; the palette is tuned for this, but it is not identical. |
| tmux | Requires RGB passthrough, or colours are downgraded — see below. |

**tmux setup.** Add to `~/.tmux.conf`:

```tmux
set -sa terminal-features ',*:RGB'
```

Linux TTY and other bare consoles are not supported yet.

## Prayer times

The segment is optional and off unless configured. Times are computed on your machine using
standard astronomical methods — several calculation conventions and both Asr schools are
supported.

```zsh
INZSH_SALAH_LAT=21.4225      # your latitude
INZSH_SALAH_LON=39.8262      # your longitude
INZSH_SALAH_METHOD=mwl       # calculation convention
INZSH_SALAH_SCHOOL=shafi     # or hanafi
```

## Privacy

No telemetry. No network calls by default — prayer times are computed locally.

One exception, opt-in and off unless you enable it: `INZSH_SALAH_AUTOLOCATE=1` queries a
third-party IP geolocation service to determine your location, which means your IP address is
sent to that service. Setting your coordinates manually avoids this entirely.

## Colour accessibility

Every foreground/background pairing is verified against WCAG AA, in both presets and at both
colour depths. The palette is checked under protanopia, deuteranopia and tritanopia simulation,
and no state is signalled by colour alone — each carries a glyph.

## Something looks wrong?

Run the built-in diagnostic and paste its output into the issue:

```zsh
inzsh doctor
```

One block covering zsh version, terminal, `$TERM`, colour depth, locale, Nerd Font and tmux —
everything the bug template asks for, and nothing private: your coordinates, if the prayer
segment has any, are never printed.

## Contributing

Issues are welcome. Pull requests are considered case-by-case — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

The segment-rank idea — one integer per segment controlling both order and visibility — comes
from [comfyline](https://gitlab.com/imnotpua/comfyline_prompt) by *not pua*. InZsh is an
independent implementation.

## License

MIT — see [LICENSE](LICENSE).
