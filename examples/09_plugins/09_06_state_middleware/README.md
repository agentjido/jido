# 09_06 State Middleware

An Agent Plugin reads the complete state before and after an Action, then
reduces only its owned audit field.

## What you will learn

- How `prepare/2` reads the complete current Agent state without changing it.
- How a custom Directive owns its `validate/1` callback.
- How `reduce/2` reads the prior state, candidate state, prepared input, and
  validated Directives.
- How a reducer returns only its Plugin-owned state value.

## Read the code

Read [the Directive, Plugin, and Agent](state_middleware.ex), then read the
[behavior tests](../../../test/examples/09_plugins/09_06_state_middleware/state_middleware_test.exs).

## Run it

```sh
mix test test/examples/09_plugins/09_06_state_middleware --include example --seed 0
```

Expected result: the Action changes `count`. The Plugin records the count before and after the
Action, the validated note, and the number of successful Turns. Direct
evaluation returns a candidate. Live execution commits the same reduction.

## Important behavior

The Plugin uses `Jido.Plugin` and defines only its state callbacks. Core
controls state ownership and reduction order. The reducer reads the complete
candidate but can return only the Plugin-owned `audit` value.

## Limits

The audit field is committed state, not an append-only event log. The example
does not export or persist an audit history.

## Files

- [Directive, Plugin, and Agent](state_middleware.ex)
- [Tests](../../../test/examples/09_plugins/09_06_state_middleware/state_middleware_test.exs)

Previous: [Composition](../09_05_composition/README.md) | Next: [Commit Projection](../09_08_commit_projection/README.md)
