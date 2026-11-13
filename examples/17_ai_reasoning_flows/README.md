# 17 AI Reasoning Flows

Reasoning strategies are normal Jido Flows. Every supported lesson uses
deterministic inference or pure Flow behavior.

1. [ReAct tool loop](17_01_react_tool_loop/README.md) shows one bounded tool-use round.
2. Chain, tree, and graph comparison lessons will use the same offline case.
3. [Custom reasoning Flow](17_05_custom_reasoning_flow/README.md) shows schema-owned defaults and overrides.

Run the current chapter:

```sh
mix test.examples examples/17_ai_reasoning_flows --warnings-as-errors
```

The chapter has no live provider runner.
