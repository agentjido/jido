# Child Lifecycle

Feature ID: `05_01_child_lifecycle`. Status: implemented within the tested scope.

## Added feature

A parent starts real children, tracks a restarted PID with the same ID, and stops owned processes. Read this after the Runtime group and the previous Multi-agent example.

## Use

```elixir
alias Jido.Examples.ChildLifecycle

{:ok, server} = Jido.start_agent(jido, ChildLifecycle)
ChildLifecycle.start_worker(server, "worker")
```

## Evidence

3 enabled tests:

- pure evaluation plans a child; only live dispatch starts it.
- abnormal restart keeps committed child state and updates the tracked PID.
- explicit child stop and parent stop remove owned processes.

Run:

```shell
mix test --include integration test/examples/05_multi_agent/05_01_child_lifecycle --seed 0
```

[Source](../../../../lib/examples/05_multi_agent/05_01_child_lifecycle/child_lifecycle.ex) ·
[Tests](../../../../test/examples/05_multi_agent/05_01_child_lifecycle/child_lifecycle_test.exs)

## Boundary and next question

A restarted child retains committed state. A fresh-state worker restart must be an explicit application decision.

See the [gap register](../../runtime-multi-agent-gaps.md) and
[verification report](../../runtime-multi-agent-results.md).
