# 13_11 Durable Signal Resume

A host calculates one schedule occurrence and sends its Signal to an open
durable wait.

## What you will learn

- How scheduled Signals resume saved Flow work.
- Why `Jido.Durable` does not own a scheduler process.

## Read the code

Read [the Flow](signal_resume.ex), then [the test](signal_resume_test.exs).

## Run it

`mix test.examples examples/13_durable_execution/13_11_durable_signal_resume --warnings-as-errors`

Expected result: the occurrence Signal matches the saved wait and completes
the Flow.

## Important behavior

The example uses `Jido.Plugin.Scheduler.occurrence_signal/5`. AgentServer can
use the same Signal and delivery path.

## Limits

The durable facade stores work. The host still owns schedule calculation,
timer process lifecycle, and duplicate-delivery policy.

## Core Fit and Gaps

Scheduler Signal construction and durable wait delivery compose through public
contracts. No hidden scheduler runs inside `Jido.Durable`.

## Files

- [Flow](signal_resume.ex)
- [Tests](signal_resume_test.exs)

[Previous: Restart Recovery](../13_10_durable_flow_restart/README.md) |
[Next: Timed Resume](../13_12_durable_timed_resume/README.md)
