---
modules:
  - Jido.Agent.Contract
  - Jido.Agent.Plugin
  - Jido.Agent.Plugin.Pipeline
  - Jido.Agent.Route
  - Jido.Agent.Runner
  - Jido.Agent.Turn.SignalHandler
---

## Purpose

Protect pure Agent evaluation from one accepted Signal to one complete candidate.
This component selects one route, prepares execution input, runs the selected
Action or Flow, validates the result, applies pure Agent Plugin preparation and
reduction, and returns an ordered Directive batch.

The component does not own Agent authoring, live AgentServer timing or process
state, Directive dispatch, persistence, or executable internals from
`jido_action`.

## Obligations

### jido.agent_evaluation.I1 — One fixed route

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Runner`
- **must:** Select the first declared matching route, bind the unchanged source Signal to the Turn, and do not try a later route after selected work fails.
- **kind:** ordering
- **status:** active

### jido.agent_evaluation.I2 — Normalized route input

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Turn`
- **must:** Accept map, keyword-last-value, and nil Signal data. Shallow-merge route defaults with Signal data taking precedence. Reject other data before executable work.
- **kind:** functional
- **status:** active

### jido.agent_evaluation.I3 — Protected execution context

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Runner`
- **must:** Reject reserved caller context keys, preserve other caller values, add the current Agent and Signal values, and pass execution options to the executor.
- **kind:** functional
- **status:** active

### jido.agent_evaluation.I4 — Current handler contract

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Runner`
- **must:** Run the selected Action or Flow against its current contract, including after code reload. Pass-through returns the unchanged Signal. Transform returns one Signal without routing it again.
- **kind:** functional
- **status:** active

### jido.agent_evaluation.I5 — Complete candidate state

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Runner`
- **must:** Return only a complete valid candidate state while retaining Agent identity and definition fields. A failure returns no candidate, leaves the source unchanged, and does not prevent later evaluation.
- **kind:** functional
- **status:** active

### jido.agent_evaluation.I6 — Ordered Plugin preparation

- **scope:** `Jido.Agent.Plugin.prepare/3`
- **must:** Prepare Agent Plugins in declaration order and keep portable package inputs separate. Preserve application rejection reasons and contain callback faults.
- **kind:** ordering
- **status:** active

### jido.agent_evaluation.I7 — Ordered Directive validation

- **scope:** `Jido.Agent.Plugin.Pipeline.run/6`
- **must:** Validate the complete Directive batch in order before Plugin reduction. Accept built-in Directives and declared Plugin-owned Directives only.
- **kind:** ordering
- **status:** active

### jido.agent_evaluation.I8 — Owned Plugin reduction

- **scope:** `Jido.Agent.Plugin.Pipeline.run/6`
- **must:** Reduce Agent Plugins in declaration order and let each reducer replace only its owned state value. Reject executable writes to Plugin-owned state and invalid reducer results.
- **kind:** ordering
- **status:** active

### jido.agent_evaluation.I9 — Atomic pure result

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Runner`
- **must:** Apply executable state and accepted definition changes to one candidate and return the validated Directive batch without dispatch. Reject a batch that changes a Plugin declaration and runs a Directive owned by that Plugin. A later validation failure does not change the source or undo work that the executable already performed.
- **kind:** functional
- **status:** active

### jido.agent_evaluation.I10 — Closed AgentServer handoff

- **scope:** `Jido.Agent.Runner.prepare_for_server/4`, `Jido.Agent.Runner.finish_for_server/2`
- **must:** Prepare and finish the same pure evaluation for an accepted AgentServer Command. Return route, input, composition, and candidate validation failures with their closed stage and do not run live process behavior.
- **kind:** functional
- **status:** active
