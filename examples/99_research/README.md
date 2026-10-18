# Research examples

Research records an unsupported contract. It is separate from the stable
learning path. Original example numbers remain unchanged.

- [05_04 Remote Child](05_04_remote_child/README.md): remote startup is rejected.
- [05_05 Remote Lifecycle](05_05_remote_lifecycle/README.md): node-loss lifecycle is unsupported.
- [99_02 Distributed Authority](99_02_distributed_authority/README.md): external
  fencing is an application workaround, not a Jido cluster ownership guarantee.

```sh
mix test test/examples/99_research --include example --seed 0
```

The remote rejection test checks the current local runtime boundary. The old
remote success proposals are retained as `.exs` files and are not loaded.
The separate Topology Controller, director, and gate proposals were removed.
Use [Agent topology](../07_topology/README.md) for current local composition,
[data authoring](../01_basic/01_07_data_defined_agent/README.md) for definitions,
and the [authoring tests](../../test/authoring/agents/json_test.exs) for format checks.
