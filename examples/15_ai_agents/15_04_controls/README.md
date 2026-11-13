# 15_04 Limits and tool policy

Use ordinary Jido Actions for local admission checks. Use ReAct `limits` and
the request `tool_policy` for model calls, tool rounds, elapsed time, and tool
visibility. This is the current graph-first control surface.

The [tests](controls_test.exs)
check allow and deny results, normalized limits, and a request with tools disabled.

```sh
mix test.examples examples/15_ai_agents/15_04_controls --warnings-as-errors
```

Previous: [Structured output](../15_03_structured_output/README.md) | Next: [Streaming](../15_05_streaming/README.md)
