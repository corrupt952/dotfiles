import type { Plugin } from "@opencode-ai/plugin"
import { mkdirSync, writeFileSync } from "fs"
import { join } from "path"

const NOTIFY_DIR = "/tmp/wezterm-notifications"

const WezTermNotify: Plugin = async () => {
  const paneId = process.env.WEZTERM_PANE
  if (!paneId) return {}

  mkdirSync(NOTIFY_DIR, { recursive: true })

  const notifyPath = join(NOTIFY_DIR, `${paneId}.json`)

  const writeStatus = (status: string) => {
    writeFileSync(
      notifyPath,
      JSON.stringify({ status, timestamp: Math.floor(Date.now() / 1000) }),
    )
  }

  writeStatus("initial")

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.idle":
          writeStatus("done")
          break
        case "session.error":
          writeStatus("error")
          break
        case "permission.asked":
          writeStatus("waiting")
          break
        case "server.instance.disposed":
          writeStatus("idle")
          break
      }
    },
  }
}

export default WezTermNotify
