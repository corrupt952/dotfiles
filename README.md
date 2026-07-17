# dotfiles

[![lint](https://github.com/corrupt952/dotfiles/actions/workflows/lint.yaml/badge.svg)](https://github.com/corrupt952/dotfiles/actions/workflows/lint.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Personal macOS workstation configuration, declared as a Nix flake and applied with [nix-darwin](https://github.com/nix-darwin/nix-darwin) + [home-manager](https://github.com/nix-community/home-manager).

## Requirements

- macOS (this configuration only supports `aarch64-darwin`)
- [1Password for Mac](https://1password.com/downloads/mac/), with **Settings > Developer > Integrate with 1Password CLI** enabled

Everything else, including Nix itself, is installed by `setup.sh`.

## Setup

```sh
./setup.sh [username]
```

`username` defaults to the current macOS user. The script:

1. Verifies 1Password for Mac is installed
2. Writes machine-local identity files under `machine-local/` (gitignored)
3. Installs Nix via [Lix](https://lix.systems/) if it isn't already present
4. Runs `darwin-rebuild switch` against this flake

Re-run `./setup.sh` any time to reapply the configuration after editing it.

## What's managed

- **macOS defaults** (`darwin.nix`) — Dock, Finder, trackpad, menu bar clock, Touch ID for `sudo`, scheduled Nix GC/store optimisation
- **Shell & tools** (`modules/`) — zsh, tmux, WezTerm, git (aliases, delta, per-workspace identities), fzf/ripgrep/direnv, Ruby, opencode, and Claude Code settings/hooks
- **Workspace identities** (`modules/workspaces`) — per-directory Git identity and [sallyport](https://github.com/corrupt952/sallyport)-managed environment variables, driven by `machine-local/identities.nix`
- A few of my own tools, pulled in as flake inputs: [xckit](https://github.com/corrupt952/xckit), [closest](https://github.com/corrupt952/closest), [tmuxist](https://github.com/corrupt952/tmuxist), [sallyport](https://github.com/corrupt952/sallyport)

## Structure

```
flake.nix           # inputs (nixpkgs, nix-darwin, home-manager, ...) and outputs
darwin.nix          # system-level (nix-darwin) configuration
home-manager.nix    # top-level home-manager configuration
modules/            # one directory per home-manager module
machine-local/      # gitignored; machine-specific identity, created by setup.sh
```

## CI

Pushes are linted with [shellcheck](https://www.shellcheck.net/), [actionlint](https://github.com/rhysd/actionlint), [zizmor](https://zizmor.sh/), and [statix](https://github.com/oppiliappan/statix) — see `.github/workflows/lint.yaml`.

## License

[MIT](./LICENSE)
