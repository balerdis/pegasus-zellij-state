import assert from "node:assert/strict"
import test from "node:test"
import { createEventProcessor } from "../adapters/opencode/pegasus-zellij-state.ts"

function event(type, properties = {}) {
  return { type, properties }
}

test("a known root working-to-idle identifies orchestrator-idle", () => {
  const reports = []
  const processEvent = createEventProcessor((state) => reports.push(state))

  processEvent(event("session.created", { info: { id: "root" } }))
  processEvent(event("session.status", { sessionID: "root", status: { type: "working" } }))
  processEvent(event("session.status", { sessionID: "root", status: { type: "idle" } }))
  processEvent(event("session.status", { sessionID: "root", status: { type: "idle" } }))

  assert.deepEqual(reports, ["working", "orchestrator-idle", "orchestrator-idle"])
})

test("a subagent and an unknown session report normal idle", () => {
  const reports = []
  const processEvent = createEventProcessor((state) => reports.push(state))

  processEvent(event("session.created", { info: { id: "subagent", parentID: "root" } }))
  processEvent(event("session.status", { sessionID: "subagent", status: { type: "working" } }))
  processEvent(event("session.status", { sessionID: "subagent", status: { type: "idle" } }))
  processEvent(event("session.status", { sessionID: "unknown", status: { type: "idle" } }))

  assert.deepEqual(reports, ["working", "idle", "idle"])
})
