# Retain this module identity for the existing saved document contract.
defmodule JidoTest.Authoring.Agents.Fixtures.KeywordCounter do
  use Jido.Agent, name: "authoring_counter", vsn: 3

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    metadata %{case: "counter"}
  end

  routes do
    route "counter.add", JidoTest.Authoring.Agents.Fixtures.Add,
      defaults: %{amount: 1},
      priority: 10

    route "counter.*", JidoTest.Authoring.Agents.Fixtures.Add,
      defaults: %{amount: 5},
      priority: -1
  end
end

defmodule JidoTest.Authoring.Agents.Fixtures.BlockCounter do
  use Jido.Agent, name: "authoring_counter", vsn: 3

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    metadata %{case: "counter"}
  end

  routes do
    signal_source "/authoring/counter"

    route "counter.add", JidoTest.Authoring.Agents.Fixtures.Add, as: :add do
      defaults %{amount: 1}
      priority 10
    end

    route "counter.*", JidoTest.Authoring.Agents.Fixtures.Add do
      defaults %{amount: 5}
      priority -1
    end
  end
end
