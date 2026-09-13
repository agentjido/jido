defmodule JidoTest.Authoring.Agents.Fixtures.RequiredProfile do
  use Jido.Agent,
    name: "authoring_required_profile",
    schema: Zoi.object(%{name: Zoi.string(), active: Zoi.boolean() |> Zoi.default(false)}),
    routes: [{"profile.rename", JidoTest.Authoring.Agents.Fixtures.Rename}]
end
