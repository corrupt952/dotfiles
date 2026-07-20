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
lock_dir="$notify_path.lock"

@mkdir@ -p -- "$notify_dir"

# Nanosecond epoch as this event's ordering key. Concurrent hooks for the same
# pane (parallel subagents, delayed jq/mkdir scheduling) can finish out of
# order, so writes are serialized under a lock and an older event's write is
# skipped rather than clobbering a newer one.
event_ns="$(@date@ +%s%N)"

attempts=0
while ! @mkdir@ -- "$lock_dir" 2>/dev/null; do
  attempts=$((attempts + 1))
  if ((attempts > 1000)); then
    # Previous holder crashed without cleaning up; break the stale lock.
    rmdir -- "$lock_dir" 2>/dev/null || true
    attempts=0
  fi
  sleep 0.005
done
trap 'rmdir -- "$lock_dir" 2>/dev/null || true' EXIT

current_ns=0
if [[ -f "$notify_path" ]]; then
  current_ns="$(@jq@ -r '.timestamp_ns // 0' "$notify_path" 2>/dev/null || printf 0)"
fi

if ((event_ns > current_ns)); then
  temporary_path="$notify_path.$$.tmp"
  printf '{"status":"%s","timestamp_ns":%s}\n' "$status" "$event_ns" > "$temporary_path"
  @mv@ -- "$temporary_path" "$notify_path"
fi
