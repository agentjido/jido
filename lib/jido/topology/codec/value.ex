defmodule Jido.Topology.Codec.Value do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Agent.Codec.{Data, Registry}
  alias Jido.Topology.{Ref, Reference}

  def encode(value, registry, depth \\ 0)
  def encode(_, _, depth) when depth > 100, do: Authoring.error("Topology data is too deep")

  def encode(%Ref{component: component, key: key}, _registry, _depth),
    do: {:ok, %{"$type" => "topology.ref", "component" => component, "key" => key}}

  def encode(%Reference{kind: kind, key: key}, registry, depth) do
    with {:ok, key} <- Data.encode(key, registry, depth + 1),
         do: {:ok, %{"$type" => "topology.#{kind}", "key" => key}}
  end

  def encode(value, registry, depth) when is_map(value) and not is_struct(value) do
    with {:ok, pairs} <-
           Authoring.traverse(Enum.sort(value), fn {key, item} ->
             with {:ok, key} <- encode(key, registry, depth + 1),
                  {:ok, item} <- encode(item, registry, depth + 1),
                  do: {:ok, [key, item]}
           end),
         do: {:ok, %{"$type" => "map", "entries" => pairs}}
  end

  def encode(value, registry, depth) when is_tuple(value) do
    with {:ok, items} <- encode(Tuple.to_list(value), registry, depth + 1),
         do: {:ok, %{"$type" => "tuple", "items" => items}}
  end

  def encode(value, registry, depth) when is_list(value),
    do: Authoring.traverse(value, &encode(&1, registry, depth + 1))

  def encode(value, registry, depth), do: Data.encode(value, registry, depth)

  def decode(
        %{"$type" => "topology.ref", "component" => component, "key" => key} = value,
        _registry
      )
      when map_size(value) == 3, do: Ref.new(component, key)

  def decode(%{"$type" => type, "key" => key} = value, registry)
      when map_size(value) == 2 and type in ["topology.input", "topology.member"] do
    with {:ok, key} <- Data.decode(key, registry),
         {:ok, _} <- Jido.Topology.Validation.key(key) do
      {:ok, %Reference{kind: if(type == "topology.input", do: :input, else: :member), key: key}}
    end
  end

  def decode(%{"$type" => "map", "entries" => pairs} = value, registry)
      when map_size(value) == 2 do
    with {:ok, pairs} <-
           Authoring.traverse(pairs, fn
             [key, item] ->
               with {:ok, key} <- decode(key, registry),
                    {:ok, item} <- decode(item, registry),
                    do: {:ok, {key, item}}

             _ ->
               Authoring.error("Invalid topology map entry")
           end) do
      if length(pairs) == map_size(Map.new(pairs)),
        do: {:ok, Map.new(pairs)},
        else: Authoring.error("Duplicate decoded map key")
    end
  end

  def decode(%{"$type" => "tuple", "items" => items} = value, registry)
      when map_size(value) == 2 do
    with {:ok, items} <- Authoring.traverse(items, &decode(&1, registry)),
         do: {:ok, List.to_tuple(items)}
  end

  def decode(value, registry) when is_list(value),
    do: Authoring.traverse(value, &decode(&1, registry))

  def decode(value, registry), do: Data.decode(value, registry)

  def entries(%Ref{}), do: []
  def entries(%Reference{key: key}), do: entries(key)

  def entries(value)
      when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value), do: []

  def entries(value) when is_atom(value), do: [{:atom, value}]
  def entries(value) when is_struct(value), do: [{:value, value}]

  def entries(value) when is_map(value),
    do: Enum.flat_map(Enum.sort(value), fn {key, value} -> entries(key) ++ entries(value) end)

  def entries(value) when is_tuple(value), do: entries(Tuple.to_list(value))
  def entries(value) when is_list(value), do: Enum.flat_map(value, &entries/1)

  defp definition_entries(definition) do
    agents = definition.agents ++ definition.groups

    entries =
      [{:schema, definition.schema}] ++
        Enum.map(agents, &{:agent, &1.module}) ++
        entries(definition.metadata) ++
        Enum.flat_map(agents, fn agent ->
          entries(agent.initial_state) ++ entries(Map.take(agent, [:count, :members, :key_by]))
        end) ++ Enum.flat_map(definition.resources, &entries(&1.config))

    entries ++
      Enum.flat_map(definition.includes, fn include ->
        entries(include.inputs) ++ definition_entries(include.topology)
      end)
  end

  def registry(definition) do
    entries = definition_entries(definition)

    entries
    |> Enum.uniq()
    |> Enum.with_index()
    |> Map.new(fn {{kind, _} = value, index} ->
      {"#{kind}/#{index}", value}
    end)
    |> Registry.new()
  end
end
