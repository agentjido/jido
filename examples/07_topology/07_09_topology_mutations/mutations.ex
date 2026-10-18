defmodule Jido.Examples.Topology.Mutations do
  @moduledoc "Adds, resizes, replaces, and removes members through Agent mutations."
  use Jido.Agent, name: "topology_mutations"

  alias Jido.Agent.Directive, as: D
  alias Jido.Examples.Topology.Cell

  agent do
    schema Zoi.object(%{worker_count: Zoi.integer() |> Zoi.min(1) |> Zoi.default(2)})
  end

  routes do
    signal_source "/examples/topology/mutations"

    route "examples.topology.mutations.workers.add", as: :workers_add do
      action %{count: count}, schema: Zoi.object(%{count: Zoi.integer()}), context: context do
        {:ok, %{context.agent_state | worker_count: count},
         [
           D.agent_add(:workers, Cell,
             count: Jido.Agent.Topology.state(:worker_count),
             initial_state: %{label: "worker"}
           )
         ]}
      end
    end

    route "examples.topology.mutations.workers.bind", as: :workers_bind do
      action %{count: count}, schema: Zoi.object(%{count: Zoi.integer()}), context: context do
        {:ok, %{context.agent_state | worker_count: count}}
      end
    end

    route "examples.topology.mutations.workers.resize", as: :workers_resize do
      action %{count: count}, schema: Zoi.object(%{count: Zoi.integer()}), context: context do
        {:ok, context.agent_state, [D.agent_update(:workers, %{count: count})]}
      end
    end

    route "examples.topology.mutations.observer.replace", as: :observer_replace do
      action _input, schema: Zoi.object(%{}), context: context do
        {:ok, context.agent_state,
         [D.agent_replace(:observer, Cell, initial_state: %{label: "replacement"})]}
      end
    end

    route "examples.topology.mutations.workers.remove", as: :workers_remove do
      action _input, schema: Zoi.object(%{}), context: context do
        {:ok, context.agent_state, [D.agent_remove(:workers)]}
      end
    end
  end

  topology do
    agent :observer, Cell do
      initial_state %{label: "observer"}
    end
  end
end
