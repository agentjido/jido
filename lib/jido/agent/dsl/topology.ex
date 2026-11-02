defmodule Jido.Agent.DSL.Topology do
  @moduledoc false
  alias Jido.Agent.DSL.Entry

  @member %Spark.Dsl.Entity{
    name: :agent,
    target: Entry,
    args: [:name, :definition],
    schema: [
      name: [type: :atom, required: true],
      definition: [type: :any, required: true],
      count: [type: :any, default: 1],
      initial_state: [type: :any, default: %{}]
    ]
  }
  @connection %Spark.Dsl.Entity{
    name: :connect,
    target: Entry,
    args: [:path],
    schema: [
      path: [type: :string, required: true],
      from: [type: :any, required: true],
      to: [type: :any, required: true],
      delivery: [type: :atom, default: :single]
    ]
  }
  @connections %Spark.Dsl.Section{name: :connections, entities: [@connection]}
  @topology %Spark.Dsl.Section{
    name: :__topology__,
    imports: [Jido.Agent.DSL.References],
    entities: [@member],
    sections: [@connections]
  }
  use Spark.Dsl.Extension, sections: [@topology]

  def lower(dsl) do
    alias Spark.Dsl.Extension, as: E

    %{
      agents:
        Enum.map(
          E.get_entities(dsl, [:__topology__]),
          &Map.take(&1, [:name, :definition, :count, :initial_state])
        ),
      connections:
        Enum.map(E.get_entities(dsl, [:__topology__, :connections]), fn entry ->
          entry
          |> Map.take([:path, :from, :to, :delivery])
          |> Map.update!(:from, &endpoint/1)
          |> Map.update!(:to, &endpoint/1)
        end)
    }
  end

  defp endpoint(value) when is_atom(value), do: %{kind: :agent, name: value}
  defp endpoint(value), do: value
end

defmodule Jido.Agent.DSL.References do
  @moduledoc false
  defdelegate state(key), to: Jido.Agent.Topology
end
