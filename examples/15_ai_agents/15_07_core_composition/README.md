# 15_07 Core composition

`Jido.AI.Agent` prepends the AI Plugin and keeps application Plugins. Both
Plugins use one Agent definition, one state value, and one commit boundary.

The [tests](core_composition_test.exs)
check Plugin order, initial state, and a complete offline reasoning request.

```sh
mix test.examples examples/15_ai_agents/15_07_core_composition --warnings-as-errors
```

Previous: [Request contract](../15_06_request_contract/README.md) | Next: [Model defaults](../15_08_model_helpers/README.md)
