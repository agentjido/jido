defmodule Jido.Examples.TopologyUpgrade do
  @moduledoc "Builds and compares desired local worker sets through public Topology values."

  alias Jido.Topology.Builder

  def build(id, count, worker_module \\ __MODULE__.WorkerV1) do
    Builder.new(name: "research_upgrade_topology")
    |> Builder.agent(:observer, __MODULE__.WorkerV1)
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

  def diff(_old, _target), do: {:error, :topology_identity_mismatch}

  def work(server, value) do
    Jido.AgentServer.call(
      server,
      Jido.Signal.new!(
        "examples.research.topology_upgrade.work",
        %{value: value},
        source: "/examples/research/topology_upgrade"
      )
    )
  end
end

defmodule Jido.Examples.TopologyUpgrade.WorkerV1 do
  @moduledoc "The original worker definition adds each input to its total."
  use Jido.Agent, name: "research_topology_worker_v1"

  agent do
    schema Zoi.object(%{
             label: Zoi.string() |> Zoi.default("cell"),
             received: Zoi.integer() |> Zoi.default(0),
             total: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/research/topology_upgrade"

    route "examples.research.topology_upgrade.work" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok,
         %{
           context.agent_state
           | total: context.agent_state.total + value,
             received: context.agent_state.received + 1
         }}
      end
    end
  end
end

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
    signal_source "/examples/research/topology_upgrade"

    route "examples.research.topology_upgrade.work" do
      action %{value: value},
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
