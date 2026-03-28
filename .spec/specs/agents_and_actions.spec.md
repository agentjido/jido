# Agents And Actions

Current-truth contract for Jido agent modules and the action surface they execute.

## Intent

This subject covers how Jido agents define state, stay pure at the decision boundary, and expose action-driven behavior without collapsing runtime concerns into agent state.

```spec-meta
id: jido.agents_and_actions
kind: subsystem
status: active
summary: Jido agents are schema-backed pure decision units with explicit action surfaces.
surface:
  - guides/getting-started.livemd
  - guides/core-loop.md
  - guides/agents.md
  - guides/actions.md
  - lib/jido.ex
  - lib/jido/agent.ex
  - lib/jido/agent/schema.ex
  - lib/jido/agent/state.ex
  - lib/jido/actions
  - test/examples/basics
  - test/jido/actions
  - test/jido/agent/agent_test.exs
  - test/jido/agent/schema_test.exs
  - test/jido/agent/schema_coverage_test.exs
  - test/jido/agent/state_test.exs
```

## Requirements

```spec-requirements
- id: jido.agents_and_actions.schema_defined_agents
  statement: Jido shall let agent modules declare schema-backed state, defaults, and hooks through `use Jido.Agent`.
  priority: must
  stability: stable

- id: jido.agents_and_actions.pure_cmd_contract
  statement: Jido shall treat `cmd/2` and `cmd/3` as pure decision functions that return an updated agent together with explicit effects.
  priority: must
  stability: stable

- id: jido.agents_and_actions.action_execution_surface
  statement: Jido shall provide action surfaces for validated state transformation and built-in control, lifecycle, status, and scheduling behaviors.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/agents.md
  covers:
    - jido.agents_and_actions.schema_defined_agents
    - jido.agents_and_actions.pure_cmd_contract

- kind: guide_file
  target: guides/actions.md
  covers:
    - jido.agents_and_actions.action_execution_surface

- kind: command
  target: mix test test/jido/agent/agent_test.exs test/jido/agent/schema_test.exs test/jido/agent/schema_coverage_test.exs test/jido/agent/state_test.exs test/jido/actions/lifecycle_test.exs test/jido/actions/control_test.exs test/jido/actions/status_test.exs test/jido/actions/scheduling_test.exs test/examples/basics/counter_agent_test.exs test/examples/basics/error_handling_test.exs
  execute: true
  covers:
    - jido.agents_and_actions.schema_defined_agents
    - jido.agents_and_actions.pure_cmd_contract
    - jido.agents_and_actions.action_execution_surface
```
