defmodule Jido.Examples.Research.DataDefinedTopology.Definitions do
  @moduledoc "Distinct data Agents that share compiled behavior and a catalog Action."

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Codec.Registry
  alias Jido.Examples.Research.DataDefinedTopology.{Record, RecordCount, Worker}

  @schemas %{
    alice:
      Zoi.object(%{
        label: Zoi.string() |> Zoi.default("Alice"),
        total: Zoi.integer() |> Zoi.default(0)
      }),
    bob:
      Zoi.object(%{
        label: Zoi.string() |> Zoi.default("Bob"),
        total: Zoi.integer() |> Zoi.default(0),
        category: Zoi.string() |> Zoi.default("review")
      }),
    charlie:
      Zoi.object(%{
        label: Zoi.string() |> Zoi.default("Charlie"),
        total: Zoi.integer() |> Zoi.default(0),
        enabled: Zoi.boolean() |> Zoi.default(true)
      })
  }

  def direct(key) when key in [:alice, :bob, :charlie] do
    Agent.new!(
      module: Worker,
      name: Atom.to_string(key),
      schema: Map.fetch!(@schemas, key),
      plugins: if(key == :bob, do: [], else: [RecordCount]),
      routes: [{"examples.research.data_defined_topology.#{key}.record", Record}],
      metadata: %{"document_id" => "agents/#{key}"}
    )
  end

  # Stable IDs represent the application catalog. Stored strings select
  # existing code and schemas; they do not create code or atoms.
  def registry do
    Registry.new!(
      Map.merge(
        %{
          "agents/worker" => {:agent, Worker},
          "actions/record" => {:action, Record},
          "plugins/record-count" => {:plugin, RecordCount}
        },
        Map.new(@schemas, fn {key, schema} -> {"schemas/#{key}", {:schema, schema}} end)
      )
    )
  end

  def stored(key) do
    registry = registry()

    with {:ok, document} <- Codec.encode(direct(key), registry),
         do: Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
  end

  def entry(key, source, state \\ %{}),
    do: %{key: key, module: source, initial_state: state}

  def path(%Agent{routes: [route | _]}), do: route.path
  def path(module) when is_atom(module), do: path(module.definition())
end
