# 15_02 Action and Flow tools

Declare an Action and a Flow as model tools. ReAct validates every call, runs
the selected tool as an explicit graph node, and returns the correlated result
to the next model round.

The [tests](../../../test/examples/15_ai_basics/15_02_tool_flow/tool_flow_test.exs)
run both tools directly, run one deterministic Flow-tool round, and check the
per-request visible and hidden tool policy.

```sh
mix test.examples test/examples/15_ai_basics/15_02_tool_flow --warnings-as-errors
```

Previous: [Basic Agent](../15_01_basic_agent/README.md) | Next: [Structured output](../15_03_structured_output/README.md)
