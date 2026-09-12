# Telemetry, tracing, and logs

Jido uses one semantic event catalog for runtime observation. Telemetry
handlers, metric reporters, semantic logs, and the optional OpenTelemetry
mapping all use this catalog.

Observation does not change an Agent result. It does not make work durable and
it does not replace an audit record. An abrupt process or VM failure can prevent
a terminal event.

## Select the correct tool

| Need | Tool |
| --- | --- |
| Inspect one committed Agent | `Jido.AgentServer.agent/1` |
| Inspect the committed Agent and revision | `Jido.AgentServer.snapshot/1` |
| Inspect current runtime work | `Jido.AgentServer.status/1` |
| Keep a short history for one Agent | Agent debug buffer |
| Observe runtime work across Agents | Semantic Telemetry events |
| Build standard runtime metrics | `Jido.Telemetry.metrics/0` |
| Correlate work across services | Optional OpenTelemetry mapping |
| Record durable business or security facts | Application audit records |

See [Runtime State and Debugging](runtime-state-and-debugging.html) for the
inspection APIs and the Agent debug buffer.

## Understand one Turn

An admitted Signal starts one Agent Turn span. The Turn evaluates a candidate
Agent and then attempts one commit.

If evaluation or commit fails, the Turn ends without a new live revision. Jido
then emits the terminal `turn.settled` event.

If commit succeeds, Jido makes the candidate Agent live and ends the Turn span.
The caller can receive the committed Agent while post-commit Directive work is
still active. Each Directive has its own span. Jido emits `turn.settled` after
all owned Directive attempts stop.

The normal order is:

```text
agent.turn.start
  agent.commit.start
  agent.commit.stop
agent.turn.stop              committed Agent is live
  agent.directive.start      zero or more Directives
  agent.directive.stop
agent.turn.settled           terminal bounded result
```

A Directive failure does not undo a successful commit. Use `committed?`,
`status`, `stage`, and the state revisions to distinguish a pre-commit failure
from a post-commit failure.

## Event catalog

Span families use `:start` and one terminal event. A returned failure uses
`:stop`. An error, throw, or exit that escapes the observed boundary uses
`:exception`. Point events have no matching start event.

| Family | Event | Main metadata | Main measurements |
| --- | --- | --- | --- |
| Agent lifecycle | `[:jido, :agent, :lifecycle, event]` | Agent identity, `operation`, `status`, `activation_id` | `duration`, `state_version` |
| Definition upgrade | `[:jido, :agent, :definition_upgrade, event]` | Agent identity, source and target Agent modules, `status` | `duration`, revisions |
| Turn result | `[:jido, :agent, :turn, event]` | Turn, Signal, trace, `status`, `stage`, `committed?` | `duration`, revisions, `directive_count` |
| Commit | `[:jido, :agent, :commit, event]` | Turn identity, `status`, `stage` | `duration` |
| Directive | `[:jido, :agent, :directive, event]` | Turn identity, `directive_module`, `status` | `duration`, `directive_index` |
| Turn settlement | `[:jido, :agent, :turn, :settled]` | Turn identity, `status`, `stage`, `committed?` | total `duration`, revisions, Directive counts |
| Admission rejection | `[:jido, :agent, :admission, :rejected]` | Agent and Signal identity, `admission_reason` | `queue_depth`, `queue_limit` |
| Persistence | `[:jido, :persistence, :operation, event]` | Agent identity, `operation`, `adapter_module`, `persistence_reason` | `duration`, revisions |
| Local Topology | `[:jido, :topology, :operation, event]` | `topology_id`, `topology_operation`, `status` | `duration`, component counts |
| Scheduler delivery | `[:jido, :scheduler, :delivery]` | `scheduler_outcome`, `status` | `count` |

Fields can be absent when they do not apply. Every event contains
`schema_version: 1`.

