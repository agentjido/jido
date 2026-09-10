# 05_01 Child Lifecycle

A parent Agent starts, tracks, restarts, and stops owned child Agents without
putting child PIDs in domain state.

## What you will learn

- How `SpawnChild` and `StopChild` Directives manage owned children.
- How stable child identity survives an abnormal restart.

## Read the code

Read [the parent Agent](child_lifecycle.ex), then read the shared
[Worker Agent](../support/worker.ex) and [Keep State Action](../../support/keep_state.ex).

## Run it

```sh
mix test test/examples/05_multi_agent/05_01_child_lifecycle --include example --seed 0
```

Expected result: the parent creates one child per tag, preserves committed child
state across restart, and removes owned processes on stop.

## Important behavior

The Agent stores desired child tags. AgentServer stores live child metadata.
An explicit child stop and parent shutdown remove the owned processes.

## Limits

This example does not implement a worker queue or capacity policy.

## Files

- [Source](child_lifecycle.ex)
- [Tests](../../../test/examples/05_multi_agent/05_01_child_lifecycle/child_lifecycle_test.exs)
- [Worker Agent](../support/worker.ex)
- [Keep State Action](../../support/keep_state.ex)

Previous: [Durable Scheduling](../../04_runtime/04_11_durable_scheduling/README.md) | Next: [Correlated Requests](../05_02_correlated_requests/README.md)
