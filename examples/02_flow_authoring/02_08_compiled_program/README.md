# 02_08 Compiled Program

Map and Choice remain named canonical components in the inspected Flow graph.

## What you will learn

- How higher-order components appear before execution.
- How their references produce a small dependency graph.

## Read the code

Read [the Flow](compiled_program.ex), then [the test](compiled_program_test.exs).

## Run it

`mix test.examples examples/02_flow_authoring/02_08_compiled_program --warnings-as-errors`

Expected result: `items` is a root, `selected` depends on it, and the graph has
no synthetic vertices.

## Important behavior

Authoring inspection preserves component identity before Runic compilation.

## Limits

This lesson does not prove Map concurrency or Choice branch execution.

## Files

- [Flow](compiled_program.ex)
- [Tests](compiled_program_test.exs)

[Previous: Inputs and Output](../02_07_inputs_and_output/README.md) |
[Next: Flow Execution](../../03_flow_execution/README.md)
