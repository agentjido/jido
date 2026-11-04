# 11 Plugin Tests

These tests prove the public behavior in the
[Plugin example section](../../../examples/11_plugins/README.md).

```sh
mix test test/examples/11_plugins --include example --seed 0
```

The tests cover direct and live preparation, live-only runtime admission,
signature verification, runtime-generation replay protection, consumed nonces,
encrypted Signals, and input composition. They also cover full-state
preparation and owned-state middleware reduction.
Persisted Plugin conversion is tested in `test/examples/13_persistence`.

Live Plugin Changes (`11_06`) proves installation, validated replacement, explicit owned-state discard, and runtime cleanup.

Plugin DSL (`11_04`) proves custom section and entity lowering, owned-state
reduction, Map validation, and JSON import through a stable Registry. Live
Plugin Changes also proves File-backed thaw without replaying commit hooks.
