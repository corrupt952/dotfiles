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
  local branches="$1"
  local local_branches="$2"
  local remote_branches="$3"
  local branch local_mark remote_mark

  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue

    if has_branch "$branch" "$local_branches"; then
      local_mark='\033[0;32m✔\033[0m'
    else
      local_mark='\033[0;31m✗\033[0m'
    fi

    if has_branch "$branch" "$remote_branches"; then
      remote_mark='\033[0;32m✔\033[0m'
    else
      remote_mark='\033[0;31m✗\033[0m'
    fi

    printf '[l:%b, r:%b]\t%s\n' "$local_mark" "$remote_mark" "$branch"
  done <<< "$branches"
}

select_branch() {
  local local_branches remote_branches selectable_branches branch

  local_branches="$(fetch_local_branches)"
  remote_branches="$(fetch_remote_branches)"
  selectable_branches="$(
    printf '%s\n%s\n' "$local_branches" "$remote_branches" |
      grep -Fvx '' |
      sort -u || true
  )"

  # fzf evaluates the preview in its child shell.
  # shellcheck disable=SC2016
  branch="$(
    print_branch_list "$selectable_branches" "$local_branches" "$remote_branches" |
      fzf --ansi --exit-0 --nth 2 --delimiter $'\t' \
        --preview 'branch=$(printf "%s\n" {} | awk -F "\t" "{print \$2}"); git --no-pager log -20 --color=always "refs/heads/$branch" || git --no-pager log -20 --color=always "refs/remotes/origin/$branch"' 2>/dev/null |
      awk -F '\t' '{print $2}'
  )" || return 0

  [[ -n "$branch" ]] || return 0

  if has_branch "$branch" "$local_branches"; then
    git switch -- "$branch"
  elif has_branch "$branch" "$remote_branches"; then
    git switch --track -c "$branch" "origin/$branch"
  fi
}

print_help() {
  cat <<'EOF'
Usage: git-select-branch [options]

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
        printf 'git-select-branch: unknown option: %s\n' "$1" >&2
        return 2
        ;;
    esac
    shift
  done

  if [[ "$fetch" == true ]]; then
    git fetch --prune --all
  fi

  select_branch
}

main "$@"
