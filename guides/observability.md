# Observability

**After:** You can monitor Jido agents in production with metrics, traces, and structured logging.

This guide covers production-grade observability for Jido agents. For development debugging, see [Seeing What Happened](observability-intro.md).

## Production Logger Configuration

Configure structured JSON logging for production:

```elixir
# config/prod.exs
config :logger, :default_handler,
  formatter: {
    :logger_formatter_json,
    %{
      template: [:time, :level, :msg, :metadata],
      single_line: true
    }
  }

config :logger,
  level: :info,
  metadata: [:agent_id, :jido_trace_id, :jido_span_id, :jido_instance, :signal_type, :duration_ms]

config :jido, :observability,
  log_level: :info,
  debug_events: :off,
  redact_sensitive: true
```

Per-instance observability tuning allows different Jido instances to use different verbosity and redaction settings:

```elixir
config :my_app, MyApp.PublicJido,
  telemetry: [log_level: :info],
  observability: [debug_events: :off, redact_sensitive: true]

config :my_app, MyApp.InternalJido,
  telemetry: [log_level: :debug, log_args: :full],
  observability: [debug_events: :all, redact_sensitive: false, tracer: MyApp.OtelTracer]
```

Settings resolve in this order: Debug override → instance config → global config → default.
Invalid values are ignored and fall back to Jido defaults.

The `:redact_sensitive` option replaces sensitive data with `[REDACTED]` in logs and telemetry.

## Telemetry Event Reference

Jido emits telemetry events for all core operations. Use these for metrics collection and alerting.

### Agent Events

| Event | Description | Measurements | Metadata |
|-------|-------------|--------------|----------|
| `[:jido, :agent, :cmd, :start]` | Command execution started | `system_time` | `agent_id`, `agent_module`, `action`, `jido_instance` |
| `[:jido, :agent, :cmd, :stop]` | Command completed | `duration`, `directive_count` | `agent_id`, `agent_module`, `directive_count`, `jido_instance` |
| `[:jido, :agent, :cmd, :exception]` | Command failed | `duration` | `agent_id`, `agent_module`, `error`, `stacktrace`, `jido_instance` |

### AgentServer Events

| Event | Description | Measurements | Metadata |
|-------|-------------|--------------|----------|
| `[:jido, :agent_server, :signal, :start]` | Signal processing started | `system_time` | `agent_id`, `signal_type`, `jido_instance` |
| `[:jido, :agent_server, :signal, :stop]` | Signal processing completed | `duration` | `agent_id`, `signal_type`, `directive_count`, `jido_instance` |
| `[:jido, :agent_server, :signal, :exception]` | Signal processing failed | `duration` | `agent_id`, `signal_type`, `error`, `jido_instance` |
| `[:jido, :agent_server, :directive, :start]` | Directive execution started | `system_time` | `agent_id`, `directive_type`, `directive`, `jido_instance` |
| `[:jido, :agent_server, :directive, :stop]` | Directive execution completed | `duration` | `agent_id`, `directive_type`, `directive`, `result`, `jido_instance` |
| `[:jido, :agent_server, :directive, :exception]` | Directive execution failed | `duration` | `agent_id`, `directive_type`, `directive`, `error`, `jido_instance` |
| `[:jido, :agent_server, :queue, :overflow]` | Directive queue overflow | `queue_size` | `agent_id`, `signal_type`, `jido_instance` |

### Strategy Events

| Event | Description | Measurements | Metadata |
|-------|-------------|--------------|----------|
| `[:jido, :agent, :strategy, :init, :start]` | Strategy initialization started | `system_time` | `agent_id`, `strategy`, `jido_instance` |
| `[:jido, :agent, :strategy, :init, :stop]` | Strategy initialization completed | `duration` | `agent_id`, `strategy`, `jido_instance` |
| `[:jido, :agent, :strategy, :init, :exception]` | Strategy initialization failed | `duration` | `agent_id`, `strategy`, `error`, `jido_instance` |
| `[:jido, :agent, :strategy, :cmd, :start]` | Strategy command started | `system_time` | `agent_id`, `strategy`, `jido_instance` |
| `[:jido, :agent, :strategy, :cmd, :stop]` | Strategy command completed | `duration` | `agent_id`, `strategy`, `directive_count`, `jido_instance` |
| `[:jido, :agent, :strategy, :cmd, :exception]` | Strategy command failed | `duration` | `agent_id`, `strategy`, `error`, `jido_instance` |
| `[:jido, :agent, :strategy, :tick, :start]` | Strategy tick started | `system_time` | `agent_id`, `strategy`, `jido_instance` |
| `[:jido, :agent, :strategy, :tick, :stop]` | Strategy tick completed | `duration` | `agent_id`, `strategy`, `jido_instance` |
| `[:jido, :agent, :strategy, :tick, :exception]` | Strategy tick failed | `duration` | `agent_id`, `strategy`, `error`, `jido_instance` |

