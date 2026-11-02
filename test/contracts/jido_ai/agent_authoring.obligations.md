---
modules:
  - Jido.AI.Agent
  - Jido.AI.Agent.DSL
  - Jido.AI.Agent.Plugin
  - Jido.AI.Agent.Plugin.Reasoning
  - Jido.AI.Agent.Plugin.Tool
  - Jido.AI.Reasoning
---

## Purpose

Protect the public authoring surface for graph-first AI Agents. This component
owns the `ai` declarations, reasoning and tool normalization, the generated
request route, and the read-only `reasoning/0`, `explain/0`, and `preflight/1`
helpers. It does not own model execution, tool execution, or AgentServer work.

## Obligations

### jido_ai.agent_authoring.I1 — Canonical AI declaration

- **scope:** `use Jido.AI.Agent`, the `ai`, `reasoning`, and `tools` declarations
- **must:** Normalize one reasoning declaration and one ordered static tool list into one `jido.ai.request` Flow route and one Agent Plugin contribution.
- **kind:** functional
- **status:** active

### jido_ai.agent_authoring.I2 — Invalid authoring input is rejected

- **scope:** `Jido.AI.Agent.DSL`, `Jido.AI.Agent.Plugin`
- **must:** Reject missing or repeated reasoning declarations, repeated tools blocks, tools that are not Actions or Flows, unknown reasoning fields, and configuration that fails the selected Flow schema.
- **kind:** functional
- **status:** active

### jido_ai.agent_authoring.I3 — Route ownership stays explicit

- **scope:** `Jido.AI.Agent.Plugin`, generated Agent definitions
- **must:** Add exactly one AI request route whose direct executable is the selected reasoning Flow. Do not add a hidden runtime pipeline around that Flow.
- **kind:** functional
- **status:** active

### jido_ai.agent_authoring.I4 — Portable inspection and preflight

- **scope:** generated `reasoning/0`, `explain/0`, and `preflight/1`
- **must:** Return the selected Flow, defaults, schemas, and ordered tool modules without model execution. Preflight must validate request data and compile the Flow into a portable workflow or return an error.
- **kind:** functional
- **status:** active
