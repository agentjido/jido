# Remote Child tests

The folder test proves placement on one known Erlang node, result delivery to
the parent, and explicit cleanup:

```shell
mix test test/examples/05_multi_agent/05_05_remote_child --include example --seed 0
```

The deeper two-node core acceptance tests remain under
[`test/jido/agent_server`](../../../jido/agent_server).
