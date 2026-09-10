# 04_06 State Recovery

A persistent counter restores its state, revision, and handled Signal IDs.

## What you will learn

- How to hibernate and restore an Agent with a persistence adapter.
- How a stable Signal ID supports application-owned duplicate handling.

## Read the code

Read [the persistent counter](persistent_counter_recovery.ex), then read its
behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_06_state_recovery --include example --seed 0
```

Expected result: the restored Agent continues from its last revision, a repeated
Signal ID does not increment twice, and a corrupt record cannot start an Agent.

## Important behavior

A successful repeated command keeps the same domain state but still creates a
new commit revision. Invalid input creates no commit.

## Limits

The example uses local ETS persistence and an unbounded handled-ID list. A real
application needs durable storage and an ID retention policy.

## Files

- [Source](persistent_counter_recovery.ex)
- [Tests](../../../test/examples/04_runtime/04_06_state_recovery/persistent_counter_recovery_test.exs)

Previous: [Runtime Inspection](../04_05_runtime_inspection/README.md) | Next: [Agent Observation](../04_07_agent_observation/README.md)
