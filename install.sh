#!/usr/bin/env bash

set -Ceuo pipefail

readonly DOTFILES_REPO="https://github.com/corrupt952/dotfiles.git"
readonly MISE_BIN="$HOME/.local/bin/mise"
readonly MISE_TEAM_ID="4993Y37DX6"
readonly MISE_RELEASE_KEY="24853EC9F655CE80B48E6C3A8B81C9D17413A06D"
readonly MISE_MINIMUM_RELEASE_AGE="3d"

if [[ -f "${BASH_SOURCE[0]:-}" ]]; then
  DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
else
  DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Workspace/corrupt952/dotfiles}"
fi
readonly DOTFILES_DIR
readonly MISE_LOCAL_CONFIG="$DOTFILES_DIR/mise.local.toml"

require_1password_app() {
  if [[ -d /Applications/1Password.app ]]; then
    return
  fi

  cat >&2 <<'EOF'
1Password for Mac is required before running this setup.
Install the app and enable Settings > Developer > Integrate with 1Password CLI.
The `op` executable itself is managed by mise. Then run this script again.
https://1password.com/downloads/mac/
EOF
  exit 1
}

require_command_line_tools() {
  if /usr/bin/xcode-select -p >/dev/null 2>&1; then
    return
  fi

  /usr/bin/xcode-select --install || true
  echo "Finish installing the Command Line Tools, then run this script again." >&2
  exit 1
}

verify_mise() {
  local team_id

  if ! /usr/bin/codesign --verify --strict "$MISE_BIN" 2>/dev/null; then
    echo "$MISE_BIN has no valid code signature." >&2
    return 1
  fi

  team_id="$(/usr/bin/codesign -dv "$MISE_BIN" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')"
  if [[ "$team_id" != "$MISE_TEAM_ID" ]]; then
    echo "$MISE_BIN is signed by team '$team_id', expected $MISE_TEAM_ID." >&2
    return 1
  fi

  if ! /usr/sbin/spctl --assess --type install "$MISE_BIN" 2>/dev/null; then
    echo "$MISE_BIN is not notarized." >&2
    return 1
  fi
}

download_mise_installer() {
  local work_dir="$1"

  if ! command -v gpg >/dev/null 2>&1; then
    /usr/bin/curl --proto '=https' --tlsv1.2 -fsSL https://mise.run -o "$work_dir/install.sh"
    return
  fi

  /usr/bin/curl --proto '=https' --tlsv1.2 -fsSL https://mise.jdx.dev/install.sh.sig -o "$work_dir/install.sh.sig"
  /usr/bin/curl --proto '=https' --tlsv1.2 -fsSL \
    "https://keys.openpgp.org/vks/v1/by-fingerprint/$MISE_RELEASE_KEY" -o "$work_dir/release.asc"
  /bin/mkdir -m 700 "$work_dir/gnupg"
  GNUPGHOME="$work_dir/gnupg" gpg --batch --quiet --import "$work_dir/release.asc"
  if ! GNUPGHOME="$work_dir/gnupg" gpg --batch --status-fd 1 \
    --output "$work_dir/install.sh" --decrypt "$work_dir/install.sh.sig" 2>/dev/null \
    | /usr/bin/grep -q "^\[GNUPG:\] VALIDSIG .*$MISE_RELEASE_KEY"; then
    echo "The mise installer is not signed by the mise release key." >&2
    exit 1
  fi
}

install_mise() {
  local work_dir

  if [[ -x "$MISE_BIN" ]]; then
    if verify_mise; then
      return
    fi
    exit 1
  fi

  work_dir="$(/usr/bin/mktemp -d)"
  download_mise_installer "$work_dir"
  MISE_INSTALL_PATH="$MISE_BIN" \
    MISE_SELF_UPDATE_MINIMUM_RELEASE_AGE="$MISE_MINIMUM_RELEASE_AGE" \
    MISE_INSTALL_HELP=0 \
    /bin/sh "$work_dir/install.sh"
  /bin/rm -r -- "$work_dir"

  if ! verify_mise; then
    /bin/rm -- "$MISE_BIN"
    exit 1
  fi
}

clone_dotfiles() {
  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    return
  fi

  if [[ -e "$DOTFILES_DIR" ]]; then
    echo "$DOTFILES_DIR exists but is not a git checkout." >&2
    exit 1
  fi

  /bin/mkdir -p "$(dirname -- "$DOTFILES_DIR")"
  /usr/bin/git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
}

write_local_config() {
  if [[ -e "$MISE_LOCAL_CONFIG" ]]; then
    return
  fi

  printf '[dotfiles]\n' > "$MISE_LOCAL_CONFIG"
  /bin/chmod 600 "$MISE_LOCAL_CONFIG"
}

link_mise_config() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mise"

  if [[ -L "$config_dir" && "$(/usr/bin/readlink "$config_dir")" == "$DOTFILES_DIR" ]]; then
    return
  fi

  if [[ -d "$config_dir" && ! -L "$config_dir" ]]; then
    if ! /bin/rmdir "$config_dir" 2>/dev/null; then
      echo "$config_dir is not empty. Move it aside and run this script again." >&2
      exit 1
    fi
  elif [[ -e "$config_dir" || -L "$config_dir" ]]; then
    echo "$config_dir already exists. Move it aside and run this script again." >&2
    exit 1
  fi

  /bin/mkdir -p "$(dirname -- "$config_dir")"
  /bin/ln -s "$DOTFILES_DIR" "$config_dir"
}

install_nix() {
  if [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
    return
  fi

  /usr/bin/curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    https://install.lix.systems/lix \
    | /bin/sh -s -- install
}

main() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This setup currently supports macOS only." >&2
    exit 1
  fi

  if (( $# > 0 )); then
    echo "Usage: install.sh" >&2
    exit 1
  fi

  require_1password_app
  require_command_line_tools
  install_mise
  clone_dotfiles
  write_local_config
  link_mise_config
  "$MISE_BIN" bootstrap --yes
  install_nix
}

main "$@"
