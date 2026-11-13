# Sequential Flow

A typed Flow passes results between ordered steps and produces one Agent state
candidate.

## What you will learn

- How input, result, and control dependencies connect Flow steps.
- How Flow input, Flow output, and Agent state schemas protect different bounds.
- How one Flow execution becomes one Agent commit.

## Read the code

Read [the Agent and Flow](sequential_flow.ex) first. Then read
[the behavior tests](sequential_flow_test.exs).

## Run it

```sh
mix test.examples examples/03_flow_execution/03_17_sequential_flow
```

Expected result: the value is doubled, failures do not commit, and schema
errors report the boundary that rejected the value.

## Important behavior

The `double` and `gate` steps use the short inline Step syntax. The `gate` step
is a control dependency for `finish`; its result is not copied into the final
input. `Finish` is a named Action because the runtime Flow constructor and
codec test reuse its stable module identity.

The source shows the compile-time Flow DSL. The behavior test also shows the
reader-facing runtime Flow constructor with `Jido.Flow.new/1`, then encodes and
decodes that data definition through `Jido.Flow.Codec`. That longer runtime
path stays in the test so the first source Flow remains focused.

## Limits

This example does not teach parallel execution, collections, or external I/O.

## Files

- [Source](sequential_flow.ex)
- [Tests](sequential_flow_test.exs)

Previous: [Dynamic Invoke](../../03_flow_execution/03_15_dynamic_invoke/README.md) |
Next: [Effectful Steps](../04_02_effectful_steps/README.md)
