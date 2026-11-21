# 15_08 Model defaults

Use a direct ReqLLM model name as a reasoning default. A request can replace
the default model without changing the Agent definition. Invalid non-string
model values fail preflight validation.

## What you will learn

- How model defaults stay in the Agent definition.
- How one request can select another valid model name.

## Read the code

Read [the model definitions](models.ex), then [the tests](model_helpers_test.exs).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_08_model_helpers --warnings-as-errors
```

Expected result: two defaults and one valid override normalize, while an
invalid model value fails preflight.

## Important behavior

Model selection data contains no provider credential.

## Limits

The example validates model selection data only. It does not resolve
credentials or call a provider.

## Files

- [Model definitions](models.ex)
- [Tests](model_helpers_test.exs)

Previous: [Core composition](../15_07_core_composition/README.md) | Next: [JSON Agent](../15_09_json_agent/README.md)
