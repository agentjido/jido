# Telemetry Events

This guide lists every `:telemetry` event Jido emits, with its measurements and metadata. Use it when you write a handler or a metric. For how to use the events, see [Telemetry and Tracing](../operations/telemetry-tracing-and-logs.md), and for reporters and spans, see [Metrics and OTel](../operations/metrics-and-open-telemetry.md).

## Inventory functions

| Function | Returns |
| --- | --- |
| `Jido.Telemetry.AgentServer.event_names/0` | The AgentServer events |
| `Jido.Telemetry.Exec.event_names/0` | The Action and Flow events |
| `Jido.Telemetry.AI.events/0` | The AI events, plus the lower-layer events a handler for AI work needs |
| `Jido.Telemetry.metrics/0` | Metric definitions for AgentServer and persistence events |
| `Jido.Telemetry.AI.metrics/0` | Metric definitions for AI Agent, reasoning, tool, and model events |

No function lists the persistence store, dispatch, or Bus events. Name them from the tables below.

```elixir
events = Jido.Telemetry.AgentServer.event_names()

true = [:jido, :agent_server, :turn, :stop] in events
true = [:jido, :agent_server, :effects, :stop] in events
9 = length(events)

[[:jido, :action, :start] | _] = Jido.Telemetry.Exec.event_names()
true = [:jido, :ai, :agent, :stop] in Jido.Telemetry.AI.events()
true = [:req_llm, :request, :stop] in Jido.Telemetry.AI.events()
```

## AgentServer events

