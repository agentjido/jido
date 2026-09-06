# PERSIST-01 acceptance notes

```sh
mix test test/jido/persistence/checkpoint_identity_test.exs --seed 0
```

All three tests pass. The loader rejects a different nested identity. The
original rejection assertion remains enabled.

[Tests](../../../jido/persistence/checkpoint_identity_test.exs) ·
[Example](../../../../examples/99_research/99_06_checkpoint_identity/README.md)
