defmodule JidoTest.Authoring.Agents.Fixtures.OrderedRoutes do
  use Jido.Agent, name: "authoring_ordered_routes"

  agent do
    schema Zoi.object(%{selected: Zoi.string() |> Zoi.default("none")})
  end

  routes do
    route "ordered.pick", JidoTest.Authoring.Agents.Fixtures.Choose do
      defaults %{label: "first"}
      priority 5
    end

    route "ordered.pick", JidoTest.Authoring.Agents.Fixtures.Choose do
      defaults %{label: "second"}
      priority 5
    end
  end
end
