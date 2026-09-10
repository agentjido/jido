# 04_08 Causal Trace

A parent and two child Agents keep one trace across work and result Signals.

## What you will learn

- How spawn, child work, and parent result Turns retain causal metadata.
- How an external collector correlates work without changing business Signals.

## Read the code

Read [the parent Agent](causal_trace.ex), then the [worker Agent](worker.ex), the
shared [EventProbe](../support/event_probe.ex), and the behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_08_causal_trace --include example --seed 0
```

Expected result: the parent, child, and result Turns share one trace ID with the
expected parent span relationships.

## Important behavior

The Agents return business state and Directives only. Jido adds the trace and
causal fields to runtime events.

## Limits

The example test runs locally. Core tests cover the same causal contract across
connected Erlang nodes.

## Files

- [Parent Agent](causal_trace.ex)
- [Worker Agent](worker.ex)
- [Shared EventProbe](../support/event_probe.ex)
- [Tests](../../../test/examples/04_runtime/04_08_causal_trace/causal_trace_test.exs)

Previous: [Agent Observation](../04_07_agent_observation/README.md) | Next: [Recoverable Delivery](../04_09_recoverable_delivery/README.md)
