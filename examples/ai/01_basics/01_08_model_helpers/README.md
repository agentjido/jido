# 01_08 Model defaults

Use a direct ReqLLM model name as a reasoning default. A request can replace
the default model without changing the Agent definition. Invalid non-string
model values fail preflight validation.

The [tests](../../../../test/examples/ai/01_basics/01_08_model_helpers/model_helpers_test.exs)
compare two Agent defaults and one request override. They do not call a provider.

```sh
mix test.examples test/examples/ai/01_basics/01_08_model_helpers --warnings-as-errors
```

Previous: [Core composition](../01_07_core_composition/README.md) | Next: [JSON Agent](../01_09_json_agent/README.md)
