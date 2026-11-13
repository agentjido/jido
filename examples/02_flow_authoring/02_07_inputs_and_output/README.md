# 02_07 Inputs and Output

Flow and Action schemas validate separate input and output boundaries.

## What you will learn

- Where Flow input validation occurs.
- How explicit output protects the public result shape.

## Read the code

Read [the Flow](inputs_and_output.ex), then [the test](inputs_and_output_test.exs).

## Run it

`mix test.examples examples/02_flow_authoring/02_07_inputs_and_output --warnings-as-errors`

Expected result: `%{left: 2, right: 3}` returns `%{answer: 5}`, and invalid
input fails before Action work starts.

## Important behavior

The Flow schema and target Action schema remain separate validation contracts.

## Limits

This lesson does not cover side effects or partial execution.

## Files

- [Flow](inputs_and_output.ex)
- [Tests](inputs_and_output_test.exs)

[Previous: Validation](../02_06_validation/README.md) |
[Next: Compiled Program](../02_08_compiled_program/README.md)
