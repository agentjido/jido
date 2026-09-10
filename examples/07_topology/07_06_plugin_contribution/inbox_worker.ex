defmodule Jido.Examples.Topology.InboxWorker do
  @moduledoc "An Agent whose Plugin declaration contributes its input Bus."
  use Jido.Agent,
    name: "topology_inbox_worker",
    plugins: [{Jido.Examples.Topology.InboxPlugin, bus: "inbox"}]

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/topology/plugin_contribution"

    route "examples.topology.plugin_contribution.work" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | total: context.agent_state.total + value}}
      end

      define :work, args: [:value]
    end
  end
end
