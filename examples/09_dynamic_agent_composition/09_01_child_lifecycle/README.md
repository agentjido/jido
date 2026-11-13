# 09_01 Logical Agent lifecycle

A Jido instance creates, activates, stops, and restores one durable logical
Agent without putting its process PID in domain state.

## What you will learn

- How stable identity survives activation replacement.
- How the Jido instance owns the activation process.

## Read the code

Read [the parent Agent](child_lifecycle.ex), then read the shared
[Worker Agent](../support/worker.ex).

## Run it

```sh
mix test.examples examples/09_dynamic_agent_composition/09_01_child_lifecycle
```

Expected result: one stable Agent Ref preserves committed state across two
different activation processes.

## Important behavior

The Agent record owns domain state. The Jido instance owns its current
AgentServer activation. Stopping the activation does not delete the record.

## Limits

This example has no dynamic parent Agent relation. It does not implement
adoption or ownership transfer.

## Files

- [Source](child_lifecycle.ex)
- [Tests](child_lifecycle_test.exs)
- [Worker Agent](../support/worker.ex)
- Previous: [Pending Job Recovery](../../13_durable_execution/13_13_pending_job_recovery/README.md)

Next: [Correlated Requests](../09_02_correlated_requests/README.md)
