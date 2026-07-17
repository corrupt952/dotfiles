#!/usr/bin/env bash

set -Ceuo pipefail

readonly CONFIG_NAME="workstation"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly MACHINE_LOCAL_DIR="$SCRIPT_DIR/machine-local"
readonly MACHINE_IDENTITIES_FILE="$MACHINE_LOCAL_DIR/identities.nix"
readonly NIX_FEATURES="nix-command flakes"
readonly NIX_DARWIN="github:nix-darwin/nix-darwin/nix-darwin-26.05"

require_1password_app() {
  if [[ -d /Applications/1Password.app ]]; then
    return
  fi

  cat >&2 <<'EOF'
1Password for Mac is required before running this setup.
Install the app and enable Settings > Developer > Integrate with 1Password CLI.
The `op` executable itself is managed by Nix. Then run this script again.
https://1password.com/downloads/mac/
EOF
  exit 1
}

verify_1password_cli() {
  local op_bin="/etc/profiles/per-user/$1/bin/op"

  if [[ ! -x "$op_bin" ]]; then
    echo "Nix activation completed, but the 1Password CLI was not installed at $op_bin." >&2
    exit 1
  fi

  "$op_bin" --version >/dev/null
}

write_machine_identity() {
  local target_user="$1"
  local target_home

  if ! /usr/bin/id "$target_user" >/dev/null 2>&1; then
    echo "macOS user '$target_user' does not exist." >&2
    exit 1
  fi

  target_home="$(resolve_home_directory "$target_user")"
  if [[ -z "$target_home" || "$target_home" != /* ]]; then
    echo "Could not resolve an absolute home directory for '$target_user'." >&2
    exit 1
  fi

  /bin/mkdir -p "$MACHINE_LOCAL_DIR"
  /bin/chmod 700 "$MACHINE_LOCAL_DIR"
  printf '%s\n' "$target_user" >| "$MACHINE_LOCAL_DIR/username"
  printf '%s\n' "$target_home" >| "$MACHINE_LOCAL_DIR/home-directory"

  if [[ ! -e "$MACHINE_IDENTITIES_FILE" ]]; then
    cat > "$MACHINE_IDENTITIES_FILE" <<'EOF'
{
  corrupt952 = { };
  labee = { };

  # example = {
  #   directory = "example";
  #   git = {
  #     name = "Example User";
  #     email = "user@example.com";
  #     signingKey = null;
  #   };
  #   sallyport = {
  #     expand = false;
  #     env = { };
  #   };
  # };
}
EOF
  fi

  /bin/chmod 600 \
    "$MACHINE_LOCAL_DIR/username" \
    "$MACHINE_LOCAL_DIR/home-directory" \
    "$MACHINE_IDENTITIES_FILE"
}

resolve_home_directory() {
  local account_record
  local home_directory
  local passwd_record

  if account_record="$(
    /usr/bin/dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null
  )"; then
    home_directory="${account_record#NFSHomeDirectory:}"
    home_directory="${home_directory#"${home_directory%%[![:space:]]*}"}"
    printf '%s\n' "$home_directory"
    return
  fi

  # Directory Services can transiently reject dscl in restricted environments.
  if account_record="$(/usr/bin/dscacheutil -q user -a name "$1" 2>/dev/null)"; then
    home_directory="$(
      printf '%s\n' "$account_record" \
        | /usr/bin/sed -n -E 's/^dir:[[:space:]]*//p'
    )"
    if [[ -n "$home_directory" ]]; then
      printf '%s\n' "$home_directory"
      return
    fi
  fi

  # `id -P` reads the same account database in passwd(5) format on macOS.
  if passwd_record="$(/usr/bin/id -P "$1" 2>/dev/null)"; then
    printf '%s\n' "$passwd_record" | /usr/bin/awk -F: '{ print $(NF - 1) }'
  fi
}

load_nix_environment() {
  if command -v nix >/dev/null 2>&1; then
    return
  fi

  local profile
  for profile in \
    /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
    "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
    if [[ -r "$profile" ]]; then
      # Lix's profile script currently reads ZSH_VERSION without a default.
      # Do not leak this script's nounset option into external shell code.
      set +u
      # shellcheck source=/dev/null
      source "$profile"
      set -u
      break
    fi
  done
}

install_nix() {
  load_nix_environment

  if command -v nix >/dev/null 2>&1; then
    return
  fi

  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    https://install.lix.systems/lix \
    | sh -s -- install

  load_nix_environment
}

main() {
  local nix_bin
  local target_user

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This setup currently supports macOS only." >&2
    exit 1
  fi

  if (( $# > 1 )); then
    echo "Usage: $0 [username]" >&2
    exit 1
  fi

  target_user="${1:-$(id -un)}"
  require_1password_app
  write_machine_identity "$target_user"

  install_nix

  if ! command -v nix >/dev/null 2>&1; then
    echo "Nix was installed but is not available in this shell." >&2
    echo "Open a new shell and run this script again." >&2
    exit 1
  fi

  nix_bin="$(command -v nix)"

  sudo -H "$nix_bin" \
    --extra-experimental-features "$NIX_FEATURES" \
    run "$NIX_DARWIN#darwin-rebuild" -- \
    switch --flake "path:$SCRIPT_DIR#$CONFIG_NAME"

  verify_1password_cli "$target_user"
}

main "$@"
