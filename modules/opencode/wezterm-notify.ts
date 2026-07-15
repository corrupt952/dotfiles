import type { Plugin } from "@opencode-ai/plugin";
import { mkdirSync, renameSync, writeFileSync } from "fs";
import { basename, join } from "path";

const NOTIFY_ROOT = "/tmp/wezterm-notifications";

const WezTermNotify: Plugin = async () => {
  const paneId = process.env.WEZTERM_PANE;
  const socket = process.env.WEZTERM_UNIX_SOCKET;
  if (!paneId || !socket) return {};

  const notifyDir = join(NOTIFY_ROOT, basename(socket));
  const notifyPath = join(notifyDir, `${paneId}.json`);
  const temporaryPath = `${notifyPath}.${process.pid}.tmp`;

  mkdirSync(notifyDir, { recursive: true });

  const writeStatus = (status: string) => {
    writeFileSync(
      temporaryPath,
      JSON.stringify({ status, timestamp: Math.floor(Date.now() / 1000) }),
    );
    renameSync(temporaryPath, notifyPath);
  };

  writeStatus("initial");
  process.once("exit", () => writeStatus("idle"));

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.idle":
          writeStatus("done");
          break;
        case "session.error":
          writeStatus("error");
          break;
        case "permission.asked":
          writeStatus("waiting");
          break;
        case "permission.replied":
          writeStatus("initial");
          break;
        case "session.deleted":
          writeStatus("idle");
          break;
      }
    },
  };
};

export default WezTermNotify;
