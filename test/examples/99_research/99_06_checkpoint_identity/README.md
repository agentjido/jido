# PERSIST-01 acceptance notes

```sh
mix test test/examples/99_research/99_06_checkpoint_identity --include example --seed 0
```

The folder test proves that the loader rejects a different nested identity.
The deeper core suite also covers valid restore and outer-envelope mismatch.

[Core tests](../../../jido/persistence/checkpoint_identity_test.exs) ·
[Example](../../../../examples/99_research/99_06_checkpoint_identity/README.md)
