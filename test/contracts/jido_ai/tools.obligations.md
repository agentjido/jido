---
modules:
  - Jido.AI.Skill
  - Jido.AI.ToolResult
  - Jido.AI.ToolSource
  - Jido.AI.Toolset
---

## Purpose

Protect AI tool capability selection and result projection. This component
owns the static Action allowlist, trusted runtime sources, request-level
selection, tool argument validation, portable execution identity, and bounded
model-visible results. It does not own ReAct routing or approval waits.

## Obligations

### jido_ai.tools.I1 — Protected static allowlist

- **scope:** `Jido.AI.Toolset`
- **must:** Accept ordered Jido Action and Flow modules in an Agent definition and reject duplicate modules or model tool names.
- **kind:** security
- **status:** active

### jido_ai.tools.I2 — Trusted dynamic sources

- **scope:** `Jido.AI.ToolSource.load/1`, `run/3`
- **must:** Load dynamic tools only from the trusted `jido_ai_tool_sources` execution context. Validate the source behavior and keep request data unable to add a capability.
- **kind:** security
- **status:** active

### jido_ai.tools.I3 — Request policy only reduces capability

- **scope:** `Jido.AI.Toolset.select/2`
- **must:** Apply visible, hidden, review, and requirement policy only to known static or trusted dynamic tools. Reject unknown names and never create a new tool.
- **kind:** security
- **status:** active

### jido_ai.tools.I4 — Calls validate before execution

- **scope:** `Jido.AI.Toolset.resolve_call/2`, `validate_call/2`
- **must:** Resolve a call by exact model tool name and validate or coerce its arguments through the selected Action, Flow, or dynamic definition before execution.
- **kind:** functional
- **status:** active

### jido_ai.tools.I5 — Portable source and tool identity

- **scope:** dynamic source configuration, resolved execution data, tool observations
- **must:** Reject process-local or non-canonical source data. Store portable source execution data and a stable tool identity without storing executable callbacks in the graph.
- **kind:** persisted-format
- **status:** active

### jido_ai.tools.I6 — Bounded structured and content-part results

- **scope:** `Jido.AI.ToolResult`
- **must:** Keep local result data separate from bounded model content. Preserve valid ReqLLM content parts and result metadata, and replace oversized or invalid content with a safe portable result.
- **kind:** security
- **status:** active
