# Telemetry, tracing, and logs

Jido reports runtime work through version-1 semantic Telemetry events. These
events describe work. They do not authorize work, change a result, or provide a
durable audit record.

## Use semantic events

Jido emits these event families:

```elixir
[:jido, :agent, :lifecycle, event]
[:jido, :agent, :turn, event]
[:jido, :agent, :commit, event]
[:jido, :agent, :directive, event]
[:jido, :agent, :turn, :settled]
[:jido, :agent, :admission, :rejected]
[:jido, :persistence, :operation, event]
[:jido, :topology, :operation, event]
```

For a span, `event` is `:start`, `:stop`, or `:exception`. A returned failure
uses `:stop`. An error, throw, or exit that escapes the boundary uses
`:exception`.

A successful Turn span ends when its commit becomes live. Directive work can
finish later. `turn.settled` reports the terminal public Outcome after all
owned Directive attempts finish. A committed Turn can have an OK Turn result
and a failed settlement.

Lifecycle operations are `activate`, `stop`, `hibernate`, and `thaw`.
Persistence operations are `load`, `compare_and_swap`, and `delete`. Local
Topology operations are `activate`, `repair`, and `cleanup`.

## Use safe fields

Every semantic event contains `schema_version: 1`. Applicable Agent events
contain the Agent Ref projection:

- `agent_namespace`
- `agent_partition`
- `agent_id`

Activation, Turn, source Signal, effective Signal, trace parent, and Signal
causation IDs have separate fields.

Errors use bounded `error_type`, `error_code`, and `retryable?` fields. A code
appears only when `Jido.Error.code/1` recognizes it. Events do not include an
error message or error details.

Durations, counts, capacity, and revisions are integer measurements. Do not use
Agent, Signal, trace, topology, node, or error IDs as default metric tags.

The semantic boundary omits state, payloads, caller context, checkpoints,
records, encoded keys, raw errors, stacktraces, process handles, credentials,
arbitrary application metadata, and OpenTelemetry `tracestate`.

## Use metrics and logs

`Jido.Telemetry.metrics/0` returns count and duration metrics from semantic
events. It uses only fixed operation, status, stage, reason, and component tags.

Set the semantic log mode in the Jido configuration:

```elixir
config :jido, :telemetry,
  semantic_log_mode: :interesting,
  semantic_slow_threshold_ms: 250
```

The modes are:

- `:off` logs no semantic event.
- `:errors` logs non-OK terminal facts.
- `:interesting` also logs operations at or over the slow threshold.
- `:all` logs every terminal semantic fact.

`MyApp.Jido.debug(:on)` sets `:interesting` for that Jido instance.
`MyApp.Jido.debug(:verbose)` sets `:all`. The instance setting has priority
over the global semantic log mode.

Telemetry calls handlers in the emitting process. A handler must not call the
observed Agent or do direct network or storage I/O. Copy the bounded event to a
consumer process and return.

## Enable OpenTelemetry

Jido declares `opentelemetry_api` as an optional dependency. A host that wants
OpenTelemetry must add the API and SDK to its own dependencies:

```elixir
{:opentelemetry_api, "~> 1.0"},
{:opentelemetry, "~> 1.0"}
```

The host must start and configure the SDK. The host also owns sampling,
exporters, collectors, credentials, resources, and vendor configuration. Jido
does not add or start the SDK, and it does not do export work in a Telemetry
handler.

When an SDK tracer is available, Jido maps the semantic catalog directly to
OpenTelemetry:

- Agent Turn becomes `jido.agent.turn`.
- Agent Directive becomes `jido.agent.directive`.
- Agent lifecycle includes the bounded operation, such as
  `jido.agent.lifecycle.activate`.
- Persistence and Topology replace `operation` with the bounded operation,
  such as `jido.persistence.load`.
- `turn.settled` becomes a zero-duration span with a link to its completed Turn
  span.

Jido sends only the bounded semantic fields as `jido.*` attributes. A failed
operation gets OpenTelemetry error status. An escaping fault adds a safe
`exception` event with type and kind only. Jido does not add the raw reason,
message, or stacktrace.

Disable this mapping without disabling semantic Telemetry:

```elixir
config :jido, :opentelemetry, enabled: false
```

If the optional API or an SDK tracer is absent, the OpenTelemetry path is a
no-op. Semantic Telemetry, metrics, and logs continue to work.

## Transfer trace context

Signals keep the complete portable W3C carrier across process, node, queue,
and durable boundaries. Jido extracts this carrier before it starts semantic
spans and injects the active OpenTelemetry span into outgoing Signals.

Jido-owned Tasks capture and attach the full process-local OpenTelemetry
context. They restore the earlier context after they finish. Lower packages
own context transfer for Tasks that they start.
