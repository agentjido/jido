defmodule Jido.Bus.Snapshot do
  @moduledoc """
  Snapshot data
  """

  @type t :: %Jido.Bus.Snapshot{
          source_id: String.t(),
          source_version: non_neg_integer,
          source_type: String.t(),
          data: binary,
          metadata: binary,
          created_at: DateTime.t()
        }

  defstruct [
    :source_id,
    :source_version,
    :source_type,
    :data,
    :metadata,
    :created_at
  ]
end
