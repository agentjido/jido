# Agent Observation tests

The folder test proves that semantic Turn events distinguish a successful
commit from a committed Directive failure:

```shell
mix test test/examples/04_runtime/04_09_agent_observation --include example --seed 0
```

The deeper core acceptance tests remain at
[`test/jido/observe/agent_lifecycle_test.exs`](../../../jido/observe/agent_lifecycle_test.exs).

Persistence and local Topology observation tests are in
[`test/jido/persistence_test.exs`](../../../jido/persistence_test.exs) and
[`test/jido/topology/controller_test.exs`](../../../jido/topology/controller_test.exs).

Run the full boundary demonstration with:

```shell
mix run examples/04_runtime/04_09_agent_observation/semantic_boundaries.exs
```
