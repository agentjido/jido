defmodule Jido.Topology.Codec.Deriver do
  @moduledoc false

  alias Jido.Codec.Registry
  alias Jido.Topology.Codec.Value

  def topology(definition) do
    Registry.derive(definition_entries(definition))
  end

  defp definition_entries(definition) do
    agents = definition.agents ++ definition.groups

    entries =
      [{:schema, definition.schema}] ++
        Enum.map(agents, &{:agent, &1.module}) ++
        Value.registry_entries(definition.metadata) ++
        Enum.flat_map(agents, fn agent ->
          Value.registry_entries(agent.initial_state) ++
            Value.registry_entries(Map.take(agent, [:count, :members, :key_by, :node]))
        end) ++
        Enum.flat_map(definition.resources, &Value.registry_entries(&1.config))

    entries ++
      Enum.flat_map(definition.includes, fn include ->
        Value.registry_entries(include.inputs) ++ definition_entries(include.topology)
      end)
  end
end
