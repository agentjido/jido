# Metrics and OTel

This guide connects Jido's telemetry to a metrics reporter and to OpenTelemetry spans. Jido defines the metrics and maps the spans. Your application owns the reporter, the SDK, sampling, and export.

## Report metrics

`Jido.Telemetry.metrics/0` returns `Telemetry.Metrics` definitions. Pass them to any compatible reporter. This example uses `Telemetry.Metrics.ConsoleReporter`, which is part of `telemetry_metrics` and prints each measurement.

```elixir
defmodule MetricsGuide.Ticket do
  use Jido.Agent, name: "metrics_guide_ticket"

  state do
    schema Jido.Joi.object(%{closed: Jido.Joi.boolean() |> Jido.Joi.default(false)})
  end

  routes do
    signal_source "/support"

    route "ticket.close", as: :close do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, %{context.agent_state | closed: true}}
      end
    end
  end
end

{:ok, device} = StringIO.open("")

{:ok, reporter} =
  Telemetry.Metrics.ConsoleReporter.start_link(
    metrics: Jido.Telemetry.metrics(),
    device: device
  )

{:ok, _pid} = Jido.start_link(name: MetricsGuide.Jido)
{:ok, ticket} = Jido.start_agent(MetricsGuide.Jido, MetricsGuide.Ticket, id: "ticket-1")
{:ok, _agent, []} = Jido.AgentServer.call(ticket, MetricsGuide.Ticket.close_signal!(%{}))

{_input, printed} = StringIO.contents(device)
true = printed =~ "Event name: jido.agent_server.turn.stop"
true = printed =~ "Metric measurement: :duration"
true = printed =~ "status: :ok"

GenServer.stop(reporter)
```

In an application, start your reporter in your supervision tree.

<!-- partial -->
```elixir
children = [
  {TelemetryMetricsPrometheus, metrics: Jido.Telemetry.metrics() ++ Jido.Telemetry.AI.metrics()},
  MyApp.Jido
]
```

The reporter in this fragment comes from its own package. If your reporter does not support `summary` metrics, convert them to `Telemetry.Metrics.distribution/2` with buckets that fit your Turn times.

## The metric catalog

| Metric | Type | Tags |
| --- | --- | --- |
| `jido.agent_server.turn.stop.count` | Counter | `status`, `stage` |
| `jido.agent_server.turn.stop.duration` | Summary, ms | `status`, `stage` |
| `jido.agent_server.turn.settled.count` | Counter | `status`, `stage` |
| `jido.agent_server.commit.count` | Counter | `status` |
| `jido.agent_server.directives.returned.count` | Counter | None |
| `jido.agent_server.effects.start.count` | Counter | None |
| `jido.agent_server.effects.stop.count` | Counter | `status`, `stage` |
| `jido.agent_server.lifecycle.start.count` | Counter | None |
| `jido.agent_server.lifecycle.stop.count` | Counter | None |
| `jido.persistence.operation.stop.count` | Counter | `operation`, `status`, `persistence_reason` |
| `jido.persistence.operation.stop.duration` | Summary, ms | `operation`, `status`, `persistence_reason` |
| `jido.persistence.operation.exception.count` | Counter | `operation`, `status`, `persistence_reason` |
| `jido.persistence.operation.exception.duration` | Summary, ms | `operation`, `status`, `persistence_reason` |

Each counter counts events. `jido.agent_server.directives.returned.count` counts committed Turns. To count Directives, build your own `Telemetry.Metrics.sum/2` on the `directive_count` measurement.

Tags hold fixed words only, so these metrics are safe for a time series database. Do not add `agent_id`, `turn_id`, or `signal_type` as tags. Their values are unbounded. Put them on traces and logs.

`persistence_reason` separates the writers: `:activate` when an AgentServer starts, `:commit` for a Turn commit, `:hibernate` for a hibernate save, `:stored_upgrade` for `Jido.Persistence.upgrade_agent/5`, and `:manual` for a direct save. A direct save can set its own value with `:reason`.

### AI metrics

`Jido.Telemetry.AI.metrics/0` adds Agent, reasoning, tool, and model request metrics, token counts, and total cost. Tags include `tool_name` and `reasoning_name`, which your code defines. See [Telemetry Events](../reference/telemetry-event-reference.md).

### What to alert on

