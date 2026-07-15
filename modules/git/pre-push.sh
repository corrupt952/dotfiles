input_file="$(mktemp)"
trap 'rm -f -- "$input_file"' EXIT
cat > "$input_file"

is_allowed() {
  [[ "${1:-}" =~ ^(y|yes)$ ]]
}

is_zero_oid() {
  [[ "$1" =~ ^0+$ ]]
}

while read -r _local_ref local_oid remote_ref remote_oid; do
  case "$remote_ref" in
    refs/heads/main | refs/heads/master)
      if ! is_allowed "${GIT_ALLOW_PUSH_MAIN_BRANCH:-}"; then
        printf "Don't push default branch!!! (master or main)\nSet 'GIT_ALLOW_PUSH_MAIN_BRANCH'\n" >&2
        exit 1
      fi
      ;;
  esac

  if is_allowed "${GIT_ALLOW_FORCE_PUSH:-}" ||
    is_zero_oid "$local_oid" ||
    is_zero_oid "$remote_oid"; then
    continue
  fi

  if ! git merge-base --is-ancestor "$remote_oid" "$local_oid"; then
    printf "Don't force push!!!\nSet 'GIT_ALLOW_FORCE_PUSH'\n" >&2
    exit 1
  fi
done < "$input_file"

git-lfs pre-push "$@" < "$input_file"
