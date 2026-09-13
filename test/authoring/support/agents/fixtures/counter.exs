defmodule JidoTest.Authoring.Agents.Fixtures.KeywordCounter do
  use Jido.Agent,
    name: "authoring_counter",
    vsn: 3,
    schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}),
    metadata: %{case: "counter"},
    routes: [
      {"counter.add", JidoTest.Authoring.Agents.Fixtures.Add,
       defaults: %{amount: 1}, priority: 10},
      {"counter.*", JidoTest.Authoring.Agents.Fixtures.Add, defaults: %{amount: 5}, priority: -1}
    ]
end

defmodule JidoTest.Authoring.Agents.Fixtures.BlockCounter do
  use Jido.Agent, name: "authoring_counter", vsn: 3

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    metadata %{case: "counter"}
  end

  routes do
    signal_source "/authoring/counter"

    route "counter.add", JidoTest.Authoring.Agents.Fixtures.Add do
      defaults %{amount: 1}
      priority 10
      define :add, args: [{:optional, :amount}]
    end

    route "counter.*", JidoTest.Authoring.Agents.Fixtures.Add do
      defaults %{amount: 5}
      priority -1
    end
  end
end
