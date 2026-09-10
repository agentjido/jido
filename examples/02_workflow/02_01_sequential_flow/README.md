# Sequential Flow

A typed Flow passes results between ordered steps and produces one Agent state
candidate.

## What you will learn

- How input, result, and control dependencies connect Flow steps.
- How Flow input, Flow output, and Agent state schemas protect different bounds.
- How one Flow execution becomes one Agent commit.

## Read the code

Read [the Agent and Flow](sequential_flow.ex) first. Then read
[the behavior tests](../../../test/examples/02_workflow/02_01_sequential_flow/sequential_flow_test.exs).

## Run it

```sh
mix test test/examples/02_workflow/02_01_sequential_flow --include example --seed 0
```

Expected result: the value is doubled, failures do not commit, and schema
errors report the boundary that rejected the value.

## Important behavior

The `double` and `gate` steps use the short inline Step syntax. The `gate` step
is a control dependency for `finish`; its result is not copied into the final
input. `Finish` is a named Action because the Builder and codec test reuses its
stable module identity.

## Limits

This example does not teach parallel execution, collections, or external I/O.

## Files

- [Source](sequential_flow.ex)
- [Tests](../../../test/examples/02_workflow/02_01_sequential_flow/sequential_flow_test.exs)

Previous: [Basic examples](../../01_basic/README.md) | Next: [Effectful Steps](../02_02_effectful_steps/README.md)
