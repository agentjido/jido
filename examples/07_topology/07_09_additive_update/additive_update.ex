defmodule Jido.Examples.Topology.AdditiveUpdate do
  @moduledoc "Builds one local worker topology for a public additive update."

  def build(id, count, worker_module \\ __MODULE__.Worker) do
    with {:ok, definition} <-
           Jido.Topology.new(%{
             startup: [retry_interval: 10],
             name: "topology_additive_update",
             agents: [%{key: :observer, module: __MODULE__.Worker}],
             groups: [%{key: :workers, module: worker_module, count: count}]
           }) do
      Jido.Topology.instantiate(definition, id: id)
    end
  end

  def record(server, value) do
    with {:ok, signal} <- __MODULE__.Worker.record_signal(%{value: value}),
         do: Jido.AgentServer.call(server, signal)
  end
end

defmodule Jido.Examples.Topology.AdditiveUpdate.Worker do
  @moduledoc "Stores a local total so retained state is visible after an update."
  use Jido.Agent, name: "topology_additive_worker"

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/topology/additive_update"

    route "examples.topology.additive_update.record", as: :record do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | total: context.agent_state.total + value}}
      end
    end
  end
end

defmodule Jido.Examples.Topology.AdditiveUpdate.ReplacementWorker do
  @moduledoc "A changed worker definition used to prove that updates are additive only."
  use Jido.Agent, name: "topology_additive_replacement_worker"

  agent do
    schema Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)})
  end
end
