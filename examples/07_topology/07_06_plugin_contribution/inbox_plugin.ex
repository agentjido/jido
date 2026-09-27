defmodule Jido.Examples.Topology.InboxFacet do
  @moduledoc "Adds one static Bus and one subscription for its Agent declaration."
  @behaviour Jido.Plugin

  alias Jido.Topology.Plugin.Contribution

  @impl true
  def contribute(context, opts) do
    bus = Keyword.fetch!(opts, :bus)

    {:ok,
     %Contribution{
       plugin: context.plugin,
       resources: [%{key: bus, config: []}],
       connections: [
         %{agent: context.agent_key, to: bus, path: "examples.topology.plugin_contribution.work"}
       ]
     }}
  end
end

defmodule Jido.Examples.Topology.InboxPlugin do
  @moduledoc "A Plugin package with one Topology-owned facet."
  use Jido.Plugin, option_keys: [topology: [:bus]]

  @impl true
  defdelegate contribute(context, opts), to: Jido.Examples.Topology.InboxFacet
end
