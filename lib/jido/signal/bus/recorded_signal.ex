defmodule Jido.Signal.Bus.RecordedSignal do
  @moduledoc """
  A Signal record returned by Bus publish, replay, and durable delivery.

  `cursor` is the ordered Bus position. A durable consumer passes this cursor
  to `Jido.Signal.Bus.ack/3`.

  Signal wire encoding belongs to `Jido.Signal.Serialization`. This module is
  a value type and does not define a second serialization path.
  """

  alias Jido.Signal
  alias Jido.Signal.ID

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              cursor: Zoi.integer() |> Zoi.min(1),
              type: Zoi.string(),
              created_at: Zoi.any(),
              signal: Zoi.any()
            }
          )

  @typedoc "A stored Signal with its Bus cursor"
  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for a recorded Signal."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc false
  @spec build([Signal.t()], pos_integer()) ::
          {:ok, [map()], [{map(), Signal.t(), t()}], pos_integer()}
          | {:error, {:invalid_signal, non_neg_integer(), String.t()}}
  def build(signals, start_cursor) do
    signals
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], start_cursor}, fn {signal, index}, {:ok, entries, cursor} ->
      case build_entry(signal, cursor) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries], cursor + 1}}
        {:error, reason} -> {:halt, {:error, {:invalid_signal, index, reason}}}
      end
    end)
    |> case do
      {:ok, entries, next_cursor} ->
        entries = Enum.reverse(entries)
        {:ok, Enum.map(entries, &elem(&1, 0)), entries, next_cursor}

      {:error, _reason} = error ->
        error
    end
  end

  @doc false
  @spec decode([map()]) :: {:ok, [t()]} | {:error, term()}
  def decode(records) when is_list(records) and is_integer(length(records)) do
    records
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, decoded} ->
      case from_record(record) do
        {:ok, public} -> {:cont, {:ok, [public | decoded]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      error -> error
    end
  end

  def decode(_records), do: {:error, :invalid_store_records}

  @doc false
  @spec from_record(map()) :: {:ok, t()} | {:error, term()}
  def from_record(%{
        "format_version" => 1,
        "id" => id,
        "cursor" => cursor,
        "type" => type,
        "created_at" => created_at,
        "signal" => signal_map
      })
      when is_binary(created_at) and is_map(signal_map) do
    with true <- is_binary(id),
         true <- is_integer(cursor) and cursor > 0,
         true <- is_binary(type),
         {:ok, datetime, _offset} <- DateTime.from_iso8601(created_at),
         {:ok, signal} <- Signal.from_map(signal_map),
         true <- signal.type == type do
      {:ok,
       %__MODULE__{
         id: id,
         cursor: cursor,
         type: type,
         created_at: datetime,
         signal: signal
       }}
    else
      _invalid -> {:error, :invalid_store_record}
    end
  end

  def from_record(_record), do: {:error, :unsupported_store_record}

  defp build_entry(%Signal{} = signal, cursor) do
    with {:ok, signal} <- validate_signal(signal),
         {:ok, signal, signal_map} <- canonicalize_signal(signal) do
      created_at = DateTime.utc_now()

      stored = %{
        "format_version" => 1,
        "id" => ID.generate!(),
        "cursor" => cursor,
        "type" => signal.type,
        "created_at" => DateTime.to_iso8601(created_at),
        "signal" => signal_map
      }

      public = %__MODULE__{
        id: stored["id"],
        cursor: cursor,
        type: signal.type,
        created_at: created_at,
        signal: signal
      }

      {:ok, {stored, signal, public}}
    end
  end

  defp build_entry(_signal, _cursor), do: {:error, "expected a Signal struct"}

  defp validate_signal(signal) do
    case Zoi.parse(Signal.schema(), signal) do
      {:ok, signal} -> {:ok, signal}
      {:error, errors} -> {:error, Zoi.prettify_errors(errors)}
    end
  end

  defp canonicalize_signal(signal) do
    signal_map = Signal.to_map(signal)

    case Signal.from_map(signal_map) do
      {:ok, canonical_signal} -> {:ok, canonical_signal, signal_map}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end
end
