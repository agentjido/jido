# Agent Hierarchy

Feature ID: `07_02_hierarchy`. Status: implemented within the topology spike scope.

A coordinator owns one leader. The leader owns three workers. All processes remain in the Jido Agent pool.

[Source](../../../../examples/07_topology/07_02_hierarchy/hierarchy.ex) ·
[Guide](../../../../examples/07_topology/README.md) ·
[Tests](../../../../test/examples/07_topology/07_02_hierarchy)

The spike supports local eager activation and periodic repair. It does not
provide cluster placement or a database adapter.
