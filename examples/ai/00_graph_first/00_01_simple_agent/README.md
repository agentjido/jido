# 00_01 Simple Agent

Define one `Jido.AI.Agent` with the ReAct Flow and two Action tools. The Agent
route points directly to the reasoning Flow. The offline runner inspects the
static graph and one expanded parallel tool graph. It does not call a provider.

The [tests](../../../../test/examples/ai/00_graph_first/00_01_simple_agent/simple_agent_test.exs)
also run one complete two-tool round with deterministic model results. They
check the final reply and the committed Session Thread.

```sh
mix test.examples test/examples/ai/00_graph_first/00_01_simple_agent --warnings-as-errors
mix run examples/ai/00_graph_first/00_01_simple_agent/simple_agent.exs
```

Next: [Schema-driven overrides](../00_02_schema_driven_overrides/README.md).
