defmodule Jido.Tracing.Trace do
  @moduledoc """
  Trace data helpers for Signal correlation.

  Jido writes both the legacy `jido*` context attributes and W3C
  `traceparent`/`tracestate` attributes for new traces. It reads a complete
  legacy or W3C context for backward compatibility. A partial or malformed
  representation is ignored as one unit and is never merged into a valid
  representation.
  """

  alias Jido.Signal
  alias Jido.Signal.Trace, as: SignalTrace

  @legacy_context_names %{
    trace_id: "jidotraceid",
    span_id: "jidospanid",
    parent_span_id: "jidoparentspanid",
    causation_id: "jidocausationid"
  }
  @traceparent "traceparent"
  @tracestate "tracestate"
  @telemetry_keys [:trace_id, :span_id, :parent_span_id, :causation_id]

  @doc """
  Creates a new root trace with legacy and W3C context.
  """
  @spec new_root() :: map()
  def new_root do
    trace_id = Signal.ID.generate!()
    span_id = Signal.ID.generate!()

    w3c = %SignalTrace{
      trace_id: legacy_trace_id_to_w3c(trace_id),
      span_id: legacy_span_id_to_w3c(span_id),
      trace_flags: "00",
      tracestate: nil
    }

    %{
      trace_id: trace_id,
      span_id: span_id,
      parent_span_id: nil,
      causation_id: nil,
      traceparent: SignalTrace.to_traceparent(w3c),
      tracestate: w3c.tracestate
    }
  end

  @doc """
  Creates a child trace from a complete parent trace context.

  A malformed parent returns `{:error, :invalid_trace_context}`.
  """
  @spec child_of(map(), String.t()) :: map() | {:error, :invalid_trace_context}
  def child_of(trace, causation_id) when is_map(trace) and is_binary(causation_id) do
    case normalize(trace) do
      %{legacy: nil, w3c: nil} ->
        {:error, :invalid_trace_context}

      normalized ->
        build_child(normalized, causation_id)
    end
  end

  def child_of(_trace, _causation_id), do: {:error, :invalid_trace_context}

  @doc """
  Attaches a complete trace representation to a Signal.

  Valid legacy and W3C representations are written together when both exist.
  Stale fields from an invalid representation are removed.
  """
  @spec put(Signal.t(), map()) :: {:ok, Signal.t()} | {:error, term()}
  def put(%Signal{} = signal, trace_data) when is_map(trace_data) do
    case normalize(trace_data) do
      %{legacy: nil, w3c: nil} ->
        {:error, :invalid_trace_context}

      %{legacy: legacy, w3c: w3c} ->
        signal = delete_legacy(signal)

        with {:ok, signal} <- put_w3c(signal, w3c),
             {:ok, signal} <- put_legacy(signal, legacy) do
          {:ok, signal}
        end
    end
  end

  def put(_signal, _trace_data), do: {:error, :invalid_args}

  @doc """
  Gets one complete trace context from a Signal.

  A valid W3C context takes over when legacy fields are absent or invalid.
  Valid legacy fields remain the compatibility values when both formats exist.
  """
  @spec get(Signal.t()) :: map() | nil
  def get(%Signal{} = signal) do
    legacy =
      @legacy_context_names
      |> Map.new(fn {key, context_name} -> {key, Signal.get_context(signal, context_name)} end)
      |> normalize_legacy()

    case %{legacy: legacy, w3c: SignalTrace.get(signal)} do
      %{legacy: nil, w3c: nil} -> nil
      normalized -> denormalize(normalized)
    end
  end

  @doc false
  @spec telemetry_context(term()) :: map()
  def telemetry_context(trace) when is_map(trace) do
    case normalize(trace) do
      %{legacy: nil, w3c: nil} -> %{}
      normalized -> normalized |> denormalize() |> Map.take(@telemetry_keys)
    end
  end

  def telemetry_context(_trace), do: %{}

  @doc false
  @spec context_names() :: [String.t()]
  def context_names do
    Map.values(@legacy_context_names) ++ [@traceparent, @tracestate]
  end

  defp normalize(trace) do
    %{
      legacy: normalize_legacy(trace),
      w3c: normalize_w3c(trace)
    }
  end

  defp normalize_legacy(trace) do
    values = Map.take(trace, Map.keys(@legacy_context_names))

    if Enum.any?(values, fn {_key, value} -> not is_nil(value) end) do
      trace_id = Map.get(values, :trace_id)
      span_id = Map.get(values, :span_id)
      parent_span_id = Map.get(values, :parent_span_id)
      causation_id = Map.get(values, :causation_id)

      if valid_id?(trace_id) and valid_id?(span_id) and valid_optional_id?(parent_span_id) and
           valid_optional_id?(causation_id) do
        values
        |> Map.put(:trace_id, trace_id)
        |> Map.put(:span_id, span_id)
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
      end
    end
  end

  defp normalize_w3c(trace) do
    traceparent = Map.get(trace, :traceparent)
    tracestate = Map.get(trace, :tracestate)

    if not is_nil(traceparent) or not is_nil(tracestate) do
      case SignalTrace.from_traceparent(traceparent, tracestate) do
        {:ok, parsed} -> parsed
        {:error, :invalid_traceparent} -> nil
      end
    end
  end

  defp denormalize(%{legacy: legacy, w3c: w3c}) do
    legacy = legacy || legacy_from_w3c(w3c)
    Map.merge(legacy, w3c_fields(w3c))
  end

  defp legacy_from_w3c(%SignalTrace{} = trace) do
    %{trace_id: trace.trace_id, span_id: trace.span_id}
  end

  defp build_child(%{legacy: %{} = legacy, w3c: %SignalTrace{} = w3c}, causation_id) do
    legacy_child = legacy_child(legacy, causation_id)

    w3c_child = %SignalTrace{
      trace_id: w3c.trace_id,
      span_id: legacy_span_id_to_w3c(legacy_child.span_id),
      trace_flags: w3c.trace_flags,
      tracestate: w3c.tracestate
    }

    Map.merge(legacy_child, w3c_fields(w3c_child))
  end

  defp build_child(%{legacy: %{} = legacy, w3c: nil}, causation_id) do
    legacy_child(legacy, causation_id)
  end

  defp build_child(%{legacy: nil, w3c: %SignalTrace{} = w3c}, causation_id) do
    w3c_child = SignalTrace.child(w3c)

    %{
      trace_id: w3c_child.trace_id,
      span_id: w3c_child.span_id,
      parent_span_id: w3c.span_id,
      causation_id: causation_id
    }
    |> Map.merge(w3c_fields(w3c_child))
  end

  defp legacy_child(legacy, causation_id) do
    %{
      trace_id: legacy.trace_id,
      span_id: Signal.ID.generate!(),
      parent_span_id: legacy.span_id,
      causation_id: causation_id
    }
  end

  defp legacy_trace_id_to_w3c(trace_id), do: String.replace(trace_id, "-", "")

  defp legacy_span_id_to_w3c(span_id) do
    span_id
    |> String.replace("-", "")
    |> String.slice(-16, 16)
  end

  defp w3c_fields(nil), do: %{}

  defp w3c_fields(%SignalTrace{} = trace) do
    %{
      traceparent: SignalTrace.to_traceparent(trace),
      tracestate: trace.tracestate
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp put_w3c(signal, nil), do: {:ok, SignalTrace.delete(signal)}
  defp put_w3c(signal, %SignalTrace{} = trace), do: SignalTrace.put(signal, trace)

  defp put_legacy(signal, nil), do: {:ok, signal}

  defp put_legacy(signal, legacy) do
    Enum.reduce_while(@legacy_context_names, {:ok, signal}, fn {key, context_name},
                                                               {:ok, signal} ->
      case Map.get(legacy, key) do
        nil ->
          {:cont, {:ok, signal}}

        value ->
          case Signal.put_context(signal, context_name, value) do
            {:ok, signal} -> {:cont, {:ok, signal}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end

  defp delete_legacy(signal) do
    Enum.reduce(Map.values(@legacy_context_names), signal, &Signal.delete_context(&2, &1))
  end

  defp valid_id?(value) do
    is_binary(value) and value != "" and byte_size(value) <= 256 and String.valid?(value)
  end

  defp valid_optional_id?(nil), do: true
  defp valid_optional_id?(value), do: valid_id?(value)
end
