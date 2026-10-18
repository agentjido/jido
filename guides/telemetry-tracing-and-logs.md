# Telemetry, Tracing, and Logs

Use `Jido.Telemetry.metrics/0` for the standard metric catalog. Attach Telemetry
handlers for event observation. Use a host-managed OpenTelemetry SDK for traces.
Observation is best effort and is not a durable audit record.

## Current events

AgentServer events use the `[:jido, :agent_server]` prefix.

| Event suffix | Meaning | Metric |
| --- | --- | --- |
| `[:lifecycle, :start]` | Server starts | Count |
| `[:lifecycle, :stop]` | Server stops | Count |
| `[:turn, :start]` | Turn starts | None |
| `[:turn, :stop]` | Evaluation and commit result | Count and duration |
| `[:commit]` | Committed state becomes live | Count |
| `[:directives, :returned]` | Committed Turn returns Directives | Count |
| `[:turn, :settled]` | Evaluation and commit result is recorded | Count |
| `[:effects, :start]` | Owned effects start | Count |
| `[:effects, :stop]` | Owned effects finish | Count |

Turn stop and settlement can occur before effects finish. Use effects stop to
observe the effects result. A failed effect does not undo a committed revision.
Settlement and effects are point events; neither has a duration measurement.
The returned-Directives counter counts events, including events with zero
Directives. Read the `directive_count` measurement for the number of Directives.

Persistence emits `[:jido, :persistence, :operation, ending]`, where `ending` is
`:start`, `:stop`, or `:exception`. Both terminal events have count and duration
metrics. Scheduler emits `[:jido, :scheduler, :delivery]` with a delivery counter.

There are no default metrics for the removed Agent lifecycle spans, commit
spans, Plugin commit notification spans, Directive spans, admission rejection
points, or Topology controller events. AgentServer does not currently emit a
Turn `:exception` event; failed Turns use `:stop` with a non-OK status.

## Attach a handler

```elixir
defmodule MyApp.TurnObserver do
  def handle(event, measurements, metadata, receiver) do
    send(receiver, {:jido_event, event, measurements, metadata})
  end
end

:ok = :telemetry.attach_many(
  "my-turn-observer",
  [
    [:jido, :agent_server, :turn, :stop],
    [:jido, :agent_server, :effects, :stop]
  ],
  &MyApp.TurnObserver.handle/4,
  self()
)

# Remove the handler when it is no longer needed.
:ok = :telemetry.detach("my-turn-observer")
```

Handlers run in the emitting process. Keep them short. Do not call the observed
Server or perform storage or network work in a handler.

Turn metadata includes `agent_id`, `turn_id`, `signal_id`, status, stage, and
available trace IDs. Terminal measurements include `state_version_before`,
`state_version_after`, and `directive_count`. Turn duration uses Erlang native
time units. Persistence metadata can also include namespace, operation, adapter,
and persistence reason. Do not assume every event has every field.

The scalar metadata filter excludes Agent state, Plugin state, Signal data,
Directive data, raw errors, process handles, credentials, and caller context.

## Metrics

```elixir
metrics = Jido.Telemetry.metrics()
```

Pass the list to a `Telemetry.Metrics` compatible reporter. The catalog has
14 definitions. Metric names follow the event name and end in `.count` or
`.duration`. For example:

```elixir
"jido.agent_server.turn.stop.count"
"jido.agent_server.turn.stop.duration"
"jido.agent_server.commit.count"
"jido.agent_server.effects.stop.count"
"jido.persistence.operation.exception.duration"
"jido.scheduler.delivery.count"
```

Duration summaries convert native units to milliseconds. Point events have
counters only. Tags use bounded `status`, `stage`, `operation`,
`persistence_reason`, and `scheduler_outcome` values. Default tags do not include
Agent, Signal, Turn, trace, module, or error IDs.

A host can define a revision gauge separately:

```elixir
Telemetry.Metrics.last_value("my_app.agent.revision",
  event_name: [:jido, :agent_server, :turn, :stop],
  measurement: :state_version_after
)
```

## Semantic logs

Jido attaches its semantic log handler at application startup. It uses the same
event names as the metric catalog. Configure it with:

```elixir
config :jido, :telemetry,
  semantic_log_mode: :interesting,
  semantic_slow_threshold_ms: 250
```

| Mode | Output |
| --- | --- |
| `:off` | No semantic log entries |
| `:errors` | Non-OK status and exception events |
| `:interesting` | Errors and events at or above the slow threshold |
| `:all` | All catalog events, including lifecycle and effects start points |

The default mode is `:off`. The default slow threshold is 1,000 milliseconds.
`Jido.Debug.enable(instance, :verbose)` selects `:all` for events emitted within
that instance's semantic log scope. `Jido.Debug.disable(instance)` removes the
override. Metadata filtering still applies.

## OpenTelemetry

The host must supply the optional `opentelemetry_api` dependency and start and
configure its own SDK. The host owns sampling, resources, export, and storage.
Jido does not start an SDK or export trace data itself.

```elixir
Jido.Telemetry.open_telemetry?()
```

The result is false when the API is absent, mapping is disabled, or the active
tracer is a no-op tracer. Telemetry events, metrics, and logs still work.

```elixir
config :jido, :opentelemetry, enabled: false
```

The Turn span is named `jido.agent_server.turn`. Persistence operation spans
include the operation name. Point events map to instantaneous spans with the
current trace context where available. They do not have metric durations.

Read [Observe Agent Turns](observe-agent-turns.html) for a runnable observer.
