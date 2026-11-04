# 14_01 Saved Agent State tests

See [the lesson](../../../../examples/14_durable_agents/14_01_saved_agent/README.md)
and [the behavior test](saved_agent_test.exs).

```sh
mix test test/examples/14_durable_agents/14_01_saved_agent --include example --seed 0 --warnings-as-errors
```

One test proves a committed request survives SIGKILL and fresh-BEAM restore.
The other rejects missing required storage without creating fresh state.
