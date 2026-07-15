if ! command -v kubectl >/dev/null 2>&1; then
  exit 0
fi

if ! context="$(kubectl config current-context 2>/dev/null)" || [[ -z "$context" ]]; then
  exit 0
fi

namespace="$(
  kubectl config view \
    -o "jsonpath={.contexts[?(@.name==\"${context}\")].context.namespace}" \
    2>/dev/null
)" || namespace=""

[[ -n "$namespace" ]] || namespace="default"
context="${context##*/}"

printf '(%s/%s)' "$context" "$namespace"
