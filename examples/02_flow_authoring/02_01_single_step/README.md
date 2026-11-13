# 02_01 Single Step

One data-authored Step becomes one validated canonical Flow component.

## What you will learn

- How `Jido.Flow.new!/1` normalizes a Step.
- Why every Flow needs an explicit output.

## Read the code

Read [the Flow](single_step.ex), then [the test](single_step_test.exs).

## Run it

`mix test.examples examples/02_flow_authoring/02_01_single_step --warnings-as-errors`

Expected result: the dependency map contains one independent `echo` component,
and the invalid definition reports its missing output.

## Important behavior

Authoring validates structure before execution starts.

## Limits

This lesson does not execute the Flow or teach runtime state.

## Files

- [Flow](single_step.ex)
- [Tests](single_step_test.exs)

[Next: Dependency Graph](../02_02_dependency_graph/README.md)
