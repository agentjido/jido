defmodule JidoTest.Authoring.Agents.Fixtures.NestedProfile do
  use Jido.Agent, name: "authoring_nested_profile"

  agent do
    schema Zoi.object(%{
             profile:
               Zoi.object(%{name: Zoi.string(), tags: Zoi.array(Zoi.string())})
               |> Zoi.default(%{name: "anonymous", tags: []})
           })
  end

  routes do
    route "nested.rename", JidoTest.Authoring.Agents.Fixtures.RenameNested
  end
end
