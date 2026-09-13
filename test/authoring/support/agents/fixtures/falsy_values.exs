defmodule JidoTest.Authoring.Agents.Fixtures.FalsyValues do
  use Jido.Agent, name: "authoring_falsy_values"

  agent do
    schema Zoi.object(%{
             enabled: Zoi.boolean() |> Zoi.default(false),
             amount: Zoi.integer() |> Zoi.default(0),
             note: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
           })
  end

  routes do
    route "config.set", JidoTest.Authoring.Agents.Fixtures.SetConfig do
      defaults %{enabled: true, amount: 7, note: "default"}
    end
  end
end
