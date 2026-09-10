# Bounded Iteration

An Iterate component repairs local state until it is complete or reaches a
fixed limit.

## What you will learn

- How Iterate owns and validates local loop state.
- How `while` and `max_iterations` bound repeated work.
- How invalid replacement state rejects the complete Agent Turn.

## Read the code

Read [the Agent and Flow](bounded_iteration.ex) first. Then read
[the behavior tests](../../../test/examples/02_workflow/02_06_bounded_iteration/bounded_iteration_test.exs).

## Run it

```sh
mix test test/examples/02_workflow/02_06_bounded_iteration --include example --seed 0
```

Expected result: complete input runs no repair, three repairs succeed,
exhaustion fails, and an oversized repair fails state validation.

## Important behavior

The loop body is used once, so it stays inline and uses its generated name.
`repair_size` gives replacement-state validation a normal domain input instead
of a test-only callback.

## Limits

Iteration is local to one Flow execution. This example does not model durable
or multi-Turn work.

## Files

- [Source](bounded_iteration.ex)
- [Tests](../../../test/examples/02_workflow/02_06_bounded_iteration/bounded_iteration_test.exs)

Previous: [Ordered Batch](../02_05_ordered_batch/README.md) | Next: [Nested Flow](../02_07_nested_flow/README.md)
