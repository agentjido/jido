# Bus Swarm

Feature ID: `07_03_bus_swarm`. Status: implemented within the topology spike scope.

A stored JSON definition starts 1000 workers and one coordinator. One Bus Signal reaches every worker. The test sets Jido task capacity to 4096.

[Source](../../../../examples/07_topology/07_03_bus_swarm/swarm.ex) ·
[Guide](../../../../examples/07_topology/README.md) ·
[Tests](../../../../test/examples/07_topology/07_03_bus_swarm)

The spike supports local eager activation and periodic repair. It does not
provide cluster placement or a database adapter.
