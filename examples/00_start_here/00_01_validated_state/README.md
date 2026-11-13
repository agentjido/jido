# 00_01 Validated state

Define the portable state of one expense-approval Agent and reject invalid
state before work starts.

## What you will learn

- How an Agent declares state with `Jido.Joi`.
- How defaults and validation protect Agent creation.

## Read the code

Read [the Agent](validated_state.ex), then read the behavior test.

## Run it

```sh
mix test.examples examples/00_start_here/00_01_validated_state --warnings-as-errors
```

Expected result: valid state creates an Agent value and a negative amount is
rejected.

## Important behavior

The Agent is a value. This lesson does not start a process.

## Limits

The Agent has no routes or behavior yet.

## Files

- [Source](validated_state.ex)
- [Tests](validated_state_test.exs)

Next: [Submit Action](../00_02_submit_action/README.md)
