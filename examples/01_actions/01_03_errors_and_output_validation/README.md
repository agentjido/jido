# 01_03 Errors and Output Validation

One Action makes a work failure and an invalid successful output visible as
different structured errors.

## What you will learn

- How an Action returns a `Jido.Error.ExecutionError`.
- How `Jido.Exec` rejects normal output that breaks the output schema.

## Read the code

Read [the Action](errors_and_output_validation.ex), then read
[the tests](errors_and_output_validation_test.exs).

## Run it

`mix test.examples examples/01_actions/01_03_errors_and_output_validation --warnings-as-errors`

Expected result: the three paths return an execution error, a validation
error, and one accepted result.

## Important behavior

An `{:ok, output}` tuple is not enough. The output must pass the declared
schema before it becomes an execution result.

## Limits

This lesson does not select a retry policy for either error.

## Files

- [Action](errors_and_output_validation.ex)
- [Tests](errors_and_output_validation_test.exs)

