# Seeing What Happened

**After:** You can see what your agent did via logs and telemetry.

When your agent runs, Jido emits telemetry events and structured logs automatically. This guide shows you how to observe agent behavior during development.

## Quick Start: Enable Debug Logging

Add this to `config/dev.exs`:

```elixir
config :logger, level: :debug
```

Now when you run `cmd/2` or start an `AgentServer`, you'll see structured log output.

## What Gets Logged

When you execute a command:

```elixir
{agent, directives} = MyAgent.cmd(agent, {SomeAction, %{value: 42}})
```

You'll see output like:

```
[debug] [Agent] Command started agent_id="agent_abc123" agent_module=MyAgent action="{SomeAction, %{value: 42}}"
[debug] [Agent] Command completed agent_id="agent_abc123" duration_μs=1234 directive_count=2
```

AgentServer operations log signal processing:

```
[debug] [AgentServer] Signal processing started agent_id="agent_abc123" signal_type="jido.agent.cmd"
[debug] [AgentServer] Signal processing completed agent_id="agent_abc123" duration_μs=5678 directive_count=1
```

## Telemetry Events

Jido emits these events automatically:

| Event | When |
|-------|------|
| `[:jido, :agent, :cmd, :start]` | `cmd/2` begins |
| `[:jido, :agent, :cmd, :stop]` | `cmd/2` completes |
| `[:jido, :agent, :cmd, :exception]` | `cmd/2` raises |
| `[:jido, :agent_server, :signal, :start]` | Signal processing begins |
| `[:jido, :agent_server, :signal, :stop]` | Signal processing completes |
| `[:jido, :agent_server, :directive, :start]` | Directive execution begins |
| `[:jido, :agent_server, :directive, :stop]` | Directive execution completes |
| `[:jido, :agent, :strategy, :cmd, :start]` | Strategy executes command |
| `[:jido, :agent, :strategy, :cmd, :stop]` | Strategy command completes |

All events include metadata:

- `:agent_id` — the agent's unique identifier
- `:agent_module` — the agent module name
- `:duration` — execution time (nanoseconds, on `:stop` events)
- `:directive_count` — number of directives produced

## Attach a Handler

Attach your own telemetry handler to collect metrics or log in your preferred format:

```elixir
defmodule MyApp.JidoMetrics do
  require Logger

  def setup do
    :telemetry.attach_many(
      "my-jido-handler",
      [
        [:jido, :agent, :cmd, :stop],
        [:jido, :agent, :cmd, :exception],
        [:jido, :agent_server, :signal, :stop]
      ],
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:jido, :agent, :cmd, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info("Agent command completed",
      agent_id: metadata.agent_id,
      duration_ms: duration_ms,
      directives: metadata.directive_count
    )
  end

  def handle_event([:jido, :agent, :cmd, :exception], _measurements, metadata, _config) do
    Logger.error("Agent command failed",
      agent_id: metadata.agent_id,
      error: inspect(metadata.error)
    )
  end

  def handle_event([:jido, :agent_server, :signal, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info("Signal processed",
      agent_id: metadata.agent_id,
      signal_type: metadata.signal_type,
      duration_ms: duration_ms
    )
  end
end
```

Call `MyApp.JidoMetrics.setup()` in your application startup.

## Correlation IDs

Jido automatically correlates signals across a processing chain. When trace context is active, telemetry metadata includes:

- `:jido_trace_id` — shared across the entire call chain
- `:jido_span_id` — unique to the current operation
- `:jido_parent_span_id` — the parent operation that triggered this one
- `:jido_causation_id` — the signal ID that caused this signal

Use these to trace a request through multiple agents or action chains:

```elixir
def handle_event(event, measurements, metadata, _config) do
  if trace_id = metadata[:jido_trace_id] do
    Logger.metadata(trace_id: trace_id)
  end

  # Your logging/metrics code
end
```

## Local Introspection (Debug Mode)

For quick debugging without setting up telemetry handlers, AgentServer has a built-in debug mode that records recent events in memory:

```elixir
{:ok, pid} = MyApp.Jido.start_agent(MyAgent, debug: true)

# ... run some operations ...

{:ok, events} = Jido.AgentServer.recent_events(pid, limit: 10)
```

See [Runtime - Debug Mode](runtime.md#debug-mode) for details.

## Next Steps

This guide covers development observability. For production monitoring with custom metrics, OpenTelemetry integration, and performance dashboards, see [Observability](observability.md).

Key modules:

- `Jido.Telemetry` — built-in telemetry handler and event definitions
- `Jido.Observe` — unified observability façade with span helpers
- `Jido.Tracing.Context` — correlation ID propagation
