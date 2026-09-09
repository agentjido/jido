# Durable Scheduling tests

The folder test proves that an acknowledged occurrence stays complete after
restore and that the schedule continues:

```shell
mix test test/examples/04_runtime/04_13_durable_scheduling --include example --seed 0
```

The deeper Scheduler and recovery acceptance tests remain under
[`test/jido/plugin/scheduler`](../../../jido/plugin/scheduler).
