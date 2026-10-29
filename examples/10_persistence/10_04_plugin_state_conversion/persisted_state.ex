defmodule Jido.Examples.Persistence.PluginStateConversion.Agent do
  @moduledoc "An Agent with a Plugin-owned value that has a stored representation."
  use Jido.Agent,
    name: "persisted_plugin_state",
    plugins: [Jido.Examples.Persistence.PluginStateConversion.Package]

  state do
    schema Zoi.object(%{visible: Zoi.integer() |> Zoi.default(0)})
  end
end
