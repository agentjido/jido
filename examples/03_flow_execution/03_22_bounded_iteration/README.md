# Bounded Iteration

An Iterate component repairs local state until it is complete or reaches a
fixed limit.

## What you will learn

- How Iterate calls a child Flow and validates the returned loop state.
- How `while` and `max_iterations` bound repeated work.
- How invalid replacement state rejects the complete Agent Turn.

## Read the code

Read [the Agent and Flow](bounded_iteration.ex) first. Then read
[the behavior tests](bounded_iteration_test.exs).

## Run it

```sh
mix test.examples examples/03_flow_execution/03_22_bounded_iteration --warnings-as-errors
```

Expected result: complete input runs no repair, three repairs succeed,
exhaustion fails, and an oversized repair fails state validation.

## Important behavior

The child Flow subtracts the repaired items and increments the repair count.
Its output replaces the loop state. The next pass reads that state through
`state()`. An oversized repair returns a negative count. The parent rejects
that replacement state before the Agent commits.

The Iterate `while` condition is a `Jido.Expr` value. It is portable static
data, not an anonymous loop predicate.

## Limits

Iteration is local to one Flow execution. Use a child Flow that runs to
completion without waits or handoffs.

## Files

- [Source](bounded_iteration.ex)
- [Tests](bounded_iteration_test.exs)

Previous: [Ordered Batch](../03_21_ordered_batch/README.md) | Next: [Nested Flow](../03_23_nested_flow/README.md)
