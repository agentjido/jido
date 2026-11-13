# 13_09 Durable Flow Start and Result

`Jido.Durable.start/4` saves and runs one Flow from a Signal without an Agent
or AgentServer.

## What you will learn

- How the Jido instance owns the durable persistence adapter.
- How a portable operation reference returns status and result.

## Read the code

Read [the Flow](start_and_result.ex), then [the test](start_and_result_test.exs).

## Run it

`mix test.examples examples/13_durable_execution/13_09_durable_flow_start --warnings-as-errors`

Expected result: the durable result has the same output shape as
`Jido.Exec.run/4`.

## Important behavior

A durable operation cannot select or replace the instance persistence adapter.

## Limits

This mode has no Agent identity, Agent state, or AgentServer effects lifecycle.

## Core Fit and Gaps

The public durable facade, Signal, Flow, and persistence contracts compose
without a separate workflow model. No core gap was found.

## Files

- [Flow](start_and_result.ex)
- [Tests](start_and_result_test.exs)

[Previous: Waterpark](../13_08_waterpark/README.md) |
[Next: Restart Recovery](../13_10_durable_flow_restart/README.md)
