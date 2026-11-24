---
modules:
  - Jido.AI.Reasoning.ReAct
  - Jido.AI.Reasoning.ReAct.Guards
  - Jido.AI.Reasoning.ReAct.Actions.Advance
  - Jido.AI.Reasoning.ReAct.Actions.Initialize
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

### jido_ai.react.I4 — Durable resume uses saved checkpoints

- **scope:** ReAct Flow waits and durable AgentServer resume
- **must:** Resume the same saved graph and Turn after restart. Retain the same review wait identity. If the ReAct Iterate has no saved result, resume from the start of that component. Reuse a confirmed tool receipt at the same run, tool round, and position when the validated call matches, even if its provider call ID changes. Reject a changed call at an existing position. A lost process can repeat work that had no confirmed receipt.
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

### jido_ai.react.I8 — Provider options have no hidden generation limits

- **scope:** `Jido.AI.Reasoning.ReAct`
- **must:** Keep omitted provider options empty. Preserve a supplied partial options Map without adding a hidden token, timeout, or temperature value. Runtime budgets remain separate from provider generation options.
- **kind:** functional
- **status:** active

### jido_ai.react.I9 — Terminal loop state carries one Turn

- **scope:** ReAct loop initialization, completion, and review
- **must:** Keep the Turn in the terminal decision and omit the redundant top-level Turn. Preserve the Session, outcome, and effects used by the continuation.
- **kind:** functional
- **status:** active

### jido_ai.react.I10 — Agent guard Actions apply through durable resume

- **scope:** `Jido.AI.Reasoning.ReAct.Guards` and stock ReAct
- **must:** Apply an Agent input guard before model work and an Agent output guard before saving or publishing final reply content. Retain both targets across a tool-review wait. Send progress without provider chunks when there is an output guard. Dispatch approved output after the hosted Agent commits. Exclude rejected reply content from the committed Session.
- **kind:** ordering
- **status:** active
