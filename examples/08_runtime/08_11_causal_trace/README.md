# 08_11 Causal Trace

A parent and two child Agents keep one trace across work and result Signals.

## What you will learn

- How `agent_start`, `agent_send`, and `parent_send` retain causal metadata.
- How an external collector correlates work without changing business Signals.

## Read the code

Read [the parent Agent](causal_trace.ex), then the [worker Agent](worker.ex), the
shared [EventProbe](../support/event_probe.ex), and the behavior test.

## Run it

```sh
mix test.examples examples/08_runtime/08_11_causal_trace
```

Expected result: the parent, child, and result Turns share one trace ID with the
expected parent span relationships.

## Important behavior

The Agents return business state and Directives only. Jido adds the trace and
causal fields to runtime events.

## Limits

The example proves local causal propagation only. It does not prove remote
Agent placement or cross-node lifecycle guarantees.

## Files

- [Parent Agent](causal_trace.ex)
- [Worker Agent](worker.ex)
- [Shared EventProbe](../support/event_probe.ex)
- [Tests](causal_trace_test.exs)

Previous: [Agent Observation](../08_10_agent_observation/README.md) |
Next: [Definition Changes and Diff](../08_12_definition_changes/README.md)
