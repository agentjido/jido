# 03_08 Subflow

One parent Step calls a reusable child Flow.

## What you will learn

- How parent input maps into a child Flow.
- How the child result returns through the parent Step.

## Read the code

Read [the parent and child Flows](subflow.ex), then [the test](subflow_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_08_subflow --warnings-as-errors`

Expected result: the parent returns the child's validated output.

## Important behavior

The parent Step compiles to one Subflow node. The child workflow stays inside
that node.

## Limits

This lesson does not hand work to another host or process.

## Files

- [Parent and child Flows](subflow.ex)
- [Tests](subflow_test.exs)

[Previous: Iterate](../03_07_iterate/README.md) |
[Next: Invoke](../03_09_invoke/README.md)
