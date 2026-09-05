# Independent Agents

Feature ID: `07_01_independent`. Status: implemented within the topology spike scope.

Two Agents start from one static topology. Their state and lifecycle are independent.

[Source](../../../../lib/examples/07_topology/07_01_independent/independent.ex) ·
[Guide](../../../../lib/examples/07_topology/README.md) ·
[Tests](../../../../test/examples/07_topology/07_01_independent)

The spike supports local eager activation and periodic repair. It does not
provide cluster placement or a database adapter.
