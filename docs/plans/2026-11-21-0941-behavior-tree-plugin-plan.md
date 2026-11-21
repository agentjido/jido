---
title: Bundle Behavior Trees in Jido v3
type: implementation-plan
date: 2026-11-21
last_reviewed: 2026-11-21
artifact_contract: kata-plan/v1
artifact_readiness: implementation-ready
domain: software
execution: code
product_contract_source: direct-request
---

# Bundle Behavior Trees in Jido v3

## Goal Capsule

Provide an opt-in Behavior Tree Plugin for Jido v3. Use the existing tree
engine and the v3 Turn lifecycle. Make and verify local changes on the v3
integration base. The implementer stops after local verification.

## Product Contract

### Summary

Jido developers can run trees inside an Agent or through the standalone
executor. Developers moving from v2 have a guide for each entry point.

### Problem Frame

The standalone package uses a v2 Strategy and v2 Action effects. Jido v3
uses Agent routes, Plugin state reduction, and post-commit Directives.

### Actors

Jido Agent authors, standalone tree users, and tool authors.

### Requirements

- R1. Keep the engine, built-in nodes, blackboard, and custom node callbacks.
- R2. Add explicit tick, halt, reset, and blackboard Signals to an opt-in Plugin.
- R3. Resume running nodes and pass Action results and Directives through the
  v3 Turn. Reject the full tick when a node returns an error.
- R4. Document and test the standalone executor and tool wrapper.
- R5. Publish guides in the core documentation index and provide an offline
  runnable example. Check the old package's direct consumers.

### Key Flows

A Signal selects a contributed route. A route Action runs one traversal.
The Plugin reducer stores the continuation. AgentServer commits before it
dispatches the leaf Directives.

### Acceptance Examples

The first tick returns running. The next tick resumes, commits Action
results, and emits a Signal. Halt clears progress and keeps the blackboard.
Reset restores the configured tree and blackboard.

### Success Criteria

Focused tests, runnable example output, and core gates cover R1 through R5.

### Scope Boundaries

Local implementation and proof. Package retirement and release require
separate authorization.

### Key Decisions

Keep the established tree namespace and Signal type strings where possible.

### Rejected Alternatives

A second OTP application would duplicate application ownership. A v2 Strategy
shim would retain an obsolete execution contract.

### Dependencies

Core v3 at `aa61e26d` and standalone source at `58e04e7`.

### Outstanding Questions

None identified for local implementation.

### Sources

[Core architecture](../architecture/module-dependency-map.md),
[Plugin routing](../../guides/plugins/plugin-input-and-routes.md), and
[Action context](../../guides/actions/action-context.md).

## Planning Contract

### Product Contract Preservation

The plan preserves the direct request.

### Current System

The old Strategy mutates private Strategy state. The standalone GenServer
has manual and automatic tick modes. The Skill wrapper runs an independent
tree and projects the final blackboard as tool output.

### Target System

The Plugin owns `:behavior_tree`. It contributes the five legacy Signal
types and reduces a Directive from its route Action. A leaf calls
`Jido.Exec`, stores its result on the blackboard, and returns downstream
Directives to the Turn.

### Key Technical Decisions

- KTD1. Keep engine modules in `Jido.BehaviorTree` and add a capability layer
  owner. Preserve standalone calls with v3 Action contracts.
- KTD2. Use an internal Directive for the Plugin state change. The route
  Action returns the complete candidate state with the owned field intact.
- KTD3. Merge plain Action result maps into candidate Agent state and retain
  the latest Action result on the blackboard. Core validates the complete
  state and Directive batch before commit.
- KTD4. Use Joi schemas for the Skill wrapper. Its output is the final
  blackboard. Tool execution rejects Directive requests.

### System Boundaries and Change Surface

| Surface | Planned change | Compatibility |
| --- | --- | --- |
| Engine and custom nodes | Keep the two-value and context-aware tick forms | Compile the existing node API against v3 |
| Agent | Use Plugin config and Signal routes | Replace Strategy options and commands |
| Effects | Return v3 candidate data and Directives | Replace v2 StateOps |
| Tool | Accept Joi schemas and emit tool schema | Convert old keyword schemas |

### Implementation Units

- U1 (R1, R4). Port the engine, standalone executor, and Skill. Run the
  reused tests with v3 Actions and Joi schemas.
- U2 (R2, R3). Add Plugin routes, owned state, and a reducer. Test direct and
  live Turns, invalid input, reset, continuation, and failed tick atomicity.
  Requires U1.
- U3 (R5). Add guide links, migration instructions, and a deterministic
  example. Run the command and compare its result with the README. Requires U2.

### Work Graph

U1 → U2 → U3. U3 is the integration check.

### Verification Contract

Run these commands from the isolated core checkout.

- R1 and R4. `mix test test/jido/behavior_tree`
- R2 and R3. `mix test test/jido/plugin/behavior_tree_test.exs` and
  `mix test.contracts`
- R5. `mix test.examples examples/11_built_in_capabilities/11_07_behavior_tree`
  and the runner documented in that example
- All requirements. `mix test.ci`, `mix quality`, and
  `mix format --check-formatted`

### Rollout and Recovery

The separate package and v3 core share BEAM module names. Change the core
version and remove the old dependency in the same consumer change. Keep the
old package available for v2 users until the migration has evidence.

### Risks and Assumptions

Keep tree state free of process-local resources. JSON authoring of tree
structs and restart recovery for time-based nodes need separate contracts.

### Open Planning Decisions

The package retirement decision is deferred to the release owner.

### Definition of Done

The v3 Agent and standalone entry points meet the focused behavior checks.
The runner, guides, contract records, and core gates have current evidence.

### Planning Sources

[Agent Runner](../../lib/jido/agent/runner.ex),
[Plugin pipeline](../../lib/jido/agent/plugin/pipeline.ex), and
[Exec](../../lib/jido/exec.ex).

## Adapter Results

Markdown is the canonical plan. No optional adapters were requested.
