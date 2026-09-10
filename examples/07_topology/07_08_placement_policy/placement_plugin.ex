defmodule Jido.Examples.Topology.PlacementPolicy.AgentFacet do
  @moduledoc "Owns the exact-placement Directive."
  use Jido.Agent.Plugin

  alias Jido.Examples.Topology.PlacementPolicy.Move

  @impl true
  def directives(_opts), do: [Move]
end

defmodule Jido.Examples.Topology.PlacementPolicy.ServerFacet do
  @moduledoc "Applies a committed placement Directive through the Topology Controller."
  use Jido.AgentServer.Plugin

  alias Jido.Examples.Topology.PlacementPolicy.Move
  alias Jido.Plugin.DirectiveContext
  alias Jido.Topology.Controller

  @impl true
  def dispatch(nil, %Move{} = move, %DirectiveContext{jido: jido}, _opts) do
    case Controller.whereis(jido, move.topology_id) do
      nil ->
        {:error, :topology_controller_not_found}

      controller ->
        Controller.place_agent(controller, move.target, move.node, member: move.member)
    end
  end
end

defmodule Jido.Examples.Topology.PlacementPolicy.Plugin do
  @moduledoc "A Plugin package that applies placement policy after Agent commit."
  use Jido.Plugin,
    agent: Jido.Examples.Topology.PlacementPolicy.AgentFacet,
    agent_server: Jido.Examples.Topology.PlacementPolicy.ServerFacet
end
