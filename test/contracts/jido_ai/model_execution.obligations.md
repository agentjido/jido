---
modules:
  - Jido.AI.Actions.Embed
  - Jido.AI.Budget
  - Jido.AI.Context
  - Jido.AI.Context.Snapshot
  - Jido.AI.Reasoning.Actions.CallModel
  - Jido.AI.Usage
---

## Purpose

Protect one provider-call lifecycle. This component owns model selection,
fallback and retry control, resource budgets, usage accounting, streaming
normalization, portable model failures, context snapshots, and embedding
requests. It does not own reasoning strategy routing.

## Obligations

### jido_ai.model_execution.I1 — Bounded retries and fallbacks

- **scope:** `Jido.AI.Reasoning.Actions.CallModel`
- **must:** Retry only retryable failures within the configured retry and model-call limits. Move through fallback models in order and return one normalized outcome for every attempt.
- **kind:** ordering
- **status:** active

### jido_ai.model_execution.I2 — Budgets stop new provider work

- **scope:** `Jido.AI.Budget`, model-call admission
- **must:** Check elapsed time, model calls, tokens, reported cost, tool rounds, and tool calls at their declared boundaries. Stop new work with a stable limit reason when a maximum is reached.
- **kind:** functional
- **status:** active

### jido_ai.model_execution.I3 — Usage and cache accounting

- **scope:** `Jido.AI.Usage`, recorded model attempts
- **must:** Normalize and add provider usage, including cache read, write, creation, and cached-token values, without losing a provider-reported total cost.
- **kind:** functional
- **status:** active

### jido_ai.model_execution.I4 — Streaming and non-streaming parity

- **scope:** `Jido.AI.Reasoning.Actions.CallModel`
- **must:** Produce the same normalized final outcome and usage for streaming and non-streaming calls. Publish ordered stream events without adding partial assistant messages to conversation history.
- **kind:** ordering
- **status:** active

### jido_ai.model_execution.I5 — Portable model errors and contexts

- **scope:** `Jido.AI.Context`, `Jido.AI.Context.Snapshot`, model outcomes
- **must:** Preserve the exact prepared ReqLLM request, store safe portable snapshots, and convert provider faults into bounded retryable or terminal data without raw exception or process-local values.
- **kind:** security
- **status:** active

### jido_ai.model_execution.I6 — Embedding action contract

- **scope:** `Jido.AI.Actions.Embed`
- **must:** Accept one string or an ordered list of strings, use the selected embedding model, and return ordered vectors and usage or one normalized error.
- **kind:** functional
- **status:** active
