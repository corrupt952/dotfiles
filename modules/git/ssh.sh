op_ssh_key="${OP_SSH_KEY:-}"

if [[ -z "$op_ssh_key" ]]; then
  exec ssh "$@"
fi

if ! command -v op >/dev/null 2>&1; then
  printf 'git-ssh: OP_SSH_KEY is set but the 1Password CLI is unavailable\n' >&2
  exit 127
fi

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}"
cache_dir="$cache_root/ssh-pub"
cache_name="$(printf '%s' "$op_ssh_key" | tr '/ ' '__')"
cache_file="$cache_dir/$cache_name.pub"

mkdir -p -- "$cache_dir"

if [[ ! -s "$cache_file" ]]; then
  temporary_file="$(mktemp "$cache_dir/.git-ssh.XXXXXX")"
  trap 'rm -f -- "$temporary_file"' EXIT
  op read "op://$op_ssh_key/public key" > "$temporary_file"
  mv -- "$temporary_file" "$cache_file"
  trap - EXIT
fi

exec ssh -i "$cache_file" -o IdentitiesOnly=yes "$@"
