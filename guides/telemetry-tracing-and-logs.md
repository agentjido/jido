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
owned Directive attempts finish. A committed Turn can therefore have an OK
Turn result and a failed settlement.

Lifecycle operations are `activate`, `stop`, `hibernate`, and `thaw`.
Persistence operations are `load`, `compare_and_swap`, and `delete`. Local
Topology operations are `activate`, `repair`, and `cleanup`.

## Use safe fields

Every semantic event contains `schema_version: 1`. Applicable Agent events
contain the Agent Ref projection:

- `agent_namespace`
- `agent_partition`
- `agent_id`

The current `jido_instance` and `partition` fields remain during migration.
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

## Use default metrics

`Jido.Telemetry.metrics/0` returns count and duration metrics from semantic
events. It uses only fixed operation, status, stage, reason, and component tags.

`Jido.Telemetry.legacy_metrics/0` keeps the three old Agent Server metric
definitions during migration.

## Configure semantic logs

Set the semantic log mode in the Jido telemetry configuration:

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

When no semantic mode is set, the old `log_level: :trace` maps to `:all`, and
`:debug` maps to `:interesting`. The old Signal and Directive logger remains
available.

## Keep handlers fast

Telemetry calls handlers in the emitting process. A handler must not call the
observed Agent or do direct network or storage I/O. Copy the bounded event to a
consumer process and return. A failing handler must not change the runtime
result.

## Transfer trace context

Signals keep the complete portable W3C carrier across process, node, queue,
and durable boundaries. Jido-owned Tasks explicitly attach the captured local
context and restore the earlier context after they finish. Lower packages own
context transfer for Tasks that they start.

## Connect OpenTelemetry

Jido Core has no OpenTelemetry dependency and starts no SDK or exporter. A host
bridge can translate the semantic event catalog. It must end a Turn span at the
live result and report settlement as a later correlated fact.

The host owns the OpenTelemetry API and SDK, sampling, exporters, collectors,
credentials, and vendor configuration. Do not use old Agent Server events,
`Jido.Observe` callbacks, or debug history as a second span source.

## Keep compatibility paths separate

`Jido.Observe`, old Agent Server events, tracing helpers, old logging, and the
bounded debug buffer remain available. No removal is part of this seam. The
strict tracer mode of `Jido.Observe` is also not part of semantic runtime
emission.
