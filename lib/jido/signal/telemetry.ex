defmodule Jido.Signal.Telemetry do
  @moduledoc """
  Canonical telemetry helper for Jido Signal.

  Signal-aware events pass the Signal to `execute/4`. The helper reads its
  valid W3C trace context and adds the trace ID, span ID, and trace flags to
  the event metadata.

  Trace context stays on the Signal. This module does not use process state.
  """

  alias Jido.Signal
  alias Jido.Signal.Trace

  @type event_name :: [atom()]

  @doc """
  Emits a telemetry event.
  """
  @spec execute(event_name(), map(), map()) :: :ok
  def execute(event_name, measurements, metadata \\ %{}) do
    :telemetry.execute(event_name, measurements, drop_nil_entries(metadata))
  end

  @doc "Emits a telemetry event with trace metadata from a Signal."
  @spec execute(event_name(), map(), map(), Signal.t()) :: :ok
  def execute(event_name, measurements, metadata, %Signal{} = signal) do
    metadata = metadata |> add_signal_trace(signal) |> drop_nil_entries()
    :telemetry.execute(event_name, measurements, metadata)
  end

  defp drop_nil_entries(metadata) when is_map(metadata) do
    Map.reject(metadata, fn {_key, value} -> is_nil(value) end)
  end

  defp drop_nil_entries(metadata) do
    Enum.reduce(metadata, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end

  defp add_signal_trace(metadata, signal) do
    case Trace.get(signal) do
      %Trace{} = trace ->
        Map.merge(metadata, %{
          jido_trace_id: trace.trace_id,
          jido_span_id: trace.span_id,
          jido_trace_flags: trace.trace_flags
        })

      nil ->
        metadata
    end
  end
end
