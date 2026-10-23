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

Expected result: both Turn events report successful commits. A separate
effects event reports the later Directive failure without exposing private
Agent state.

The standalone collector also prints the public metric names:

```sh
MIX_ENV=test mix run examples/04_runtime/04_07_agent_observation/demo.exs
```

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
- [Tests](../../../test/examples/04_runtime/04_07_agent_observation/agent_observation_test.exs)

Turn commit and effect dispatch have separate results. Inspect the Turn event
for the commit and `[:jido, :agent_server, :effects, :stop]` for delivery failure.

`Jido.Telemetry.metrics/0` supplies current AgentServer counters and Turn
and persistence duration summaries. Lifecycle, commit, effects, and settlement
are point events with counters only. `turn.settled` records the commit result;
`effects.stop` can report a later failure without undoing it. See the
[metric guide](../../../guides/observe-agent-turns.livemd).

Previous: [Runtime Inspection](../04_05_runtime_inspection/README.md) | Next: [Causal Trace](../04_08_causal_trace/README.md)
