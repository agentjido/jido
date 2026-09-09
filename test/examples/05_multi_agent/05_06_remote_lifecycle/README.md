# Remote Lifecycle tests

The folder test proves that node loss reports an unreachable child and does
not create a replacement:

```shell
mix test test/examples/05_multi_agent/05_06_remote_lifecycle --include example --seed 0
```

The deeper two-node core acceptance tests remain at
[`test/jido/agent_server/remote_lifecycle_test.exs`](../../../jido/agent_server/remote_lifecycle_test.exs).
