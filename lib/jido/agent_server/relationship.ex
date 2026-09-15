defmodule Jido.AgentServer.Relationship do
  @moduledoc false

  @spec record(String.t(), term(), term(), term(), map()) :: map()
  def record(parent_id, parent_partition, tag, creation_cause, meta) do
    %{
      parent_id: parent_id,
      parent_partition: parent_partition,
      tag: tag,
      creation_cause: creation_cause,
      meta: meta
    }
  end
end
