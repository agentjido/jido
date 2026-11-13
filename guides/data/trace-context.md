# Trace Context

This guide shows how to create a `Jido.Trace`, accept one from an HTTP request, and follow it through an Agent Turn and the Signals that the Turn sends.

`Jido.Trace` is one validated W3C Trace Context value. Jido carries it on Signals, gives it to Actions, and adds it to logs and telemetry. Exporting spans is a separate step, covered in Metrics and OTel.

## Create a trace

`Jido.Trace.new/1` starts a new root. `Jido.Trace.child/2` starts a new span in the same trace.

```elixir
alias Jido.Trace

root = Trace.new(trace_flags: "01", tracestate: "vendor=value")
child = Trace.child(root, causation_id: "order-signal-1")

true = child.trace_id == root.trace_id
true = child.span_id != root.span_id
true = child.parent_span_id == root.span_id
"01" = child.trace_flags
"vendor=value" = child.tracestate
```

| Field | Value |
| --- | --- |
| `:trace_id` | 32 lower-case hex characters, not all zero |
| `:span_id` | 16 lower-case hex characters, not all zero |
| `:trace_flags` | 2 lower-case hex characters |
| `:tracestate` | W3C list, or `nil` |
| `:parent_span_id` | The parent's span ID, or `nil` for a root |
| `:causation_id` | The ID of what caused this span, or `nil`. It is application data and is not part of the W3C format |

`Jido.Trace.new/1` accepts only `:trace_flags` and `:tracestate`, and `Jido.Trace.child/2` accepts only `:causation_id`. Any other option raises `ArgumentError`, as does an invalid value. The default flags are `"00"`. Jido carries the flags and makes no sampling decision. `Jido.Trace.with_causation/2` returns a copy with a new causation ID.

## Accept a trace from a caller

`Jido.Trace.from_traceparent/2` parses W3C version `00` headers. `Jido.Trace.to_traceparent/1` formats one for an outgoing request.

```elixir
alias Jido.Trace

header = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

{:ok, incoming} = Trace.from_traceparent(header, "vendor=value")

"4bf92f3577b34da6a3ce929d0e0e4736" = incoming.trace_id
^header = Trace.to_traceparent(incoming)

{:error, :invalid_traceparent} = Trace.from_traceparent("01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
{:error, :invalid_traceparent} = Trace.from_traceparent("garbage")
```

An invalid `traceparent` is an error. An invalid `tracestate` is dropped, and the trace stays usable, so a bad vendor header cannot reject a request. A valid `tracestate` has at most 32 unique members and 512 bytes.

```elixir
alias Jido.Trace

{:ok, %{tracestate: nil}} =
  Trace.from_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", "Vendor=value")

true = Trace.valid?("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
false = Trace.valid?("garbage")
```

`Jido.Trace.valid?/1` accepts a struct, a string, or any other term.

## Put a trace on a Signal

`Jido.Signal.Context.put_trace/2` stores a trace as flat CloudEvents extension attributes. Those attributes travel with the Signal across transports. [CloudEvents Context](../signals/cloudevents-envelope-and-context.md) covers the other functions in that module.

```elixir
alias Jido.Signal.Context

signal = Jido.Signal.new!("order.received", %{order_id: "o-1"}, source: "/orders/api")
{:ok, traced} = Context.put_trace(signal, incoming)

%{"traceparent" => ^header, "tracestate" => "vendor=value"} = traced.extensions
^incoming = Context.get_trace(traced)
```

## Follow a trace through a Turn

`Jido.AgentServer` starts each Turn from the Signal's trace:

- With a trace on the Signal, the Turn runs as a child span of it.
- Without one, the Turn starts a new root trace.

An Action reads the Turn's trace from `context.trace_context`. `Jido.AgentServer` also adds the fields to the Logger metadata. The pure `cmd/3` path does not set this key.

```elixir
defmodule TraceGuide.OrderDesk do
  use Jido.Agent, name: "trace_guide_order_desk"

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/orders/desk"

    route "order.confirm", as: :confirm do
      action %{order_id: order_id},
        schema: Jido.Joi.object(%{order_id: Jido.Joi.string()}),
        context: context do
        send(context.observer, {:turn_trace, context.trace_context, Logger.metadata()})

        audit = Jido.Signal.new!("order.audit", %{order_id: order_id}, source: "/orders/desk")
        directive = Jido.Agent.Directive.emit(audit, {:pid, target: context.observer})

        {:ok, context.agent_state, [directive]}
      end
    end
  end
end

{:ok, _instance} = Jido.start(name: TraceGuide.Jido)
{:ok, desk} = Jido.start_agent(TraceGuide.Jido, TraceGuide.OrderDesk, id: "desk-1")
:ok = Jido.AgentServer.await_ready(desk)
```

Send a traced Signal. The Turn keeps the trace ID and adds a span.

```elixir
alias Jido.Signal.Context

{:ok, request} =
  %{order_id: "o-1"}
  |> TraceGuide.OrderDesk.confirm_signal!()
  |> Context.put_trace(incoming)

{:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
  Jido.AgentServer.call(desk, request, context: %{observer: self()})

turn_trace =
  receive do
    {:turn_trace, trace, logger_metadata} ->
      true = logger_metadata[:trace_id] == trace.trace_id
      true = logger_metadata[:span_id] == trace.span_id
      trace
  after
    1_000 -> raise "the Turn did not report"
  end

true = turn_trace.trace_id == incoming.trace_id
true = turn_trace.parent_span_id == incoming.span_id
```

A Signal that the Turn emits or replies with carries the Turn's span. Its causation ID is the ID of the input Signal. When another Agent handles that Signal, its Turn becomes a child of this span, so one trace ID follows the whole chain.

```elixir
alias Jido.Signal.Context

emitted =
  receive do
    {:signal, signal} -> signal
  after
    1_000 -> raise "the Turn did not emit"
  end

emitted_trace = Context.get_trace(emitted)

true = emitted_trace.trace_id == incoming.trace_id
true = emitted_trace.span_id == turn_trace.span_id
true = emitted_trace.causation_id == request.id
```

The `traceparent` carries one span ID, so `:parent_span_id` is `nil` on a trace read back from a Signal. Jido sets that field again when it creates the next child.

`:trace_context` and `:turn_id` are reserved. A call that passes either one in its `:context` option returns an error.

Jido keeps a process-local copy of the current trace in `Jido.Trace.Context`, and restores it inside the tasks that run Actions. Its functions are internal. Read `context.trace_context` in your Action.

## Add trace fields to your own output

`Jido.Trace.telemetry_context/1` returns the semantic fields, without the `nil` ones. `Jido.Trace.metadata/1` adds the W3C carrier fields, for code that forwards the trace.

```elixir
alias Jido.Trace

%{trace_id: _, span_id: _, parent_span_id: _, causation_id: "order-signal-1"} =
  context_fields = Trace.telemetry_context(child)

false = Map.has_key?(context_fields, :traceparent)
false = Map.has_key?(Trace.telemetry_context(Trace.new()), :parent_span_id)

%{traceparent: "00-" <> _, tracestate: "vendor=value"} = Trace.metadata(child)
```

Jido's Turn telemetry includes these trace fields. Telemetry and Tracing describes the events and logs.

## Related

- [CloudEvents Context](../signals/cloudevents-envelope-and-context.md) lists the Signal attributes.
- Metrics and OTel connects traces to OpenTelemetry.
- [Telemetry Events](../reference/telemetry-event-reference.md) lists event metadata.
