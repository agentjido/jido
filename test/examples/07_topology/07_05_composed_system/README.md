# Composed topology test

```sh
mix test test/examples/07_topology/07_05_composed_system --include example
```

The test starts the JSON composition, checks one shared Bus, sends work to all
five workers, checks the logical ownership tree, and checks shutdown cleanup.
It uses no external service.

See the [source guide](../../../../examples/07_topology/07_05_composed_system/README.md).
