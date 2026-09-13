defmodule JidoTest.Authoring.Agents.Fixtures.Invalid.MissingSource do
  use Jido.Agent, name: "invalid_missing_source"

  agent do
  end

  routes do
    route "counter.add", JidoTest.Authoring.Agents.Fixtures.Add do
      define :add, args: [:amount]
    end
  end
end
