# Recoverable Delivery tests

The folder test proves that the application delivery protocol resumes saved
intent after loss without duplicating the external record:

```shell
mix test test/examples/04_runtime/04_11_recoverable_delivery --include example --seed 0
```

The deeper core-boundary tests remain at
[`test/jido/agent_server/effect_recovery_test.exs`](../../../jido/agent_server/effect_recovery_test.exs).
