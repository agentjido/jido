# 05_05 Remote Lifecycle

A parent Agent records whether a remote child was observed to exit or became
unreachable because its node connection was lost.

## What you will learn

- How remote child lifecycle Signals report observed facts.
- Why `:noconnection` does not prove that a remote process stopped.

## Read the code

Read [the lifecycle Agent](remote_lifecycle.ex), then read the
[remote counter](../05_04_remote_child/remote_counter.ex) that it owns.

## Run it

```sh
mix test test/examples/05_multi_agent/05_05_remote_lifecycle --include example --seed 0
```

Expected result: loss of the child node records an `:unreachable` observation,
removes the child from the parent's live registry, and does not create a
replacement.

## Important behavior

Connected process exit is an observed exit. Lost connectivity is uncertainty.
Reconnect requires an explicit new placement request.

This example starts the child before it disconnects. For uncertainty during
the start operation, keep the tag unresolved, retry the same start request,
and reconcile `AgentServer.status/1`, `AgentServer.children/1`, and the target
Agent identity. Do not create a replacement until that check resolves the old
request.

## Limits

This example does not claim that the child is dead after a disconnect. It does
not implement a distributed lease or automatic replacement policy.

## Files

- [Source](remote_lifecycle.ex)
- [Remote child](../05_04_remote_child/remote_counter.ex)
- [Tests](../../../test/examples/05_multi_agent/05_05_remote_lifecycle/remote_lifecycle_test.exs)

Previous: [Remote Child](../05_04_remote_child/README.md) | Next: [Orphan Adoption](../05_06_orphan_adoption/README.md)
