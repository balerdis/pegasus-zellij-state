import type { Plugin } from "@opencode-ai/plugin"
import { spawn } from "node:child_process"
import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const REPORT_SCRIPT = join(homedir(), ".config", "pegasus-zellij-state", "scripts", "agent-report.sh")
const ACTIVE_STATUS = new Set(["active", "busy", "pending", "running", "streaming", "working", "retry"])

function inZellij() {
  return Boolean(process.env.ZELLIJ_PANE_ID || process.env.ZELLIJ)
}

function paneId() {
  return process.env.ZELLIJ_PANE_ID || "current"
}

function report(state: "working" | "blocked" | "idle", message = "") {
  if (!inZellij()) return
  if (!existsSync(REPORT_SCRIPT)) return

  const child = spawn(REPORT_SCRIPT, [paneId(), state, message], {
    detached: true,
    stdio: "ignore",
    env: process.env,
  })

  child.unref()
}

function statusType(status: unknown) {
  if (!status) return ""
  if (typeof status === "string") return status
  if (typeof status === "object" && status !== null && "type" in status && typeof status.type === "string") {
    return status.type
  }
  return ""
}

function stateForEvent(event: any): "working" | "blocked" | "idle" | undefined {
  const type = event?.type || ""

  if (type === "session.status") {
    const current = statusType(event?.properties?.status)
    if (current === "idle") return "idle"
    if (ACTIVE_STATUS.has(current)) return "working"
    return undefined
  }

  if (type === "permission.asked" || type === "question.asked") return "blocked"
  if (type === "session.idle" || type === "session.deleted") return "idle"

  if (
    type === "permission.replied" ||
    type === "question.replied" ||
    type === "question.rejected" ||
    type === "session.compacted"
  ) {
    return "working"
  }

  return undefined
}

function eventMessage(event: any) {
  const type = event?.type || "opencode"
  const status = statusType(event?.properties?.status)
  return status ? `${type}:${status}` : type
}

const PegasusZellijStatePlugin: Plugin = async () => {
  return {
    event: async ({ event }: any) => {
      const state = stateForEvent(event)
      if (state) report(state, eventMessage(event))
    },

    "chat.message": async () => {
      report("working", "chat.message")
    },

    "tool.execute.before": async ({ tool }: any) => {
      report("working", tool ? `tool.execute.before:${tool}` : "tool.execute.before")
    },

    "tool.execute.after": async ({ tool }: any) => {
      report("working", tool ? `tool.execute.after:${tool}` : "tool.execute.after")
    },

    "permission.ask": async () => {
      report("blocked", "permission.asked")
    },
  }
}

export default PegasusZellijStatePlugin
