# 03_25 Flow Directives

A multi-step Flow returns one ordered Directive batch only after every
component succeeds.

## What you will learn

- How Directives from several Flow components keep canonical execution order.
- How a successful side component can contribute a Directive without becoming
  the final Flow output.
- How failure discards the complete batch before commit and dispatch.

## Read the code

Read [the Agent and Flows](flow_directives.ex), then [the recording
Plugin](effects.ex), and finish with the behavior test.

## Run it

```sh
mix test.examples examples/03_flow_execution/03_25_flow_directives
```

Expected result: direct execution returns `first`, `side`, and `final` in order.
Live dispatch sees the committed version. The failing Flow changes no state and
dispatches no record.

## Important behavior

Flow collects Directives from each successful component. It returns the batch
only after the complete execution succeeds. AgentServer validates the candidate
and batch, commits once, and then dispatches in batch order.

## Limits

This example teaches the Agent integration boundary. Detailed Flow scheduling,
dependency, and executor mechanics belong to `jido_action` tests.

## Files

- [Agent and Flows](flow_directives.ex)
- [Recording Plugin](effects.ex)
- [Tests](flow_directives_test.exs)

Previous: [Executable Continuation](../04_08_executable_continuation/README.md) |
Next: [Flow Durability](../../13_durable_execution/README.md)
