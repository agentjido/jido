defmodule Jido.SignalStore.RecordedEvent do
  @moduledoc """
  Contains the persisted stream identity, type, data, and metadata for a single event.

  Events are immutable once recorded.

  ## Recorded event fields

    - `event_id` - a globally unique UUID to identify the event.

    - `event_number` - a globally unique, monotonically incrementing and gapless
      integer used to order the event amongst all events.

    - `stream_id` - the stream identity for the event.

    - `stream_version` - the version of the stream for the event.

    - `causation_id` - an optional UUID identifier used to identify which
      message you are responding to.

    - `correlation_id` - an optional UUID identifier used to correlate related
      messages.

    - `data` - the event data deserialized into a struct.

    - `metadata` - a string keyed map of metadata associated with the event.

    - `created_at` - the datetime, in UTC, indicating when the event was
      created.

  """

  use TypedStruct
  alias Jido.SignalStore.RecordedEvent

  @type causation_id :: uuid() | nil
  @type correlation_id :: uuid() | nil
  @type created_at :: DateTime.t()
  @type data :: domain_event()
  @type domain_event :: struct()
  @type event_id :: uuid()
  @type event_number :: non_neg_integer()
  @type event_type :: String.t()
  @type metadata :: map()
  @type stream_id :: String.t()
  @type stream_version :: non_neg_integer()
  @type uuid :: String.t()

  @type enriched_metadata :: %{
          :event_id => event_id(),
          :event_number => event_number(),
          :stream_id => stream_id(),
          :stream_version => stream_version(),
          :correlation_id => correlation_id(),
          :causation_id => causation_id(),
          :created_at => created_at(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  typedstruct do
    field(:event_id, event_id(), enforce: true)
    field(:event_number, event_number(), enforce: true)
    field(:stream_id, stream_id(), enforce: true)
    field(:stream_version, stream_version(), enforce: true)
    field(:causation_id, causation_id())
    field(:correlation_id, correlation_id())
    field(:event_type, event_type(), enforce: true)
    field(:data, data(), enforce: true)
    field(:metadata, metadata(), default: %{})
    field(:created_at, created_at(), enforce: true)
  end

  @doc """
  Enrich the event's metadata with fields from the `RecordedEvent` struct and
  any additional metadata passed as an option.
  """
  @spec enrich_metadata(t(), [{:additional_metadata, map()}]) :: enriched_metadata()
  def enrich_metadata(%RecordedEvent{} = event, opts) do
    %RecordedEvent{
      event_id: event_id,
      event_number: event_number,
      stream_id: stream_id,
      stream_version: stream_version,
      correlation_id: correlation_id,
      causation_id: causation_id,
      created_at: created_at,
      metadata: metadata
    } = event

    additional_metadata = Keyword.get(opts, :additional_metadata, %{})

    %{
      event_id: event_id,
      event_number: event_number,
      stream_id: stream_id,
      stream_version: stream_version,
      correlation_id: correlation_id,
      causation_id: causation_id,
      created_at: created_at
    }
    |> Map.merge(metadata || %{})
    |> Map.merge(additional_metadata)
  end
end
