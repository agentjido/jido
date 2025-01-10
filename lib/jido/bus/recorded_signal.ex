defmodule Jido.Bus.RecordedSignal do
  @moduledoc """
  Contains the persisted stream identity, type, data, and metadata for a single signal.

  Signals are immutable once recorded.

  ## Recorded signal fields

    - `signal_id` - a globally unique UUID to identify the signal.

    - `signal_number` - a globally unique, monotonically incrementing and gapless
      integer used to order the signal amongst all signals.

    - `stream_id` - the stream identity for the signal.

    - `stream_version` - the version of the stream for the signal.

    - `jido_causation_id` - an optional UUID identifier used to identify which
      message you are responding to.

    - `jido_correlation_id` - an optional UUID identifier used to correlate related
      messages.

    - `data` - the signal data deserialized into a struct.

    - `metadata` - a string keyed map of metadata associated with the signal.

    - `created_at` - the datetime, in UTC, indicating when the signal was
      created.

  """

  alias Jido.Bus.RecordedSignal

  @type jido_causation_id :: uuid() | nil
  @type jido_correlation_id :: uuid() | nil
  @type created_at :: DateTime.t()
  @type data :: domain_signal()
  @type domain_signal :: struct()
  @type signal_id :: uuid()
  @type signal_number :: non_neg_integer()
  @type type :: String.t()
  @type metadata :: map()
  @type stream_id :: String.t()
  @type stream_version :: non_neg_integer()
  @type uuid :: String.t()
  @type signal :: struct()

  @type t :: %RecordedSignal{
          signal_id: signal_id(),
          signal_number: signal_number(),
          stream_id: stream_id(),
          stream_version: stream_version(),
          jido_causation_id: jido_causation_id(),
          jido_correlation_id: jido_correlation_id(),
          type: type(),
          data: data(),
          metadata: metadata(),
          created_at: created_at()
        }

  @type enriched_metadata :: %{
          :signal_id => signal_id(),
          :signal_number => signal_number(),
          :stream_id => stream_id(),
          :stream_version => stream_version(),
          :jido_correlation_id => jido_correlation_id(),
          :jido_causation_id => jido_causation_id(),
          :created_at => created_at(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  defstruct [
    :signal_id,
    :signal_number,
    :stream_id,
    :stream_version,
    :jido_causation_id,
    :jido_correlation_id,
    :type,
    :data,
    :created_at,
    metadata: %{}
  ]

  @doc """
  Enrich the signal's metadata with fields from the `RecordedSignal` struct and
  any additional metadata passed as an option.
  """
  @spec enrich_metadata(t(), [{:additional_metadata, map()}]) :: enriched_metadata()
  def enrich_metadata(%RecordedSignal{} = signal, opts) do
    %RecordedSignal{
      signal_id: signal_id,
      signal_number: signal_number,
      stream_id: stream_id,
      stream_version: stream_version,
      jido_correlation_id: jido_correlation_id,
      jido_causation_id: jido_causation_id,
      created_at: created_at,
      metadata: metadata
    } = signal

    additional_metadata = Keyword.get(opts, :additional_metadata, %{})

    %{
      signal_id: signal_id,
      signal_number: signal_number,
      stream_id: stream_id,
      stream_version: stream_version,
      jido_correlation_id: jido_correlation_id,
      jido_causation_id: jido_causation_id,
      created_at: created_at
    }
    |> Map.merge(metadata || %{})
    |> Map.merge(additional_metadata)
  end

  @doc """
  Map a list of `Jido.Bus.RecordedSignal` structs to their signal data.
  """
  @spec map_from_recorded_signals(list(RecordedSignal.t())) :: [signal]
  def map_from_recorded_signals(recorded_signals) when is_list(recorded_signals) do
    Enum.map(recorded_signals, &map_from_recorded_signal/1)
  end

  @doc """
  Map an `Jido.Bus.RecordedSignal` struct to its signal data.
  """
  @spec map_from_recorded_signal(RecordedSignal.t()) :: signal
  def map_from_recorded_signal(%RecordedSignal{data: data}), do: data
end
