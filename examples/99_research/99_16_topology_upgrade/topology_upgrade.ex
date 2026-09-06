defmodule Jido.Examples.TopologyUpgrade.WorkerV2 do
  @moduledoc "Revision 2 multiplies each work input by ten."
  use Jido.Agent, name: "research_topology_worker_v2"

  agent do
    schema Zoi.object(%{
             label: Zoi.string() |> Zoi.default("cell"),
             received: Zoi.integer() |> Zoi.default(0),
             total: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/topology"

    route "topology.work" do
      action %{value: value},
        name: "research_topology_work_v2",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok,
         %{
           context.agent_state
           | total: context.agent_state.total + value * 10,
             received: context.agent_state.received + 1
         }}
      end
    end
  end
end

defmodule Jido.Examples.TopologyUpgrade do
  @moduledoc """
  Builds and compares desired local worker sets through public Topology values.
  The example diff covers Agents only. It does not apply changes or handle
  ownership, Bus connections, or rollout recovery.
  """
  alias Jido.Examples.Topology.Cell
  alias Jido.Topology.Builder

  def build(id, count, worker_module \\ Cell) do
    Builder.new(name: "research_upgrade_topology")
    |> Builder.agent(:observer, Cell)
    |> Builder.group(:workers, worker_module, count: count)
    |> Builder.startup(retry_interval: 10)
    |> Builder.build(id: id)
  end

  @doc "Compares two validated Agent plans with the same topology identity."
  def diff(%{id: id} = old, %{id: id} = target) do
    old_agents = old.plan.agents
    target_agents = target.plan.agents
    old_keys = Map.keys(old_agents)
    target_keys = Map.keys(target_agents)
    common = old_keys -- (old_keys -- target_keys)
    {unchanged, changed} = Enum.split_with(common, &(old_agents[&1] == target_agents[&1]))

    {:ok,
     %{
       added: Enum.sort(target_keys -- old_keys),
       removed: Enum.sort(old_keys -- target_keys),
       changed: Enum.sort(changed),
       unchanged: Enum.sort(unchanged)
     }}
  end

  def diff(_, _), do: {:error, :topology_identity_mismatch}
end
