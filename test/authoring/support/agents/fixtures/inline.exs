defmodule JidoTest.Authoring.Agents.Fixtures.InlineCounter do
  use Jido.Agent, name: "authoring_inline", vsn: 1

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
    metadata %{case: "inline"}
  end

  routes do
    signal_source "/authoring/inline"

    route "inline.add", defaults: %{amount: 1} do
      action %{amount: amount},
        name: "authoring_inline_add",
        schema: Zoi.object(%{amount: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + amount * 2}}
      end

      define :add, args: [{:optional, :amount}]
    end
  end
end
