---
modules:
  - Jido.Plugin.FSM
  - Jido.Plugin.FSM.Transition
---

## Purpose

Protect the bundled FSM Plugin's Agent authoring, route selection, and
owned state.

## Obligations

### jido.plugin.fsm.I1 — Canonical provider and authoring

- **scope:** `Jido.Plugin.FSM`, `Jido.Plugin.FSM.Transition`
- **must:** Use `Jido.Plugin.FSM` for DSL and map definitions. Keep the `jido.fsm` provider ID and version 1. Reject invalid transition graphs and routes.
- **kind:** functional
- **status:** active

### jido.plugin.fsm.I2 — Route selection and state update

- **scope:** `Jido.Plugin.FSM.prepare/2`, `Jido.Plugin.FSM.select_route/2`, `Jido.Plugin.FSM.reduce/2`
- **must:** Select a matching managed route by current state. Use normal routing for unmanaged Signals. Keep the source state until the Action or Flow succeeds, including when a durable Flow waits.
- **kind:** ordering
- **status:** active

### jido.plugin.fsm.I3 — Saved FSM state

- **scope:** `Jido.Plugin.FSM.state_spec/1`
- **must:** Preserve the current FSM state and its definition version on restore. Preserve that state when an explicit upgrade replaces the beta provider.
- **kind:** functional
- **status:** active
