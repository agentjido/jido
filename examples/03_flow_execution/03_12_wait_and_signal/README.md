# 03_12 Wait and Signal

A host stores one waiting workflow and resumes it with an addressed Signal or
timer.

## What you will learn

- How Selection compiles to one Wait node.
- Why immediate `Jido.Exec.run/4` rejects a Flow that can wait.

## Read the code

Read [the waiting Flow](wait_and_signal.ex), then
[the test](wait_and_signal_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_12_wait_and_signal --warnings-as-errors`

Expected result: the host resumes the saved workflow through both supported
resume paths.

## Important behavior

The test host is a deterministic local execution probe. Durable hosting is in
chapter 13.

## Limits

This lesson does not claim persistence across BEAM loss.

## Files

- [Waiting Flow](wait_and_signal.ex)
- [Tests](wait_and_signal_test.exs)

[Previous: Effects and Failure](../03_11_effects_and_failure/README.md) |
[Next: Compile to Runic](../03_13_compile_to_runic/README.md)
