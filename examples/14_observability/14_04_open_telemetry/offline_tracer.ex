defmodule Jido.Examples.Observability.OpenTelemetry.OfflineTracer do
  @moduledoc "A bounded host tracer that forwards spans to one local process."

  import Bitwise
  require Record

  @behaviour :otel_tracer

  Record.defrecordp(
    :span_ctx,
    Record.extract(:span_ctx, from_lib: "opentelemetry_api/include/opentelemetry.hrl")
  )

  @impl true
  def start_span(context, {__MODULE__, owner}, name, options) do
    parent = :otel_tracer.current_span_ctx(context)
    sequence = System.unique_integer([:positive, :monotonic])
    span_id = band(sequence, 0xFFFFFFFFFFFFFFFF)

    {trace_id, trace_flags, tracestate} =
      if :otel_span.is_valid(parent) do
        {
          span_ctx(parent, :trace_id),
          span_ctx(parent, :trace_flags),
          span_ctx(parent, :tracestate)
        }
      else
        {sequence, 1, :otel_tracestate.new()}
      end

    span =
      span_ctx(
        trace_id: trace_id,
        hex_trace_id: hex_id(trace_id, 128),
        span_id: span_id,
        hex_span_id: hex_id(span_id, 64),
        trace_flags: trace_flags,
        tracestate: tracestate,
        is_valid: true,
        is_remote: false,
        is_recording: true,
        span_sdk: {__MODULE__, owner}
      )

    send(owner, {:span_started, name, options})
    span
  end

  @impl true
  def with_span(context, tracer, name, options, fun) do
    span = start_span(context, tracer, name, options)
    active_context = :otel_tracer.set_current_span(context, span)
    token = :otel_ctx.attach(active_context)

    try do
      fun.(span)
    after
      :otel_span.end_span(span)
      :otel_ctx.detach(token)
    end
  end

  def set_attribute(span, key, value) do
    notify(span, {:span_attribute, key, value})
    true
  end

  def set_attributes(span, attributes) do
    notify(span, {:span_attributes, attributes})
    true
  end

  def add_event(span, name, attributes) do
    notify(span, {:span_event, name, attributes})
    true
  end

  def add_events(span, events) do
    notify(span, {:span_events, events})
    true
  end

  def set_status(span, status) do
    notify(span, {:span_status, status})
    true
  end

  def update_name(span, name) do
    notify(span, {:span_name, name})
    true
  end

  def end_span(span), do: end_span(span, :default)

  def end_span(span, timestamp) do
    notify(span, {:span_ended, timestamp})
    true
  end

  defp notify(span, event) do
    {__MODULE__, owner} = span_ctx(span, :span_sdk)
    send(owner, event)
  end

  defp hex_id(value, bits) do
    value
    |> then(&<<&1::size(bits)>>)
    |> Base.encode16(case: :lower)
  end
end
