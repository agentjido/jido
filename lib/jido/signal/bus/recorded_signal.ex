defmodule Jido.Signal.Bus.RecordedSignal do
  @moduledoc """
  Represents a signal that has been recorded in the bus log.

  This struct wraps a signal with additional metadata about when it was recorded.
  """
  use TypedStruct

  typedstruct do
    @typedoc "A recorded signal with metadata"

    field(:id, String.t(), enforce: true)
    field(:type, String.t(), enforce: true)
    field(:created_at, DateTime.t(), enforce: true)
    field(:signal, Jido.Signal.t(), enforce: true)
  end
end
