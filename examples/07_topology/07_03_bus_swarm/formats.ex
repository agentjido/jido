defmodule Jido.Examples.Topology.Formats do
  @moduledoc "data and JSON forms of the Swarm DSL, using stable application Registry IDs."
  alias Jido.Codec.Registry
  alias Jido.Examples.Topology.{Cell, Swarm}
  alias Jido.Topology.{Codec, Reference}

  @doc "Returns data for the same definition as Swarm.topology/0."
  def data do
    %{
      startup: [concurrency: 32],
      metadata: %{purpose: "Bus fan-out"},
      schema: Swarm.topology().schema,
      name: "bus_swarm",
      agents: [%{key: :coordinator, module: Cell}],
      groups: [%{key: :workers, module: Cell, count: Reference.input(:worker_count)}],
      resources: [%{key: :work, kind: :bus}],
      relationships: [%{parent: :coordinator, child: :workers}],
      connections: [%{agent: :workers, to: :work, path: "examples.topology.cell.work"}]
    }
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
    document = __DIR__ |> Path.join("fixtures/swarm.json") |> File.read!() |> JSON.decode!()
    Codec.decode(document, registry())
  end
end
