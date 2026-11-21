# 03_14 Runic Runner

A compiled Flow runs through `Runic.Runner` with manual dispatch control.

## What you will learn

- How each authored Step becomes one scheduler unit.
- Where the direct Runic escape path starts and ends.

## Read the code

Read [the Runner example](runic_runner.ex), then [the test](runic_runner_test.exs).

## Run it

`mix test.examples examples/03_flow_execution/03_14_runic_runner --warnings-as-errors`

Expected result: manual dispatch produces the same validated Flow result.

## Important behavior

The application owns manual Runic scheduling when it leaves the normal Jido
execution facade.

## Limits

This advanced path does not add Jido persistence, waits, or recovery by itself.

## Core Fit and Gaps

The public compile operation and Runic Runner compose without private Jido
runtime access. No core gap was found.

## Files

- [Runner example](runic_runner.ex)
- [Tests](runic_runner_test.exs)

[Previous: Compile to Runic](../03_13_compile_to_runic/README.md) |
[Next: Human Approval](../03_15_human_approval/README.md)
