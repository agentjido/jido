# Multi-agent example tests

This folder mirrors the numbered learning path in
[the multi-agent examples](../../../examples/05_multi_agent/README.md).

Run the section behavior tests:

```sh
mix test test/examples/05_multi_agent --include example --seed 0
```

The local tests use public AgentServer APIs. The remote tests start isolated,
connected Erlang peers and confirm cleanup through the public APIs on each node.
