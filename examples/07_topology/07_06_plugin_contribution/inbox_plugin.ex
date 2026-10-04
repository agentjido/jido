defmodule Jido.Examples.Topology.InboxFacet do
  @moduledoc "Adds one Bus, subscription, and owned helper group for its Agent declaration."
  @behaviour Jido.Plugin

  alias Jido.Topology.Plugin.Contribution

  @impl true
  def contribute(context, opts) do
    bus = Keyword.fetch!(opts, :bus)
    child = Keyword.fetch!(opts, :child)

    {:ok,
     %Contribution{
       plugin: context.plugin,
       resources: [%{key: bus, config: []}],
       relationships: [
         %{parent: context.agent_key, child: child, on_parent_exit: :stop}
       ],
       connections: [
         %{agent: context.agent_key, to: bus, path: "examples.topology.plugin_contribution.work"}
       ]
     }}
  end
end

defmodule Jido.Examples.Topology.InboxPlugin do
  @moduledoc "A Plugin package with one Topology-owned facet."
  use Jido.Plugin, option_keys: [topology: [:bus, :child]]

  @impl true
  defdelegate contribute(context, opts), to: Jido.Examples.Topology.InboxFacet
end
