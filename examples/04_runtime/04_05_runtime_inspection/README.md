# 04_05 Runtime Inspection

A debugger reads committed Agent state and runtime phase through public APIs.

## What you will learn

- How `agent/2`, `snapshot/2`, and `status/2` describe a running Agent.
- How `plugin_state/3` and `children/2` expose bounded public runtime views.
- How to enable, read, bound, and disable the opt-in debug event buffer.
- How to redact private fields before inspection data leaves the application.

## Read the code

Read [the live debugger](agent_live_debugger.ex), then read its behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_05_runtime_inspection --include example --seed 0
```

Expected result: the debugger returns committed public state, Plugin state,
child data, and revision data without the secret field. It remains safe while
test support holds an active Turn.

## Important behavior

Inspection does not change the Agent. During active work, the snapshot still
contains the last committed state while status reports a non-idle phase.

The bounded debug buffer is off by default. `set_debug/3` enables collection
for later Turns. `recent_events/3` returns newest events first and honors the
configured maximum. Disabling the buffer clears it. Debug entries contain
bounded outcome and identity data. They do not copy Agent state, full Signals,
or private Server state.

## Limits

The redaction policy is application code. The example selects public domain
fields instead of copying and then removing known secrets. Jido does not infer
which domain fields are secret. Semantic Telemetry remains in the next lesson.

## Files

- [Source](agent_live_debugger.ex)
- [Tests](../../../test/examples/04_runtime/04_05_runtime_inspection/agent_live_debugger_test.exs)

Previous: [Managed Jobs](../04_04_managed_jobs/README.md) | Next: [Agent Observation](../04_07_agent_observation/README.md)
