# 00_02 Submit Action

Validate and prepare one submitted expense with a named Action.

## What you will learn

- How an Action validates its input and output.
- How one Action uses the same execution model as a one-step Flow.

## Read the code

Read [the Action](submit_action.ex), then read the behavior test.

## Run it

```sh
mix test.examples examples/00_start_here/00_02_submit_action --warnings-as-errors
```

Expected result: valid input returns a submitted expense and invalid input
returns a validation error.

## Important behavior

`Jido.Exec` lowers the Action to its canonical one-step Flow before execution.

## Limits

The Action returns a value. It does not store Agent state.

## Files

- [Source](submit_action.ex)
- [Tests](submit_action_test.exs)

Previous: [Validated state](../00_01_validated_state/README.md) |
Next: [Triage Flow](../00_03_triage_flow/README.md)
