# 04_05 Runtime Inspection

A debugger reads committed Agent state and runtime phase through public APIs.

## What you will learn

- How `snapshot/2` and `status/2` describe a running Agent.
- How to redact private fields before inspection data leaves the application.

## Read the code

Read [the live debugger](agent_live_debugger.ex), then read its behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_05_runtime_inspection --include example --seed 0
```

Expected result: the debugger returns committed public state and revision data
without the secret field, including while test support holds an active Turn.

## Important behavior

Inspection does not change the Agent. During active work, the snapshot still
contains the last committed state while status reports a non-idle phase.

## Limits

The redaction policy is application code. Jido does not infer which domain
fields are secret.

## Files

- [Source](agent_live_debugger.ex)
- [Tests](../../../test/examples/04_runtime/04_05_runtime_inspection/agent_live_debugger_test.exs)

Previous: [Managed Jobs](../04_04_managed_jobs/README.md) | Next: [State Recovery](../04_06_state_recovery/README.md)
