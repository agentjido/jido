defmodule Jido.Examples.Topology.ComposedFormats do
  @moduledoc "Builder and JSON forms of the composed system, with stable Registry IDs."
  alias Jido.Agent.Codec.Registry
  alias Jido.Examples.Topology.{Cell, ComposedSystem, WorkerTeam}
  alias Jido.Topology.{Builder, Codec, Ref, Reference}

  @doc "Builds the same composition as the Spark module."
  def builder do
    Builder.new(name: "composed_system")
    |> Builder.schema(ComposedSystem.topology().schema)
    |> Builder.agent(:director, Cell)
    |> Builder.bus(:events)
    |> Builder.include(:east, WorkerTeam,
      inputs: %{worker_count: Reference.input(:east_workers), label: "east"},
      bindings: %{events: :events}
    )
    |> Builder.include(:west, WorkerTeam,
      inputs: %{worker_count: Reference.input(:west_workers), label: "west"},
      bindings: %{events: :events}
    )
    |> Builder.owns(:director, Ref.ref(:east, :leader))
    |> Builder.owns(:director, Ref.ref(:west, :leader))
    |> Builder.startup(concurrency: 4, task_timeout: 5_000)
  end

  @doc "Returns stable code and schema names used in the JSON document."
  def registry do
    Registry.new!(%{
      "agents/cell" => {:agent, Cell},
      "schemas/composed" => {:schema, ComposedSystem.topology().schema},
      "schemas/team" => {:schema, WorkerTeam.topology().schema},
      "fields/east_workers" => {:atom, :east_workers},
      "fields/west_workers" => {:atom, :west_workers},
      "fields/worker_count" => {:atom, :worker_count},
      "fields/label" => {:atom, :label}
    })
  end

  @doc "Encodes the composition tree as JSON, including both team definitions."
  def json do
    with {:ok, document} <- Codec.encode(ComposedSystem.topology(), registry()),
         do: {:ok, JSON.encode!(document)}
  end

  @doc "Reads the checked-in composition document."
  def from_file do
    document = __DIR__ |> Path.join("composed_system.json") |> File.read!() |> JSON.decode!()
    Codec.decode(document, registry())
  end
end
