# Telemetry and Tracing

This guide explains the signals Jido gives you about a running system: telemetry events, trace context, and semantic logs. For a walk through a live Turn, start with [Observe Agent Turns](observe-agent-turns.livemd). For every event's fields, use [Telemetry Events](../reference/telemetry-event-reference.md).

Observation is best effort. It cannot change an Agent result, and a handler failure does not affect a Turn. It is not a durable audit record, so use [Audit Records](../built-in-plugins/audit-records.md) when you need one.

## Event families

Jido emits events with `:telemetry`.

| Prefix | Reports | Inventory |
| --- | --- | --- |
| `[:jido, :agent_server, :turn]` | Turn `:start` and `:stop`, and the point event `:settled` | `Jido.Telemetry.AgentServer.event_names/0` |
| `[:jido, :agent_server, :commit]` | A committed Turn | Same |
| `[:jido, :agent_server, :directives, :returned]` | The Directives a committed Turn returned | Same |
| `[:jido, :agent_server, :effects]` | Post-commit `:start` and `:stop` | Same |
| `[:jido, :agent_server, :lifecycle]` | AgentServer process `:start` and `:stop` | Same |
| `[:jido, :persistence, :operation]` | Store `:start`, `:stop`, and `:exception` | `Jido.Telemetry.metrics/0` |
| `[:jido, :action]`, `[:jido, :flow]` | Action attempts and Flow calls | `Jido.Telemetry.Exec.event_names/0` |
| `[:jido, :dispatch]` | Signal dispatch | [Telemetry Events](../reference/telemetry-event-reference.md) |
| `[:jido, :signal, :bus]` | Bus publish, delivery, subscriptions, and acks | [Telemetry Events](../reference/telemetry-event-reference.md) |
| `[:jido, :ai]` | AI Agent, reasoning, and tool work | `Jido.Telemetry.AI.events/0` |

Runic owns the events for managed Flow scheduling, and ReqLLM owns model request events. `Jido.Telemetry.AI.events/0` includes them.

### Turn results and effect results

A Turn can commit before its effects finish, so one Turn has two results. Read each from its own event.

| Question | Event | Field |
| --- | --- | --- |
| Did the Turn commit? | `[:jido, :agent_server, :turn, :stop]` | `status`, `stage`, `committed?` |
| Did the effects finish? | `[:jido, :agent_server, :effects, :stop]` | `status`, `stage`, `directive_completed` |

A Turn `status` is `:ok`, `:error`, `:cancelled`, `:timed_out`, or `:indeterminate`. A Turn with no Directives emits no effects events. Action and Flow events use `outcome` in place of `status`, and a normal error completes a span with `outcome: :error`. An `:exception` event means that a raise, throw, or exit escaped the span.

### What events contain

Turn, effect, lifecycle, and persistence events pass through a fixed allowlist:

- **Metadata** holds bounded IDs, module names, and fixed status words. Jido drops an ID longer than 256 bytes.
- **Measurements** hold integers, such as `duration`, `state_version_after`, and `directive_count`. `duration` is in native time units.
- **Never included:** Agent and Plugin state, Signal and Directive data, raw errors, process handles, credentials, and caller context.

An error appears as `error_type`, `retryable?`, and sometimes `error_code`. To read the message, use the value returned to the caller.

The next example shows that an unknown field and a Signal's data do not reach a handler.

```elixir
defmodule TelemetryGuide.Capture do
  def handle(event, measurements, metadata, target) do
    send(target, {event, measurements, metadata})
  end
end

defmodule TelemetryGuide.Ticket do
  use Jido.Agent, name: "telemetry_guide_ticket"

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

:ok =
  :telemetry.attach(
    "telemetry-guide",
    [:jido, :agent_server, :turn, :stop],
    &TelemetryGuide.Capture.handle/4,
    self()
  )

{:ok, _pid} = Jido.start_link(name: TelemetryGuide.Jido)
{:ok, ticket} = Jido.start_agent(TelemetryGuide.Jido, TelemetryGuide.Ticket, id: "ticket-1")

{:ok, _agent, []} =
  Jido.AgentServer.call(ticket, TelemetryGuide.Ticket.update_signal!(%{subject: "private text"}))

{turn_measurements, turn_metadata} =
  receive do
    {[:jido, :agent_server, :turn, :stop], measurements, metadata} -> {measurements, metadata}
  after
    1_000 -> raise "no Turn stop event"
  end

%{status: :ok, agent_id: "ticket-1", signal_type: "ticket.update", schema_version: 1} = turn_metadata
%{state_version_after: 1} = turn_measurements
false = inspect(turn_metadata) =~ "private text"
```

`schema_version` is on each normalized event. Check it if you parse events into another system.

Action, Flow, Dispatch, and Bus events have their own metadata. They carry more fields, such as `:action` and `:node_path`, and do not pass through this same allowlist. Review them before you forward all metadata to an outside service.

### Write a handler

Handlers run in the process that emits the event, which is often the AgentServer. Slow handlers therefore slow Turns. `:telemetry` also detaches a handler that raises. Keep handlers short, and send heavy work to another process.

