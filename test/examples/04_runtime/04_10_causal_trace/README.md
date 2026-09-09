# Causal Trace tests

The folder test proves one trace across parent work, child work, and child
results:

```shell
mix test test/examples/04_runtime/04_10_causal_trace --include example --seed 0
```

The deeper local and remote core acceptance tests remain under
[`test/jido/observe`](../../../jido/observe).