Each event passes through the [normalized fields](#normalized-fields) allowlist, so every metadata map also has `schema_version`. Point events carry `monotonic_time` and `system_time` in addition to the measurements listed.

| Event | Emitted | Measurements | Metadata |
| --- | --- | --- | --- |
| `[:jido, :agent_server, :lifecycle, :start]` | The server starts | None added | `agent_id` |
| `[:jido, :agent_server, :lifecycle, :stop]` | The server stops | None added | `agent_id` |
| `[:jido, :agent_server, :turn, :start]` | A Turn starts | `monotonic_time`, `system_time` | [Turn fields](#turn-fields) |
| `[:jido, :agent_server, :commit]` | A Turn committed. Emitted before Turn stop. | `state_version_before`, `state_version_after`, `directive_count` | Turn fields, `status`, `stage`, `committed?` |
| `[:jido, :agent_server, :directives, :returned]` | A Turn committed. Emitted after commit. | `directive_count` | Turn fields |
| `[:jido, :agent_server, :turn, :stop]` | A Turn ended, committed or not | `duration`, `state_version_before`, `state_version_after`, `directive_count` | Turn fields, `status`, `stage`, `committed?` |
| `[:jido, :agent_server, :turn, :settled]` | Right after Turn stop | `state_version_before`, `state_version_after`, `directive_count` | Turn fields, `status`, `stage`, `committed?` |
| `[:jido, :agent_server, :effects, :start]` | Directive work starts. Not emitted for a Turn with no Directives. | `directive_count` | Turn fields |
| `[:jido, :agent_server, :effects, :stop]` | Directive work ends | `directive_completed`, `directive_count` | Turn fields, `status`, `stage`, `committed?` |

### Turn fields

`agent_id`, `agent_module`, `agent_name`, `signal_id`, `signal_type`, `turn_id`, and the trace fields `trace_id`, `span_id`, and, for a traced caller, `parent_span_id`.

Turn events have no instance, namespace, or partition. Filter on `agent_id` or `agent_module`.

### Turn results

A Turn's `stage` on `:stop`, `:settled`, and `:commit` is `:commit` when it committed and `:evaluate` when it did not. On `[:jido, :agent_server, :effects, :stop]`, the stage says where the effects ended. `status` is one of the normalized values below. A Turn status maps from the runtime's result, so `:succeeded` is reported as `:ok` and `:failed` as `:error`.

`Jido.Telemetry.AI.events/0` also names `[:jido, :agent_server, :turn, :exception]`, but no code in this package emits it. A failed Turn ends with `:stop`, so do not wait for the exception event.

## Persistence events

Both families are spans with `:start` and `:stop`. An adapter raise, throw, or exit reports `:stop` with an error status, because the store catches it first. `:exception` fires only when code in the span itself raises. They pass through the allowlist.

| Event prefix | Emitted around | Measurements | Metadata |
| --- | --- | --- | --- |
| `[:jido, :persistence, :operation]` | `Jido.Persistence` load, compare-and-swap, and delete | Start: `monotonic_time`, `system_time`, `expected_revision`. Stop: `duration`, and `revision_after`. | `operation`, `persistence_reason`, `status`, `adapter_module`, `agent_id`, `agent_module`, `agent_namespace`, `agent_partition`, and error fields |
| `[:jido, :persistence, :store]` | One adapter call in `Jido.Persistence.Store` | Start: `monotonic_time`, `system_time`. Stop: `duration`. | `operation`, `adapter_module`, `status`, and error fields |

`status` comes from the result:

| Adapter or operation result | `status` |
| --- | --- |
| `:ok`, `{:ok, _}`, `{:ok, _, _}` | `:ok` |
| `{:error, :not_found}`, `{:error, :deleted}` | `:not_found` |
| `{:error, :conflict}` | `:conflict` |
| `{:error, :indeterminate}`, `{:error, {:indeterminate, _}}` | `:indeterminate` |
| `{:error, {:rejected, _}}` | `:rejected` |
| Any other `{:error, reason}` | `:error`, with `error_type`, `retryable?`, and possibly `error_code` |

An `:exception` event adds `kind`, and its `status` is `:error`. Only the `:operation` family has metric definitions.

## Action and Flow events

`:telemetry.span/3` emits these, so they include `telemetry_span_context` and do not pass through the allowlist. The start event has `monotonic_time` and `system_time`. The stop and exception events have `duration` and `monotonic_time`.

| Event prefix | Metadata |
| --- | --- |
| `[:jido, :action]` | `action`, `action_name`, `node_name`, `runnable_id`, `activation_id`, `attempt_id`, `attempt`. In a Flow: `component`, `node_path`, `component_kind`, `invoke_phase`. In a Turn: `agent_id`, `agent_module`, `turn_id`, `trace_id`, `span_id`, `parent_span_id`. |
| `[:jido, :flow]` | `kind` (always `:flow`), `flow`, and `target` when the target is a module. Emitted only by `Jido.Exec.run/4`, once per call. A Flow that runs in a Turn, through `Jido.Durable`, or through `Runic.Runner` emits Action events and Runic events, not these. |

Each `:stop` event adds:

| `outcome` | Also added |
| --- | --- |
| `:ok` | `effect_count` |
| `:handoff` (Flow only) | `effect_count` |
| `:error` | `error_type`, `retryable?` |
| `:unknown` | None |

`:exception` is reserved for a raise, throw, or exit that escapes the span. A raise inside an Action's `run/2` becomes a stop event with `outcome: :error`, and one event fires for each attempt.

## Dispatch events

These carry trace fields from the Signal and do not pass through the allowlist. `target` and `target_kind` are summaries from the adapter's options, for example `:unknown` for the logger adapter.

| Event | Measurements | Metadata |
| --- | --- | --- |
| `[:jido, :dispatch, :start]` | None | `adapter`, `runtime_surface` (always `:dispatch`), `signal_type`, `target`, `target_kind` |
| `[:jido, :dispatch, :stop]` | `latency_ms` | Start fields, `outcome: :ok`, `success?: true` |
| `[:jido, :dispatch, :exception]` | `latency_ms` | Start fields, `success?: false`, `outcome`, `error_type`, `retryable?`. With `outcome: :raised`, also `exception_kind` and `exception_module`. |

An adapter that returns `{:error, reason}` emits `:exception` with `outcome: :error`. This differs from Action events, where an error is a stop event.

Signal-aware events add `jido_trace_id`, `jido_span_id`, and `jido_trace_flags` when the Signal carries a valid trace. Nil metadata values are dropped.

## Signal Bus events

These do not pass through the allowlist. All have `bus_name`, `bus_jido`, and `bus_registry`, without nil values.

| Event | Emitted | Measurements | Added metadata |
| --- | --- | --- | --- |
| `[:jido, :signal, :bus, :publish]` | A publish was accepted | `count`, `duration` (native) | None |
| `[:jido, :signal, :bus, :deliver]` | A record was sent to a subscriber | `system_time` | `subscription_id`, `subscription_path`, `durable`, `cursor`, `signal_id`, `signal_type` |
| `[:jido, :signal, :bus, :ack]` | A durable cursor moved | `cursor` | `subscription_id` |
| `[:jido, :signal, :bus, :delivery_error]` | A durable delivery or store read failed | `system_time` | `subscription_id`, `reason`, and, when a record is known, `signal_id` and `signal_type` |
| `[:jido, :signal, :bus, :subscription, :attached]` | A subscriber attached | `system_time` | `subscription_id`, `subscription_path`, `durable` |
| `[:jido, :signal, :bus, :subscription, :detached]` | A subscriber detached | `system_time` | `subscription_id`, `subscription_path`, `durable` |

`reason` on `:delivery_error` is the raw failure term. Review it before you forward it to another service.

## AI events

Jido derives these from the AgentServer and Action events above. They do not pass through the allowlist.

| Event | Emitted | Measurements |
| --- | --- | --- |
| `[:jido, :ai, :agent, :start]` | A Turn for a `jido.ai.request` Signal starts | `monotonic_time`, `system_time` |
| `[:jido, :ai, :agent, :stop]` | That Turn stops | The Turn's measurements, plus `model_calls`, `tool_rounds`, `tool_calls`, `tool_errors`, `retries`, `reasoning_steps`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`, `reasoning_tokens`, `total_cost` |
| `[:jido, :ai, :reasoning, :start]` | A reasoning Flow starts | `monotonic_time`, `system_time` |
| `[:jido, :ai, :reasoning, :stop]` | It returns | `duration` |
| `[:jido, :ai, :reasoning, :exception]` | A raise, throw, or exit leaves it | `duration` |
| `[:jido, :ai, :tool, :start]`, `:stop`, `:exception` | A tool Action in the Flow's `tools` component runs | That Action's measurements |
| `[:jido, :ai, :limit, :exceeded]` | A model response breaks an output limit | `value`, `maximum`. Neither is present for `limit: :token_limit`. |
| `[:jido, :ai, :telemetry, :correlation, :cleanup]` | A sweep expired at least one entry | `expired`, `size` |

Metadata:

| Field | Events |
| --- | --- |
| `agent_id`, `agent_module`, `agent_name`, `agent_definition_id`, `agent_description`, `agent_version`, `reasoning`, `reasoning_name`, `request_id`, `turn_id`, `trace_id`, `span_id`, `parent_span_id` | Agent, reasoning, and tool |
| `run_id`, `session_id`, `thread_id` | Agent stop, reasoning, and tool |
| `status`, `committed?`, `reason_code`, `error_type`, `error_code` | Agent stop. `status` is the request status, such as `:completed`. |
| `reason` | Agent stop, when `reason_code` is `:limits`. A fixed budget message. |
| `limit`, `model`, `request_id`, `run_id`, `agent_id`, `turn_id` | Limit exceeded. `limit` is `:output_chars`, `:token_limit`, or `:tool_calls_per_response`. It also carries the Agent fields when the Turn runs in an AgentServer. |
| `reasoning_method`, `reasoning_operation_id` | Reasoning |
| `status`, `req_llm_request_id`, `error_type` | Reasoning stop. `status` is `:ok`, `:error`, or `:unknown`. |
| `action`, `tool_name`, `tool_call_id`, `tool_description`, `node_name`, `activation_id`, `attempt_id`, `attempt`, `status`, `error_type`, `retryable?` | Tool |

Values that are nil are removed. A Turn exception does not occur, so `[:jido, :ai, :agent, :exception]` does not fire in practice.

Jido does not own model request events. `Jido.Telemetry.AI.events/0` includes them, under `[:req_llm, ...]`, and `Jido.Telemetry.AI.metrics/0` builds model metrics from them. See the ReqLLM documentation for their fields.

## Runic events

Runic owns Runner execution events. `Jido.Telemetry.AI.events/0` includes them, and they are under `[:runic, :runner, ...]`: `:workflow`, `:runnable`, `:store`, `:promise`, and `:rehydration`. See the Runic documentation.

## Normalized fields

AgentServer and persistence events are the only ones that pass through this allowlist. Jido drops any other field or any value that does not match.

| Metadata | Allowed values |
| --- | --- |
| `schema_version` | Always present. Currently `1`. |
| `agent_namespace`, `agent_id`, `activation_id`, `turn_id`, `source_signal_id`, `signal_id`, `signal_type`, `trace_id`, `span_id`, `parent_span_id`, `causation_id`, `cause_turn_id`, `child_activation_id`, `topology_id`, `node_id`, `agent_name` | A valid UTF-8 string of at most 256 bytes |
| `agent_partition` | A valid UTF-8 string of at most 128 bytes |
| `agent_module`, `directive_module`, `adapter_module`, `plugin_module`, `facet_module` | A non-nil atom |
| `committed?`, `retryable?` | A boolean |
| `status` | `:ok`, `:error`, `:cancelled`, `:timed_out`, `:conflict`, `:indeterminate`, `:not_found`, `:rejected` |
| `stage` | `:evaluate`, `:commit`, `:after_commit`, `:directive` |
| `kind` | `:error`, `:throw`, `:exit` |
| `operation` | `:activate`, `:stop`, `:hibernate`, `:thaw`, `:load`, `:compare_and_swap`, `:delete` |
| `persistence_reason` | `:commit`, `:activate`, `:stop`, `:hibernate`, `:thaw`, `:manual`, `:topology`, `:stored_upgrade` |
| `admission_reason` | `:deadline_expired`, `:overloaded` |
| `topology_operation` | `:activate`, `:repair`, `:update`, `:place`, `:cleanup` |
| `component_kind`, `error_type` | A non-nil atom |
| `error_code` | A value from `Jido.Error.stable_codes/0` |

Measurements are integers. `system_time` and `monotonic_time` can be negative. The rest must be non-negative, and only these names pass: `count`, `duration`, `state_version`, `state_version_before`, `state_version_after`, `directive_count`, `directive_index`, `directive_completed`, `directive_failed`, `directive_skipped`, `queue_depth`, `queue_limit`, `wait_duration`, `expected_revision`, `revision_before`, `revision_after`, `target_revision`, `component_count`, `ready_count`, `failed_count`, `epoch`.

The allowlist permits more names than the current code emits. For example, no event emits `queue_depth`. The tables above state what is emitted.

`duration` is in native time units. Use `System.convert_time_unit/3`.

The next example captures one Turn and shows that a Signal's data and an unknown field do not appear.

```elixir
defmodule TelemetryRef.Capture do
  def handle(event, measurements, metadata, target) do
    send(target, {event, measurements, metadata})
  end
end

defmodule TelemetryRef.Ticket do
  use Jido.Agent, name: "telemetry_ref_ticket"

  state do
    schema Jido.Joi.object(%{subject: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    signal_source "/support"

    route "ticket.update", as: :update do
      action %{subject: subject}, schema: Jido.Joi.object(%{subject: Jido.Joi.string()}), context: context do
        {:ok, %{context.agent_state | subject: subject}}
      end
    end
  end
end

:ok = :telemetry.attach("telemetry-ref", [:jido, :agent_server, :turn, :stop], &TelemetryRef.Capture.handle/4, self())

{:ok, _pid} = Jido.start_link(name: TelemetryRef.Jido)
{:ok, ticket} = Jido.start_agent(TelemetryRef.Jido, TelemetryRef.Ticket, id: "ticket-1")

{:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
  Jido.AgentServer.call(ticket, TelemetryRef.Ticket.update_signal!(%{subject: "private"}))

{measurements, metadata} =
  receive do
    {[:jido, :agent_server, :turn, :stop], m, md} -> {m, md}
  after
    1_000 -> raise "no Turn stop event"
  end

%{status: :ok, stage: :commit, committed?: true, signal_type: "ticket.update", schema_version: 1} = metadata
%{state_version_before: 0, state_version_after: 1, directive_count: 0} = measurements
false = inspect(metadata) =~ "private"

:ok = :telemetry.detach("telemetry-ref")
```

## Metrics

`Jido.Telemetry.metrics/0` and `Jido.Telemetry.AI.metrics/0` return these definitions. Each `.duration` metric is a `Telemetry.Metrics.summary/2` that converts native time to milliseconds.

| Metric | Type | Tags |
| --- | --- | --- |
| `jido.agent_server.turn.stop.count` | Counter | `status`, `stage` |
| `jido.agent_server.turn.stop.duration` | Summary | `status`, `stage` |
| `jido.agent_server.turn.settled.count` | Counter | `status`, `stage` |
| `jido.agent_server.commit.count` | Counter | `status` |
| `jido.agent_server.directives.returned.count` | Counter | None |
| `jido.agent_server.effects.start.count` | Counter | None |
| `jido.agent_server.effects.stop.count` | Counter | `status`, `stage` |
| `jido.agent_server.lifecycle.start.count` | Counter | None |
| `jido.agent_server.lifecycle.stop.count` | Counter | None |
| `jido.persistence.operation.stop.count` | Counter | `operation`, `status`, `persistence_reason` |
| `jido.persistence.operation.stop.duration` | Summary | `operation`, `status`, `persistence_reason` |
| `jido.persistence.operation.exception.count` | Counter | `operation`, `status`, `persistence_reason` |
| `jido.persistence.operation.exception.duration` | Summary | `operation`, `status`, `persistence_reason` |
| `jido.ai.agent.stop.count` | Counter | `status`, `reasoning_name` |
| `jido.ai.agent.stop.duration` | Summary | `status`, `reasoning_name` |
| `jido.ai.reasoning.stop.count` | Counter | `reasoning_name`, `reasoning_method`, `status` |
| `jido.ai.reasoning.stop.duration` | Summary | `reasoning_name`, `reasoning_method`, `status` |
| `jido.ai.tool.stop.count` | Counter | `status`, `tool_name` |
| `jido.ai.tool.stop.duration` | Summary | `status`, `tool_name` |
| `jido.ai.model.request.count` | Counter | `provider`, `model`, `operation` |
| `jido.ai.model.request.exception.count` | Counter | `provider`, `model`, `operation` |
| `jido.ai.model.request.duration` | Summary | `provider`, `model`, `operation` |
| `jido.ai.model.input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_write_tokens`, `reasoning_tokens`, `total_cost` | Sum | `provider`, `model` |
| `jido.ai.telemetry.correlation.expired` | Sum | None |
| `jido.ai.telemetry.correlation.size` | Last value | None |

Each counter counts events. `jido.agent_server.directives.returned.count` does not sum the Directives in an event. Read `directive_count` if you need that.

## Related

- [Telemetry and Tracing](../operations/telemetry-tracing-and-logs.md)
- [Metrics and OTel](../operations/metrics-and-open-telemetry.md)
- [Configuration Reference](configuration-reference.md)
