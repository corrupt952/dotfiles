# dotfiles

[![CI](https://github.com/corrupt952/dotfiles/actions/workflows/ci.yaml/badge.svg)](https://github.com/corrupt952/dotfiles/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Personal macOS workstation configuration. [mise](https://mise.jdx.dev/) installs the tools, deploys the dotfiles and applies the macOS settings; [nix-darwin](https://github.com/nix-darwin/nix-darwin) and [home-manager](https://github.com/nix-community/home-manager) still provide Nix itself, nix-direnv and a few packages.

## Requirements

- macOS on Apple Silicon
- [1Password for Mac](https://1password.com/downloads/mac/), with **Settings > Developer > Integrate with 1Password CLI** enabled

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/corrupt952/dotfiles/main/install.sh | bash
```

To read the script before running it:

```sh
curl -fsSLo install.sh https://raw.githubusercontent.com/corrupt952/dotfiles/main/install.sh
less install.sh
bash install.sh
```

The script runs only once it has been downloaded in full. It:

1. Checks for 1Password for Mac and the Xcode Command Line Tools
2. Installs mise to `~/.local/bin/mise` and checks its Developer ID signature and notarization (and the installer's GPG signature when `gpg` is available)
3. Clones this repository to `~/Workspace/corrupt952/dotfiles` and links `~/.config/mise` to it
4. Writes the machine-local files (`machine-local/`, `config.local.toml`), both gitignored
5. Runs `mise bootstrap`: tools, dotfiles, plugin repositories, macOS settings
6. Installs Nix via [Lix](https://lix.systems/) and runs `darwin-rebuild switch`

Run `./install.sh` from the checkout to apply changes again.

## Machine-local settings

`config.local.toml` holds what differs per machine and stays out of git, such as the per-workspace Git identities and [sallyport](https://github.com/corrupt952/sallyport) files, as inline `[dotfiles]` entries:

```toml
[dotfiles]
"~/.config/git/profiles/example" = { content = '''
[user]
	email = "user@example.com"
	name = "Example User"
''' }
```

## Structure

```
install.sh          # bootstrap a new Mac, or re-apply on this one
config.toml         # global mise config: tools, env, dotfiles, bootstrap
mise.lock           # pinned versions, URLs and checksums
modules/            # files deployed by [dotfiles], grouped by tool
flake.nix           # nix-darwin + home-manager
darwin.nix          # Nix settings and the user
home-manager.nix    # the packages still taken from nixpkgs
```

## CI

Pushes run shellcheck, [jactionlint](https://github.com/jdx/jactionlint), [zizmor](https://zizmor.sh/) and [statix](https://github.com/oppiliappan/statix), plus the tests for the Claude Code bash guard and the mise lock check; see `.github/workflows/ci.yaml`.

## License

[MIT](./LICENSE)
