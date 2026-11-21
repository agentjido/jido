# 03_01 Single Action

`Jido.Exec` lowers one Action to a canonical one-step Flow and returns its
validated result.

## What you will learn

- One Action and one authored Flow use the same execution model.
- The compiled workflow contains input, Action, and output nodes.

## Read the code

Read [the Action](single_action.ex), then [the test](single_action_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_01_single_action --warnings-as-errors`

Expected result: input values `3` and `2` return `%{value: 5}`.

## Important behavior

Action validation and instrumentation remain active because execution goes
through `Jido.Exec`.

## Limits

This lesson has no process, persistence, or effect dispatch.

## Files

- [Action](single_action.ex)
- [Tests](single_action_test.exs)

[Next: Steps and References](../03_02_steps_and_references/README.md)
