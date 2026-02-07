# Debugging

**After:** You can systematically debug agent behavior using instance-scoped debug mode, ring buffers, and telemetry.

## Quick Reference

| I need to… | Do this |
|------------|---------|
| See what happened | `MyApp.Jido.debug(:on)` + `recent/2` |
| See full detail / action args | `MyApp.Jido.debug(:verbose)` |
| Collect production metrics | Telemetry handlers + metrics backend |
| Correlate across agents | Trace context + `jido_trace_id` |

## Step 0: Logger Configuration

`Jido.Debug` does **not** change the global Logger level. You must ensure Logger allows debug messages through:

```elixir
# config/dev.exs
config :logger, level: :debug

config :logger, :default_formatter,
  format: "[$level] $message $metadata\n",
  metadata: [:agent_id, :agent_module, :jido_instance, :jido_trace_id, :jido_span_id]
```

Without `level: :debug`, Logger discards debug messages before Jido sees them.

## Instance-Scoped Debug

The primary workflow for development debugging. Toggle debug mode on a running instance:

```elixir
MyApp.Jido.debug(:on)       # developer-friendly verbosity
MyApp.Jido.debug(:verbose)  # maximum detail — trace-level, full args
MyApp.Jido.debug(:off)      # back to configured defaults
MyApp.Jido.debug()          # query current level => :off
MyApp.Jido.debug_status()   # full status map with active overrides
```

### Debug Levels

| Level | Telemetry `log_level` | `log_args` | `debug_events` | Ring buffer |
|-------|----------------------|------------|----------------|-------------|
| `:off` | config value | config value | config value | per-agent opt-in |
| `:on` | `:debug` | `:keys_only` | `:minimal` | all agents in instance |
| `:verbose` | `:trace` | `:full` | `:all` | all agents in instance |

Redaction is never automatically disabled. Explicit opt-in only:

```elixir
MyApp.Jido.debug(:verbose, redact: false)
```

> **Security warning:** Never disable redaction in production.

### Boot-Time Config

Enable debug at startup without IEx interaction:

```elixir
# config/dev.exs
config :my_app, MyApp.Jido, debug: true   # or :verbose
```

## Config Resolution Order

For any observability setting, `Jido.Observe.Config` resolves in this order:

1. **`Jido.Debug` runtime override** — `persistent_term`, per-instance
2. **Per-instance app config** — `config :my_app, MyApp.Jido, telemetry: [...]`
3. **Global app config** — `config :jido, :telemetry` / `config :jido, :observability`
4. **Hardcoded default**

When `instance` is `nil`, steps 1–2 are skipped.

```elixir
# Per-instance config tuning (production)
config :my_app, MyApp.PublicJido,
  telemetry: [log_level: :info],
  observability: [debug_events: :off, redact_sensitive: true]

config :my_app, MyApp.InternalJido,
  telemetry: [log_level: :debug, log_args: :full],
  observability: [debug_events: :all, redact_sensitive: false]
```

## Ring Buffer (Recent Events)

Debug mode records events in an in-memory ring buffer for quick inspection:

```elixir
MyApp.Jido.debug(:on)

# ... run some operations ...

{:ok, events} = MyApp.Jido.recent(pid)        # last 500 events
{:ok, events} = MyApp.Jido.recent(pid, 100)   # last 100 events
```

Events are returned newest-first with `:at`, `:type`, and `:data` fields.

- **Default buffer size:** 500 (configurable via `debug_max_events`)
- **Instance debug** enables recording for all agents automatically
- **Per-agent debug** still works independently:

```elixir
{:ok, pid} = MyApp.Jido.start_agent(MyAgent, debug: true)
Jido.AgentServer.set_debug(pid, true)
```

## Telemetry Events

All events carry `:jido_instance` metadata. Key events:

| Event | When |
|-------|------|
| `[:jido, :agent, :cmd, :start\|:stop\|:exception]` | `cmd/2` lifecycle |
| `[:jido, :agent_server, :signal, :start\|:stop]` | Signal processing |
| `[:jido, :agent_server, :directive, :start\|:stop]` | Directive execution |

Attach a handler:

```elixir
:telemetry.attach("my-handler",
  [:jido, :agent, :cmd, :stop],
  fn _event, measurements, metadata, _config ->
    Logger.info("cmd completed",
      agent_id: metadata.agent_id,
      jido_instance: metadata.jido_instance,
      duration_ms: System.convert_time_unit(measurements.duration, :native, :millisecond)
    )
  end,
  nil
)
```

Custom debug events must include `:jido_instance` in metadata for per-instance gating.

See [Observability](observability.md) for the full event reference.

## Correlation & Tracing

Jido propagates these keys through signal processing chains:

| Key | Purpose |
|-----|---------|
| `:jido_trace_id` | Shared across the entire call chain |
| `:jido_span_id` | Unique to the current operation |
| `:jido_parent_span_id` | Parent operation that triggered this one |
| `:jido_causation_id` | Signal ID that caused this signal |

Search logs by trace ID:

```elixir
Logger.metadata(trace_id: metadata[:jido_trace_id])
```

See [Observability](observability.md) for OpenTelemetry integration.

## Common Issues

### Agent hangs / await timeout

```elixir
# Check ring buffer for the last thing that happened
{:ok, events} = MyApp.Jido.recent(pid)

# Timeout errors include diagnostics
{:error, {:timeout, diag}} = Jido.AgentServer.call(pid, signal, 5_000)

# Inspect current agent state and signal queue
Jido.AgentServer.state(pid)
```

### No debug output appearing

1. **Check Logger level** — must be `:debug` in config
2. **Check debug level** — `MyApp.Jido.debug()` should return `:on` or `:verbose`
3. **Custom debug events** need `:jido_instance` in metadata to be gated correctly

### Too much noise

- Use **per-instance** debug instead of global config
- Use `:on` (`:minimal` debug events) instead of `:verbose` (`:all`)
- Tune thresholds:

```elixir
config :my_app, MyApp.Jido,
  telemetry: [
    slow_signal_threshold_ms: 500,
    slow_directive_threshold_ms: 200
  ]
```

### Debug state leaking in tests

`Jido.Debug` uses `:persistent_term` — state persists across test cases if not reset.

```elixir
setup do
  on_exit(fn -> Jido.Debug.reset(jido) end)
end
```

## Related

- [Seeing What Happened](observability-intro.md)
- [Observability](observability.md)
- [Runtime — Debug Mode](runtime.md#debug-mode)
- [Testing](testing.md#debugging-failing-tests)
