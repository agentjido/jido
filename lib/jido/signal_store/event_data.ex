defmodule Jido.SignalStore.EventData do
  @moduledoc """
  EventData contains the data for a single event before being persisted to
  storage.
  """

  use TypedStruct

  @type uuid :: String.t()

  typedstruct do
    @typedoc "Represents event data before persistence to storage"

    field(:causation_id, uuid() | nil)
    field(:correlation_id, uuid(), enforce: true)
    field(:event_type, String.t(), enforce: true)
    field(:data, struct(), enforce: true)
    field(:metadata, map(), default: %{})
  end
end
