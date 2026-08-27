defmodule Jido.Tracing.Trace do
  @moduledoc """
  Trace data helpers for signal correlation.

  Provides functions to create and attach trace data with CloudEvents
  extension context attributes.
  """

  alias Jido.Signal

  @context_names %{
    trace_id: "jidotraceid",
    span_id: "jidospanid",
    parent_span_id: "jidoparentspanid",
    causation_id: "jidocausationid"
  }

  @doc """
  Creates a new root trace with fresh trace_id and span_id.
  """
  @spec new_root() :: map()
  def new_root do
    %{
      trace_id: generate_id(),
      span_id: generate_id(),
      parent_span_id: nil,
      causation_id: nil
    }
  end

  @doc """
  Creates a child trace from a parent trace context.

  The child trace:
  - Inherits the same trace_id
  - Gets a new span_id
  - Has parent_span_id set to the parent's span_id
  - Has causation_id set to the provided value (typically the parent signal's id)
  """
  @spec child_of(map(), String.t()) :: map()
  def child_of(%{trace_id: trace_id, span_id: parent_span_id}, causation_id)
      when is_binary(causation_id) do
    %{
      trace_id: trace_id,
      span_id: generate_id(),
      parent_span_id: parent_span_id,
      causation_id: causation_id
    }
  end

  @doc """
  Attaches trace data to a signal with the v3 Signal context API.
  """
  @spec put(Signal.t(), map()) :: {:ok, Signal.t()} | {:error, term()}
  def put(%Signal{} = signal, trace_data) when is_map(trace_data) do
    Enum.reduce_while(@context_names, {:ok, signal}, fn {key, context_name}, {:ok, signal} ->
      case Map.get(trace_data, key) do
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

  def put(_signal, _trace_data) do
    {:error, :invalid_args}
  end

  @doc """
  Gets trace data from a signal.
  """
  @spec get(Signal.t()) :: map() | nil
  def get(%Signal{} = signal) do
    trace_data =
      Map.new(@context_names, fn {key, context_name} ->
        {key, Signal.get_context(signal, context_name)}
      end)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    if map_size(trace_data) == 0, do: nil, else: trace_data
  end

  defp generate_id do
    Signal.ID.generate!()
  end
end
