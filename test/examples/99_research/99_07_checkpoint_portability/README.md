# PERSIST-02 acceptance notes

```sh
mix test test/examples/99_research/99_07_checkpoint_portability --include example --seed 0
```

The folder test proves that the loader rejects a nested PID. The fixture
changes stored bytes after a valid save so the test reaches the load validator.
The deeper core suite covers all prohibited term classes.

[Core tests](../../../jido/persistence/checkpoint_portability_test.exs) ·
[Example](../../../../examples/99_research/99_07_checkpoint_portability/README.md)
