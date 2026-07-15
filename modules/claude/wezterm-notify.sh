#!@bash@

set -Ceuo pipefail

pane_id="${WEZTERM_PANE:-}"
socket="${WEZTERM_UNIX_SOCKET:-}"
if [[ -z "$pane_id" || -z "$socket" ]]; then
  exit 0
fi

payload="$(</dev/stdin)"
event="$(
  printf '%s' "$payload" | @jq@ -r '.hook_event_name // "unknown"' 2>/dev/null ||
    printf 'unknown'
)"

case "$event" in
  SessionStart) status="initial" ;;
  Notification | PermissionRequest | Elicitation) status="waiting" ;;
  SubagentStop | Stop) status="done" ;;
  StopFailure) status="error" ;;
  SessionEnd) status="idle" ;;
  *) exit 0 ;;
esac

namespace="${socket##*/}"
notify_dir="/tmp/wezterm-notifications/$namespace"
notify_path="$notify_dir/$pane_id.json"
temporary_path="$notify_path.$$.tmp"

@mkdir@ -p -- "$notify_dir"
printf '{"status":"%s","timestamp":%s}\n' "$status" "$(@date@ +%s)" > "$temporary_path"
@mv@ -- "$temporary_path" "$notify_path"
