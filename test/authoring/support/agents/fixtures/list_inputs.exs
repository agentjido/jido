defmodule JidoTest.Authoring.Agents.Fixtures.ListInputs do
  use Jido.Agent, name: "authoring_list_inputs"

  agent do
    schema Zoi.object(%{items: Zoi.array(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    signal_source "/authoring/list_inputs"

    route "items.replace", JidoTest.Authoring.Agents.Fixtures.ReplaceItems do
      define :replace, args: [:items]
    end
  end
end
