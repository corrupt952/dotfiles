#!/bin/bash
# Claude Code hook: Write status to /tmp/wezterm-notifications for WezTerm tab indicators
# Used by: SessionStart, Notification, Stop, StopFailure, SessionEnd
set -euo pipefail

PANE_ID="${WEZTERM_PANE:-}"
if [ -z "$PANE_ID" ]; then
  exit 0
fi

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

NOTIFY_DIR="/tmp/wezterm-notifications"
mkdir -p "$NOTIFY_DIR"
cat > "$NOTIFY_DIR/$PANE_ID.json" <<EOF
{"status":"$STATUS","timestamp":$(date +%s)}
EOF

exit 0
