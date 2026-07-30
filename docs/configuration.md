# Configuration reference

Every public variable the theme reads. Grows in the same pull request as the knob it
documents — an option missing here is a bug.

Precedence, everywhere: per-segment override → semantic role → default.

## Engine

| Variable | Values | Default | Effect |
|---|---|---|---|
| `INZSH_SURFACE_MODE` | `alternate` · `ramp` · `flat` | `alternate` | How segment backgrounds are assigned. `alternate` swings between the two raised surfaces so every powerline separator stays visible. `ramp` assigns by per-segment importance, bumping equal neighbours apart. `flat` uses one surface for everything (no filled-powerline look). Invalid values fall back to `alternate`. |
| `INZSH_COLOR_DEPTH` | `truecolor` · `256` · `8` | detected | Overrides colour-depth detection for terminals that misreport. The palette degrades through hand-tuned fallback tables; invalid values are ignored and detection wins. |
