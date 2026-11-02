---
modules:
  - Jido.AI.Reasoning.ReAct
  - Jido.AI.Reasoning.ReAct.Actions.DecideNext
  - Jido.AI.Reasoning.ReAct.Actions.DetectToolCycle
  - Jido.AI.Reasoning.ReAct.Actions.ExecuteTool
  - Jido.AI.Reasoning.ReAct.Actions.ExpandNext
  - Jido.AI.Reasoning.ReAct.Actions.RecordToolResults
  - Jido.AI.Reasoning.ReAct.Actions.RequestToolReview
  - Jido.AI.Reasoning.ReAct.Actions.ResolveToolReview
  - Jido.AI.Reasoning.ReAct.ModelRound
  - Jido.AI.Reasoning.ReAct.ToolReview
---

## Purpose

Protect the standard ReAct graph. This component owns model-to-tool routing,
validated parallel tool execution, approval waits, repeated-call repair,
durable tool-attempt observations, and ReAct limits. It uses the shared turn,
model-execution, conversation, and tools components.

## Obligations

### jido_ai.react.I1 — Validated tool execution

- **scope:** `Jido.AI.Reasoning.ReAct.Actions.ExpandNext`, `ExecuteTool`
- **must:** Resolve every requested tool through the selected Toolset before execution. Execute only validated calls and return a safe tool error for an Action, Flow, or source failure.
- **kind:** functional
- **status:** active

### jido_ai.react.I2 — Deterministic parallel result order

- **scope:** ReAct tool-call Flow expansion and result recording
- **must:** Run one independent graph Action per tool call and append results in the model call order, independent of completion order.
- **kind:** ordering
- **status:** active

### jido_ai.react.I3 — Approval precedes reviewed execution

- **scope:** `Jido.AI.Reasoning.ReAct.ToolReview`, review Actions
- **must:** Suspend before a reviewed tool executes, accept only the matching wait decision, record the request and decision, and execute only after approval.
- **kind:** ordering
- **status:** active

### jido_ai.react.I4 — Durable resume does not duplicate work

- **scope:** ReAct Flow waits and durable AgentServer resume
- **must:** Resume the same saved graph after restart, retain the same review wait identity, and do not repeat completed model calls or tool attempts.
- **kind:** persisted-format
- **status:** active

### jido_ai.react.I5 — Repeated tool cycles request repair

- **scope:** `Jido.AI.Reasoning.ReAct.Actions.DetectToolCycle`
- **must:** Detect consecutive tool-call batches with the same names and arguments, ignore provider call IDs, count the cycle, and add one model repair instruction.
- **kind:** functional
- **status:** active

### jido_ai.react.I6 — One durable observation per tool attempt

- **scope:** `Jido.AI.Reasoning.ReAct.Actions.RecordToolResults`
- **must:** Append one versioned `ai_tool_attempt` record for each executed call with identity, input, status, bounded output, content parts, error, timing, effects count, round, and review state.
- **kind:** persisted-format
- **status:** active

### jido_ai.react.I7 — Tool limits stop new work

- **scope:** `Jido.AI.Reasoning.ReAct.Actions.DecideNext`
- **must:** Enforce configured tool-round and total tool-call limits before a new tool batch starts and return a stable blocked result when a limit is reached.
- **kind:** functional
- **status:** active
