defmodule JidoTest.Authoring.Agents.Fixtures.Invalid.PluginConflict do
  use Jido.Agent, name: "invalid_plugin_conflict"

  agent do
    schema Zoi.object(%{first: Zoi.integer() |> Zoi.default(0)})
    plugin JidoTest.Authoring.Agents.Fixtures.FirstPlugin
  end
end