### Correlation Metadata

When trace context is active, all events include:

- `:jido_trace_id` — shared across the entire call chain
- `:jido_span_id` — unique to the current operation
- `:jido_parent_span_id` — the parent operation
- `:jido_causation_id` — the signal ID that caused this signal

## Metrics Collection

### Prometheus with TelemetryMetricsPrometheus

```elixir
# mix.exs
defp deps do
  [
    {:telemetry_metrics_prometheus, "~> 1.1"}
  ]
end
```

```elixir
# lib/my_app/telemetry.ex
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {TelemetryMetricsPrometheus, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      # Agent command latency histogram
      distribution("jido.agent.cmd.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1000, 2500]],
        tags: [:agent_module]
      ),

      # Command throughput
      counter("jido.agent.cmd.stop.count",
        tags: [:agent_module]
      ),

      # Error rate
      counter("jido.agent.cmd.exception.count",
        tags: [:agent_module]
      ),

      # Signal processing latency
      distribution("jido.agent_server.signal.duration",
        unit: {:native, :millisecond},
        reporter_options: [buckets: [10, 50, 100, 250, 500, 1000]],
        tags: [:signal_type]
      ),

      # Directive execution
      counter("jido.agent_server.directive.stop.count",
        tags: [:directive_type]
      ),

      # Queue overflow events
      counter("jido.agent_server.queue.overflow.count"),

      # Directives per command
      summary("jido.agent.cmd.directive_count",
        tags: [:agent_module]
      )
    ]
  end
end
```

Alternatively, use Jido's built-in metric definitions which include automatic per-instance scoping:

```elixir
children = [
  {TelemetryMetricsPrometheus, metrics: Jido.Telemetry.metrics()}
]
```

Add to your application supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Telemetry,
    # ... other children
  ]

  Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
end
```

### StatsD with TelemetryMetricsStatsd

```elixir
# mix.exs
defp deps do
  [
    {:telemetry_metrics_statsd, "~> 0.7"}
  ]
end
```

```elixir
defmodule MyApp.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {TelemetryMetricsStatsd,
       metrics: metrics(),
       host: System.get_env("STATSD_HOST", "localhost"),
       port: String.to_integer(System.get_env("STATSD_PORT", "8125")),
       prefix: "jido"}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      counter("agent.cmd.count"),
      counter("agent.cmd.exception.count"),
      summary("agent.cmd.duration"),
      counter("agent_server.signal.count"),
      summary("agent_server.signal.duration"),
      counter("agent_server.directive.count"),
      last_value("agent_server.queue.overflow.count")
    ]
  end
