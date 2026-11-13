# 17 AI Reasoning Flows

Reasoning strategies are normal Jido Flows. Every supported lesson uses
deterministic inference or pure Flow behavior.

1. [ReAct tool loop](17_01_react_tool_loop/README.md) shows one bounded tool-use round.
2. [Linear reasoning comparison](17_02_linear_reasoning_comparison/README.md) compares Chain of Thought, Chain of Draft, and Algorithm of Thoughts.
3. [Branching reasoning comparison](17_03_branching_reasoning_comparison/README.md) compares Tree of Thoughts and Graph of Thoughts.
4. [Revision and adaptive reasoning](17_04_revision_and_adaptive/README.md) compares TRM with local strategy selection.
5. [Custom reasoning Flow](17_05_custom_reasoning_flow/README.md) shows schema-owned defaults and overrides.

Run the current chapter:

```sh
mix test.examples examples/17_ai_reasoning_flows --warnings-as-errors
```

The chapter has no live provider runner.
