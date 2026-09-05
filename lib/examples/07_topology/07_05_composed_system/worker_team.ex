defmodule Jido.Examples.Topology.WorkerTeam do
  @moduledoc "A reusable team with one leader, a worker group, and an imported work Bus."
  use Jido.Topology, name: "worker_team"

  topology do
    schema Zoi.object(%{
             worker_count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(2),
             label: Zoi.string() |> Zoi.default("team")
           })
  end

  imports do
    bus :events
  end

  agents do
    agent :coordinator, Jido.Examples.Topology.Cell do
      initial_state %{label: input(:label)}
    end

    group :workers, Jido.Examples.Topology.Cell do
      count input(:worker_count)
      initial_state %{label: input(:label)}
    end
  end

  relationships do
    owns :coordinator, :workers
  end

  connections do
    subscribe :workers, to: :events, path: "topology.work"
  end

  exports do
    agent :leader, from: :coordinator
    group :workers, from: :workers
    bus :events, from: :events
  end
end
