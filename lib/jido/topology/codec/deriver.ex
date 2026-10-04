defmodule Jido.Topology.Codec.Deriver do
  @moduledoc false

  alias Jido.Codec.Registry
  alias Jido.Agent.Authoring
  alias Jido.Topology.Codec.Value

  def topology(definition) do
    with {:ok, entries} <- definition_entries(definition), do: Registry.derive(entries)
  end

  defp definition_entries(definition) do
    agents = definition.agents ++ definition.groups

    entries =
      Value.registry_entries(definition.metadata) ++
        Enum.flat_map(agents, fn agent ->
          Value.registry_entries(agent.initial_state) ++
            Value.registry_entries(Map.take(agent, [:count, :members, :key_by, :node]))
        end) ++
        Enum.flat_map(definition.resources, &Value.registry_entries(&1.config))

    with {:ok, members} <- Authoring.traverse(agents, &member_entries/1),
         {:ok, included} <-
           Authoring.traverse(definition.includes, fn include ->
             with {:ok, nested} <- definition_entries(include.topology),
                  do: {:ok, Value.registry_entries(include.inputs) ++ nested}
           end),
         {:ok, children} <-
           Authoring.traverse(definition.children, fn child ->
             with {:ok, nested} <- definition_entries(child.topology),
                  {:ok, owner} <- owner_entries(child.director),
                  do:
                    {:ok,
                     nested ++
                       owner ++
                       Value.registry_entries(child.input) ++ Value.registry_entries(child.gate)}
           end) do
      {:ok,
       [{:schema, definition.schema}] ++
         List.flatten(members) ++ entries ++ List.flatten(included) ++ List.flatten(children)}
    end
  end

  defp member_entries(%{definition: definition}), do: Jido.Agent.Codec.Deriver.entries(definition)
  defp member_entries(%{module: module}), do: {:ok, [{:agent, module}]}
  defp owner_entries(nil), do: {:ok, []}
  defp owner_entries(definition), do: Jido.Agent.Codec.Deriver.entries(definition)
end
