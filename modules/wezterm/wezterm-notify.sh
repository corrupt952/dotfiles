#!@bash@

set -Ceuo pipefail

pane_id="${WEZTERM_PANE:-}"
socket="${WEZTERM_UNIX_SOCKET:-}"
if [[ -z "$pane_id" || -z "$socket" ]]; then
  exit 0
fi

# The id goes into SQL unquoted, so refuse anything that is not a plain number.
if [[ ! "$pane_id" =~ ^[0-9]+$ ]]; then
  exit 0
fi

# Manual/interactive invocation with no piped input would otherwise block
# forever waiting for stdin EOF.
if [[ -t 0 ]]; then
  exit 0
fi

# Read with a bounded timeout: a known Claude Code client bug intermittently
# leaves the hook's stdin pipe open (never sends EOF), which would otherwise
# block this read forever and freeze the whole session
# (https://github.com/anthropics/claude-code/issues/78756).
payload=""
IFS= read -r -t 0.5 -d '' payload || true
event="$(
  printf '%s' "$payload" | @jq@ -r '.hook_event_name // "unknown"' 2>/dev/null ||
    printf 'unknown'
)"

case "$event" in
  SessionStart | UserPromptSubmit) status="initial" ;;
  Notification | PermissionRequest | Elicitation) status="waiting" ;;
  SubagentStop | Stop) status="done" ;;
  StopFailure) status="error" ;;
  SessionEnd) status="idle" ;;
  *) exit 0 ;;
esac

namespace="${socket##*/}"
notify_root="/tmp/wezterm-notifications"
db="$notify_root/$namespace.db"

@mkdir@ -p -- "$notify_root"

# Nanosecond epoch as this event's ordering key. Concurrent hooks for the same
# pane (parallel subagents, delayed scheduling) can finish out of order, so the
# upsert below refuses to apply an event older than the row already there.
event_ns="$(@date@ +%s%N)"
now="$(@date@ +%s)"

# One row per pane, and the upsert touches only that row. Serialising writers
# is sqlite's job here: WAL plus a busy timeout replaces the mkdir lock, the
# temp-file rename, and the read-compare-write this script used to do by hand.
# read_ns is deliberately absent from the SET list, so a new event keeps the
# pane's read marker and reads as unread by being newer than it.
# The PRAGMAs echo their result, and this hook's stdout belongs to the client
# that invoked it.
@sqlite3@ "$db" > /dev/null <<SQL
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=3000;
CREATE TABLE IF NOT EXISTS notifications (
  pane_id INTEGER PRIMARY KEY,
  status TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  event_ns INTEGER NOT NULL,
  read_ns INTEGER NOT NULL DEFAULT 0
);
INSERT INTO notifications (pane_id, status, updated_at, event_ns, read_ns)
VALUES ($pane_id, '$status', $now, $event_ns, 0)
ON CONFLICT(pane_id) DO UPDATE SET
  status = excluded.status,
  updated_at = excluded.updated_at,
  event_ns = excluded.event_ns
WHERE excluded.event_ns >= notifications.event_ns;
SQL
