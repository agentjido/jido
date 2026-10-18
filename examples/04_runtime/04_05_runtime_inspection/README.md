# 04_05 Runtime Inspection

A debugger reads committed Agent state and runtime phase through public APIs.

## What you will learn

- How `agent/2`, `snapshot/2`, and `status/2` describe a running Agent.
- How `plugin_state/3` and `children/2` expose bounded public runtime views.
- How to enable, read, and bound the debug history.
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

Debug history is off by default. Start with `debug: true` to collect terminal
Turn summaries. `debug_max_events:` sets the bound. `history/1` returns entries
in commit order. Entries exclude Agent state and full Signals.

## Limits

The redaction policy is application code. The example selects public domain
fields instead of copying and then removing known secrets. Jido does not infer
which domain fields are secret. Semantic Telemetry remains in the next lesson.

## Files

- [Source](agent_live_debugger.ex)
- [Tests](../../../test/examples/04_runtime/04_05_runtime_inspection/agent_live_debugger_test.exs)

Previous: [Managed Jobs](../04_04_managed_jobs/README.md) | Next: [Agent Observation](../04_07_agent_observation/README.md)
