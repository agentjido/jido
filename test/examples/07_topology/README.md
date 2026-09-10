# Topology example tests

This folder mirrors the numbered learning path in
[the Topology examples](../../../examples/07_topology/README.md).

Run the section behavior tests:

```sh
mix test test/examples/07_topology --include example --seed 0
```

The Bus swarm test is a local scale fixture. Other tests prove ownership,
manual repair, keyed identity, composition, Plugin contribution, lifecycle
Signals, placement-policy delegation, and cleanup.
