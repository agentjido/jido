defmodule Jido.Topology.Codec.Value do
  @moduledoc false
  alias Jido.Agent.Authoring
  alias Jido.Codec.Data
  alias Jido.Topology.{Ref, Reference}

  def encode(value, registry, depth \\ 0)
  def encode(_, _, depth) when depth > 100, do: Authoring.error("Topology data is too deep")

  def encode(%Ref{component: component, key: key} = reference, _registry, _depth) do
    with :ok <- Ref.validate(reference),
         do: {:ok, %{"$type" => "topology.ref", "component" => component, "key" => key}}
  end

  def encode(%Reference{kind: kind, key: key} = reference, registry, depth) do
    with :ok <- Reference.validate(reference),
         {:ok, key} <- Data.encode(key, registry, depth + 1),
         do: {:ok, %{"$type" => "topology.#{kind}", "key" => key}}
  end

  def encode(value, registry, depth) when is_map(value) and not is_struct(value) do
    Data.encode_map(value, &encode(&1, registry, depth + 1))
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
         do: Reference.new(if(type == "topology.input", do: :input, else: :member), key)
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
      decoded = Map.new(pairs)

      if length(pairs) == map_size(decoded),
        do: {:ok, decoded},
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

  def registry_entries(%Ref{}), do: []
  def registry_entries(%Reference{key: key}), do: Data.registry_entries(key)

  def registry_entries(value) when is_map(value) and not is_struct(value) do
    Enum.flat_map(Enum.sort(value), fn {key, item} ->
      [key, item] |> Enum.flat_map(&registry_entries/1)
    end)
  end

  def registry_entries(value) when is_tuple(value),
    do: registry_entries(Tuple.to_list(value))

  def registry_entries(value) when is_list(value), do: Enum.flat_map(value, &registry_entries/1)

  def registry_entries(value), do: Data.registry_entries(value)
end
