defmodule Jido.Examples.AdditiveUpdate do
  @moduledoc "Builds one local worker topology for a public additive update."

  def build(id, count) do
    with {:ok, definition} <-
           Jido.Topology.new(%{
             startup: [retry_interval: 10],
             name: "topology_additive_update",
             agents: [%{key: :observer, module: __MODULE__.Worker}],
             groups: [%{key: :workers, module: __MODULE__.Worker, count: count}]
           }) do
      Jido.Topology.instantiate(definition, id: id)
    end
  end

  def record(server, value) do
    Jido.AgentServer.call(
      server,
      Jido.Signal.new!(
        "examples.topology.additive_update.record",
        %{value: value},
        source: "/examples/topology/additive_update"
      )
    )
  end
end

defmodule Jido.Examples.AdditiveUpdate.Worker do
  @moduledoc "Stores a local total so retained state is visible after an update."
  use Jido.Agent, name: "topology_additive_worker"

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/topology/additive_update"

    route "examples.topology.additive_update.record" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | total: context.agent_state.total + value}}
      end
    end
  end
end
