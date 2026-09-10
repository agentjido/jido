# Runtime example tests

This folder mirrors the numbered learning path in
[the runtime examples](../../../examples/04_runtime/README.md).

Run the section behavior tests:

```sh
mix test test/examples/04_runtime --include example --seed 0
```

The tests use public Jido APIs and deterministic local adapters. Test-only
barriers stay in test support and do not appear in example Actions or Flows.
