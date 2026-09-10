# Factory example tests

This folder mirrors the numbered learning path in
[the factory examples](../../../examples/06_factory/README.md).

Run the section behavior tests:

```sh
mix test test/examples/06_factory --include example --seed 0
```

The tests use real Agents, Plugins, Flows, ReqLLM encoding, and local HTTP
responses. Test-only barriers stay in test support. No provider key is needed.
