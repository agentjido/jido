# Plugin example tests

These tests prove the public behavior in the
[Plugin example section](../../../examples/09_plugins/README.md).

```sh
mix test test/examples/09_plugins --include example --seed 0
```

The tests cover direct and live preparation, live-only runtime admission,
signature verification, runtime-generation replay protection, consumed nonces,
encrypted Signals, and input composition. They also cover full-state
preparation and owned-state middleware reduction.
Persisted Plugin conversion is tested in `test/examples/10_persistence`.

Live Plugin Changes (`09_09`) proves installation, validated replacement, explicit owned-state discard, and runtime cleanup.
