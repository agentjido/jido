# Agent Observation

Feature ID: `04_09_agent_observation`. Status: implemented within the tested scope.

## Added feature

SDK telemetry reports Agent lifecycle, Turn settlement, commits, and Directive
outcomes without command wrappers or application-generated events.

## Evidence

Nine core tests cover success, rejection, failure, cancellation, restart,
shutdown, observer failure, safe metadata, and one terminal outcome per Turn.

```shell
mix test test/jido/observe/agent_lifecycle_test.exs --seed 0
mix run lib/examples/04_runtime/04_09_agent_observation/demo.exs
```

[Source](../../../../lib/examples/04_runtime/04_09_agent_observation/turn_observation.ex) ·
[Core tests](../../../../test/jido/observe/agent_lifecycle_test.exs) ·
[Results](../../obs-01-results.md)
