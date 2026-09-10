# 09_06 State Middleware

An Agent Plugin reads the complete state before and after an Action, then
reduces only its owned audit field.

## What you will learn

- How `prepare/2` reads the complete current Agent state without changing it.
- How a custom Directive owns its `validate/1` callback.
- How `reduce/2` reads the prior state, candidate state, prepared input, and
  validated Directives.
- How a reducer returns only its Plugin-owned state value.

## Run it

```sh
mix test test/examples/09_plugins/09_06_state_middleware --include example --seed 0
```

The Action changes `count`. The Plugin records the count before and after the
Action, the validated note, and the number of successful Turns. Direct
evaluation returns a candidate. Live execution commits the same reduction.

Previous: [Composition](../09_05_composition/README.md) | Next: [Progress Observation Research](../../99_research/99_01_progress_observation/README.md)
