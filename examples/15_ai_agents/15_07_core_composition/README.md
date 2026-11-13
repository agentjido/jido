# 15_07 Core composition

`Jido.AI.Agent` prepends the AI Plugin and keeps application Plugins. Both
Plugins use one Agent definition, one state value, and one commit boundary.

## What you will learn

- How AI and application Plugins share one Agent definition.
- How Plugin state commits through one Agent boundary.

## Read the code

Read [the composed Agent](agent.ex), then [the tests](core_composition_test.exs).

## Run it

```sh
mix test.examples examples/15_ai_agents/15_07_core_composition --warnings-as-errors
```

Expected result: Plugin order and initial state are stable, and the complete
offline reasoning request commits.

## Important behavior

AI is a first-party Plugin capability on the normal Agent runtime.

## Limits

One commit boundary does not make model providers or external Plugin effects
part of one distributed transaction.

## Core Fit and Gaps

The Plugin contracts compose without a separate AI host or state model. No
core gap was found.

## Files

- [Composed Agent](agent.ex)
- [Tests](core_composition_test.exs)

Previous: [Request contract](../15_06_request_contract/README.md) | Next: [Model defaults](../15_08_model_helpers/README.md)
