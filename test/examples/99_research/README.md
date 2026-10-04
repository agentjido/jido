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
composition, transport, validation, and recovery. DSL, data, and JSON forms
now pass through the same core contract.

The child runtime tests cover ownership, activation modes, gates, event exports,
Bus isolation, lifecycle, recovery, and nesting validation. Static include
continues to compose one Controller target.

The first commit in this PR records the failing examples. The tests stay
enabled and now verify the implementation. Review the public contract in the
[API review note](../../../examples/99_research/API_REVIEW.md) before merge.
