# Telemetry, Tracing, and Logs

Jido reports actor work through semantic telemetry events. It also supplies a
tracer boundary, selective logs, and a bounded local debug buffer. These tools
describe runtime work. They are not a durable audit journal.

## Semantic actor events

Live actors emit events with this shape:

```elixir
[:jido, :agent, boundary, event]
```

The boundary is `:lifecycle`, `:turn`, `:commit`, or `:directive`. The event is
`:start`, `:stop`, or `:exception`.

`[:jido, :agent, :turn, :settled]` reports one terminal Turn outcome after all
Directive work ends or fails. A successful Turn span ends at commit. The
settlement event can report a later failure with `committed?: true`.

Important metadata includes:

- Agent module, ID, instance, partition, and activation ID
- source Signal ID, effective Signal ID, and Signal type
- Turn, trace, span, causation, and parent span IDs
- status, stage, error type, and retryability
- the `:committed?` flag

Measurements include duration, state revisions, and Directive counts. Jido does
not include state, payloads, raw error details, PIDs, or caller context in these
semantic events.

An abrupt process or VM loss can prevent final events. Export telemetry to your
monitoring system if you need data outside the current node.

## Keep handlers fast

Telemetry calls handlers in the emitting actor process. A slow handler adds
latency to the actor. Copy the bounded event to an exporter process and return
quickly. Do not make a network call in the handler.

Use stable fields such as `jido_instance`, `agent_module`, `signal_type`,
`status`, and `stage` as metric tags. Do not use IDs as low-cardinality metric
tags.

## Connect a tracer

Implement `Jido.Observe.Tracer` to connect OpenTelemetry or another tracing
system. The behavior has callbacks to start, stop, and fail spans. The default
`Jido.Observe.NoopTracer` does no external work.

```elixir
config :my_app, MyApp.Jido,
  observability: [
    tracer: MyApp.JidoTracer,
    tracer_failure_mode: :warn,
    redact_sensitive: true
  ]
```

Use `:warn` when a tracer failure must not stop Agent work. Use `:strict` only
when observability failure must fail the operation.

## Configure logs

Jido can log slow or selected Signal and Directive events. Configure thresholds
for each instance:

```elixir
config :my_app, MyApp.Jido,
  telemetry: [
    log_level: :debug,
    log_args: :keys_only,
    slow_signal_threshold_ms: 25,
    slow_directive_threshold_ms: 10,
    interesting_signal_types: ["order.failed"]
  ]
```

Use `:keys_only` or `:none` in production unless full arguments are safe. Set
`redact_sensitive: true` when your metadata can contain secrets or personal
data.

## Use the debug buffer for investigation

Enable instance debug mode for short investigations:

```elixir
:ok = MyApp.Jido.debug(:on)
{:ok, events} = MyApp.Jido.recent(server, 50)
:ok = MyApp.Jido.debug(:off)
```

The actor keeps a bounded ring buffer. It is local, ephemeral, and not a
replacement for metrics, traces, logs, or domain audit records.
