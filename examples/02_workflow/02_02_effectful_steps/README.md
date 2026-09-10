# Effectful Steps

A Flow reads through a caller-supplied service and commits only its selected,
portable result.

## What you will learn

- How runtime clients pass through execution context.
- How an early guard can prevent external I/O.
- How output projection and Agent persistence keep transient data out of state.

## Read the code

Read [the Agent and Flow](effectful_steps.ex) first. Then read
[the behavior tests](../../../test/examples/02_workflow/02_02_effectful_steps/effectful_steps_test.exs)
and [the shared service adapter](../../../test/examples/support/workflow_sdk_case.ex).

## Run it

```sh
mix test test/examples/02_workflow/02_02_effectful_steps --include example --seed 0
```

Expected result: guarded work makes no service call, selected data persists,
and a committed result can satisfy a repeated request.

## Important behavior

The service call is synchronous Action work. A later validation failure cannot
undo it. `Read` and `Project` are named because their cache and I/O contracts are
the subject of this example and use separate clauses.

## Limits

This example does not provide external retry, idempotency, or durable effect
recovery.

## Files

- [Source](effectful_steps.ex)
- [Tests](../../../test/examples/02_workflow/02_02_effectful_steps/effectful_steps_test.exs)
- [Shared test adapter](../../../test/examples/support/workflow_sdk_case.ex)

Previous: [Sequential Flow](../02_01_sequential_flow/README.md) | Next: [Conditional Routes](../02_03_conditional_routes/README.md)
