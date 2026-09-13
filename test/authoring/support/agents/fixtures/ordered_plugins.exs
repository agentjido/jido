defmodule JidoTest.Authoring.Agents.Fixtures.OrderedPlugins do
  use Jido.Agent, name: "authoring_ordered_plugins"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
    plugin JidoTest.Authoring.Agents.Fixtures.FirstPlugin
    plugin JidoTest.Authoring.Agents.Fixtures.SecondPlugin
  end

  routes do
    route "plugins.set", JidoTest.Authoring.Agents.Fixtures.SetValue
  end
end
