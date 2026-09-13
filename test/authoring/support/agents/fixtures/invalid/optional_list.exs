defmodule JidoTest.Authoring.Agents.Fixtures.Invalid.OptionalList do
  use Jido.Agent, name: "invalid_optional_list"

  agent do
  end

  routes do
    signal_source "/invalid"

    route "items.replace", JidoTest.Authoring.Agents.Fixtures.ReplaceItems do
      define :replace, args: [{:optional, :items}]
    end
  end
end
