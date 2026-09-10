# 04_07 Agent Observation

An external collector distinguishes successful Turns from committed Directive failures.

## What you will learn

- How to attach to semantic Jido telemetry events before Agent startup.
- How terminal event metadata reports status, stage, commit, and revision.

## Read the code

Read [the observed Agent](turn_observation.ex), then the shared
[EventProbe](../support/event_probe.ex), and then the behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_07_agent_observation --include example --seed 0
```

Expected result: one event reports a successful commit and another reports a
post-commit Directive failure without exposing private Agent state.

## Important behavior

The Agent emits no application telemetry and contains no observer callback.
The collector attaches and detaches outside the operation that it observes.

## Limits

The finite ETS probe is not a production exporter and has no queue or
backpressure contract.

## Files

- [Agent](turn_observation.ex)
- [Shared EventProbe](../support/event_probe.ex)
- [Demo](demo.exs)
- [Semantic boundary demo](semantic_boundaries.exs)
- [Tests](../../../test/examples/04_runtime/04_07_agent_observation/agent_observation_test.exs)

Previous: [State Recovery](../04_06_state_recovery/README.md) | Next: [Causal Trace](../04_08_causal_trace/README.md)
