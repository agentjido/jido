# PERSIST-02 acceptance notes

```sh
mix test test/jido/persistence/checkpoint_portability_test.exs --seed 0
```

All three tests pass. The loader rejects the nested PID. The original rejection
assertion remains enabled. The fixture changes stored bytes after a valid
save so the test reaches the load validator.

[Tests](../../../jido/persistence/checkpoint_portability_test.exs) ·
[Example](../../../../examples/99_research/99_07_checkpoint_portability/README.md)
