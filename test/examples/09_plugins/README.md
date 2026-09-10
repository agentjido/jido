# Plugin example tests

These tests prove the public behavior in the
[Plugin example section](../../../examples/09_plugins/README.md).

```sh
mix test test/examples/09_plugins --include example --seed 0
```

The tests cover direct and live preparation, live-only runtime admission,
signature verification, replay protection, encrypted Signals, and input
composition. They also cover full-state preparation and owned-state middleware
reduction.
