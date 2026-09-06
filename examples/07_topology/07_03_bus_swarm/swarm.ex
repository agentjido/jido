defmodule Jido.Examples.Topology.Swarm do
  @moduledoc "A Bus broadcasts work Signals to a group of 1000 Agents by default."
  use Jido.Topology, name: "bus_swarm"

  topology do
    schema Zoi.object(%{
             worker_count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(1_000)
           })

    metadata %{purpose: "Bus fan-out"}
  end

  agents do
    agent :coordinator, Jido.Examples.Topology.Cell

    group :workers, Jido.Examples.Topology.Cell do
      count input(:worker_count)
    end
  end

  resources do
    bus :work
  end

  relationships do
    owns :coordinator, :workers
  end

  connections do
    subscribe :workers, to: :work, path: "topology.work"
  end

  startup do
    concurrency 32
    ready :all
  end
end