| Watch | Why |
| --- | --- |
| `jido.agent_server.turn.stop.count` with `status` not `ok` | Turns that did not commit. `timed_out` often points at a slow dependency. |
| `jido.agent_server.effects.stop.count` with `status` not `ok` | Commits whose delivery failed. The Turn metrics do not show these. |
| `jido.persistence.operation.stop.count` with `status` `conflict` or `indeterminate` | A second writer or an unknown write result. See [Revisions and Conflicts](../durability/durable-revisions-and-conflicts.md). |
| `jido.agent_server.turn.stop.duration` | Compare with `:turn_timeout` and your admission deadline. |
| `jido.agent_server.lifecycle.start.count` above your expected rate | Crash loops, because each restart counts. |

Queue depth has no metric, because a queue belongs to one Agent. Read it from `Jido.AgentServer.status/2` under `admission`, and poll the Agents you care about. See [Runtime Debugging](runtime-state-and-debugging.md).

## Add OpenTelemetry spans

Jido maps its Turn, effect, lifecycle, and persistence events to spans when two things are true: the `opentelemetry_api` package is present, and your application runs an SDK with a real tracer. Jido does not start an SDK or configure sampling and export.

`opentelemetry_api` is an optional dependency of Jido. Add it, the SDK, and an exporter to your application.

<!-- partial -->
```elixir
defp deps do
  [
    {:jido, github: "agentjido/jido", branch: "migration/consolidated-v3"},
    {:opentelemetry_api, "~> 1.0"},
    {:opentelemetry, "~> 1.0"},
    {:opentelemetry_exporter, "~> 1.0"}
  ]
end
```

Configure the SDK and exporter as their own documentation describes. Then check the mapping at runtime.

```elixir
is_boolean(Jido.Telemetry.open_telemetry?())
```

`Jido.Telemetry.open_telemetry?/0` returns `true` only when the mapping can produce spans. It returns `false` when `opentelemetry_api` is absent, when the tracer is a no-op because no SDK runs, and when you turn the mapping off.

<!-- partial -->
```elixir
config :jido, :opentelemetry, enabled: false
config :jido, :ai_opentelemetry, enabled: false
```

### Span names

| Span | Source |
| --- | --- |
| `jido.agent_server.turn` | The Turn, from start to stop. |
| `jido.agent_server.commit`, `jido.agent_server.turn.settled`, `jido.agent_server.directives.returned`, `jido.agent_server.effects.start`, `jido.agent_server.effects.stop` | Point events, as zero-length spans. |
| `jido.agent_server.lifecycle.start`, `jido.agent_server.lifecycle.stop` | Point events, as zero-length spans. |
| `jido.persistence.load`, `jido.persistence.compare_and_swap`, `jido.persistence.delete` | Persistence operations. |
| `jido.persistence.store` | The adapter call inside an operation. |

Action and Flow events have no span mapping here. Their `trace_id` and `turn_id` metadata let you join them to the Turn.

### Span attributes

Each attribute is the metadata or measurement key with a `jido.` prefix. Underscores become dots, and a trailing `?` is removed. For example, `agent_id` becomes `jido.agent.id`, `state_version_after` becomes `jido.state.version.after`, and `committed?` becomes `jido.committed`. Modules appear as strings such as `Elixir.MyApp.OrderAgent`. Duration and clock measurements are not attributes, because the span holds its own times.

A failed event sets the span status to error and adds `error.type`. A `:cancelled` Turn is not an error. An `:exception` event also adds an `exception` span event.

### Connect traces

A Turn joins the trace on its Signal. If you attach a trace with `Jido.Signal.Context.put_trace/2`, the Turn span's parent is that remote span, and its `trace_id` matches your caller. The Turn's new span context is available to its work, so a commit span is a child of its Turn span. See [Telemetry and Tracing](telemetry-tracing-and-logs.md#trace-context).

Sampling is your SDK's decision. The SDK's default sampler is parent-based, so it follows the flags on a trace you attach. `Jido.Trace.new/1` uses flags `"00"` unless you pass `trace_flags: "01"`, and a Signal that carries a `"00"` trace produces no Turn span under that sampler. A Signal with no trace starts a root span, which that sampler keeps.

### AI spans

AI Agent, reasoning, and tool operations map to OpenTelemetry GenAI spans with standard `gen_ai.*` attributes. Jido-specific values stay under `jido.ai.*`. `Jido.Telemetry.AI` has the details.

## Next steps

- [Telemetry Events](../reference/telemetry-event-reference.md)
- [Telemetry and Tracing](telemetry-tracing-and-logs.md)
- [Production Setup](production-configuration.md)
