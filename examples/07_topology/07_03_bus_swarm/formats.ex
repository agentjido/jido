defmodule Jido.Examples.Topology.Formats do
  @moduledoc "Builder and JSON forms of the Swarm DSL, using stable application Registry IDs."
  alias Jido.Agent.Codec.Registry
  alias Jido.Examples.Topology.{Cell, Swarm}
  alias Jido.Topology.{Builder, Codec, Reference}

  @doc "Builds the same definition as Swarm.topology/0."
  def builder do
    Builder.new(name: "bus_swarm")
    |> Builder.schema(Swarm.topology().schema)
    |> Builder.metadata(%{purpose: "Bus fan-out"})
    |> Builder.agent(:coordinator, Cell)
    |> Builder.group(:workers, Cell, count: Reference.input(:worker_count))
    |> Builder.bus(:work)
    |> Builder.owns(:coordinator, :workers)
    |> Builder.subscribe(:workers, to: :work, path: "topology.work")
    |> Builder.startup(concurrency: 32, ready: :all)
  end

  @doc "Returns the stable Registry required by the example JSON document."
  def registry do
    Registry.new!(%{
      "agents/cell" => {:agent, Cell},
      "schemas/swarm" => {:schema, Swarm.topology().schema},
      "fields/worker_count" => {:atom, :worker_count},
      "fields/purpose" => {:atom, :purpose}
    })
  end

  @doc "Returns a JSON string that can be stored in a file or database."
  def json do
    with {:ok, document} <- Codec.encode(Swarm.topology(), registry()),
         do: {:ok, JSON.encode!(document)}
  end

  @doc "Loads the checked-in JSON example through the stable Registry."
  def from_file do
    document = __DIR__ |> Path.join("swarm.json") |> File.read!() |> JSON.decode!()
    Codec.decode(document, registry())
  end
end
