defmodule Jido.Tracing.Trace do
  @moduledoc false

  alias Jido.Signal
  alias Jido.Signal.Trace, as: SignalTrace

  @causation_context "jidocausationid"
  @legacy_contexts ~w(jidotraceid jidospanid jidoparentspanid)
  @telemetry_keys [:trace_id, :span_id, :parent_span_id, :causation_id]

  @doc false
  @spec new_root() :: map()
  def new_root do
    SignalTrace.new()
    |> from_signal_trace()
  end

  @doc false
  @spec child_of(map(), String.t() | nil) :: map() | {:error, :invalid_trace_context}
  def child_of(trace, causation_id)
      when is_map(trace) and (is_binary(causation_id) or is_nil(causation_id)) do
    with {:ok, parent} <- to_signal_trace(trace) do
      parent
      |> SignalTrace.child()
      |> from_signal_trace()
      |> Map.put(:parent_span_id, parent.span_id)
      |> maybe_put(:causation_id, causation_id)
    else
      _invalid -> {:error, :invalid_trace_context}
    end
  end

  def child_of(_trace, _causation_id), do: {:error, :invalid_trace_context}

  @doc false
  @spec put(Signal.t(), map()) :: {:ok, Signal.t()} | {:error, term()}
  def put(%Signal{} = signal, trace) when is_map(trace) do
    with {:ok, w3c} <- to_signal_trace(trace),
         {:ok, signal} <- SignalTrace.put(delete_legacy(signal), w3c) do
      put_causation(signal, Map.get(trace, :causation_id))
    else
      _invalid -> {:error, :invalid_trace_context}
    end
  end

  def put(_signal, _trace), do: {:error, :invalid_args}

  @doc false
  @spec get(Signal.t()) :: map() | nil
  def get(%Signal{} = signal) do
    case SignalTrace.get(signal) do
      %SignalTrace{} = trace ->
        trace
        |> from_signal_trace()
        |> maybe_put(:causation_id, Signal.get_context(signal, @causation_context))

      nil ->
        nil
    end
  end

  @doc false
  @spec telemetry_context(term()) :: map()
  def telemetry_context(trace) when is_map(trace) do
    case to_signal_trace(trace) do
      {:ok, _w3c} -> Map.take(trace, @telemetry_keys)
      {:error, :invalid_trace_context} -> %{}
    end
  end

  def telemetry_context(_trace), do: %{}

  @doc false
  @spec context_names() :: [String.t()]
  def context_names, do: ["traceparent", "tracestate", @causation_context]

  defp to_signal_trace(%{traceparent: traceparent} = trace) do
    SignalTrace.from_traceparent(traceparent, Map.get(trace, :tracestate))
  end

  defp to_signal_trace(%{trace_id: trace_id, span_id: span_id} = trace) do
    value = %SignalTrace{
      trace_id: trace_id,
      span_id: span_id,
      trace_flags: Map.get(trace, :trace_flags, "00"),
      tracestate: Map.get(trace, :tracestate)
    }

    if SignalTrace.valid?(value),
      do: {:ok, value},
      else: {:error, :invalid_trace_context}
  end

  defp to_signal_trace(_trace), do: {:error, :invalid_trace_context}

  defp from_signal_trace(%SignalTrace{} = trace) do
    %{
      trace_id: trace.trace_id,
      span_id: trace.span_id,
      trace_flags: trace.trace_flags,
      traceparent: SignalTrace.to_traceparent(trace)
    }
    |> maybe_put(:tracestate, trace.tracestate)
  end

  defp put_causation(signal, causation_id) when is_binary(causation_id) do
    Signal.put_context(signal, @causation_context, causation_id)
  end

  defp put_causation(signal, _causation_id) do
    {:ok, Signal.delete_context(signal, @causation_context)}
  end

  defp delete_legacy(signal) do
    Enum.reduce(@legacy_contexts, signal, &Signal.delete_context(&2, &1))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
