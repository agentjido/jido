# Topology example tests

Run all five example fixtures:

```sh
mix test test/examples/07_topology --include example
```

The Bus swarm test starts 1000 workers plus one coordinator. It sets the Jido
task capacity to 4096, verifies broadcast delivery to all workers, and checks
shutdown cleanup. No external service or database is required.

Core authoring and runtime acceptance tests are in `test/jido/topology`.
See the [example guide](../../../examples/07_topology/README.md).
