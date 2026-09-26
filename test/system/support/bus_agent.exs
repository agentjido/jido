defmodule JidoTest.System.BusAgent do
  @moduledoc false
  use Jido.Agent, name: "system_bus_agent"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})

    plugin Jido.Plugin.Bus.Client, config: [bus: :system_bus, path: "system.work"]
  end

  routes do
    route "system.work", JidoTest.System.ControlledWork
  end
end
