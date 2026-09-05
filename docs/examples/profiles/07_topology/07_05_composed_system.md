# Composed Topology

Feature ID: `07_05_composed_system`. Status: implemented within the local scope.

Two copies of a reusable team use separate inputs and stable identities. One
root-owned Bus supplies both teams. Public exports provide access to leaders,
workers, and the shared Bus. The root director owns the two leaders; each
leader owns its workers. DSL, Builder, and JSON forms produce the same plan.

[Source](../../../../lib/examples/07_topology/07_05_composed_system/composed_system.ex) ·
[Guide](../../../../lib/examples/07_topology/07_05_composed_system/README.md) ·
[Tests](../../../../test/examples/07_topology/07_05_composed_system)

One local controller owns startup, repair, and shutdown. There is no separate
controller for each component, live replacement, or cluster placement.
