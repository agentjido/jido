defmodule Jido.Plugin.Bus.DSL.References do
  @moduledoc false
  @spec bus(atom()) :: %{kind: :bus, name: atom()}
  def bus(name), do: %{kind: :bus, name: name}
end

defmodule Jido.Plugin.Bus.DSL do
  @moduledoc "Declares one local Signal bus and validates its connection endpoints."
  alias Jido.Agent.{Data, Error}
  alias Spark.Dsl.Extension, as: E
  @section %Spark.Dsl.Section{name: :signal_bus, schema: [name: [type: :atom, required: true]]}
  use Jido.Agent.Extension, id: "jido.signal_bus", sections: [@section]
  @impl Jido.Agent.Extension
  def authoring_imports, do: [Jido.Plugin.Bus.DSL.References]

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    name = E.get_opt(dsl, [:signal_bus], :name)

    cond do
      name != nil and config != %{} ->
        Error.fail(:ambiguous_config, [], "Use Signal bus DSL or Plugin data, not both")

      config != %{} ->
        {:ok, config}

      name != nil ->
        {:ok, %{buses: [%{name: name}]}}

      true ->
        Error.fail(:bus_name, [], "Signal bus needs an explicit local name")
    end
  end

  @impl Jido.Agent.Extension
  def normalize(value) do
    with {:ok, value} <- Data.fields(value, [:buses]),
         {:ok, buses} <- Data.list(value[:buses], &normalize_bus/1) do
      case buses do
        [_bus] -> {:ok, %{buses: buses}}
        _buses -> Error.fail(:bus_count, [], "This provider declares exactly one local bus")
      end
    end
  end

  defp normalize_bus(bus) do
    with {:ok, bus} <- Data.fields(bus, [:name]),
         :ok <- Data.name(bus[:name]),
         do: {:ok, bus}
  end

  @impl Jido.Agent.Extension
  def endpoint_kinds, do: [:bus]
  @impl Jido.Agent.Extension
  def endpoints(data), do: Enum.map(data.buses, &%{kind: :bus, name: &1.name})
  @impl Jido.Agent.Extension
  def verify_connection(_data, %{from: %{kind: :bus}, to: %{kind: :bus}}),
    do: Error.fail(:bus_to_bus, [], "Bus-to-bus connections are not supported")

  def verify_connection(_data, %{to: %{kind: :bus}, delivery: delivery}) when delivery != :single,
    do: Error.fail(:bus_delivery, :delivery, "Publication to a bus uses :single delivery")

  def verify_connection(_data, _), do: :ok
end
