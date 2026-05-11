#!/bin/bash
# Claude Code hook: Write status to /tmp/wezterm-notifications for WezTerm tab indicators
# Used by: SessionStart, Notification, Stop, StopFailure, SessionEnd
#
# Notification files are namespaced by basename of $WEZTERM_UNIX_SOCKET so
# concurrent wezterm-gui processes never collide on per-mux pane_id.
# This follows the wezterm official ExecDomain pattern:
# https://wezterm.org/config/lua/ExecDomain.html
set -euo pipefail

PANE_ID="${WEZTERM_PANE:-}"
SOCKET="${WEZTERM_UNIX_SOCKET:-}"
if [ -z "$PANE_ID" ] || [ -z "$SOCKET" ]; then
  exit 0
fi

NAMESPACE=$(basename "$SOCKET")

PAYLOAD=$(cat)
EVENT=$(echo "$PAYLOAD" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")

case "$EVENT" in
  SessionStart)  STATUS="initial" ;;
  Notification)  STATUS="waiting" ;;
  Stop)          STATUS="done"    ;;
  StopFailure)   STATUS="error"   ;;
  SessionEnd)    STATUS="idle"    ;;
  *)             exit 0           ;;
esac

NOTIFY_DIR="/tmp/wezterm-notifications/$NAMESPACE"
mkdir -p "$NOTIFY_DIR"
cat > "$NOTIFY_DIR/$PANE_ID.json" <<EOF
{"status":"$STATUS","timestamp":$(date +%s)}
EOF

exit 0
