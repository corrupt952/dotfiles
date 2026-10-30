# dotfiles

[![CI](https://github.com/corrupt952/dotfiles/actions/workflows/ci.yaml/badge.svg)](https://github.com/corrupt952/dotfiles/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Personal macOS workstation configuration. [mise](https://mise.jdx.dev/) installs the tools, deploys the dotfiles and applies the macOS settings. [Lix](https://lix.systems/) is installed on its own for projects that ship a Nix dev shell, loaded through [nix-direnv](https://github.com/nix-community/nix-direnv).

## Requirements

- macOS on Apple Silicon
- [1Password for Mac](https://1password.com/downloads/mac/) for commit signing and SSH, with **Settings > Developer > Use the SSH Agent** and **Integrate with 1Password CLI** enabled. The install runs without it and warns at the end.

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

1. Checks for the Xcode Command Line Tools
2. Installs mise to `~/.local/bin/mise` and checks its Developer ID signature and notarization (and the installer's GPG signature when `gpg` is available)
3. Clones this repository to `~/Workspace/corrupt952/dotfiles` and links `~/.config/mise` to it
4. Writes an empty `mise.local.toml` (gitignored) for machine-local settings
5. Runs `mise bootstrap`: tools, dotfiles, plugin repositories, macOS settings, the Nix gc and optimise agents
6. Installs Lix if it is missing
7. Warns if 1Password for Mac is not installed

Run `./install.sh` from the checkout to apply changes again.

## Machine-local settings

`mise.local.toml` holds what differs per machine and stays out of git, such as the per-workspace Git identities and [sallyport](https://github.com/corrupt952/sallyport) files, as inline `[dotfiles]` entries:

```toml
[dotfiles]
"~/.config/git/profiles/example" = { content = '''
[user]
	email = "user@example.com"
	name = "Example User"
''' }
```

## Structure

```text
install.sh          # bootstrap a new Mac, or re-apply on this one
mise.toml           # global mise config: tools, env, dotfiles, bootstrap
mise.lock           # pinned versions, URLs and checksums
modules/            # files deployed by [dotfiles], grouped by tool
```

## CI

Pushes run shellcheck, [jactionlint](https://github.com/jdx/jactionlint), and [zizmor](https://zizmor.sh/), plus the tests for the Claude Code bash guard and the mise lock check; see `.github/workflows/ci.yaml`.

## License

[MIT](./LICENSE)
