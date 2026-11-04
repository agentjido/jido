# 01_01 Basic AI Agent

Select ReAct, a direct model name, and instructions in the `ai` block. The
Agent definition stores these values as typed reasoning defaults.

The [tests](../../../../test/examples/ai/01_basics/01_01_basic_agent/basic_agent_test.exs)
inspect the definition and run one complete offline request. They check the
correlated reply and committed Session state.

```sh
mix test.examples test/examples/ai/01_basics/01_01_basic_agent --warnings-as-errors
```

Next: [Action and Flow tools](../01_02_tool_flow/README.md).
