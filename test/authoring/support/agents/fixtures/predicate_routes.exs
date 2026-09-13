defmodule JidoTest.Authoring.Agents.Fixtures.PredicateRoutes do
  use Jido.Agent, name: "authoring_predicate_routes"

  agent do
    schema Zoi.object(%{selected: Zoi.string() |> Zoi.default("none")})
  end

  routes do
    route "choice.set", JidoTest.Authoring.Agents.Fixtures.Choose do
      match &JidoTest.Authoring.Agents.Fixtures.Matchers.positive?/1
      defaults %{label: "positive"}
      priority 100
    end

    route "choice.set", JidoTest.Authoring.Agents.Fixtures.Choose do
      defaults %{label: "fallback"}
    end
  end
end
