defmodule Jido.Examples.Research.DataDefinedTopology.Groups.Counted do
  @moduledoc "A DSL group with one module source and per-member initial state."
  use Jido.Topology, name: "authoring_counted"

  topology do
    agents do
      group :workers, Jido.Examples.Research.DataDefinedTopology.Worker do
        count 3
        initial_state %{total: member(:index)}
      end
    end
  end
end

defmodule Jido.Examples.Research.DataDefinedTopology.Groups.Keyed do
  @moduledoc "A DSL group with stable member keys and state supplied through input."
  use Jido.Topology, name: "authoring_keyed"

  topology do
    schema Zoi.object(%{members: Zoi.list(Zoi.map())})

    agents do
      group :workers, Jido.Examples.Research.DataDefinedTopology.Worker do
        members input(:members)
        key_by :key
        initial_state %{label: member(:label), total: member(:initial)}
      end
    end
  end
end

defmodule Jido.Examples.Research.DataDefinedTopology.Groups do
  @moduledoc "Selects a module or neutral definition for the same group expansion."

  alias Jido.Topology
  alias Jido.Topology.Reference
  alias Jido.Examples.Research.DataDefinedTopology.Definitions
  alias __MODULE__.{Counted, Keyed}

  def definition(kind, source, authoring \\ :dsl)

  def definition(kind, source, :dsl) do
    base = if kind == :counted, do: Counted.topology(), else: Keyed.topology()
    [group] = base.groups
    Topology.new(%{base | groups: [Definitions.select(group, source)]})
  end

  def definition(:counted, source, :data) do
    Topology.new(
      name: "authoring_counted",
      groups: [
        Definitions.select(
          %{
            key: :workers,
            count: 3,
            initial_state: %{total: Reference.member(:index)}
          },
          source
        )
      ]
    )
  end

  def definition(:keyed, source, :data) do
    Topology.new(
      name: "authoring_keyed",
      schema: Zoi.object(%{members: Zoi.list(Zoi.map())}),
      groups: [
        Definitions.select(
          %{
            key: :workers,
            members: Reference.input(:members),
            key_by: :key,
            initial_state: %{label: Reference.member(:label), total: Reference.member(:initial)}
          },
          source
        )
      ]
    )
  end

  def input(:counted), do: %{}

  def input(:keyed) do
    %{
      members: [
        %{key: "east/one", label: "East", initial: 2},
        %{key: "west", label: "West", initial: 5}
      ]
    }
  end
end
