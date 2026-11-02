---
modules:
  - Jido.AI.Reasoning.Adaptive
  - Jido.AI.Reasoning.Adaptive.Actions.Expand
  - Jido.AI.Reasoning.Adaptive.Actions.Select
  - Jido.AI.Reasoning.AlgorithmOfThoughts
  - Jido.AI.Reasoning.AlgorithmOfThoughts.Actions.Complete
  - Jido.AI.Reasoning.AlgorithmOfThoughts.Actions.ExpandNext
  - Jido.AI.Reasoning.AlgorithmOfThoughts.ModelRound
  - Jido.AI.Reasoning.ChainOfDraft
  - Jido.AI.Reasoning.ChainOfDraft.Actions.Complete
  - Jido.AI.Reasoning.ChainOfDraft.Actions.ExpandNext
  - Jido.AI.Reasoning.ChainOfDraft.ModelRound
  - Jido.AI.Reasoning.ChainOfThought
  - Jido.AI.Reasoning.ChainOfThought.Actions.Complete
  - Jido.AI.Reasoning.ChainOfThought.Actions.ExpandNext
  - Jido.AI.Reasoning.ChainOfThought.ModelRound
  - Jido.AI.Reasoning.GraphOfThoughts
  - Jido.AI.Reasoning.GraphOfThoughts.Actions.Advance
  - Jido.AI.Reasoning.GraphOfThoughts.Actions.ExpandNext
  - Jido.AI.Reasoning.GraphOfThoughts.Actions.PrepareCall
  - Jido.AI.Reasoning.GraphOfThoughts.ModelRound
  - Jido.AI.Reasoning.TreeOfThoughts
  - Jido.AI.Reasoning.TreeOfThoughts.Actions.AcceptOutput
  - Jido.AI.Reasoning.TreeOfThoughts.Actions.ExpandNext
  - Jido.AI.Reasoning.TreeOfThoughts.Actions.PrepareCall
  - Jido.AI.Reasoning.TreeOfThoughts.Actions.SelectThoughts
  - Jido.AI.Reasoning.TreeOfThoughts.ModelRound
  - Jido.AI.Reasoning.TRM
  - Jido.AI.Reasoning.TRM.Actions.Advance
  - Jido.AI.Reasoning.TRM.Actions.ExpandNext
  - Jido.AI.Reasoning.TRM.Actions.PrepareCall
  - Jido.AI.Reasoning.TRM.ModelRound
---

## Purpose

Protect the standard reasoning strategy library other than ReAct. This
component owns Adaptive, Chain of Thought, Chain of Draft, Algorithm of
Thoughts, Graph of Thoughts, Tree of Thoughts, and TRM graph routing. It uses
the shared request-turn and model-execution contracts.

## Obligations

### jido_ai.strategies.I1 — Standard request and result interface

- **scope:** all owned root strategy Flows
- **must:** Accept the common request fields and return the common terminal state and response envelope with completed, blocked, or failed status.
- **kind:** functional
- **status:** active

### jido_ai.strategies.I2 — Portable explicit graphs

- **scope:** all owned root and model-round Flows
- **must:** Expose compilable portable Flow graphs whose steps, decisions, and expansions contain no hidden strategy runtime.
- **kind:** persisted-format
- **status:** active

### jido_ai.strategies.I3 — Consistent model-attempt records

- **scope:** every strategy model round
- **must:** Use the shared model execution and attempt record contract for every provider call, including retries, usage, output guards, and context metadata.
- **kind:** functional
- **status:** active

### jido_ai.strategies.I4 — Stable strategy routing and completion

- **scope:** Adaptive, Chain of Thought, Chain of Draft, Algorithm of Thoughts, Graph of Thoughts, Tree of Thoughts, and TRM Actions
- **must:** Keep each strategy's selection, iteration, branch, scoring, or refinement state explicit and deterministic, and complete through the common result contract when its strategy limit or acceptance rule is met.
- **kind:** ordering
- **status:** active
