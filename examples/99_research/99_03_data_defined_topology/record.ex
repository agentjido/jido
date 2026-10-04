defmodule Jido.Examples.Research.DataDefinedTopology.Record do
  @moduledoc "A shared catalog Action used by the Observer and the stored Alice definition."
  use Jido.Action,
    name: "data_topology_record",
    schema: Zoi.object(%{value: Zoi.integer()})

  @impl true
  def run(%{value: value}, context) do
    {:ok, %{context.agent_state | total: context.agent_state.total + value}}
  end
end
