defmodule Jido.Examples.Topology.ComposedFormats do
  @moduledoc "data and JSON forms of the composed system, with stable Registry IDs."
  alias Jido.Codec.Registry
  alias Jido.Examples.Topology.{Cell, ComposedSystem, WorkerTeam}
  alias Jido.Topology.{Codec, Ref, Reference}

  @doc "Returns data for the same composition as the Spark module."
  def data do
    %{
      startup: [concurrency: 4, task_timeout: 5000],
      schema: ComposedSystem.topology().schema,
      name: "composed_system",
      agents: [%{key: :director, module: Cell}],
      resources: [%{key: :events, kind: :bus}],
      includes: [
        %{
          key: :east,
          topology: WorkerTeam,
          inputs: %{worker_count: Reference.input(:east_workers), label: "east"},
          bindings: %{events: :events}
        },
        %{
          key: :west,
          topology: WorkerTeam,
          inputs: %{worker_count: Reference.input(:west_workers), label: "west"},
          bindings: %{events: :events}
        }
      ],
      relationships: [
        %{parent: :director, child: Ref.ref(:east, :leader)},
        %{parent: :director, child: Ref.ref(:west, :leader)}
      ]
    }
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
    document =
      __DIR__ |> Path.join("fixtures/composed_system.json") |> File.read!() |> JSON.decode!()

    Codec.decode(document, registry())
  end
end
