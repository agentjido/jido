# 10 Topology Tests

These tests mirror the four retained lessons in
[the topology catalog](../../../examples/10_topologies/README.md).

```sh
mix test test/examples/10_topologies --include example --seed 0
```

- `10_01`: separate member state and owner shutdown.
- `10_04`: nested member startup and complete subtree removal.
- `10_03`: local Bus broadcast and owned runtime cleanup.
- `10_05`: add, resize, replace, remove, and invalid-mutation isolation.

Tests use public AgentServer reads, readiness waits, and OTP monitors. Child
tags are opaque. The [shared assertions](../../support/agent_topology_assertions.ex)
contain only test setup and shutdown observation. Detailed recovery and
runtime fault contracts stay in the AgentServer core contract tests.

- `10_02`: direct output pipeline, explicit forward/transform routes, and cleanup.
- `10_06`: connection edits retain processes; File-backed thaw restores changed routing.
- `10_05`: state-bound resize and two full File-backed hibernate/thaw cycles retain the portable topology snapshot and revision.
