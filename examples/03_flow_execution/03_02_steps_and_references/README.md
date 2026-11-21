# 03_02 Steps and References

Three Steps use input, result, and context references in one Flow run.

## What you will learn

- How references move validated data between Steps.
- How compiled connections match the required data and ordering.

## Read the code

Read [the Flow](steps_and_references.ex), then
[the test](steps_and_references_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_02_steps_and_references --warnings-as-errors`

Expected result: every Step runs with the referenced value and the Flow returns
the explicit final output.

## Important behavior

Each authored Step compiles to one Action node.

## Limits

This lesson does not introduce branches or parallel work.

## Files

- [Flow](steps_and_references.ex)
- [Tests](steps_and_references_test.exs)

[Previous: Single Action](../03_01_single_action/README.md) |
[Next: Choice](../03_03_choice/README.md)
