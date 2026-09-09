# Pending Job Recovery tests

The folder test proves that saved approval survives loss and that the
application starts a new attempt explicitly:

```shell
mix test test/examples/04_runtime/04_12_pending_job_recovery --include example --seed 0
```

The deeper process and VM acceptance tests remain under
[`test/jido/agent_server`](../../../jido/agent_server).
