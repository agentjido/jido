defmodule Jido.Examples.Research.DataDefinedTopology.Startup.Topology do
  @moduledoc "A DSL Topology with three module-defined members."
  use Jido.Topology, name: "authoring_startup"

  topology do
    agents do
      agent :alice, Jido.Examples.Research.DataDefinedTopology.Worker, initial_state: %{total: 2}
      agent :bob, Jido.Examples.Research.DataDefinedTopology.Worker, initial_state: %{total: 3}

      agent :charlie, Jido.Examples.Research.DataDefinedTopology.Worker,
        initial_state: %{total: 4}
    end
  end
end

defmodule Jido.Examples.Research.DataDefinedTopology.Startup do
  @moduledoc "Builds equivalent DSL and data targets before the first activation."

  alias Jido.Topology
  alias Jido.Examples.Research.DataDefinedTopology.{Definitions, Worker}
  alias __MODULE__.Topology, as: DSLTopology

  def definition(:dsl, entries),
    do: Topology.new(%{DSLTopology.topology() | agents: entries})

  def definition(:data, entries), do: Topology.new(name: "authoring_startup", agents: entries)

  def module_entries do
    for {key, total} <- [alice: 2, bob: 3, charlie: 4],
        do: Definitions.entry(key, Worker, %{total: total})
  end

  def data_entries(form) do
    Enum.reduce_while([alice: 2, bob: 3, charlie: 4], {:ok, []}, fn {key, total}, {:ok, acc} ->
      case source(form, key) do
        {:ok, source} -> {:cont, {:ok, acc ++ [Definitions.entry(key, source, %{total: total})]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def mixed_entries(form) do
    with {:ok, entries} <- data_entries(form),
         do: {:ok, [Definitions.entry(:alice, Worker, %{total: 2}) | tl(entries)]}
  end

  def add_members(instance, entries) do
    with {:ok, definition} <-
           Topology.new(%{
             instance.definition
             | agents: instance.definition.agents ++ entries
           }),
         do: Topology.instantiate(definition, id: instance.id, input: instance.input)
  end

  defp source(:dsl_value, _key), do: {:ok, Worker.definition()}
  defp source(:direct, key), do: {:ok, Definitions.direct(key)}
  defp source(:json, key), do: Definitions.stored(key)
end
