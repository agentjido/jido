defmodule JidoTest.OpenTelemetryTracer do
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
  def start_span(context, {__MODULE__, state}, name, opts) do
    {owner, _failure} = owner_and_failure(state)
    parent = :otel_tracer.current_span_ctx(context)
    sequence = System.unique_integer([:positive, :monotonic])
    span_id = band(sequence, 0xFFFFFFFFFFFFFFFF)

    {trace_id, trace_flags} =
      if :otel_span.is_valid(parent) do
        {span_ctx(parent, :trace_id), span_ctx(parent, :trace_flags)}
      else
        {sequence, 1}
      end

    span =
      span_ctx(
        trace_id: trace_id,
        hex_trace_id: hex_id(trace_id, 128),
        span_id: span_id,
        hex_span_id: hex_id(span_id, 64),
        trace_flags: trace_flags,
        is_valid: true,
        is_remote: false,
        is_recording: true,
        span_sdk: {__MODULE__, state}
      )

    send(owner, {:otel_start, span, parent, name, opts})
    span
  end

  @impl true
  def with_span(context, tracer, name, opts, fun) do
    span = start_span(context, tracer, name, opts)
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
    maybe_fail(span, :set_attribute)
    notify(span, {:otel_set_attribute, ids(span), key, value})
    true
  end

  def set_attributes(span, attributes) do
    maybe_fail(span, :set_attributes)
    notify(span, {:otel_set_attributes, ids(span), attributes})
    true
  end

  def add_event(span, name, attributes) do
    maybe_fail(span, :add_event)
    notify(span, {:otel_event, ids(span), name, attributes})
    true
  end

  def add_events(span, events) do
    maybe_fail(span, :add_events)
    notify(span, {:otel_events, ids(span), events})
    true
  end

  def set_status(span, value) do
    maybe_fail(span, :set_status)
    notify(span, {:otel_status, ids(span), status(value, :code)})
    true
  end

  def update_name(span, name) do
    maybe_fail(span, :update_name)
    notify(span, {:otel_update_name, ids(span), name})
    true
  end

  def end_span(span) do
    maybe_fail(span, :end_span)
    notify(span, {:otel_end, ids(span), :default})
    true
  end

  def end_span(span, timestamp) do
    maybe_fail(span, :end_span)
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
    {__MODULE__, state} = span_ctx(span, :span_sdk)
    {owner, _failure} = owner_and_failure(state)
    send(owner, message)
  end

  defp maybe_fail(span, callback) do
    {__MODULE__, state} = span_ctx(span, :span_sdk)

    case owner_and_failure(state) do
      {_owner, ^callback} -> raise "test tracer #{callback} failure"
      {_owner, _failure} -> :ok
    end
  end

  defp owner_and_failure(owner) when is_pid(owner), do: {owner, nil}

  defp owner_and_failure(%{owner: owner, fail: failure}) when is_pid(owner),
    do: {owner, failure}

  defp hex_id(value, bits) do
    value
    |> then(&<<&1::size(bits)>>)
    |> Base.encode16(case: :lower)
  end
end
