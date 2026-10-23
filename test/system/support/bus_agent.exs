defmodule JidoTest.System.BusAgent do
  @moduledoc false
  use Jido.Agent, name: "system_bus_agent"

  state do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  plugins do
    plugin(Jido.Plugin.Bus.Client, config: %{bus: :system_bus, path: "system.work"})
  end

  routes do
    route "system.work", JidoTest.System.ControlledWork do
      state(from: output())
    end
  end
end
