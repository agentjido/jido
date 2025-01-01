defmodule Jido.SignalStore.SnapshotData do
  @moduledoc """
  Snapshot data
  """

  use TypedStruct

  typedstruct do
    field(:source_uuid, String.t(), enforce: true)
    field(:source_version, non_neg_integer(), enforce: true)
    field(:source_type, String.t(), enforce: true)
    field(:data, binary(), enforce: true)
    field(:metadata, binary(), enforce: true)
    field(:created_at, DateTime.t(), enforce: true)
  end
end
