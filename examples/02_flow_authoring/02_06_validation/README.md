# 02_06 Validation

Flow construction rejects unknown references and dependency cycles before run.

## What you will learn

- How reference validation names an unknown component.
- How cycle validation reports an invalid dependency graph.

## Read the code

Read [the invalid definitions](validation.ex), then [the test](validation_test.exs).

## Run it

`mix test.examples examples/02_flow_authoring/02_06_validation --warnings-as-errors`

Expected result: both invalid definitions return structured validation errors.

## Important behavior

No Action starts when Flow authoring fails.

## Limits

This lesson does not cover runtime Action failure or retry policy.

## Files

- [Invalid definitions](validation.ex)
- [Tests](validation_test.exs)

[Previous: Authoring Equivalence](../02_05_authoring_equivalence/README.md) |
[Next: Inputs and Output](../02_07_inputs_and_output/README.md)
