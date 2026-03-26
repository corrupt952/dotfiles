#!/bin/bash
# Claude Code hook: Notify WezTerm via OSC 1337 user variable
# Used by: Notification, Stop hooks
set -euo pipefail

PANE_ID="${WEZTERM_PANE:-}"

# No pane ID means not running in WezTerm
if [ -z "$PANE_ID" ]; then
  exit 0
fi

# Read hook payload from stdin
PAYLOAD=$(cat)
EVENT=$(echo "$PAYLOAD" | jq -r '.hook_event_name // "unknown"' 2>/dev/null || echo "unknown")

# Determine status based on event type
case "$EVENT" in
  Notification)
    STATUS="waiting"
    ;;
  Stop)
    STATUS="done"
    ;;
  *)
    STATUS="unknown"
    ;;
esac

# Write notification file for WezTerm to pick up
NOTIFY_DIR="/tmp/wezterm-notifications"
mkdir -p "$NOTIFY_DIR"
cat > "$NOTIFY_DIR/$PANE_ID.json" <<EOF
{"status":"$STATUS","timestamp":$(date +%s)}
EOF

exit 0
