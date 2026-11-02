---
modules:
  - Jido.AI.Reasoning.Actions.DecideInput
  - Jido.AI.Reasoning.Actions.FinalizeTurn
  - Jido.AI.Reasoning.Actions.GuardInput
  - Jido.AI.Reasoning.Actions.GuardOutput
  - Jido.AI.Reasoning.Actions.ProjectConversation
  - Jido.AI.Reasoning.Actions.RecordModelAttempt
  - Jido.AI.Reasoning.Actions.StartRequest
  - Jido.AI.Reasoning.Result
---

## Purpose

Protect the shared request-turn contract used by all reasoning graphs. This
component owns request initialization, basic guards, model-attempt records,
terminal result values, the response envelope, and the versioned request
outcome observation. It does not own strategy-specific routing.

## Obligations

### jido_ai.turn.I1 — One terminal request outcome

- **scope:** `Jido.AI.Reasoning.Actions.FinalizeTurn`
- **must:** Append exactly one `ai_request_outcome` entry for a terminal request and return the Session that contains it.
- **kind:** ordering
- **status:** active

### jido_ai.turn.I2 — Common response shape

- **scope:** `Jido.AI.Reasoning.Result`, final response data
- **must:** Return completed, blocked, and failed results with stable status, output, reason code, reason, reasoning, request identity, usage, budgets, and attempt summaries.
- **kind:** functional
- **status:** active

### jido_ai.turn.I3 — Model attempts are observations

- **scope:** `Jido.AI.Reasoning.Actions.RecordModelAttempt`
- **must:** Append one versioned model-attempt observation per provider attempt and keep that observation outside projected conversation messages.
- **kind:** persisted-format
- **status:** active

### jido_ai.turn.I4 — Unsuccessful requests do not enter later context

- **scope:** input and output guards, finalization, conversation projection
- **must:** Keep blocked and failed request data available for inspection while excluding their user, assistant, and tool messages from later model context.
- **kind:** security
- **status:** active

### jido_ai.turn.I5 — Stable versioned outcome fields

- **scope:** `ai_request_outcome` payloads
- **must:** Use version 1 portable fields for flow identity, status, output, reasons, timing, model and tool counts, retries, budgets, reasoning-step count, and usage across all core strategies.
- **kind:** persisted-format
- **status:** active
