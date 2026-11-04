# 01_03 Structured output

Set a strict JSON Schema as the ReAct `output_schema` default. The inference
request receives this schema. A valid structured model object becomes the
completed response output.

The [tests](../../../../test/examples/ai/01_basics/01_03_structured_output/structured_output_test.exs)
check preflight data and a deterministic structured response.

```sh
mix test.examples test/examples/ai/01_basics/01_03_structured_output --warnings-as-errors
```

Previous: [Action and Flow tools](../01_02_tool_flow/README.md) | Next: [Limits and tool policy](../01_04_controls/README.md)
