defmodule Jido.Examples.Topology.InboxFacet do
  @moduledoc "Adds one static Bus and one subscription for its Agent declaration."
  use Jido.Topology.Plugin

  alias Jido.Topology.Plugin.Contribution

  @impl true
  def contribute(context, opts) do
    bus = Keyword.fetch!(opts, :bus)

    {:ok,
     %Contribution{
       plugin: context.plugin,
       resources: [%{key: bus, config: []}],
       connections: [%{agent: context.agent_key, to: bus, path: "plugin.work"}]
     }}
  end
end

defmodule Jido.Examples.Topology.InboxPlugin do
  @moduledoc "A Plugin package with one Topology-owned facet."
  use Jido.Plugin,
    topology: Jido.Examples.Topology.InboxFacet,
    option_keys: [topology: [:bus]]
end

defmodule Jido.Examples.Topology.InboxWorker do
  @moduledoc "An Agent whose Plugin declaration contributes its input Bus."
  use Jido.Agent,
    name: "topology_inbox_worker",
    plugins: [{Jido.Examples.Topology.InboxPlugin, bus: "inbox"}]

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/topology/plugin"

    route "plugin.work" do
      action %{value: value},
        name: "topology_plugin_work",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | total: context.agent_state.total + value}}
      end

      define :work, args: [:value]
    end
  end
end

defmodule Jido.Examples.Topology.PluginContribution do
  @moduledoc "A Topology whose Agent Plugin contributes its Bus connection."
  use Jido.Topology, name: "plugin_contribution"

  agents do
    agent :worker, Jido.Examples.Topology.InboxWorker
  end
end
