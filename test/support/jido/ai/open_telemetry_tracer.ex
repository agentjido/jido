defmodule Jido.AITest.OpenTelemetryTracer do
  @moduledoc false

  import Bitwise
  require Record

  @behaviour :otel_tracer

  Record.defrecordp(
    :span_ctx,
    Record.extract(:span_ctx, from_lib: "opentelemetry_api/include/opentelemetry.hrl")
  )

  Record.defrecordp(
    :status,
    Record.extract(:status, from_lib: "opentelemetry_api/include/opentelemetry.hrl")
  )

  @impl true
  def start_span(context, {__MODULE__, owner}, name, opts) do
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

    send(owner, {:otel_start, span, parent, name, opts})
    span
  end

  @impl true
  def with_span(context, tracer, name, opts, fun) do
    span = start_span(context, tracer, name, opts)
    token = context |> :otel_tracer.set_current_span(span) |> :otel_ctx.attach()

    try do
      fun.(span)
    after
      :otel_span.end_span(span)
      :otel_ctx.detach(token)
    end
  end

  def set_attribute(span, key, value) do
    notify(span, {:otel_set_attribute, ids(span), key, value})
    true
  end

  def set_attributes(span, attributes) do
    notify(span, {:otel_set_attributes, ids(span), attributes})
    true
  end

  def add_event(span, name, attributes) do
    notify(span, {:otel_event, ids(span), name, attributes})
    true
  end

  def add_events(span, events) do
    notify(span, {:otel_events, ids(span), events})
    true
  end

  def set_status(span, value) do
    notify(
      span,
      {:otel_status, ids(span), status(value, :code), status(value, :message)}
    )

    true
  end

  def update_name(span, name) do
    notify(span, {:otel_update_name, ids(span), name})
    true
  end

  def end_span(span) do
    notify(span, {:otel_end, ids(span), :default})
    true
  end

  def end_span(span, timestamp) do
    notify(span, {:otel_end, ids(span), timestamp})
    true
  end

  def ids(span) do
    %{
      trace_id: span_ctx(span, :trace_id),
      span_id: span_ctx(span, :span_id),
      hex_trace_id: span_ctx(span, :hex_trace_id),
      hex_span_id: span_ctx(span, :hex_span_id)
    }
  end

  defp notify(span, message) do
    {__MODULE__, owner} = span_ctx(span, :span_sdk)
    send(owner, message)
  end

  defp hex_id(value, bits) do
    value
    |> then(&<<&1::size(bits)>>)
    |> Base.encode16(case: :lower)
  end
end
