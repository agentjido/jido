defmodule JidoTest.TopologyRestoreProbe do
  @moduledoc false
  use Jido.Agent, name: "topology_restore_probe"

  agent do
    schema Zoi.object(%{topology_cold_restore_count: Zoi.integer() |> Zoi.default(0)})
  end
end
