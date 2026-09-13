defmodule JidoTest.Authoring.Agents.Fixtures.FlowCounter do
  use Jido.Agent, name: "authoring_flow", vsn: 2

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    metadata %{case: "flow"}
    plugin JidoTest.Authoring.Agents.Fixtures.CountTurns, config: [initial: 2]
  end

  routes do
    signal_source "/authoring/flow"

    route "flow.add", JidoTest.Authoring.Agents.Fixtures.AddFlow do
      defaults %{amount: 2}
      define :add, args: [{:optional, :amount}]
    end
  end
end