Lifecycle operations are `:activate`, `:stop`, `:hibernate`, and `:thaw`.
Persistence operations are `:load`, `:compare_and_swap`, and `:delete`.
Topology operations are `:activate`, `:repair`, and `:cleanup`.

Public status values are `:ok`, `:error`, `:cancelled`, `:timed_out`,
`:conflict`, `:indeterminate`, `:not_found`, and `:rejected`. Public Turn stages
are `:evaluate`, `:commit`, and `:directive`.

## Attach a handler

Use `:telemetry.attach_many/4` when one consumer needs more than one event.
The handler runs in the process that emits the event. It must return quickly.
It must not call the observed Agent or do storage or network work.

```elixir
defmodule MyApp.JidoObserver do
  def handle(event, measurements, metadata, receiver) do
    send(receiver, {:jido_event, event, measurements, metadata})
  end
end

events = [
  [:jido, :agent, :turn, :stop],
  [:jido, :agent, :turn, :exception],
  [:jido, :agent, :turn, :settled],
  [:jido, :agent, :admission, :rejected]
]

:ok =
  :telemetry.attach_many(
    "my-app-jido-observer",
    events,
    &MyApp.JidoObserver.handle/4,
    self()
  )
```

Detach the handler when its owner stops:

```elixir
:ok = :telemetry.detach("my-app-jido-observer")
```

Use `agent_namespace`, `agent_partition`, and `agent_id` to select one logical
Agent. Use `activation_id` to select one live activation and `turn_id` to
select one Turn.

For an executable example, see [Observe Agent Turns](observe-agent-turns.html).

## Safe metadata

Jido applies one strict allowlist before it emits an event. The public fields
can include:

- Agent identity: `agent_namespace`, `agent_partition`, and `agent_id`.
- Runtime identity: `agent_module`, `target_agent_module`, and `activation_id`.
- Turn and Signal identity: `turn_id`, `source_signal_id`, `signal_id`, and
  `signal_type`.
- Trace and cause identity: `trace_id`, `span_id`, `parent_span_id`,
  `causation_id`, `cause_turn_id`, and `child_activation_id`.
- Result fields: `status`, `stage`, `kind`, `committed?`, `error_type`,
  `error_code`, and `retryable?`.
- Operation fields for Directive, persistence, Topology, and Scheduler work.

IDs and types have a maximum size of 256 bytes. An Agent partition has a
maximum size of 128 bytes. Invalid UTF-8 and invalid values are omitted.

Measurements contain integer times, durations, revisions, queue sizes, and
counts. Times and durations in raw events use the Erlang native time unit.

Events do not contain Agent state, Plugin-owned state, Signal data, Directive
data, caller context, checkpoints, persistence records, encoded keys, raw
errors, error messages, stacktraces, PIDs, references, credentials, or
arbitrary application metadata.

`error_code` is present only for a code that `Jido.Error.code/1` recognizes.
Telemetry does not contain the full error returned to the caller.

## Metrics

`Jido.Telemetry.metrics/0` returns `Telemetry.Metrics` definitions. Pass this
list to a compatible reporter in the host application:

```elixir
metrics = Jido.Telemetry.metrics()
```

The list contains count and duration metrics for both `:stop` and `:exception`
events from these span families:

- Agent lifecycle
- Definition upgrade
- Turn result
- commit
- Directive
- persistence
- local Topology

It also contains settlement count and duration, admission rejection count, and
Scheduler delivery count. Duration summaries convert the Erlang native unit to
milliseconds.

Default metric tags use only `operation`, `status`, `stage`,
`admission_reason`, `persistence_reason`, `topology_operation`, and
`scheduler_outcome`. They do not use Agent, Signal, Turn, trace, Topology,
module, or error IDs. A host can build a separate high-cardinality view when it
needs one.

## Semantic logs

Jido attaches its semantic log handler when the Jido application starts.
Configure its global mode as follows:

```elixir
config :jido, :telemetry,
  semantic_log_mode: :interesting,
  semantic_slow_threshold_ms: 250
```

