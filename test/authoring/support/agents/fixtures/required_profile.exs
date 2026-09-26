defmodule JidoTest.Authoring.Agents.Fixtures.RequiredProfile do
  use Jido.Agent, name: "authoring_required_profile"

  agent do
    schema Zoi.object(%{name: Zoi.string(), active: Zoi.boolean() |> Zoi.default(false)})
  end

  routes do
    route "profile.rename", JidoTest.Authoring.Agents.Fixtures.Rename
  end
end