end
```

## Custom Telemetry Handler

For custom metrics backends or specialized logging:

```elixir
defmodule MyApp.JidoTelemetryHandler do
  require Logger

  @events [
    [:jido, :agent, :cmd, :start],
    [:jido, :agent, :cmd, :stop],
    [:jido, :agent, :cmd, :exception],
    [:jido, :agent_server, :signal, :start],
    [:jido, :agent_server, :signal, :stop],
    [:jido, :agent_server, :signal, :exception],
    [:jido, :agent_server, :directive, :start],
    [:jido, :agent_server, :directive, :stop],
    [:jido, :agent_server, :directive, :exception],
    [:jido, :agent_server, :queue, :overflow],
    [:jido, :agent, :strategy, :cmd, :start],
    [:jido, :agent, :strategy, :cmd, :stop],
    [:jido, :agent, :strategy, :cmd, :exception]
  ]

  def attach do
    :telemetry.attach_many(
      "my-jido-handler",
      @events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:jido, :agent, :cmd, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    if duration_ms > 1000 do
      Logger.warning("Slow agent command",
        agent_id: metadata.agent_id,
        agent_module: metadata.agent_module,
        jido_instance: metadata[:jido_instance],
        jido_trace_id: metadata[:jido_trace_id],
        jido_span_id: metadata[:jido_span_id],
        duration_ms: duration_ms
      )
    end

    MyMetrics.histogram("jido.cmd.duration", duration_ms, %{
      agent_module: to_string(metadata.agent_module),
      jido_instance: to_string(metadata[:jido_instance])
    })
  end

  def handle_event([:jido, :agent, :cmd, :exception], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.error("Agent command failed",
      agent_id: metadata.agent_id,
      agent_module: metadata.agent_module,
      jido_instance: metadata[:jido_instance],
      jido_trace_id: metadata[:jido_trace_id],
      error: inspect(metadata.error),
      duration_ms: duration_ms
    )

    MyMetrics.increment("jido.cmd.errors", %{
      agent_module: to_string(metadata.agent_module),
      jido_instance: to_string(metadata[:jido_instance])
    })
  end

  def handle_event([:jido, :agent_server, :queue, :overflow], measurements, metadata, _config) do
    Logger.error("Agent queue overflow",
      agent_id: metadata.agent_id,
      jido_instance: metadata[:jido_instance],
      queue_size: measurements.queue_size
    )

    MyMetrics.increment("jido.queue.overflow")
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok
end
```

Call `MyApp.JidoTelemetryHandler.attach()` in your application startup.

## OpenTelemetry Integration

Core `jido` intentionally stays free of direct OpenTelemetry dependencies.
Use a separate package (for example, `jido_otel`) to provide a concrete tracer
implementation, then configure Jido to use that module.

### Quick Start (External `jido_otel` Package)

```elixir
# mix.exs
defp deps do
  [
    {:jido_otel, "~> 0.1"},
    {:opentelemetry_exporter, "~> 1.7"}
  ]
end
```

```elixir
# config/prod.exs
config :jido, :observability,
  tracer: JidoOtel.Tracer,
  log_level: :info,
  redact_sensitive: true,
  tracer_failure_mode: :warn

# OpenTelemetry exporter configuration
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :grpc,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")
```

### Custom Tracer Extensions

For custom backend behavior, you can still implement `Jido.Observe.Tracer` directly:

```elixir
defmodule MyApp.CustomTracer do
  @behaviour Jido.Observe.Tracer

  @impl true
  def span_start(event_prefix, metadata) do
    # Start external span and return tracer context.
  end

  @impl true
  def span_stop(tracer_ctx, measurements) do
    # Complete external span.
    :ok
  end

  @impl true
  def span_exception(tracer_ctx, kind, reason, stacktrace) do
    # Record exception in external tracer.
    :ok
  end

  @impl true
  def with_span_scope(event_prefix, metadata, fun) do
    # Optional sync span scoping callback.
    # Must call `fun.()` exactly once and preserve result/error semantics.
    _ = {event_prefix, metadata}
    fun.()
  end
end
```

### Sync vs Async Tracer Semantics

- `with_span/3` uses optional `with_span_scope/3` when implemented.
- `start_span/2` + finish callbacks remain explicit lifecycle APIs for async work.
- Existing tracers that implement only `span_start/2`, `span_stop/2`, and `span_exception/4` continue to work unchanged.

### Tracer Failure Modes

Use `:tracer_failure_mode` to control callback failures:

- `:warn` (default): isolate tracer failures and continue app flow
- `:strict`: raise immediately when tracer callbacks fail

```elixir
config :jido, :observability,
  tracer: MyApp.CustomTracer,
  tracer_failure_mode: :strict
```

## Correlation IDs and Distributed Tracing

Jido automatically propagates trace context through signal chains via `Jido.Tracing.Context`.

### Extracting Trace IDs

```elixir
defmodule MyApp.RequestHandler do
  require Logger

  def handle_request(conn) do
    # Set correlation ID from incoming request
    trace_id = get_req_header(conn, "x-trace-id") || generate_trace_id()

    Logger.metadata(trace_id: trace_id)

    signal = Signal.new!("process_request", conn.params,
      source: "/api/request",
      extensions: %{
        "jido_ext_trace" => %{
          "trace_id" => trace_id,
          "span_id" => generate_span_id(),
          "parent_span_id" => nil
        }
      }
    )

    {:ok, result} = AgentServer.call(pid, signal)
    result
  end

  defp generate_trace_id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  defp generate_span_id, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
```

### Cross-Agent Tracing

When agents spawn child agents or emit signals to other agents, trace context propagates automatically:

```elixir
def handle_event([:jido, :agent_server, :signal, :stop], _measurements, metadata, _config) do
  Logger.info("Signal processed",
    agent_id: metadata.agent_id,
    signal_type: metadata.signal_type,
    jido_instance: metadata[:jido_instance],
    jido_trace_id: metadata[:jido_trace_id],
    jido_span_id: metadata[:jido_span_id],
    jido_parent_span_id: metadata[:jido_parent_span_id],
    jido_causation_id: metadata[:jido_causation_id]
  )
end
```

## Custom Namespace Events and Spans

### Non-Gated Domain Events (`emit_event/3`)

Use `Jido.Observe.emit_event/3` for production domain lifecycle events that must
always emit telemetry regardless of `:debug_events` config.

`Jido.Observe.EventContract` provides lightweight key validation helpers so
downstream namespaces keep stable metadata/measurement contracts.

```elixir
alias Jido.Observe
alias Jido.Observe.EventContract

with {:ok, validated} <-
       EventContract.validate_event(
         [:jido, :ai, :request, :completed],
         %{duration_ms: 42},
         %{request_id: "req-1", terminal_state: :completed, model: "gpt-4.1"},
         required_metadata: [:request_id, :terminal_state],
         required_measurements: [:duration_ms]
       ) do
  Observe.emit_event(validated.event, validated.measurements, validated.metadata)
end
```

### Async Request Lifecycle Pattern

For long-lived request workflows, use a request-root span plus async child spans.
Propagate correlation metadata across async boundaries, then emit terminal
domain events (`completed`, `failed`, `cancelled`, `rejected`).

Important: OpenTelemetry current-span context is process-local. Across `Task` boundaries,
explicitly propagate only correlation metadata and start/finish spans in the owning process.

```elixir
alias Jido.Observe
alias Jido.Observe.EventContract
alias Jido.Tracing.Context, as: TraceContext

# Root request span
request_span = Observe.start_span([:jido, :ai, :request], %{request_id: request_id})
trace_metadata = TraceContext.to_telemetry_metadata()

# Async tool span
task =
  Task.async(fn ->
    child_metadata = Map.merge(trace_metadata, %{request_id: request_id, tool: "search"})
    tool_span = Observe.start_span([:jido, :ai, :request, :tool], child_metadata)
    result = ExternalSearch.run(query)
    Observe.finish_span(tool_span, %{result_count: length(result.items)})
  end)

Task.await(task)

# Terminal lifecycle event
{:ok, validated} =
  EventContract.validate_event(
    [:jido, :ai, :request, :completed],
    %{duration_ms: 125},
    %{request_id: request_id, terminal_state: :completed},
    required_metadata: [:request_id, :terminal_state],
    required_measurements: [:duration_ms]
  )

Observe.emit_event(
  validated.event,
  validated.measurements,
  Map.merge(validated.metadata, trace_metadata)
)

Observe.finish_span(request_span, %{directive_count: 1})
```

### Recommended Event Taxonomy

| Event | Purpose | Required Metadata | Required Measurements |
|-------|---------|-------------------|-----------------------|
| `[:jido, :ai, :request, :start]` | Request lifecycle start | `request_id` | — |
| `[:jido, :ai, :request, :tool, :start]` | Async tool lifecycle start | `request_id`, `tool` | — |
| `[:jido, :ai, :request, :tool, :stop]` | Async tool lifecycle stop | `request_id`, `tool` | `duration` or `duration_ms` |
| `[:jido, :ai, :request, :completed]` | Request completed | `request_id`, `terminal_state` | `duration_ms` |
| `[:jido, :ai, :request, :failed]` | Request failed | `request_id`, `terminal_state` | `duration_ms` |
| `[:jido, :ai, :request, :cancelled]` | Request cancelled | `request_id`, `terminal_state` | `duration_ms` |
| `[:jido, :ai, :request, :rejected]` | Request rejected | `request_id`, `terminal_state` | `duration_ms` |

### Recommended Contract Keys and Metric Tags

| Category | Keys | Notes |
|----------|------|-------|
| Metadata | `request_id`, `terminal_state`, `tool`, `model` | Use IDs and categorical values, avoid payloads. |
| Measurements | `duration_ms`, `token_count`, `result_count`, `cost_usd` | Numeric measurements only. |
| Metric Tags | `jido_instance`, `terminal_state`, `tool`, `model` | Keep tag cardinality bounded. |

## Dashboard Metrics Recommendations

### Key Metrics to Track

| Metric | Type | Alert Threshold |
|--------|------|-----------------|
| `jido.agent.cmd.duration` p99 | Histogram | > 1s |
| `jido.agent.cmd.exception.count` rate | Counter | > 1/min per agent |
| `jido.agent_server.signal.duration` p95 | Histogram | > 500ms |
| `jido.agent_server.queue.overflow.count` | Counter | > 0 |
| `jido.agent_server.directive.exception.count` | Counter | > 0 |

### Grafana Dashboard Panels

**Command Latency Distribution:**
```promql
histogram_quantile(0.99, 
  sum(rate(jido_agent_cmd_duration_bucket[5m])) by (le, jido_instance, agent_module)
)
```

**Error Rate by Agent:**
```promql
sum(rate(jido_agent_cmd_exception_count[5m])) by (jido_instance, agent_module)
/ 
sum(rate(jido_agent_cmd_stop_count[5m])) by (jido_instance, agent_module)
```

**Signal Throughput:**
```promql
sum(rate(jido_agent_server_signal_stop_count[1m])) by (jido_instance, signal_type)
```

**Directive Execution Rate:**
```promql
sum(rate(jido_agent_server_directive_stop_count[1m])) by (jido_instance, directive_type)
```

## Alerting Patterns

### Prometheus Alerting Rules

```yaml
groups:
  - name: jido
    rules:
      - alert: JidoHighCommandLatency
        expr: histogram_quantile(0.99, sum(rate(jido_agent_cmd_duration_bucket[5m])) by (le)) > 2000
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Jido command latency p99 > 2s"

      - alert: JidoHighErrorRate
        expr: |
          sum(rate(jido_agent_cmd_exception_count[5m])) 
          / sum(rate(jido_agent_cmd_stop_count[5m])) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Jido agent error rate > 5%"

      - alert: JidoQueueOverflow
        expr: increase(jido_agent_server_queue_overflow_count[5m]) > 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Jido directive queue overflow detected"

      - alert: JidoDirectiveFailures
        expr: increase(jido_agent_server_directive_exception_count[5m]) > 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Jido directive execution failures"
```

### SLO Definitions

| SLI | Target | Calculation |
|-----|--------|-------------|
| Command Success Rate | 99.9% | `1 - (cmd.exception.count / cmd.stop.count)` |
| Signal Latency p99 | < 500ms | `histogram_quantile(0.99, signal.duration)` |
| Directive Success Rate | 99.99% | `1 - (directive.exception.count / directive.stop.count)` |
| Queue Overflow Rate | 0 | `queue.overflow.count == 0` |

## Debug Events in Development

Enable verbose telemetry for debugging:

```elixir
# config/dev.exs
config :jido, :observability,
  log_level: :debug,
  debug_events: :all,
  redact_sensitive: false
```

Toggle debug mode at runtime for a specific instance:

```elixir
MyApp.Jido.debug(:on)       # sets debug_events to :minimal
MyApp.Jido.debug(:verbose)  # sets debug_events to :all
MyApp.Jido.debug(:off)      # back to configured defaults
```

Emit debug events from custom code:

```elixir
Jido.Observe.emit_debug_event(
  [:my_app, :custom, :step],
  %{duration: 1234},
  %{agent_id: agent.id, jido_instance: MyApp.Jido, step: 3, status: :processing}
)
```

Debug events are no-ops when `:debug_events` is `:off` (production default).

## Key Modules

- `Jido.Observe` — Unified observability façade with span helpers
- `Jido.Observe.EventContract` — Lightweight required-key validation for custom event contracts
- `Jido.Observe.Config` — Per-instance config resolution (debug override → instance → global → default)
- `Jido.Debug` — Per-instance runtime debug mode
- `Jido.Telemetry` — Built-in telemetry handler and metrics definitions
- `Jido.Tracing.Context` — Correlation ID propagation
- `Jido.Observe.Tracer` — Behaviour for OpenTelemetry integration
- `Jido.Observe.NoopTracer` — Default no-op tracer
- `Jido.Observe.Log` — Threshold-based logging

## Further Reading

- [Seeing What Happened](observability-intro.md) — Development debugging
- [Configuration](configuration.md) — Environment-specific settings
- [Testing](testing.md) — Testing with telemetry
