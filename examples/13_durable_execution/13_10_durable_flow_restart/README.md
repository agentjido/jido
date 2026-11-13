# 13_10 Durable Flow Restart Recovery

A restarted Jido instance restores one waiting Flow and resumes it with the
same wait identity.

## What you will learn

- How namespace and persistence identify saved Flow work.
- Which confirmed work does not repeat after recovery.

## Read the code

Read [the Flow](restart_recovery.ex), then [the test](restart_recovery_test.exs).

## Run it

`mix test.examples examples/13_durable_execution/13_10_durable_flow_restart --warnings-as-errors`

Expected result: status restores the same wait ID and the approval Signal
continues the saved Flow.

## Important behavior

Confirmed authored component boundaries do not repeat.

## Limits

Work inside one unfinished composite component can repeat after recovery. The
application must make external effects idempotent.

## Core Fit and Gaps

Instance restart uses the same public Flow, wait, Signal, and persistence
contracts. Recovery remains explicit and tested.

## Files

- [Flow](restart_recovery.ex)
- [Tests](restart_recovery_test.exs)

[Previous: Start and Result](../13_09_durable_flow_start/README.md) |
[Next: Signal Resume](../13_11_durable_signal_resume/README.md)
