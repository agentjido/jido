defmodule JidoTest.System.BusAgent do
  @moduledoc false
  use Jido.Agent,
    name: "system_bus_agent",
    schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
    routes: [{"system.work", JidoTest.System.ControlledWork}],
    plugins: [{Jido.Plugin.Bus.Client, bus: :system_bus, path: "system.work"}]
end
