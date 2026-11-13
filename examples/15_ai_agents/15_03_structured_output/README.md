# 15_03 Structured output

Set a strict JSON Schema as the ReAct `output_schema` default. The inference
request receives this schema. A valid structured model object becomes the
completed response output.

The [tests](structured_output_test.exs)
check preflight data and a deterministic structured response.

```sh
mix test.examples examples/15_ai_agents/15_03_structured_output --warnings-as-errors
```

Previous: [Action and Flow tools](../15_02_tool_flow/README.md) | Next: [Limits and tool policy](../15_04_controls/README.md)
