defmodule Jido.Examples.Topology.ComposedSystem do
  @moduledoc "Two isolated teams share one root-owned Bus and report to a director."
  use Jido.Topology, name: "composed_system"

  topology do
    schema Zoi.object(%{
             east_workers: Zoi.integer() |> Zoi.min(0) |> Zoi.default(2),
             west_workers: Zoi.integer() |> Zoi.min(0) |> Zoi.default(3)
           })
  end

  agents do
    agent :director, Jido.Examples.Topology.Cell
  end

  resources do
    bus :events
  end

  topologies do
    include :east, Jido.Examples.Topology.WorkerTeam do
      inputs %{worker_count: input(:east_workers), label: "east"}
      bind :events, to: :events
    end

    include :west, Jido.Examples.Topology.WorkerTeam do
      inputs %{worker_count: input(:west_workers), label: "west"}
      bind :events, to: :events
    end
  end

  relationships do
    owns :director, ref(:east, :leader)
    owns :director, ref(:west, :leader)
  end

  startup do
    concurrency 4
    task_timeout 5_000
  end
end
