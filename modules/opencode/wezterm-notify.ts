import type { Plugin } from "@opencode-ai/plugin";
import { spawnSync } from "child_process";

// The shared hook owns the storage format (sqlite under
// /tmp/wezterm-notifications), so this plugin only translates opencode's event
// names into the hook event names claude and codex already send.
const NOTIFY_HOOK = "@weztermNotifyHook@";

const HOOK_EVENTS: Record<string, string> = {
  "session.idle": "Stop",
  "session.error": "StopFailure",
  "permission.asked": "PermissionRequest",
  "permission.replied": "UserPromptSubmit",
  "session.deleted": "SessionEnd",
};

// Synchronous because the process-exit handler below has no chance to await,
// and the hook is a single sqlite upsert.
const notify = (hookEventName: string) => {
  try {
    spawnSync(NOTIFY_HOOK, {
      input: JSON.stringify({ hook_event_name: hookEventName }),
      stdio: ["pipe", "ignore", "ignore"],
      timeout: 3000,
    });
  } catch {
    // A missing or failing hook must never take opencode down with it.
  }
};

const WezTermNotify: Plugin = async () => {
  if (!process.env.WEZTERM_PANE || !process.env.WEZTERM_UNIX_SOCKET) return {};

  notify("SessionStart");
  process.once("exit", () => notify("SessionEnd"));

  return {
    event: async ({ event }) => {
      const hookEventName = HOOK_EVENTS[event.type];
      if (hookEventName) notify(hookEventName);
    },
  };
};

export default WezTermNotify;
