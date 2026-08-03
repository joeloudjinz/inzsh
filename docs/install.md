# Install guide

Two supported paths — as an [oh-my-zsh](https://ohmyz.sh) custom theme, or a plain `source`
from `.zshrc` — plus a manual route for anyone who prefers to wire things themselves. One
installer covers the first two, and one command takes any of it back out.

## Requirements

- **zsh 5.8 or newer** — `zsh --version` tells you.
- A **[Nerd Font](https://nerdfonts.com)** — the prompt uses powerline separators.
- A supported terminal — see the [README](../README.md#supported-terminals).

Nothing else. The theme is pure zsh: no plugins, no network, no dependencies.

## Get the code

```zsh
git clone https://github.com/joeloudjinz/inzsh.git ~/.inzsh
cd ~/.inzsh
```

Any location works — the installer records the path it was run from, so pick one the clone
will stay at.

## Install

```zsh
zsh install.zsh
```

That is the whole install. With no flag the installer uses oh-my-zsh when it finds one
(`$ZSH`, or `~/.oh-my-zsh`) and the plain path otherwise; a flag pins the choice:

```zsh
zsh install.zsh --omz     # force the oh-my-zsh path
zsh install.zsh --plain   # force the plain path, oh-my-zsh or not
```

Open a new shell and the prompt is there.

### What the oh-my-zsh path does

- Symlinks the theme into your custom themes directory —
  `${ZSH_CUSTOM:-$ZSH/custom}/themes/inzsh.zsh-theme` — pointing back at the clone.
- Sets `ZSH_THEME="inzsh"` in `.zshrc`. Your previous theme line is not deleted: it is
  commented out and tagged, so uninstall can put back exactly what was there.

```zsh
#ZSH_THEME="robbyrussell" # inzsh:disabled
ZSH_THEME="inzsh" # inzsh:managed
```

### What the plain path does

Appends one managed block to `${ZDOTDIR:-$HOME}/.zshrc` (creating the file if you have none):

```zsh
# >>> inzsh >>>
source '/path/to/your/clone/inzsh.zsh-theme'
# <<< inzsh <<<
```

### What the installer promises

- **Your `.zshrc` is backed up before the first edit** — to `.zshrc.inzsh.bak`, next to the
  original. That backup is your pre-inzsh state: later runs never overwrite it.
- **Running it again changes nothing.** Install over an install and every file, and the
  backup, is byte-for-byte what it was. Re-run it freely — after moving the clone, for
  instance, it repairs the link or the path and touches nothing else.
- **It only touches what it names.** The managed block, the tagged theme lines, the one
  symlink. Everything else in `.zshrc` is yours and stays yours.

## Uninstall

```zsh
zsh install.zsh --uninstall
```

Undoes both paths, whichever was used: the managed block comes out, the tagged theme lines go
back to what they were, the symlink is removed. `.zshrc` returns to its pre-install content.
The backup is deliberately left in place — delete `.zshrc.inzsh.bak` yourself once you are
sure, and delete the clone if you are done with it.

Uninstalling twice is uninstalling once; with nothing installed it says so and exits cleanly.

## Manual install

Prefer not to run an installer? Both paths are two lines by hand:

```zsh
# plain: source the entry point from .zshrc
source ~/.inzsh/inzsh.zsh-theme

# oh-my-zsh: link it as a custom theme, then set ZSH_THEME="inzsh"
ln -s ~/.inzsh/inzsh.zsh-theme "${ZSH_CUSTOM:-$ZSH/custom}/themes/inzsh.zsh-theme"
```

There is also a single-file build — the whole library concatenated in dependency order —
for installs where a clone is unwanted:

```zsh
make bundle    # writes dist/inzsh.zsh-theme; copy it anywhere and source it
```

## After installing

Every knob the theme reads is in the [configuration reference](configuration.md).
