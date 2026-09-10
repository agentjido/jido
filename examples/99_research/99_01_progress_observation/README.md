# 99_01 Progress Observation

Status: application extension; not a Jido progress API.

A bounded temporary buffer exposes live progress while terminal state remains
owned by the Agent.

## What this proves

- Progress retention is bounded and observer loss does not fail work.
- Waiting reasons and terminal results remain queryable through public APIs.

## Read the code

Read [the Agent](progress_observation.ex), then [the progress buffer](buffer.ex).
The active-Turn barrier exists only in test support.

## Run it

```sh
mix test test/examples/99_research/99_01_progress_observation --include example --seed 0
```

Expected result: progress stays bounded, cancellation preserves committed state,
and a terminal result survives Agent and observer replacement.

## Gap and limits

Jido has no first-class progress stream contract. This local ETS buffer has one
producer, is not durable, and does not push notifications to consumers.

## Files

- [Agent](progress_observation.ex)
- [Buffer](buffer.ex)
- [Tests](../../../test/examples/99_research/99_01_progress_observation/progress_observation_test.exs)

Previous: [Plugin State Middleware](../../09_plugins/09_06_state_middleware/README.md) | Next: [Distributed Authority](../99_02_distributed_authority/README.md)