Handlers are global to the node. To report on one subset of Agents, filter inside the handler on `agent_id` or `agent_module`. Turn events do not carry an instance, namespace, or partition. See [Instances and Tenants](configuration-and-tenant-isolation.md#what-a-partition-does-not-do).

## Trace context

`Jido.Trace` holds one W3C trace value. A Signal carries it through `Jido.Signal.Context`, and each Turn's events report it.

1. A Signal with no trace starts a new root trace.
2. A Signal with a trace starts a child: same `trace_id`, new `span_id`, and the caller's span as `parent_span_id`.
3. A Signal emitted by the Turn carries the trace forward, with the emitted Signal's ID as its causation.

To join a caller's trace, parse its header and attach the result to the Signal.

```elixir
traceparent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
{:ok, inbound} = Jido.Trace.from_traceparent(traceparent)

{:ok, traced} =
  TelemetryGuide.Ticket.update_signal!(%{subject: "traced"})
  |> Jido.Signal.Context.put_trace(inbound)

%{"traceparent" => ^traceparent} = traced.extensions

{:ok, _agent, []} = Jido.AgentServer.call(ticket, traced)

receive do
  {[:jido, :agent_server, :turn, :stop], _measurements, metadata} ->
    "4bf92f3577b34da6a3ce929d0e0e4736" = metadata.trace_id
    "00f067aa0ba902b7" = metadata.parent_span_id
after
  1_000 -> raise "no Turn stop event"
end

:telemetry.detach("telemetry-guide")
```

To send the trace onward, call `Jido.Trace.to_traceparent/1`. `Jido.Trace.from_traceparent/2` returns `{:error, :invalid_traceparent}` for a value that is not version `00` W3C format, and it drops an invalid `tracestate`. Inbound trace headers come from outside your system, so a bad value must not fail the request. Continue without a trace.

An Action can read the current trace from its context under `:trace_context`.

## Log modes

The semantic logger is a telemetry handler that Jido attaches when its application starts. It logs one bounded line per event, using the same allowlist. It covers the events in `Jido.Telemetry.metrics/0`. Set a mode in configuration.

<!-- partial -->
```elixir
config :jido, :telemetry,
  semantic_log_mode: :interesting,
  semantic_slow_threshold_ms: 1_000
```

| Mode | Logs |
| --- | --- |
| `:off` | Nothing. This is the default, and any unknown value means the same. |
| `:errors` | An `:exception` event, or any event with a status other than `:ok`. |
| `:interesting` | Errors, and events with a `duration` at or above the threshold. |
| `:all` | Every event in the catalog. |

An error line logs at `:warning`. Every other line logs at `:debug`, so a production `Logger` level of `:info` hides them, including the slow events from `:interesting`. A line looks like this:

```text
[warning] [jido.semantic] event=agent_server.effects.stop agent_id=invoice-1 directive_completed=0 directive_count=1 stage=directive status=error turn_id=...
```

Jido reads the mode for each event, so you can change it on a running node with `Application.put_env/3`. A cancelled Turn counts as an error here, because its status is not `:ok`.

AI events have their own settings under `config :jido, :ai_telemetry`, with the same modes. Prompts, model output, tool arguments, and tool results are not logged. See `Jido.Telemetry.AI`.

### Limit warnings

Under `:ai_telemetry`, the modes `:errors`, `:interesting`, and `:all` log a `:warning` when a model or request hits a limit. With `:off`, these lines do not appear, so turn the mode on to see them. They contain sizes and IDs, and never model output.

The first line reports one model response. A `ReAct` request can recover from it through a repair round, so one line does not mean that a request failed. Many of them mean that you are paying for answers you reject.

```text
[warning] [jido.ai.semantic] event=ai.limit.exceeded agent_id=memo-1 limit=output_chars maximum=32000 model=openai:gpt-4o-mini request_id=... run_id=... value=41250
```

| `limit` | Meaning | What to change |
| --- | --- | --- |
| `output_chars` | The answer passed `limits.output_chars`. `value` is its length, and `maximum` is the limit. | Raise `limits.output_chars`, or ask for shorter answers in `instructions`. |
| `token_limit` | The provider stopped at a token limit, with `finish_reason: :length`. It carries no `value`. | Raise `options.max_tokens`. |
| `tool_calls_per_response` | One response asked for more than 4 tool calls. | This limit is fixed. Ask for fewer calls in `instructions`. |

The second line reports the end of a request that stayed blocked. It logs when the status is `:blocked` and the reason code is `:limits` or `:output`. A `:limits` line also carries the budget's reason. Other blocked requests, such as those with reason code `:input`, stay at `:debug`, because the caller controls them.

```text
[warning] [jido.ai.semantic] event=ai.agent.stop agent_id=memo-1 reason=maximum tool rounds reached reason_code=limits status=blocked ...
```

To alert on these, count `[:jido, :ai, :limit, :exceeded]` by its `limit` field. `Jido.Telemetry.AI.metrics/0` includes the counter `jido.ai.limit.exceeded.count`. [Output limits](../ai/budgets-and-usage.md#output-limits) explains how to choose values.

### Debug one instance

`set_debug/2` on `Jido.Telemetry` raises the log mode for one instance. `:on` selects `:interesting`, `:verbose` selects `:all`, and `:off` removes the override. The instance option `debug: true` or `debug: :verbose` sets the same value at start.

```elixir
:ok = Jido.Telemetry.set_debug(TelemetryGuide.Jido, :verbose)
:ok = Jido.Telemetry.set_debug(TelemetryGuide.Jido, :off)
```

Today this override applies only to persistence operations, because they are the only events that carry their instance. Turn and effect events follow the global mode. To see Turn events, set `semantic_log_mode` for the node.

The AgentServer option `debug: true` is separate. It keeps Turn history for `Jido.AgentServer.history/1`, and it does not change logging.

## Next steps

- [Metrics and OTel](metrics-and-open-telemetry.md)
- [Runtime Debugging](runtime-state-and-debugging.md)
- [Telemetry Events](../reference/telemetry-event-reference.md)
