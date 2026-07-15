set -o noclobber

fetch_local_branches() {
  git for-each-ref --format='%(refname:strip=2)' refs/heads
}

fetch_remote_branches() {
  git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin |
    grep -Fvx HEAD || true
}

has_branch() {
  local branch="$1"
  local branches="$2"
  grep -Fqx -- "$branch" <<< "$branches"
}

print_branch_list() {
  local local_branches="$1"
  local remote_branches="$2"
  local branch remote_mark

  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue

    if has_branch "$branch" "$remote_branches"; then
      remote_mark='\033[0;32m✔\033[0m'
    else
      remote_mark='\033[0;31m✗\033[0m'
    fi

    printf '[l:\033[0;32m✔\033[0m, r:%b]\t%s\n' "$remote_mark" "$branch"
  done <<< "$local_branches"
}

delete_branches() {
  local local_branches remote_branches branches branch

  local_branches="$(fetch_local_branches)"
  remote_branches="$(fetch_remote_branches)"

  # fzf evaluates the preview in its child shell.
  # shellcheck disable=SC2016
  branches="$(
    print_branch_list "$local_branches" "$remote_branches" |
      fzf --ansi --exit-0 --multi --nth 2 --delimiter $'\t' \
        --preview 'branch=$(printf "%s\n" {} | awk -F "\t" "{print \$2}"); git --no-pager log -20 --color=always "refs/heads/$branch" || git --no-pager log -20 --color=always "refs/remotes/origin/$branch"' 2>/dev/null |
      awk -F '\t' '{print $2}'
  )" || return 0

  [[ -n "$branches" ]] || return 0

  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    git branch -D -- "$branch"
  done <<< "$branches"
}

print_help() {
  cat <<'EOF'
Usage: git-delete-branch [options]

Options:
  -n, --no-fetch Do not fetch remote branches
  -h, --help     Show this help
EOF
}

main() {
  local fetch=true

  while (( $# > 0 )); do
    case "$1" in
      -n | --no-fetch)
        fetch=false
        ;;
      -h | --help)
        print_help
        return
        ;;
      *)
        printf 'git-delete-branch: unknown option: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done

  if [[ "$fetch" == true ]]; then
    git fetch --prune --all
  fi

  delete_branches
}

main "$@"
