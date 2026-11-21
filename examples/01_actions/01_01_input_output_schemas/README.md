# 01_01 Input and Output Schemas

One Action accepts a validated profile and returns one validated public result.

## What you will learn

- How `Jido.Joi` protects Action input and output.
- How `Jido.Exec` stops invalid input before Action work starts.

## Read the code

Read [the Action](input_output_schemas.ex), then read
[the tests](input_output_schemas_test.exs).

## Run it

`mix test.examples examples/01_actions/01_01_input_output_schemas --warnings-as-errors`

Expected result: valid input returns `ADA`; a negative age returns a
`Jido.Error.ValidationError`.

## Important behavior

The Action callback receives parsed input. Its normal output must also match
the declared output schema.

## Limits

This lesson does not start a process or perform I/O.

## Files

- [Action](input_output_schemas.ex)
- [Tests](input_output_schemas_test.exs)
