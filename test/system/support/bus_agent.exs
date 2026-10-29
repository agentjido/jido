defmodule JidoTest.System.BusAgent do
  @moduledoc false
  use Jido.Agent,
    name: "system_bus_agent",
    plugins: [{Jido.Plugin.Bus.Client, %{bus: :system_bus, path: "system.work"}}]

  state do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    route "system.work", JidoTest.System.ControlledWork
  end
end
