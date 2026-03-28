# Strategies

Current-truth contract for strategy-driven execution in Jido.

## Intent

This subject covers the boundary between pure agent logic and strategy-owned execution semantics, including direct execution, FSM execution, and custom strategy extension points.

```spec-meta
id: jido.strategies
kind: subsystem
status: active
summary: Strategies control how pure agent logic becomes state transitions and directives at runtime.
surface:
  - guides/strategies.md
  - guides/custom-strategies.md
  - guides/fsm-strategy.livemd
  - lib/jido/agent/strategy.ex
  - lib/jido/agent/strategy
  - test/examples/fsm
  - test/jido/agent/strategy
  - test/jido/agent/strategy_fsm_test.exs
  - test/jido/agent/strategy_state_test.exs
  - test/jido/agent/strategy_test.exs
```

## Requirements

```spec-requirements
- id: jido.strategies.strategy_boundary
  statement: Jido shall let strategies own the translation between pure agent results, internal state operations, and runtime directives.
  priority: must
  stability: stable

- id: jido.strategies.direct_default
  statement: Jido shall provide a direct strategy for single-turn action execution without changing the purity of agent logic.
  priority: must
  stability: stable

- id: jido.strategies.fsm_support
  statement: Jido shall provide an FSM strategy for multi-state execution flows driven by explicit machine state.
  priority: must
  stability: stable

- id: jido.strategies.custom_extension
  statement: Jido shall provide a custom strategy interface for specialized execution patterns.
  priority: should
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/strategies.md
  covers:
    - jido.strategies.strategy_boundary
    - jido.strategies.direct_default

- kind: guide_file
  target: guides/custom-strategies.md
  covers:
    - jido.strategies.custom_extension

- kind: guide_file
  target: guides/fsm-strategy.livemd
  covers:
    - jido.strategies.fsm_support

- kind: command
  target: mix test test/jido/agent/strategy_test.exs test/jido/agent/strategy/state_test.exs test/jido/agent/strategy_state_test.exs test/jido/agent/strategy_fsm_test.exs test/examples/fsm/fsm_agent_test.exs test/examples/fsm/fsm_strategy_guide_test.exs
  execute: true
  covers:
    - jido.strategies.strategy_boundary
    - jido.strategies.direct_default
    - jido.strategies.fsm_support
    - jido.strategies.custom_extension
```
