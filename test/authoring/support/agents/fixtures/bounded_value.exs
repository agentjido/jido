defmodule JidoTest.Authoring.Agents.Fixtures.BoundedValue do
  use Jido.Agent, name: "authoring_bounded_value"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.min(0) |> Zoi.max(10) |> Zoi.default(0)})
  end

  routes do
    route "value.set", JidoTest.Authoring.Agents.Fixtures.SetValue
  end
end
