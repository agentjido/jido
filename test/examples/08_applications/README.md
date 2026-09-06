# Application example tests

These tests cover the ten [application examples](../../../examples/08_applications/README.md).
The source compiles with the other examples. Each test file uses `:example` and
runs once; no fixture file uses the `_test.exs` suffix.

```sh
mix test test/examples/08_applications --include example --seed 0
```

The default test command skips these tests. `mix examples` includes them.
CI selects this directory explicitly to preserve its existing acceptance checks.
