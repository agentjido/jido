defmodule Jido.Signal.Bus.RecordedSignal do
  @moduledoc """
  Represents a signal that has been recorded in the bus log.

  This struct wraps a signal with additional metadata about when it was recorded.
  """
  use TypedStruct

  @derive {Jason.Encoder, only: [:id, :type, :created_at, :signal]}

  typedstruct do
    @typedoc "A recorded signal with metadata"

    field(:id, String.t(), enforce: true)
    field(:type, String.t(), enforce: true)
    field(:created_at, DateTime.t(), enforce: true)
    field(:signal, Jido.Signal.t(), enforce: true)
  end

  alias Jido.Signal.Serialization.JsonSerializer

  @doc """
  Serializes a RecordedSignal or a list of RecordedSignals to JSON string.

  ## Parameters

  - `recorded_signal_or_list`: A RecordedSignal struct or list of RecordedSignal structs

  ## Returns

  A JSON string representing the RecordedSignal(s)

  ## Examples

      iex> signal = %Jido.Signal{type: "example.event", source: "/example"}
      iex> recorded = %Jido.Signal.Bus.RecordedSignal{id: "rec123", type: "example.event", created_at: DateTime.utc_now(), signal: signal}
      iex> json = Jido.Signal.Bus.RecordedSignal.serialize(recorded)
      iex> is_binary(json)
      true

      iex> # Serializing multiple RecordedSignals
      iex> signal = %Jido.Signal{type: "example.event", source: "/example"}
      iex> records = [
      ...>   %Jido.Signal.Bus.RecordedSignal{id: "rec1", type: "event1", created_at: DateTime.utc_now(), signal: signal},
      ...>   %Jido.Signal.Bus.RecordedSignal{id: "rec2", type: "event2", created_at: DateTime.utc_now(), signal: signal}
      ...> ]
      iex> json = Jido.Signal.Bus.RecordedSignal.serialize(records)
      iex> is_binary(json)
      true
  """
  @spec serialize(t() | list(t())) :: binary()
  def serialize(%__MODULE__{} = recorded_signal) do
    JsonSerializer.serialize_legacy(recorded_signal)
  end

  def serialize(recorded_signals) when is_list(recorded_signals) do
    JsonSerializer.serialize_legacy(recorded_signals)
  end

  @doc """
  Deserializes a JSON string back into a RecordedSignal struct or list of RecordedSignal structs.

  ## Parameters

  - `json`: The JSON string to deserialize

  ## Returns

  `{:ok, RecordedSignal.t() | list(RecordedSignal.t())}` if successful, `{:error, reason}` otherwise

  ## Examples

      iex> json = ~s({"id":"rec123","type":"example.event","created_at":"2023-01-01T00:00:00Z","signal":{"type":"example.event","source":"/example"}})
      iex> {:ok, recorded} = Jido.Signal.Bus.RecordedSignal.deserialize(json)
      iex> recorded.id
      "rec123"

      iex> # Deserializing multiple RecordedSignals
      iex> json = ~s([{"id":"rec1","type":"event1","created_at":"2023-01-01T00:00:00Z","signal":{"type":"event1","source":"/ex"}}])
      iex> {:ok, records} = Jido.Signal.Bus.RecordedSignal.deserialize(json)
      iex> length(records)
      1
  """
  @spec deserialize(binary()) :: {:ok, t() | list(t())} | {:error, term()}
  def deserialize(json) when is_binary(json) do
    try do
      decoded = Jason.decode!(json)

      result =
        if is_list(decoded) do
          # Handle array of RecordedSignals
          Enum.map(decoded, &deserialize_single/1)
        else
          # Handle single RecordedSignal
          deserialize_single(decoded)
        end

      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  # Private helper to deserialize a single RecordedSignal map
  defp deserialize_single(record_map) when is_map(record_map) do
    # Convert string keys to atoms
    atomized_map =
      for {key, val} <- record_map, into: %{} do
        {String.to_existing_atom(key), val}
      end

    # Handle the signal field specially
    signal =
      case atomized_map[:signal] do
        signal_map when is_map(signal_map) ->
          case Jido.Signal.from_map(signal_map) do
            {:ok, signal} -> signal
            {:error, reason} -> raise "Failed to parse signal: #{reason}"
          end

        _ ->
          raise "Invalid signal field in RecordedSignal"
      end

    # Parse the created_at datetime
    created_at =
      case DateTime.from_iso8601(atomized_map[:created_at]) do
        {:ok, datetime, _} -> datetime
        {:error, reason} -> raise "Invalid created_at datetime: #{reason}"
      end

    # Construct the RecordedSignal
    %__MODULE__{
      id: atomized_map[:id],
      type: atomized_map[:type],
      created_at: created_at,
      signal: signal
    }
  end
end
