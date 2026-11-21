# 15_03 Structured output

Set a strict JSON Schema as the ReAct `output_schema` default. The inference
request receives this schema. A valid structured model object becomes the
completed response output.

## What you will learn

- How structured output enters preflight and model request data.
- How the final model object is validated before use.

## Read the code

Read [the Agent](agent.ex), then [the tests](structured_output_test.exs).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_03_structured_output --warnings-as-errors
```

Expected result: preflight contains the schema and the deterministic response
returns a validated object.

## Important behavior

Invalid structured output fails at the declared schema boundary.

## Limits

Schema validation proves output shape, not factual quality. The local client
does not call a provider.

## Files

- [Agent](agent.ex)
- [Tests](structured_output_test.exs)

Previous: [Action and Flow tools](../15_02_tool_flow/README.md) | Next: [Limits and tool policy](../15_04_controls/README.md)
