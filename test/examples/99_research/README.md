# Research probe tests

This folder contains the executable evidence for the retained
[distributed-authority probe](../../../examples/99_research/99_02_distributed_authority/README.md).
It also contains the [member authoring examples](../../../examples/99_research/99_03_data_defined_topology/README.md)
for issue 394 and the [child runtime examples](../../../examples/99_research/99_04_child_topology_runtime/README.md)
for issue 395 and runtime nesting.

```sh
mix test test/examples/99_research --include example --seed 0
```

The distributed-authority test starts local peer nodes. It proves the external
fencing workaround. It does not prove the missing Jido `DIST-03` contract.

The member tests cover startup, mixed members, live additions, groups, static
composition, transport, validation, and recovery. Module controls pass. Neutral
Topology members fail with `Expected an Agent module`. The DSL argument probe
also records the current atom restriction.

The child runtime tests cover ownership, activation modes, gates, event exports,
Bus isolation, lifecycle, recovery, and nesting validation. The static include
control passes. The proposed Runtime and child field do not exist yet.

All desired-contract tests stay enabled. They describe required behavior after
the first failing boundary; they do not yet prove that behavior for data members
or child runtimes. See the [API review note](../../../examples/99_research/API_REVIEW.md).
