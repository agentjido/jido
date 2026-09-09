# Topology example tests

Run all six example fixtures:

```sh
mix test test/examples/07_topology --include example
```

The Bus swarm test starts 1000 workers plus one coordinator. It sets the Jido
task capacity to 4096, verifies broadcast delivery to all workers, and checks
shutdown cleanup. No external service or database is required.

The Plugin contribution fixture proves that pure instance planning adds a
declared Bus and subscription before the local Controller starts them.

Core authoring and runtime acceptance tests are in `test/jido/topology`.
See the [example guide](../../../examples/07_topology/README.md).
