# Application example tests

These tests prove the public behavior described by the six
[application examples](../../../examples/08_applications/README.md).

```sh
mix test test/examples/08_applications --include example --seed 0
mix test test/examples/08_applications/08_01_audit --include example --seed 0
```

Source and test folders use the same numbered ID. Each test uses public Jido
APIs, deterministic local services, bounded asynchronous checks, and the
`:example` tag.
