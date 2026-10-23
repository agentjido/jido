# Topology example tests

These tests mirror the four retained lessons in
[the topology catalog](../../../examples/07_topology/README.md).

```sh
mix test test/examples/07_topology --include example --seed 0
```

- `07_01`: separate member state and owner shutdown.
- `07_02`: nested member startup and complete subtree removal.
- `07_03`: local Bus broadcast and owned runtime cleanup.
- `07_09`: add, resize, replace, remove, and invalid-mutation isolation.

Tests use public AgentServer reads, readiness waits, and OTP monitors. Child
tags are opaque. The [shared assertions](../support/agent_topology_assertions.ex)
contain only test setup and shutdown observation. Detailed recovery and
runtime fault contracts stay in the AgentServer core contract tests.

- `07_11`: direct output pipeline, explicit forward/transform routes, and cleanup.
- `07_12`: connection edits retain processes; File-backed thaw restores changed routing.
- `07_09`: state-bound resize and two full File-backed hibernate/thaw cycles retain the portable topology snapshot and revision.