| Mode | Output |
| --- | --- |
| `:off` | No semantic log entries |
| `:errors` | Non-OK terminal events and exceptions |
| `:interesting` | Error entries and operations at or above the slow threshold |
| `:all` | All terminal semantic events |

The default mode is `:off`. The default slow threshold is 1,000 milliseconds.
The logger does not log span start events.

`MyApp.Jido.debug(:on)` selects `:interesting` for that Jido instance.
`MyApp.Jido.debug(:verbose)` selects `:all`, and
`MyApp.Jido.debug(:off)` removes the instance override. This control changes
semantic log detail. It does not enable the Agent debug buffer and it does not
weaken metadata filtering.

## OpenTelemetry

Jido declares `opentelemetry_api` as an optional dependency. A host that wants
traces must add the API and SDK to its own dependencies:

```elixir
defp deps do
  [
    {:jido, "~> 3.0"},
    {:opentelemetry_api, "~> 1.0"},
    {:opentelemetry, "~> 1.0"}
  ]
end
```

The host must start and configure the SDK. The host also owns its sampler,
resource, exporter, collector, credentials, storage, dashboards, and alerts.
Jido does not start an SDK and does not export trace data.

Use this check after the host starts the SDK:

```elixir
Jido.Telemetry.open_telemetry?()
```

The result is `false` when the optional API is absent, the Jido mapping is
disabled, or the active tracer is a no-op tracer. Semantic Telemetry, metrics,
and logs continue to work in all three cases.

Disable only the Jido mapping as follows:

```elixir
config :jido, :opentelemetry, enabled: false
```

### Span mapping

| Semantic work | OpenTelemetry span name |
| --- | --- |
| Agent lifecycle | `jido.agent.lifecycle.<operation>` |
| Definition upgrade | `jido.agent.definition_upgrade` |
| Turn result | `jido.agent.turn` |
| Commit | `jido.agent.commit` |
| Directive | `jido.agent.directive` |
| Persistence | `jido.persistence.<operation>` |
| Local Topology | `jido.topology.<operation>` |
| Turn settlement | `jido.agent.turn.settled` |
| Admission rejection | `jido.agent.admission.rejected` |
| Scheduler delivery | `jido.scheduler.delivery` |

Point events become zero-duration spans. The settlement span has a link to its
completed Turn span. Jido maps only safe semantic fields to `jido.*`
attributes. A non-OK operation, except cancellation, gets OpenTelemetry error
status. An escaping fault adds an exception event with only its safe type and
kind.

## Trace context on Signals

`Jido.Signal.Trace` owns the public W3C carrier. Signals store `traceparent`
and optional `tracestate` values in their CloudEvents context attributes.

```elixir
signal = Jido.Signal.new!("orders.requested", %{}, source: "/orders")
trace = Jido.Signal.Trace.new(trace_flags: "01")
{:ok, signal} = Jido.Signal.Trace.put(signal, trace)

Jido.Signal.Trace.get(signal)
```

When a Signal has a valid carrier, its span becomes the parent of the new Agent
Turn span. An untraced Signal starts a local root span, and the host SDK makes
the sampling decision. An outgoing Signal carries the current Turn span.

Trace parentage and Signal causation are separate. `parent_span_id` describes
the trace graph. `causation_id` identifies the Signal that caused the outgoing
Signal.

Jido-owned Tasks capture and attach the current process context. They restore
the earlier context after they stop. A lower package must transfer context for
Tasks that it starts.

## Operating rules

- Keep Telemetry handlers small and non-blocking.
- Do not use telemetry or debug history as an audit record.
- Do not use high-cardinality IDs as default metric tags.
- Do not add application state or payloads to the Jido event catalog.
- Configure exporters and credentials only in the host application.
- Use `turn.settled` when you need the final Directive result.
- Use the Turn `:stop` event when you need the time at which a commit became
  live.
