# 15_01 Basic AI Agent

Select ReAct, a direct model name, and instructions in the `ai` block. The
Agent definition stores these values as typed reasoning defaults.

The [tests](basic_agent_test.exs)
inspect the definition and run one complete offline request. They check the
correlated reply and committed Session state.

```sh
mix test.examples examples/15_ai_basics/15_01_basic_agent --warnings-as-errors
```

Previous: [Durable Agents](../../14_durable_agents/README.md) |
Next: [Action and Flow tools](../15_02_tool_flow/README.md).
